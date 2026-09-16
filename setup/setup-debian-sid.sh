#!/usr/bin/env bash
#
# setup-debian-sid.sh — Configurador de Debian Sid csr79a
#
# Script de configuración inicial para Debian Unstable (Sid) con KDE
# Plasma. Configura los repositorios oficiales (deb822) apuntando a
# unstable, actualiza el sistema, instala un set de paquetes de
# desarrollo/multimedia/sistema/utilidades de disco, el microcode
# correcto según el fabricante de CPU, fuentes de Windows y de Ubuntu,
# añade el remoto de Flathub, y ofrece (opcional, tras detectar el
# hardware) zram, Firefox de Mozilla, el driver NVIDIA y
# switcheroo-control si hay GPU híbrida.
#
# Interfaz por pantallas (whiptail) para bienvenida, decisiones y
# resumen final; el progreso de comandos largos (apt, sed, etc.) se
# muestra como texto normal de terminal.
#
# IMPORTANTE: este script asume que ya tienes un sistema Debian
# instalado y funcionando apuntando a unstable (siguiendo, por ejemplo,
# el método recomendado por la wiki de Debian: instalar stable/testing
# mínimo y luego cambiar los repos a unstable). Este script NO instala
# Debian ni migra desde stable/testing por ti.
#
# NOTA sobre el driver NVIDIA: usa el mismo repositorio CUDA oficial de
# NVIDIA (cuda-keyring, rama "debian13") que las versiones trixie y
# testing de este mismo proyecto. NVIDIA no publica una rama dedicada
# para Sid, pero el repo de debian13 es compatible en la práctica y es
# la combinación ya probada y en uso; no se sustituye por los paquetes
# nativos de Debian (nvidia-driver/nvidia-open-kernel-dkms en
# contrib/non-free), aunque también existen como alternativa.
#
# Uso:
#   chmod +x setup-debian-sid.sh
#   ./setup-debian-sid.sh          # modo interactivo (pide confirmación)
#   ./setup-debian-sid.sh -y       # modo no interactivo (asume "sí" en todo)
#
# Licencia: MIT

set -euo pipefail

TITLE="Configurador de Debian Sid csr79a"
VERSION="1.1.0"

log()   { echo -e "\e[1;34m[*]\e[0m $*"; }
ok()    { echo -e "\e[1;32m[OK]\e[0m $*"; }
warn()  { echo -e "\e[1;33m[!]\e[0m $*"; }
error() { echo -e "\e[1;31m[ERROR]\e[0m $*" >&2; exit 1; }

# ----------------------------------------------------------------------
# 0. Opciones de línea de comandos
# ----------------------------------------------------------------------

ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    -h|--help)
      echo "Uso: $0 [-y|--yes]"
      echo "  -y, --yes   No pedir confirmación (modo no interactivo, sin pantallas)."
      exit 0
      ;;
    *)
      echo "Opción desconocida: $1" >&2
      exit 1
      ;;
  esac
done

# Pequeño helper para confirmaciones. En modo -y no se muestra ninguna
# pantalla (whiptail se salta por completo); en modo interactivo, cada
# decisión se muestra como una pantalla whiptail --yesno, que ya
# devuelve 0 (Sí) / 1 (No) directamente utilizable en un "if confirm...".
confirm() {
  local prompt="$1"
  local height="${2:-14}"
  local width="${3:-70}"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  whiptail --title "$TITLE" --yesno "$prompt" "$height" "$width"
}

info_screen() {
  local prompt="$1"
  local height="${2:-14}"
  local width="${3:-70}"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  whiptail --title "$TITLE" --msgbox "$prompt" "$height" "$width"
}

# _cleanup_profiles_ini <ruta a profiles.ini> <nombre_carpeta1> [nombre_carpeta2 ...]
#
# Quita del profiles.ini de Firefox cualquier bloque [ProfileN] cuyo
# "Path=" coincida con alguno de los nombres de carpeta pasados (solo
# el nombre base, no la ruta completa). No toca [General] ni los
# bloques [InstallXXXX] (el mecanismo moderno de Firefox para decidir
# el perfil por defecto de cada instalación), que deben conservarse
# intactos. Guarda una copia del archivo original en profiles.ini.bak
# antes de tocarlo.
_cleanup_profiles_ini() {
  local ini_file="$1"; shift
  local -a removed_names=("$@")
  [[ -f "$ini_file" ]] || return 0
  [[ ${#removed_names[@]} -gt 0 ]] || return 0

  local pattern
  pattern="$(printf '%s\n' "${removed_names[@]}" | paste -sd'|')"

  cp -- "$ini_file" "${ini_file}.bak"

  awk -v pat="$pattern" '
    function flush() {
      if (block != "") {
        if (is_profile && matched) {
          # bloque de perfil eliminado: se omite
        } else {
          printf "%s", block
        }
      }
      block = ""; is_profile = 0; matched = 0
    }
    BEGIN { block = ""; is_profile = 0; matched = 0 }
    /^\[/ {
      flush()
      is_profile = ($0 ~ /^\[Profile[0-9]+\]/)
    }
    {
      block = block $0 "\n"
      if (is_profile && $0 ~ ("^Path=(" pat ")$")) {
        matched = 1
      }
    }
    END { flush() }
  ' "$ini_file" > "${ini_file}.tmp"

  mv -- "${ini_file}.tmp" "$ini_file"
  ok "profiles.ini actualizado (se eliminaron bloques de perfil obsoletos). Copia previa: ${ini_file}.bak"
}

# Con -y también evitamos que apt/debconf se queden esperando input
# (p. ej. avisos de licencia de firmware/fuentes no libres). OJO: esto
# silencia TODOS los prompts de debconf durante la instalación, no solo
# los de firmware, así que solo se activa en modo no interactivo
# explícito.
if [[ "$ASSUME_YES" -eq 1 ]]; then
  export DEBIAN_FRONTEND=noninteractive
fi

# ----------------------------------------------------------------------
# 1. Comprobaciones previas
# ----------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
  error "No ejecutes este script directamente como root. Usa un usuario normal; se te pedirá la contraseña de sudo cuando haga falta."
fi

if ! command -v apt >/dev/null 2>&1; then
  error "Este script está pensado para sistemas basados en APT (Debian/derivados)."
fi

if ! command -v sudo >/dev/null 2>&1; then
  error "No se encontró el comando 'sudo' en este sistema."
fi

# whiptail hace falta para las pantallas de este propio script; si no
# está (Debian mínimo sin tareas de escritorio), se instala antes de
# mostrar nada.
if ! command -v whiptail >/dev/null 2>&1; then
  log "Instalando whiptail (necesario para las pantallas de este instalador)..."
  sudo apt update
  sudo apt install -y whiptail
fi

log "Comprobando permisos de sudo..."
if ! sudo -v; then
  error "No se pudieron validar los permisos de sudo."
fi

# ----------------------------------------------------------------------
# Detección de CPU (fabricante -> microcode; modelo -> solo informativo)
# ----------------------------------------------------------------------

CPU_VENDOR="$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $NF}' || true)"
CPU_MODEL_NAME="$(grep -m1 'model name' /proc/cpuinfo | sed 's/^.*: //' || true)"
CPU_MODEL_NAME="${CPU_MODEL_NAME:-desconocido}"

case "$CPU_VENDOR" in
  GenuineIntel)
    MICROCODE_PKG="intel-microcode"
    ;;
  AuthenticAMD)
    MICROCODE_PKG="amd64-microcode"
    ;;
  *)
    warn "No se ha podido determinar el fabricante de CPU (vendor_id='$CPU_VENDOR'). No se instalará ningún paquete de microcode automáticamente."
    MICROCODE_PKG=""
    ;;
esac

# NOTA: Debian solo distribuye microcode genérico por fabricante
# (intel-microcode / amd64-microcode), no hay paquetes específicos por
# modelo de CPU. El kernel/iucode-tool aplican en arranque solo el
# fragmento que corresponde a tu CPU exacta (family/model/stepping).
# Por eso el modelo detectado aquí (CPU_MODEL_NAME) es puramente
# informativo: se muestra en pantalla, pero no cambia qué paquete se
# instala.

# ----------------------------------------------------------------------
# Pantalla de bienvenida
# ----------------------------------------------------------------------

confirm "Versión del Configurador de Debian Sid csr79a ${VERSION}\n\nEste programa configura los repositorios oficiales, actualiza el sistema, instala un set de paquetes de desarrollo/multimedia/sistema/utilidades de disco, fuentes de Windows y de Ubuntu, y ofrece de forma opcional zram, Firefox de Mozilla, driver NVIDIA y switcheroo-control según el hardware detectado.\n\nCPU detectada: ${CPU_MODEL_NAME}\n\nRecuerda: Sid es la rama de desarrollo de Debian, en movimiento constante. No es apta para sistemas críticos.\n\n¿Desea continuar?" 20 76 || exit 0

# En Sid, VERSION_CODENAME en /etc/os-release NO siempre es fiable:
# históricamente ha llegado a venir vacío o con un valor de una rama
# distinta. En sistemas actuales suele reportar "sid" correctamente,
# pero por seguridad se avisa igualmente y se pide confirmación manual
# en vez de fiarse solo de este campo, igual que en la versión testing
# de este proyecto.
DETECTED_CODENAME=""
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  DETECTED_CODENAME="${VERSION_CODENAME:-}"
  if [[ "$DETECTED_CODENAME" != "sid" && "$DETECTED_CODENAME" != "unstable" ]]; then
    confirm "Aviso: este script está pensado para Debian Unstable (Sid).\n\nSe ha detectado: ${PRETTY_NAME:-desconocido} (VERSION_CODENAME='${DETECTED_CODENAME:-vacío}').\n\nEsto puede ser normal en Sid: el campo VERSION_CODENAME no siempre ha sido fiable ahí. Antes de continuar, confirma tú mismo que tus repos ya apuntan a unstable (revisa /etc/apt/sources.list.d/*.sources).\n\n¿Confirmas que este sistema ya apunta a unstable/sid?" 18 76 || exit 1
  fi
fi

# ----------------------------------------------------------------------
# 2. Repositorios (formato deb822) — apuntando a unstable
# ----------------------------------------------------------------------

LEGACY_SOURCES="/etc/apt/sources.list"
SOURCES_FILE="/etc/apt/sources.list.d/debian.sources"

if [[ -f "$LEGACY_SOURCES" ]] && grep -qE '^\s*deb(-src)?\s' "$LEGACY_SOURCES"; then
  if confirm "Se ha detectado contenido activo en $LEGACY_SOURCES (típico de una instalación desde la ISO oficial, a veces con una entrada de CD-ROM).\n\nPara evitar repositorios duplicados, se comentará su contenido, dejando que $SOURCES_FILE (creado a continuación) sea la única fuente de los repos oficiales de Debian.\n\n¿Continuar? (se guarda una copia de seguridad antes de tocar nada)" 16 76; then
    LEGACY_BACKUP="${LEGACY_SOURCES}.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$LEGACY_SOURCES" "$LEGACY_BACKUP"
    ok "Copia de seguridad: $LEGACY_BACKUP"
    sudo sed -i -E '/^\s*deb(-src)?\s/ s/^/# desactivado por setup-debian-sid.sh -- /' "$LEGACY_SOURCES"
    ok "Contenido de $LEGACY_SOURCES comentado."
  else
    warn "Se omite la limpieza de $LEGACY_SOURCES. Es probable que 'apt update' muestre avisos de repos duplicados."
  fi
fi

if [[ -f "$SOURCES_FILE" ]]; then
  # Auto-reparación de un bug conocido de versiones anteriores de este
  # script: "unstable-updates" no es una suite real en el archivo de
  # Debian (ver wiki.debian.org/SourcesList) y provoca un error 404 en
  # "apt update". Si el fichero ya existente todavía la incluye (de una
  # ejecución anterior de una versión antigua del script), se corrige
  # automáticamente en vez de solo avisar. También se detecta si ha
  # quedado una suite de otra rama (testing/trixie) de una ejecución
  # anterior de otro script de este mismo proyecto sobre la misma
  # máquina.
  if grep -qE '^Suites:.*unstable-updates' "$SOURCES_FILE"; then
    warn "Se ha detectado el bug conocido de 'unstable-updates' en $SOURCES_FILE."
    SOURCES_BACKUP_DIR="/etc/apt/sources-backups"
    sudo install -d -m 0755 "$SOURCES_BACKUP_DIR"
    SOURCES_BACKUP="${SOURCES_BACKUP_DIR}/debian.sources.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$SOURCES_FILE" "$SOURCES_BACKUP"
    ok "Copia de seguridad: $SOURCES_BACKUP"
    sudo sed -i -E 's/^(Suites:\s*unstable)\s+unstable-updates\s*$/\1/' "$SOURCES_FILE"
    ok "Corregido automáticamente: $SOURCES_FILE ahora solo apunta a 'unstable'."
  elif grep -qE '^Suites:.*(testing|trixie)' "$SOURCES_FILE"; then
    warn "Se ha detectado una suite de 'testing'/'trixie' en $SOURCES_FILE, de una configuración anterior."
    SOURCES_BACKUP_DIR="/etc/apt/sources-backups"
    sudo install -d -m 0755 "$SOURCES_BACKUP_DIR"
    SOURCES_BACKUP="${SOURCES_BACKUP_DIR}/debian.sources.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$SOURCES_FILE" "$SOURCES_BACKUP"
    ok "Copia de seguridad: $SOURCES_BACKUP"
    warn "Revisa manualmente $SOURCES_FILE antes de continuar; no se sobrescribe automáticamente."
  else
    warn "Ya existe $SOURCES_FILE, no se sobrescribe. Revísalo manualmente si hace falta."
  fi
else
  log "Escribiendo $SOURCES_FILE ..."
  # A diferencia de stable/testing, Sid NO tiene suite de seguridad
  # separada (los fixes llegan directamente por "unstable", vía sus
  # propios mantenedores) ni suite de backports (unstable ya es lo más
  # nuevo que hay). Tampoco existe una suite real de "unstable-updates":
  # al ser unstable la rama rolling, un canal aparte de actualizaciones
  # puntuales no tiene sentido (wiki.debian.org/SourcesList lo indica
  # explícitamente: "not meaningful for the rolling development
  # version"). Por eso aquí se usa únicamente "unstable".
  sudo tee "$SOURCES_FILE" >/dev/null <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: unstable
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
  ok "$SOURCES_FILE escrito."
fi

log "Actualizando índices de paquetes..."
sudo apt update

# En Sid el full-upgrade NO es un paso puntual como en testing/trixie:
# es la forma normal y necesaria de mantener el sistema. Se pregunta
# igualmente por consistencia con el resto del script, pero tenlo
# presente para el uso diario (ejecútalo con frecuencia, no solo aquí).
if confirm "En Sid, 'apt full-upgrade' no es un paso puntual: es la forma normal de mantener el sistema al día. Conviene ejecutarlo con frecuencia, no solo ahora.\n\n¿Quieres hacer 'apt full-upgrade' antes de continuar?" 14 76; then
  sudo apt full-upgrade -y
else
  warn "Se omite full-upgrade. Puedes ejecutarlo luego con: sudo apt full-upgrade"
fi

if [[ -n "$MICROCODE_PKG" ]]; then
  ok "CPU detectada: ${CPU_MODEL_NAME} (${CPU_VENDOR}) -> se instalará $MICROCODE_PKG"
fi

# ----------------------------------------------------------------------
# 3. Lista de paquetes
# ----------------------------------------------------------------------
#
# Se instalan agrupados en bloques temáticos, cada uno con su propio
# "apt install", en vez de un único comando con los ~25 paquetes juntos.
# Con "set -e" activo, un solo paquete roto/en tránsito (algo frecuente
# en Sid durante transiciones de librerías) haría abortar TODO el
# script de golpe -- y a esta altura ya se cambiaron los repos a
# unstable y se corrió full-upgrade, así que un aborto total dejaría el
# sistema a mitad de camino sin fuentes/Flathub/zram/Firefox/NVIDIA. Al
# instalar por grupos con su propio chequeo de resultado, un fallo
# puntual solo omite ESE grupo (se avisa cuál y con qué paquetes) y el
# resto de la instalación sigue igual.

if apt-cache show 7zip >/dev/null 2>&1; then
  ARCHIVE_PACKAGES=(unzip zip 7zip)
else
  warn "El paquete '7zip' no está disponible en tus repos; se usará 'p7zip-full' en su lugar."
  ARCHIVE_PACKAGES=(unzip zip p7zip-full)
fi

# Dos arrays paralelos (incides deben corresponderse 1 a 1): nombre
# descriptivo del grupo y string con sus paquetes separados por espacio.
GROUP_NAMES=(
  "Control de versiones / descargas"
  "Compresión"
  "Sistema / diagnóstico"
  "Utilidades de disco"
  "Desarrollo / compilación"
  "Multimedia"
  "Firmware"
  "Gestión de paquetes (GUI)"
  "Flatpak + integración KDE"
)

GROUP_PACKAGES=(
  "git git-lfs curl wget"
  "${ARCHIVE_PACKAGES[*]}"
  "btop fastfetch tree jq ripgrep fd-find pciutils usbutils lshw dmidecode inxi hwinfo lm-sensors acpi"
  "gnome-disk-utility"
  "build-essential gcc g++ make cmake ninja-build pkg-config autoconf automake libtool openssh-client"
  "ffmpeg gstreamer1.0-libav gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly pavucontrol"
  "firmware-linux"
  "synaptic gdebi"
  "flatpak plasma-discover-backend-flatpak"
)

if [[ -n "$MICROCODE_PKG" ]]; then
  GROUP_NAMES+=("Microcode de CPU")
  GROUP_PACKAGES+=("$MICROCODE_PKG")
fi

# Solo para mostrar el listado completo al usuario antes de confirmar.
ALL_PACKAGES=()
for pkgs in "${GROUP_PACKAGES[@]}"; do
  # shellcheck disable=SC2206
  ALL_PACKAGES+=($pkgs)
done

echo
echo "Se van a instalar los siguientes paquetes (agrupados en ${#GROUP_NAMES[@]} bloques):"
printf '  - %s\n' "${ALL_PACKAGES[@]}"
echo
confirm "Se van a instalar ${#ALL_PACKAGES[@]} paquetes (desarrollo, multimedia, sistema, utilidades de disco), en ${#GROUP_NAMES[@]} bloques independientes. Si alguno falla (típico en Sid durante transiciones de paquetes), se avisa y se continúa con el resto en vez de abortar toda la instalación.\n\n¿Continuar con la instalación?" || { warn "Instalación cancelada por el usuario."; exit 0; }

FAILED_GROUPS=()
for i in "${!GROUP_NAMES[@]}"; do
  group_name="${GROUP_NAMES[$i]}"
  # shellcheck disable=SC2206
  group_pkgs=(${GROUP_PACKAGES[$i]})
  log "Instalando (${group_name}): ${group_pkgs[*]}"
  if sudo apt install -y "${group_pkgs[@]}"; then
    ok "${group_name}: instalado correctamente."
  else
    warn "${group_name}: FALLÓ la instalación de este grupo (${group_pkgs[*]})."
    warn "Se continúa con el resto del script; podés reintentar este grupo a mano luego con: sudo apt install ${group_pkgs[*]}"
    FAILED_GROUPS+=("$group_name")
  fi
done

if [[ ${#FAILED_GROUPS[@]} -gt 0 ]]; then
  warn "Grupos que fallaron y se omitieron: ${FAILED_GROUPS[*]}"
  warn "El resto de los pasos (fuentes, Flathub, zram, Firefox, NVIDIA) no dependen de estos paquetes y continúan igual."
fi

# ----------------------------------------------------------------------
# 4. Fuentes de Windows y de Ubuntu (opcional)
# ----------------------------------------------------------------------
#
# Fuentes de Windows: ttf-mscorefonts-installer (Arial, Times New Roman,
# Courier New, etc.). Vive en el componente "contrib" (ya activado en
# nuestro sources.list) porque el propio paquete descarga los .ttf
# originales de Microsoft en tiempo de instalación y requiere aceptar
# su EULA. En modo -y (DEBIAN_FRONTEND=noninteractive) debconf acepta la
# licencia automáticamente vía preseed; en modo interactivo, debconf
# puede mostrar su propia pantalla de aceptación durante el "apt install".
#
# Fuentes de Ubuntu: fonts-ubuntu, ya empaquetada tal cual en los repos
# oficiales de Debian, sin pasos adicionales.

if confirm "¿Instalar fuentes de Windows (Arial, Times New Roman, Courier New...) vía ttf-mscorefonts-installer?\n\nEste paquete descarga las fuentes originales de Microsoft y requiere aceptar su licencia (EULA). En modo no interactivo (-y) se acepta automáticamente." 16 76; then
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections
  fi
  sudo apt install -y ttf-mscorefonts-installer
  ok "Fuentes de Windows instaladas."
else
  warn "Se omiten las fuentes de Windows."
fi

if confirm "¿Instalar las fuentes de Ubuntu (fonts-ubuntu)?"; then
  sudo apt install -y fonts-ubuntu
  ok "Fuentes de Ubuntu instaladas."
else
  warn "Se omiten las fuentes de Ubuntu."
fi

# ----------------------------------------------------------------------
# 5. Flathub
# ----------------------------------------------------------------------

if ! flatpak remote-list | grep -q '^flathub'; then
  log "Añadiendo el remoto de Flathub..."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
else
  ok "El remoto de Flathub ya está configurado."
fi

# ----------------------------------------------------------------------
# 6. ZRAM (swap comprimido en RAM, tamaño automático según RAM total)
# ----------------------------------------------------------------------

TOTAL_RAM_KB="$(grep -m1 '^MemTotal:' /proc/meminfo | awk '{print $2}')"
TOTAL_RAM_MB=$(( TOTAL_RAM_KB / 1024 ))
ZRAM_SIZE_MB=$(( TOTAL_RAM_MB / 2 ))

if [[ -z "$TOTAL_RAM_KB" || "$ZRAM_SIZE_MB" -le 0 ]]; then
  warn "No se ha podido determinar la RAM total del sistema; se omite la configuración de zram."
else
  if confirm "RAM total detectada: ${TOTAL_RAM_MB} MiB.\n\n¿Configurar zram (swap comprimido en RAM) con ${ZRAM_SIZE_MB} MiB (mitad de la RAM)?" 14 70; then
    if ! dpkg -s zram-tools >/dev/null 2>&1; then
      log "Instalando zram-tools..."
      sudo apt install -y zram-tools
    else
      ok "zram-tools ya está instalado."
    fi

    ZRAM_CONF="/etc/default/zramswap"

    if [[ -f "$ZRAM_CONF" ]]; then
      ZRAM_BACKUP="${ZRAM_CONF}.bak.$(date +%Y%m%d%H%M%S)"
      sudo cp "$ZRAM_CONF" "$ZRAM_BACKUP"
      ok "Copia de seguridad de la configuración previa: $ZRAM_BACKUP"

      if grep -q '^#\?SIZE=' "$ZRAM_CONF"; then
        SIZE_VAR="SIZE"
      elif grep -q '^#\?ALLOCATION=' "$ZRAM_CONF"; then
        SIZE_VAR="ALLOCATION"
      else
        SIZE_VAR=""
      fi

      if [[ -n "$SIZE_VAR" ]]; then
        sudo sed -i -E "/^(PERCENT|PERCENTAGE)=/ s/^/#/" "$ZRAM_CONF"

        if grep -q "^${SIZE_VAR}=" "$ZRAM_CONF"; then
          sudo sed -i "s/^${SIZE_VAR}=.*/${SIZE_VAR}=${ZRAM_SIZE_MB}/" "$ZRAM_CONF"
        else
          sudo sed -i "s/^#${SIZE_VAR}=.*/${SIZE_VAR}=${ZRAM_SIZE_MB}/" "$ZRAM_CONF"
        fi

        ok "Configurado ${SIZE_VAR}=${ZRAM_SIZE_MB} (${ZRAM_SIZE_MB} MiB) en $ZRAM_CONF"
        sudo systemctl restart zramswap.service 2>/dev/null || sudo service zramswap restart

        SWAPPINESS_VALUE=130
        SWAPPINESS_CONF="/etc/sysctl.d/99-zram-swappiness.conf"
        if confirm "¿Ajustar vm.swappiness a ${SWAPPINESS_VALUE} (recomendado con zram; por defecto es 60 y está pensado para swap en disco)?"; then
          echo "vm.swappiness=${SWAPPINESS_VALUE}" | sudo tee "$SWAPPINESS_CONF" >/dev/null
          sudo sysctl -p "$SWAPPINESS_CONF" >/dev/null
          ok "Configurado vm.swappiness=${SWAPPINESS_VALUE} de forma persistente en $SWAPPINESS_CONF"
        else
          warn "Se omite el ajuste de vm.swappiness."
        fi
      else
        warn "No se reconoció el formato de $ZRAM_CONF. Revísalo a mano: https://wiki.debian.org/ZRam"
      fi
    else
      warn "No se encontró $ZRAM_CONF tras instalar zram-tools. Revisa manualmente: https://wiki.debian.org/ZRam"
    fi
  else
    warn "Se omite la configuración de zram."
  fi
fi

# ----------------------------------------------------------------------
# 7. Firefox oficial de Mozilla (sustituye a Firefox ESR, opcional)
# ----------------------------------------------------------------------
#
# Debian, incluso en Sid, solo empaqueta "firefox-esr" en su archivo
# oficial (no distribuye la versión release por su política de marca).
# En Sid siempre se usa el formato deb822 (no hace falta la rama de
# compatibilidad con bookworm/bullseye de la versión trixie de este
# proyecto).
#
# NOTA sobre el borrado del perfil de ESR: no hay que confiar en que
# el nombre de la carpeta contenga "esr". Firefox solo le agrega ese
# sufijo al perfil cuando detecta más de una instalación compitiendo
# por el perfil por defecto; si ESR fue la única instalación que
# existió en este equipo, su carpeta puede llamarse simplemente
# "xxxxxxxx.default", sin ningún "esr" en el nombre. Por eso acá se
# toma una foto de TODAS las carpetas de perfil que ya existen antes
# de instalar nada nuevo: en este punto del script, cualquier perfil
# que exista solo puede pertenecer a ESR (el release todavía no está
# instalado), así que no hace falta adivinar el nombre.

MOZILLA_PROFILES_DIR="$HOME/.mozilla/firefox"
MOZILLA_PROFILES_INI="$MOZILLA_PROFILES_DIR/profiles.ini"

if confirm "¿Sustituir Firefox ESR de Debian por Firefox oficial del repositorio de Mozilla?"; then

  PRE_MIGRATION_PROFILE_DIRS=()
  if [[ -d "$MOZILLA_PROFILES_DIR" ]]; then
    while IFS= read -r -d '' dir; do
      case "$(basename -- "$dir")" in
        "Crash Reports"|"Pending Pings"|"Profile Groups") continue ;;
      esac
      PRE_MIGRATION_PROFILE_DIRS+=("$dir")
    done < <(find "$MOZILLA_PROFILES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
  fi

  FIREFOX_ESR_PKGS=()
  for pkg in firefox-esr firefox-esr-l10n-es; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      FIREFOX_ESR_PKGS+=("$pkg")
    fi
  done
  if [[ ${#FIREFOX_ESR_PKGS[@]} -gt 0 ]]; then
    log "Quitando Firefox ESR: ${FIREFOX_ESR_PKGS[*]}"
    # "purge" en vez de "remove": si se usa "remove", dpkg deja el
    # paquete en estado "rc" (removido, config sin purgar) y en una
    # reejecución del script "dpkg -s" sigue fallando igual, pero
    # /etc/firefox-esr queda con restos de config para siempre.
    sudo apt purge -y "${FIREFOX_ESR_PKGS[@]}"
    sudo apt autoremove -y
  else
    warn "Firefox ESR no estaba instalado como paquete (o ya se había quitado antes). Se continúa igual para poder limpiar cualquier perfil huérfano que haya quedado de una ejecución anterior."
  fi

  if [[ -d /etc/firefox-esr ]]; then
    # dpkg no borra el directorio si queda algo adentro que no le
    # pertenece a ningún paquete (por ejemplo /etc/firefox-esr/pref/).
    log "Quitando restos de configuración en /etc/firefox-esr"
    sudo rm -rf /etc/firefox-esr
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    log "Instalando gnupg (necesario para verificar la clave de Mozilla)..."
    sudo apt install -y gnupg
  fi

  sudo install -d -m 0755 /etc/apt/keyrings
  wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- \
    | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc >/dev/null

  MOZILLA_GPG_TMPHOME="$(mktemp -d)"
  trap 'rm -rf "$MOZILLA_GPG_TMPHOME"' EXIT

  MOZILLA_EXPECTED_FPR="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"
  MOZILLA_ACTUAL_FPR="$(
    GNUPGHOME="$MOZILLA_GPG_TMPHOME" gpg -n -q --import --import-options import-show \
      /etc/apt/keyrings/packages.mozilla.org.asc \
      | awk '/pub/{getline; gsub(/^ +| +$/,""); print; exit}'
  )" || true

  rm -rf "$MOZILLA_GPG_TMPHOME"
  trap - EXIT

  if [[ "$MOZILLA_ACTUAL_FPR" == "$MOZILLA_EXPECTED_FPR" ]]; then
    ok "Huella digital de la clave de Mozilla verificada correctamente."
    MOZILLA_KEY_OK=1
  else
    warn "ERROR: la huella digital de la clave de Mozilla NO coincide."
    warn "  Esperada: $MOZILLA_EXPECTED_FPR"
    warn "  Obtenida: ${MOZILLA_ACTUAL_FPR:-<vacía>}"
    warn "Por seguridad, se aborta este paso."
    sudo rm -f /etc/apt/keyrings/packages.mozilla.org.asc
    MOZILLA_KEY_OK=0
  fi

  if [[ "$MOZILLA_KEY_OK" -eq 1 ]]; then
    MOZILLA_SOURCES="/etc/apt/sources.list.d/mozilla.sources"
    sudo tee "$MOZILLA_SOURCES" >/dev/null <<'EOF'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
EOF
    ok "Repositorio de Mozilla escrito en $MOZILLA_SOURCES (formato deb822)."

    sudo tee /etc/apt/preferences.d/mozilla >/dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

    sudo apt update
    sudo apt install -y firefox

    FIREFOX_L10N_CANDIDATES=(firefox-l10n-es-es firefox-l10n-es-mx firefox-l10n-es-ar firefox-l10n-es)
    FIREFOX_L10N_PKG=""
    for pkg in "${FIREFOX_L10N_CANDIDATES[@]}"; do
      if apt-cache show "$pkg" >/dev/null 2>&1; then
        FIREFOX_L10N_PKG="$pkg"
        break
      fi
    done

    if confirm "¿Instalar también el paquete de idioma español${FIREFOX_L10N_PKG:+ ($FIREFOX_L10N_PKG)}?"; then
      if [[ -n "$FIREFOX_L10N_PKG" ]]; then
        sudo apt install -y "$FIREFOX_L10N_PKG"
      else
        warn "No se encontró ningún paquete de idioma español disponible (se probó: ${FIREFOX_L10N_CANDIDATES[*]})."
      fi
    fi

    ok "Firefox de Mozilla instalado. Comprueba la versión con: firefox --version"

    if [[ ${#PRE_MIGRATION_PROFILE_DIRS[@]} -gt 0 ]]; then
      PROFILE_LIST="$(printf '  - %s\n' "${PRE_MIGRATION_PROFILE_DIRS[@]}")"
      if confirm "Se ha(n) detectado carpeta(s) de perfil de Firefox de antes de esta instalación (pertenecen a ESR, aunque no tengan \"esr\" en el nombre):\n\n${PROFILE_LIST}\n\nSi las dejas, herramientas como AutoFirma pueden seguir usando ese perfil antiguo como referencia en vez del perfil nuevo de Firefox release.\n\nAVISO: esto borra marcadores, contraseñas guardadas, historial y extensiones de ese perfil. Es irreversible.\n\n¿Eliminar también esa(s) carpeta(s)?" 20 78; then
        REMOVED_PROFILE_NAMES=()
        for dir in "${PRE_MIGRATION_PROFILE_DIRS[@]}"; do
          rm -rf -- "$dir"
          ok "Perfil antiguo eliminado: $dir"
          REMOVED_PROFILE_NAMES+=("$(basename -- "$dir")")
        done
        _cleanup_profiles_ini "$MOZILLA_PROFILES_INI" "${REMOVED_PROFILE_NAMES[@]}"
      else
        warn "Se conserva(n) el/los perfil(es) antiguos."
      fi
    fi
  fi
else
  warn "Se omite la sustitución de Firefox."

  # Aunque no se elija sustituir Firefox en esta corrida, si quedaron
  # carpetas de perfil huérfanas de una ejecución anterior (ESR ya
  # desinstalado, pero perfil sin borrar) conviene avisarlo igual.
  if [[ -d "$MOZILLA_PROFILES_DIR" ]] && ! dpkg -s firefox-esr >/dev/null 2>&1 \
     && dpkg -s firefox >/dev/null 2>&1; then
    warn "Firefox ESR no está instalado y Firefox release sí, pero no se comprobó si quedan perfiles huérfanos en $MOZILLA_PROFILES_DIR (se omitió por elección del usuario). Revisalo manualmente si AutoFirma u otra herramienta agarra el perfil equivocado."
  fi
fi

# ----------------------------------------------------------------------
# 8. Driver NVIDIA (opcional)
# ----------------------------------------------------------------------
#
# Mismo patrón que en setup-debian-trixie.sh y setup-debian-testing.sh:
# detectar -> preguntar -> instalar por repo oficial (cuda-keyring), sin
# pinear versión.
#
# NOTA sobre el repo: NVIDIA publica el keyring/repo CUDA por versión de
# Debian estable (p. ej. "debian13"), no existe una rama "sid" dedicada.
# Se usa aquí el paquete de debian13 -- es la combinación ya probada y
# en uso, la misma que en trixie/testing; si en el futuro deja de
# funcionar, revisa la URL vigente en
# https://developer.download.nvidia.com/compute/cuda/repos/ y ajusta
# NVIDIA_KEYRING_URL más abajo.
#
# LIMITACIÓN CONOCIDA: "nvidia-open" solo soporta GPUs Turing en
# adelante (RTX 20xx, GTX 16xx, y más recientes). El script no
# distingue el modelo concreto, solo detecta "es NVIDIA".
#
# Secure Boot / MOK enrollment queda deliberadamente FUERA de este
# script: solo se detecta y se avisa, remitiendo a MANUAL.md.

NVIDIA_KEYRING_URL="https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb"

GPU_INFO="$(lspci | grep -Ei 'vga|3d' || true)"

if echo "$GPU_INFO" | grep -qi nvidia; then
  NVIDIA_LINE="$(echo "$GPU_INFO" | grep -i nvidia)"

  if confirm "GPU NVIDIA detectada:\n  ${NVIDIA_LINE}\n\nAviso: este paso instala 'nvidia-open', el módulo de kernel de código abierto de NVIDIA, vía el repositorio CUDA oficial de NVIDIA (rama debian13, la combinación usada y probada también en trixie/testing). Solo soporta GPUs Turing en adelante (RTX 20xx, GTX 16xx, RTX 30xx/40xx/50xx...). En una GPU más antigua (GTX 10xx y anteriores) este driver no cargará; en ese caso necesitarías el paquete 'nvidia-driver' (propietario clásico) en su lugar. El script no comprueba el modelo concreto, solo que el fabricante sea NVIDIA.\n\n¿Instalar el driver NVIDIA (nvidia-open, última versión disponible en el repo)?" 22 76; then

    if ! dpkg -s cuda-keyring >/dev/null 2>&1; then
      log "Añadiendo el repositorio de NVIDIA (cuda-keyring)..."
      NVIDIA_KEYRING_TMP="$(mktemp --suffix=.deb)"
      wget -qO "$NVIDIA_KEYRING_TMP" "$NVIDIA_KEYRING_URL"
      sudo dpkg -i "$NVIDIA_KEYRING_TMP"
      rm -f "$NVIDIA_KEYRING_TMP"
      sudo apt update
    else
      ok "El repositorio de NVIDIA (cuda-keyring) ya está instalado."
    fi

    # Pin de origen para el repo NVIDIA CUDA (mismo patrón que Mozilla en
    # la sección 7). Sin esto, paquetes como nvidia-driver-libs también
    # existen de forma nativa en el repo non-free de Debian con una
    # versión distinta; sin pin explícito, APT podría resolver algún
    # paquete del stack NVIDIA desde un origen distinto al resto,
    # mezclando versiones entre el módulo de kernel y las librerías.
    log "Fijando el repositorio de NVIDIA como origen preferente para el stack nvidia-*..."
    sudo tee /etc/apt/preferences.d/nvidia-cuda >/dev/null <<'EOF'
Package: nvidia-* libnvidia-*
Pin: origin developer.download.nvidia.com
Pin-Priority: 1000
EOF

    log "Instalando el driver NVIDIA (sin pinear versión -> se resuelve la más reciente del repo, ahora con origen fijado)..."
    sudo dpkg --add-architecture i386
    sudo apt update
    sudo apt install -y \
      linux-headers-amd64 \
      firmware-misc-nonfree \
      dkms \
      nvidia-open \
      nvidia-kernel-open-dkms \
      nvidia-settings \
      libvulkan-dev \
      nvidia-vulkan-icd \
      vulkan-tools \
      vulkan-validationlayers \
      nvidia-driver-libs:i386 \
      nvidia-vaapi-driver

    log "Deshabilitando el driver nouveau..."
    sudo tee /etc/modprobe.d/blacklist-nouveau.conf >/dev/null <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF

    log "Configurando GRUB para KMS de NVIDIA..."
    NVIDIA_GRUB_BACKUP="/etc/default/grub.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp /etc/default/grub "$NVIDIA_GRUB_BACKUP"
    ok "Copia de seguridad: $NVIDIA_GRUB_BACKUP"

    NVIDIA_GRUB_PARAMS=(nvidia-drm.modeset=1 nvidia-drm.fbdev=1)
    CURRENT_CMDLINE="$(grep -oP '^GRUB_CMDLINE_LINUX_DEFAULT="\K[^"]*' /etc/default/grub || true)"

    NEW_CMDLINE="$CURRENT_CMDLINE"
    for param in "${NVIDIA_GRUB_PARAMS[@]}"; do
      key="${param%%=*}"
      if [[ "$NEW_CMDLINE" != *"$key"* ]]; then
        NEW_CMDLINE="${NEW_CMDLINE:+$NEW_CMDLINE }${param}"
      fi
    done

    if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub; then
      sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_CMDLINE}\"|" /etc/default/grub
    else
      echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${NEW_CMDLINE}\"" | sudo tee -a /etc/default/grub >/dev/null
    fi
    ok "GRUB_CMDLINE_LINUX_DEFAULT resultante: ${NEW_CMDLINE}"

    sudo update-grub
    sudo update-initramfs -u

    log "Habilitando servicios de suspensión/hibernación de NVIDIA..."
    for svc in nvidia-suspend.service nvidia-hibernate.service nvidia-resume.service; do
      if sudo systemctl enable "$svc" 2>/dev/null; then
        ok "Servicio habilitado: $svc"
      else
        warn "Servicio $svc no disponible en este empaquetado del driver, se omite."
      fi
    done

    NVIDIA_INSTALLED=1

    if command -v mokutil >/dev/null 2>&1 && mokutil --sb-state 2>/dev/null | grep -qi "enabled"; then
      warn "Secure Boot está ACTIVADO en este sistema."
      warn "El módulo del kernel de NVIDIA no cargará hasta que firmes la clave MOK."
      warn "Este paso es manual (requiere reiniciar y confirmar en el MOK Manager)."
      warn "Consulta la sección 'Secure Boot / NVIDIA' en MANUAL.md ANTES de reiniciar."
    fi
  else
    warn "Se omite la instalación del driver NVIDIA."
  fi
fi

# ----------------------------------------------------------------------
# 9. switcheroo-control (gestión de GPU híbrida, opcional)
# ----------------------------------------------------------------------

GPU_COUNT="$(echo "$GPU_INFO" | grep -c . || true)"

if [[ "$GPU_COUNT" -ge 2 ]]; then
  GPU_LIST="$(echo "$GPU_INFO" | sed 's/^/  /')"
  if confirm "Se han detectado $GPU_COUNT controladores de vídeo (GPU híbrida: integrada + dedicada):\n\n${GPU_LIST}\n\n¿Instalar switcheroo-control para gestionar el cambio de GPU?" 18 76; then
    if dpkg -s switcheroo-control >/dev/null 2>&1; then
      ok "switcheroo-control ya está instalado."
    else
      sudo apt install -y switcheroo-control
    fi
    sudo systemctl enable --now switcheroo-control
    ok "switcheroo-control instalado y activo. Comprueba las GPUs detectadas con: switcherooctl list"
    SWITCHEROO_INSTALLED=1
  else
    warn "Se omite la instalación de switcheroo-control."
  fi
fi

# ----------------------------------------------------------------------
# 10. Resumen final
# ----------------------------------------------------------------------

cat <<EOF

Instalación completada.

CPU detectada: ${CPU_MODEL_NAME}

Notas específicas de Sid:
  - Sid NO tiene equipo de seguridad dedicado: los parches de seguridad
    llegan directamente por "unstable", a través de sus mantenedores de
    paquetes. Mantén el sistema actualizado con regularidad.
  - El "apt full-upgrade" en Sid no es un paso puntual: es la forma
    normal de mantener el sistema. Ejecútalo con frecuencia.
  - Si algún día quieres volver a stable/testing, es más delicado que
    en trixie: no es solo cambiar el sources.list, puede implicar
    downgrades forzados o reinstalar. Piénsalo como un cambio de
    sentido único.

Notas generales:
  - fd-find se instala como binario "fdfind", no "fd". Si lo quieres
    como "fd":
      mkdir -p ~/.local/bin
      ln -s "\$(command -v fdfind)" ~/.local/bin/fd

  - Puede que haga falta reiniciar sesión (o el sistema) para que
    algunos cambios de firmware/microcode surtan efecto.

  - GNOME Disk Utility instalado (comando: gnome-disks) como
    herramienta de gestión de discos/particiones.

  - Si configuraste zram, comprueba su estado con:
      zramswap status
      swapon --show
    El tamaño se calculó automáticamente a partir de tu RAM total
    (${TOTAL_RAM_MB:-desconocida} MiB detectados -> ${ZRAM_SIZE_MB:-N/A} MiB de zram).
    Si además ajustaste vm.swappiness, comprueba el valor activo con:
      sudo sysctl vm.swappiness

  - Si instalaste Firefox desde el repositorio de Mozilla, comprueba
    la versión con: firefox --version (debería ser una versión release,
    no "esr" en el nombre).

  - Si instalaste las fuentes de Windows, ya están disponibles para
    cualquier aplicación (LibreOffice, navegadores, etc.).

  - Si el script detectó y comentó contenido en /etc/apt/sources.list
    (típico de una instalación desde la ISO oficial), tienes la copia
    original en /etc/apt/sources.list.bak.<fecha> por si quieres
    revisarla o revertir el cambio.
EOF

if [[ "${ESR_PROFILES_REMOVED:-0}" -eq 1 ]]; then
  cat <<'EOF'

  - Se eliminó también la carpeta del perfil de Firefox ESR en $HOME.
    Al abrir el Firefox nuevo se creará un perfil limpio desde cero
    (sin marcadores/contraseñas del ESR anterior).
EOF
fi

if [[ "${NVIDIA_INSTALLED:-0}" -eq 1 ]]; then
  cat <<'EOF'

  - Driver NVIDIA instalado (nvidia-open, última versión del repo),
    junto con librerías de 32 bits (nvidia-driver-libs:i386, para
    Steam/Proton) y nvidia-vaapi-driver (aceleración de vídeo por
    hardware en navegadores). El repo NVIDIA CUDA (rama debian13) se
    fijó como origen preferente para todo el stack nvidia-*/libnvidia-*
    (ver /etc/apt/preferences.d/nvidia-cuda).
    Reinicia para que cargue el nuevo driver. Si tienes Secure Boot
    activado, no reinicies sin antes seguir la sección 'Secure Boot /
    NVIDIA' de MANUAL.md (enrollment de la clave MOK).
    Verifica tras reiniciar con: nvidia-smi
EOF
fi

if [[ "${SWITCHEROO_INSTALLED:-0}" -eq 1 ]]; then
  cat <<'EOF'

  - switcheroo-control instalado y activo (gestión de GPU híbrida).
    Comprueba las GPUs detectadas con: switcherooctl list
EOF
fi

if [[ ${#FAILED_GROUPS[@]:-0} -gt 0 ]]; then
  echo
  echo "  - ATENCIÓN: los siguientes grupos de paquetes fallaron durante la"
  echo "    instalación y se omitieron (revisá el log de arriba y reintentá"
  echo "    a mano con 'sudo apt install <paquetes>'):"
  printf '      · %s\n' "${FAILED_GROUPS[@]}"
fi

echo "Detalles completos de cada paso en MANUAL.md."

if [[ "$ASSUME_YES" -ne 1 ]]; then
  if [[ "${NVIDIA_INSTALLED:-0}" -eq 1 ]]; then
    if whiptail --title "$TITLE" \
        --yes-button "Reiniciar ahora" --no-button "Reiniciar después" \
        --yesno "Instalación completada.\n\nSe instaló el driver NVIDIA: hace falta reiniciar para que cargue.\n\n¿Reiniciar ahora?" 14 70; then
      sudo reboot
    else
      ok "Recuerda reiniciar manualmente para que el driver NVIDIA entre en uso."
    fi
  else
    whiptail --title "$TITLE" --msgbox "Instalación completada.\n\nRevisa el resumen impreso en la terminal para los detalles y próximos pasos." 12 70
  fi
fi
