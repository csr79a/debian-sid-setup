#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Conversión de Debian Testing a Debian Sid (Unstable)
# ============================================================
# - Hace copia de seguridad de la configuración APT.
# - Desactiva fuentes oficiales Debian antiguas en sources.list/*.list.
# - Crea /etc/apt/sources.list.d/debian.sources en formato deb822.
# - Apunta Debian exclusivamente a unstable.
# - Conserva repositorios de terceros para no romperlos automáticamente.
# - Ejecuta apt update.
# - Ofrece ejecutar apt full-upgrade, pero requiere confirmación.
#
# IMPORTANTE:
# Este script NO instala Debian ni revierte la conversión.
# Está pensado para un sistema Debian Testing ya instalado.
# ============================================================

SCRIPT_NAME="convertir-testing-a-sid.sh"
SOURCES_FILE="/etc/apt/sources.list.d/debian.sources"
KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
BACKUP_DIR="/root/apt-backup-testing-to-sid-$(date +%Y%m%d-%H%M%S)"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
reset='\033[0m'

info() { echo -e "${blue}==>${reset} $*"; }
ok() { echo -e "${green}OK${reset}: $*"; }
warn() { echo -e "${yellow}AVISO${reset}: $*"; }
error() { echo -e "${red}ERROR${reset}: $*" >&2; }

cleanup_on_error() {
    local rc=$?
    error "La conversión no ha terminado correctamente (código $rc)."
    error "La copia de seguridad está en: $BACKUP_DIR"
    exit "$rc"
}
trap cleanup_on_error ERR

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        error "Ejecuta este script con sudo: sudo bash $SCRIPT_NAME"
        exit 1
    fi
}

check_system() {
    [[ -r /etc/os-release ]] || { error "No se encuentra /etc/os-release."; exit 1; }
    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "debian" ]]; then
        error "Este script solo está preparado para Debian."
        exit 1
    fi

    command -v apt-get >/dev/null 2>&1 || { error "No se encuentra apt-get."; exit 1; }
    command -v awk >/dev/null 2>&1 || { error "No se encuentra awk."; exit 1; }
    command -v sed >/dev/null 2>&1 || { error "No se encuentra sed."; exit 1; }

    if [[ ! -f "$KEYRING" ]]; then
        error "No se encuentra el keyring de Debian: $KEYRING"
        exit 1
    fi
}

show_current_sources() {
    info "Fuentes Debian activas detectadas antes del cambio:"

    local found=0 file line suite
    for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$file" ]] || continue
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            echo "  $file: $line"
            found=1
        done < <(awk '
            /^[[:space:]]*#/ {next}
            /^[[:space:]]*(deb|deb-src)[[:space:]]/ {print}
            /^[[:space:]]*Types:[[:space:]]*/ {types=$0}
            /^[[:space:]]*Suites:[[:space:]]*/ {print}
        ' "$file")
    done

    if [[ "$found" -eq 0 ]]; then
        warn "No se han encontrado líneas Debian activas en las fuentes habituales."
    fi
}

backup_apt() {
    info "Creando copia de seguridad de APT..."
    mkdir -p "$BACKUP_DIR"

    [[ -f /etc/apt/sources.list ]] && cp -a /etc/apt/sources.list "$BACKUP_DIR/"
    [[ -d /etc/apt/sources.list.d ]] && cp -a /etc/apt/sources.list.d "$BACKUP_DIR/"

    ok "Copia de seguridad creada en $BACKUP_DIR"
}

comment_debian_legacy_sources() {
    info "Desactivando fuentes oficiales Debian antiguas..."

    local file tmp
    for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [[ -f "$file" ]] || continue

        # Solo modificamos líneas deb/deb-src cuyo URI apunta a los archivos
        # oficiales de Debian. Los repositorios de terceros permanecen intactos.
        tmp="${file}.tmp"
        awk '
            /^[[:space:]]*#/ {print; next}
            /^[[:space:]]*(deb|deb-src)[[:space:]]+https?:\/\/(deb\.debian\.org|ftp\.debian\.org|security\.debian\.org)(\/|[[:space:]])/ {
                print "# Desactivado por convertir-testing-a-sid.sh: " $0
                next
            }
            {print}
        ' "$file" > "$tmp"
        cat "$tmp" > "$file"
        rm -f "$tmp"
    done

    ok "Fuentes Debian oficiales antiguas desactivadas."
}

disable_old_debian_sources_files() {
    # Sustituye el debian.sources principal y desactiva otros .sources
    # oficiales de Debian que sigan apuntando a una suite distinta de Sid.
    if [[ -f "$SOURCES_FILE" ]]; then
        cp -a "$SOURCES_FILE" "$BACKUP_DIR/debian.sources.before-conversion"
        rm -f "$SOURCES_FILE"
    fi

    local file uri suites official
    for file in /etc/apt/sources.list.d/*.sources; do
        [[ -f "$file" ]] || continue

        uri="$(awk '/^[[:space:]]*URIs:[[:space:]]*/ {print $2; exit}' "$file")"
        suites="$(awk '/^[[:space:]]*Suites:[[:space:]]*/ {sub(/^[[:space:]]*Suites:[[:space:]]*/, ""); print; exit}' "$file")"
        official=0

        case "$uri" in
            https://deb.debian.org/*|http://deb.debian.org/*|https://ftp.debian.org/*|http://ftp.debian.org/*|https://security.debian.org/*|http://security.debian.org/*)
                official=1
                ;;
        esac

        if [[ "$official" -eq 1 && "$file" != "$SOURCES_FILE" ]]; then
            if [[ "$suites" != "unstable" && "$suites" != "sid" ]]; then
                cp -a "$file" "$BACKUP_DIR/$(basename "$file")"
                mv "$file" "$file.disabled-by-convertir-testing-a-sid"
                warn "Desactivado $file (suite: ${suites:-desconocida})"
            fi
        fi
    done
}

write_sid_sources() {
    info "Configurando el repositorio oficial de Debian Sid..."

    cat > "$SOURCES_FILE" <<EOF2
Types: deb
URIs: https://deb.debian.org/debian
Suites: unstable
Components: main contrib non-free non-free-firmware
Signed-By: $KEYRING
EOF2

    chmod 0644 "$SOURCES_FILE"
    ok "Creado $SOURCES_FILE"
}

check_no_old_official_sources() {
    info "Comprobando que no quedan fuentes oficiales Debian antiguas activas..."

    local bad=0 file line uri suites

    # Fuentes legacy: las líneas oficiales Debian ya fueron comentadas.
    for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [[ -f "$file" ]] || continue
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            error "Fuente Debian oficial antigua encontrada en $file: $line"
            bad=1
        done < <(awk '
            /^[[:space:]]*#/ {next}
            /^[[:space:]]*(deb|deb-src)[[:space:]]+https?:\/\/(deb\.debian\.org|ftp\.debian\.org|security\.debian\.org)(\/|[[:space:]])/ {print}
        ' "$file")
    done

    # Fuentes deb822: comprobamos URI oficial + suite.
    for file in /etc/apt/sources.list.d/*.sources; do
        [[ -f "$file" ]] || continue
        uri="$(awk '/^[[:space:]]*URIs:[[:space:]]*/ {print $2; exit}' "$file")"
        suites="$(awk '/^[[:space:]]*Suites:[[:space:]]*/ {sub(/^[[:space:]]*Suites:[[:space:]]*/, ""); print; exit}' "$file")"

        case "$uri" in
            https://deb.debian.org/*|http://deb.debian.org/*|https://ftp.debian.org/*|http://ftp.debian.org/*|https://security.debian.org/*|http://security.debian.org/*)
                if [[ "$suites" != "unstable" && "$suites" != "sid" ]]; then
                    error "Fuente Debian oficial con suite antigua en $file: $suites"
                    bad=1
                fi
                ;;
        esac
    done

    if [[ "$bad" -ne 0 ]]; then
        error "No se puede continuar hasta revisar las fuentes Debian oficiales antiguas."
        exit 1
    fi

    ok "Las fuentes oficiales Debian activas apuntan a Sid."
}

check_third_party_sources() {
    local warnings=0 file line
    for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$file" ]] || continue
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            warnings=1
            warn "Repositorio de terceros conservado: $file: $line"
        done < <(
            awk '
                /^[[:space:]]*#/ {next}
                /^[[:space:]]*(deb|deb-src)[[:space:]]/ {
                    if ($2 !~ /(^|:)\/\/(deb\.debian\.org|ftp\.debian\.org|security\.debian\.org)(\/|$)/) print
                }
                /^[[:space:]]*URIs:[[:space:]]*/ {
                    if ($2 !~ /(^|:)\/\/(deb\.debian\.org|ftp\.debian\.org|security\.debian\.org)(\/|$)/) print
                }
            ' "$file"
        )
    done

    if [[ "$warnings" -eq 1 ]]; then
        warn "Los repositorios de terceros no se han modificado. Comprueba que sean compatibles con Debian Sid."
    fi
}

apt_update() {
    info "Ejecutando apt update..."
    apt-get update
    ok "apt update completado."
}

confirm_full_upgrade() {
    echo
    echo "============================================================"
    echo " Debian Testing -> Debian Sid (unstable)"
    echo "============================================================"
    echo
    echo "Los repositorios oficiales ya apuntan a unstable."
    echo "El siguiente paso para completar la conversión es actualizar"
    echo "el sistema con apt full-upgrade."
    echo
    warn "La actualización a Sid puede instalar, eliminar o cambiar paquetes."
    echo
    read -r -p "¿Quieres ejecutar ahora 'apt-get full-upgrade'? [s/N]: " answer
    echo

    case "$answer" in
        [sS]|[sS][iI]|[yY]|[yY][eE][sS])
            info "Ejecutando apt-get full-upgrade..."
            apt-get full-upgrade
            ok "Conversión y actualización a Sid completadas."
            ;;
        *)
            warn "Se ha omitido el full-upgrade."
            echo "Los repositorios ya están preparados para Sid."
            echo "Cuando quieras continuar, ejecuta:"
            echo "  sudo apt-get full-upgrade"
            ;;
    esac
}

main() {
    require_root
    check_system

    echo
    echo "============================================================"
    echo " Conversión Debian Testing -> Debian Sid (unstable)"
    echo "============================================================"
    echo
    warn "Este script cambia únicamente la configuración oficial de APT."
    warn "No instala Debian y no convierte automáticamente repositorios de terceros."
    echo

    show_current_sources
    echo

    read -r -p "¿Continuar con la conversión a Sid? [s/N]: " answer
    echo
    case "$answer" in
        [sS]|[sS][iI]|[yY]|[yY][eE][sS]) ;;
        *)
            info "Conversión cancelada."
            exit 0
            ;;
    esac

    backup_apt
    comment_debian_legacy_sources
    disable_old_debian_sources_files
    write_sid_sources
    check_no_old_official_sources
    check_third_party_sources
    apt_update
    confirm_full_upgrade

    echo
    ok "Configuración Debian Sid finalizada."
    echo "Copia de seguridad: $BACKUP_DIR"
}

main "$@"
