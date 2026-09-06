#!/usr/bin/env bash
#
# setup-debian-sid.sh
#
# Script de configuración inicial para Debian Unstable (Sid) con KDE Plasma.
# Configura los repositorios oficiales (deb822) apuntando a unstable,
# actualiza el sistema, instala un set de paquetes de desarrollo/
# multimedia/sistema, el microcode correcto según el fabricante de CPU,
# y añade el remoto de Flathub.
#
# IMPORTANTE: este script asume que ya tienes un sistema Debian instalado
# y funcionando (siguiendo, por ejemplo, el método recomendado por la
# wiki de Debian: instalar stable mínimo y luego cambiar los repos a
# unstable, o instalar directamente con el mini.iso eligiendo el mirror
# "sid - unstable"). Este script NO instala Debian por ti.
#
# Uso:
#   chmod +x setup-debian-sid.sh
#   ./setup-debian-sid.sh          # modo interactivo (pide confirmación)
#   ./setup-debian-sid.sh -y       # modo no interactivo (asume "sí" en todo)
#
# Licencia: MIT

set -euo pipefail

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
      echo "  -y, --yes   No pedir confirmación (modo no interactivo)."
      exit 0
      ;;
    *)
      echo "Opción desconocida: $1" >&2
      exit 1
      ;;
  esac
done

confirm() {
  local prompt="$1"
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  local ans
  read -rp "$prompt [y/N] " ans
  [[ "${ans,,}" == "y" ]]
}

if [[ "$ASSUME_YES" -eq 1 ]]; then
  export DEBIAN_FRONTEND=noninteractive
fi

# ----------------------------------------------------------------------
# 1. Comprobaciones previas
# ----------------------------------------------------------------------

if [[ $EUID -eq 0 ]]; then
  echo "No ejecutes este script directamente como root. Usa un usuario normal;" \
       "se te pedirá la contraseña de sudo cuando haga falta." >&2
  exit 1
fi

if ! command -v apt >/dev/null 2>&1; then
  echo "Este script está pensado para sistemas basados en APT (Debian/derivados)." >&2
  exit 1
fi

if ! command -v sudo >/dev/null 2>&1; then
  echo "No se encontró el comando 'sudo' en este sistema." >&2
  exit 1
fi

echo "Comprobando permisos de sudo..."
if ! sudo -v; then
  echo "No se pudieron validar los permisos de sudo." >&2
  exit 1
fi

# En Sid, VERSION_CODENAME en /etc/os-release NO es fiable: suele venir
# vacío, o PRETTY_NAME muestra algo como "Debian GNU/Linux trixie/sid"
# en vez de un codename limpio "sid"/"unstable". Por eso, en vez de
# comparar ese campo como en la versión trixie, se avisa y se pide
# confirmación manual de que los repos ya apuntan a unstable.
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  if [[ "${VERSION_CODENAME:-}" != "sid" && "${VERSION_CODENAME:-}" != "unstable" ]]; then
    echo "Aviso: este script está pensado para Debian Unstable (Sid)."
    echo "  Detectado: ${PRETTY_NAME:-desconocido} (VERSION_CODENAME='${VERSION_CODENAME:-vacío}')"
    echo "  Esto es normal en Sid: el campo VERSION_CODENAME no siempre es" \
         "fiable ahí. Antes de continuar, confirma tú mismo que tus repos" \
         "ya apuntan a unstable (revisa /etc/apt/sources.list.d/*.sources" \
         "o /etc/apt/sources.list)."
    confirm "¿Confirmas que este sistema ya apunta a unstable/sid?" || exit 1
  fi
fi

# ----------------------------------------------------------------------
# 2. Repositorios (formato deb822) — apuntando a unstable
# ----------------------------------------------------------------------

LEGACY_SOURCES="/etc/apt/sources.list"
SOURCES_FILE="/etc/apt/sources.list.d/debian.sources"

if [[ -f "$LEGACY_SOURCES" ]] && grep -qE '^\s*deb(-src)?\s' "$LEGACY_SOURCES"; then
  echo "Se ha detectado contenido activo en $LEGACY_SOURCES."
  echo "Para evitar repositorios duplicados, se comentará su contenido," \
       "dejando que $SOURCES_FILE (creado a continuación) sea la única" \
       "fuente de los repos oficiales de Debian."
  if confirm "¿Continuar? (se guarda una copia de seguridad antes de tocar nada)"; then
    LEGACY_BACKUP="${LEGACY_SOURCES}.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$LEGACY_SOURCES" "$LEGACY_BACKUP"
    echo "Copia de seguridad: $LEGACY_BACKUP"
    sudo sed -i -E '/^\s*deb(-src)?\s/ s/^/# desactivado por setup-debian-sid.sh -- /' "$LEGACY_SOURCES"
    echo "Contenido de $LEGACY_SOURCES comentado."
  else
    echo "Se omite la limpieza de $LEGACY_SOURCES. Es probable que 'apt update'" \
         "muestre avisos de repos duplicados."
  fi
fi

if [[ -f "$SOURCES_FILE" ]]; then
  # Auto-reparación de un bug conocido de versiones anteriores de este
  # script: "unstable-updates" no es una suite real en el archivo de
  # Debian (ver wiki.debian.org/SourcesList) y provoca un error 404 en
  # "apt update". Si el fichero ya existente todavía la incluye, se
  # corrige automáticamente en vez de solo avisar, para que máquinas ya
  # instaladas con la versión antigua del script queden arregladas sin
  # pasos manuales.
  if grep -qE '^Suites:.*unstable-updates' "$SOURCES_FILE"; then
    echo "Se ha detectado el bug conocido de 'unstable-updates' en $SOURCES_FILE."
    SOURCES_BACKUP="${SOURCES_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$SOURCES_FILE" "$SOURCES_BACKUP"
    echo "Copia de seguridad: $SOURCES_BACKUP"
    sudo sed -i -E 's/^(Suites:\s*unstable)\s+unstable-updates\s*$/\1/' "$SOURCES_FILE"
    echo "Corregido automáticamente: $SOURCES_FILE ahora solo apunta a 'unstable'."
  else
    echo "Ya existe $SOURCES_FILE y no presenta el bug conocido; no se sobrescribe."
  fi
else
  echo "Escribiendo $SOURCES_FILE ..."
  # Nota: a diferencia de stable, Sid NO tiene suite de seguridad separada
  # (los fixes de seguridad llegan directamente por "unstable") ni suite
  # de backports (unstable ya es lo más nuevo). Tampoco existe una suite
  # real de "unstable-updates" en el archivo de Debian: al ser unstable
  # la rama rolling, no tiene sentido un canal aparte de actualizaciones
  # puntuales (ver wiki.debian.org/SourcesList: "not meaningful for the
  # rolling development version"). Por eso aquí solo se usa "unstable".
  sudo tee "$SOURCES_FILE" >/dev/null <<'EOF'
Types: deb
URIs: https://deb.debian.org/debian
Suites: unstable
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
fi

echo "Actualizando índices de paquetes..."
sudo apt update

# En Sid el full-upgrade no es un paso puntual: es la forma normal de
# mantener el sistema. Aquí se pregunta igualmente por consistencia con
# el resto del script, pero tenlo presente para el uso diario.
if confirm "¿Quieres hacer 'apt full-upgrade' antes de continuar?"; then
  sudo apt full-upgrade -y
else
  echo "Se omite full-upgrade. Puedes ejecutarlo luego con: sudo apt full-upgrade"
fi

# ----------------------------------------------------------------------
# 3. Detección de CPU para el microcode correcto
# ----------------------------------------------------------------------

CPU_VENDOR="$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $NF}')"

case "$CPU_VENDOR" in
  GenuineIntel)
    MICROCODE_PKG="intel-microcode"
    ;;
  AuthenticAMD)
    MICROCODE_PKG="amd64-microcode"
    ;;
  *)
    echo "Aviso: no se ha podido determinar el fabricante de CPU (vendor_id='$CPU_VENDOR')." \
         "No se instalará ningún paquete de microcode automáticamente."
    MICROCODE_PKG=""
    ;;
esac

if [[ -n "$MICROCODE_PKG" ]]; then
  echo "CPU detectada: $CPU_VENDOR -> se instalará $MICROCODE_PKG"
fi

# ----------------------------------------------------------------------
# 4. Lista de paquetes
# ----------------------------------------------------------------------

# El paquete "7zip" (7-Zip oficial) es relativamente reciente en el
# archivo de Debian; en Sid debería estar disponible, pero por
# seguridad se comprueba en tiempo de ejecución y, si no existe, se cae
# de vuelta a "p7zip-full" (el paquete tradicional con la misma
# funcionalidad) en vez de dejar que todo el "apt install" falle por un
# único paquete no encontrado.
if apt-cache show 7zip >/dev/null 2>&1; then
  ARCHIVE_PACKAGES=(unzip zip 7zip)
else
  echo "Aviso: el paquete '7zip' no está disponible en tus repos; se usará 'p7zip-full' en su lugar."
  ARCHIVE_PACKAGES=(unzip zip p7zip-full)
fi

PACKAGES=(
  # Control de versiones / descargas
  git git-lfs curl wget

  # Compresión
  "${ARCHIVE_PACKAGES[@]}"

  # Sistema / diagnóstico
  btop fastfetch tree jq
  ripgrep fd-find
  pciutils usbutils lshw dmidecode inxi hwinfo
  lm-sensors acpi

  # Desarrollo / compilación
  build-essential gcc g++ make
  cmake ninja-build pkg-config
  autoconf automake libtool
  openssh-client

  # Multimedia
  ffmpeg
  gstreamer1.0-libav
  gstreamer1.0-plugins-good
  gstreamer1.0-plugins-bad
  gstreamer1.0-plugins-ugly
  pavucontrol

  # Firmware (metapaquete: arrastra todo el firmware no libre disponible;
  # si prefieres algo más quirúrgico, identifica lo tuyo con: lspci -k)
  firmware-linux

  # Gestión de paquetes (interfaz gráfica)
  synaptic
  gdebi

  # Flatpak + integración con Discover (KDE Plasma)
  flatpak
  plasma-discover-backend-flatpak
)

if [[ -n "$MICROCODE_PKG" ]]; then
  PACKAGES+=("$MICROCODE_PKG")
fi

echo
echo "Se van a instalar los siguientes paquetes:"
printf '  - %s\n' "${PACKAGES[@]}"
echo
confirm "¿Continuar con la instalación?" || { echo "Instalación cancelada por el usuario."; exit 0; }

sudo apt install -y "${PACKAGES[@]}"

# ----------------------------------------------------------------------
# 5. Flathub
# ----------------------------------------------------------------------

if ! flatpak remote-list | grep -q '^flathub'; then
  echo "Añadiendo el remoto de Flathub..."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
else
  echo "El remoto de Flathub ya está configurado."
fi

# ----------------------------------------------------------------------
# 5b. ZRAM (swap comprimido en RAM, tamaño automático según RAM total)
# ----------------------------------------------------------------------
#
# El tamaño del zram se calcula automáticamente como la mitad de la RAM
# total del sistema (regla práctica habitual): 8 GB de RAM -> 4 GB de
# zram, 16 GB -> 8 GB, 32 GB -> 16 GB, etc. Se detecta en tiempo de
# ejecución a partir de /proc/meminfo, así que el script se adapta a la
# máquina donde se ejecute sin necesidad de tocar nada a mano.

TOTAL_RAM_KB="$(grep -m1 '^MemTotal:' /proc/meminfo | awk '{print $2}')"
TOTAL_RAM_MB=$(( TOTAL_RAM_KB / 1024 ))
ZRAM_SIZE_MB=$(( TOTAL_RAM_MB / 2 ))

# Salvaguarda: si por lo que sea no se pudo leer /proc/meminfo o el
# cálculo da 0, no se propone zram en vez de configurar un tamaño inválido.
if [[ -z "$TOTAL_RAM_KB" || "$ZRAM_SIZE_MB" -le 0 ]]; then
  echo
  echo "Aviso: no se ha podido determinar la RAM total del sistema; se omite la configuración de zram."
else
  echo
  echo "RAM total detectada: ${TOTAL_RAM_MB} MiB -> zram propuesto: ${ZRAM_SIZE_MB} MiB (mitad de la RAM)"
  if confirm "¿Configurar zram (swap comprimido en RAM) con ${ZRAM_SIZE_MB} MiB?"; then
    if ! dpkg -s zram-tools >/dev/null 2>&1; then
      echo "Instalando zram-tools..."
      sudo apt install -y zram-tools
    else
      echo "zram-tools ya está instalado."
    fi

    ZRAM_CONF="/etc/default/zramswap"

    if [[ -f "$ZRAM_CONF" ]]; then
      ZRAM_BACKUP="${ZRAM_CONF}.bak.$(date +%Y%m%d%H%M%S)"
      sudo cp "$ZRAM_CONF" "$ZRAM_BACKUP"
      echo "Copia de seguridad de la configuración previa: $ZRAM_BACKUP"

      if grep -q '^#\?SIZE=' "$ZRAM_CONF"; then
        SIZE_VAR="SIZE"
      elif grep -q '^#\?ALLOCATION=' "$ZRAM_CONF"; then
        SIZE_VAR="ALLOCATION"
      else
        SIZE_VAR=""
      fi

      if [[ -n "$SIZE_VAR" ]]; then
        # Solo comenta PERCENT/PERCENTAGE si la línea está activa (sin '#'
        # ya al principio); así, si se vuelve a ejecutar el script sobre
        # una configuración ya comentada, no se acumulan varios '#'.
        sudo sed -i -E "/^(PERCENT|PERCENTAGE)=/ s/^/#/" "$ZRAM_CONF"

        if grep -q "^${SIZE_VAR}=" "$ZRAM_CONF"; then
          sudo sed -i "s/^${SIZE_VAR}=.*/${SIZE_VAR}=${ZRAM_SIZE_MB}/" "$ZRAM_CONF"
        else
          sudo sed -i "s/^#${SIZE_VAR}=.*/${SIZE_VAR}=${ZRAM_SIZE_MB}/" "$ZRAM_CONF"
        fi

        echo "Configurado ${SIZE_VAR}=${ZRAM_SIZE_MB} (${ZRAM_SIZE_MB} MiB) en $ZRAM_CONF"
        sudo systemctl restart zramswap.service 2>/dev/null || sudo service zramswap restart

        echo "Estado actual del zram:"
        zramctl 2>/dev/null || true
        swapon --show 2>/dev/null || true
      else
        echo "Aviso: no se reconoció el formato de $ZRAM_CONF. Revísalo a mano:" \
             "https://wiki.debian.org/ZRam"
      fi
    else
      echo "Aviso: no se encontró $ZRAM_CONF tras instalar zram-tools." \
           "Revisa manualmente: https://wiki.debian.org/ZRam"
    fi
  else
    echo "Se omite la configuración de zram."
  fi
fi

# ----------------------------------------------------------------------
# 5c. Firefox oficial de Mozilla (sustituye a Firefox ESR, opcional)
# ----------------------------------------------------------------------
#
# Debian, incluso en Sid, solo empaqueta "firefox-esr" en su archivo
# oficial (no distribuye la versión release de Mozilla por su política
# de marca). Este paso, opcional, lo sustituye por el Firefox oficial
# de Mozilla vía su propio repositorio APT:
# https://support.mozilla.org/kb/install-firefox-linux
# En Sid siempre se usa formato deb822 (no hace falta la rama de
# compatibilidad con bookworm/bullseye de la versión trixie del script).

echo
if confirm "¿Sustituir Firefox ESR de Debian por Firefox oficial del repositorio de Mozilla?"; then

  FIREFOX_ESR_PKGS=()
  for pkg in firefox-esr firefox-esr-l10n-es; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      FIREFOX_ESR_PKGS+=("$pkg")
    fi
  done
  if [[ ${#FIREFOX_ESR_PKGS[@]} -gt 0 ]]; then
    echo "Quitando Firefox ESR: ${FIREFOX_ESR_PKGS[*]}"
    sudo apt remove -y "${FIREFOX_ESR_PKGS[@]}"
  else
    echo "Firefox ESR no estaba instalado; se continúa igualmente."
  fi

  if ! command -v gpg >/dev/null 2>&1; then
    echo "Instalando gnupg (necesario para verificar la clave de Mozilla)..."
    sudo apt install -y gnupg
  fi

  sudo install -d -m 0755 /etc/apt/keyrings
  wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- \
    | sudo tee /etc/apt/keyrings/packages.mozilla.org.asc >/dev/null

  MOZILLA_GPG_TMPHOME="$(mktemp -d)"

  MOZILLA_EXPECTED_FPR="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"
  MOZILLA_ACTUAL_FPR="$(
    GNUPGHOME="$MOZILLA_GPG_TMPHOME" gpg -n -q --import --import-options import-show \
      /etc/apt/keyrings/packages.mozilla.org.asc \
      | awk '/pub/{getline; gsub(/^ +| +$/,""); print; exit}'
  )"

  # Limpieza inmediata del directorio temporal de GPG: no hace falta un
  # trap (RETURN solo se dispara al salir de una función/script cargado
  # con "source", no aquí en el cuerpo principal), basta con borrarlo en
  # cuanto se ha extraído la huella digital.
  rm -rf "$MOZILLA_GPG_TMPHOME"

  if [[ "$MOZILLA_ACTUAL_FPR" == "$MOZILLA_EXPECTED_FPR" ]]; then
    echo "Huella digital de la clave de Mozilla verificada correctamente."
    MOZILLA_KEY_OK=1
  else
    echo "ERROR: la huella digital de la clave de Mozilla NO coincide." >&2
    echo "  Esperada: $MOZILLA_EXPECTED_FPR" >&2
    echo "  Obtenida: ${MOZILLA_ACTUAL_FPR:-<vacía>}" >&2
    echo "Por seguridad, se aborta este paso." >&2
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
    echo "Repositorio de Mozilla escrito en $MOZILLA_SOURCES (formato deb822)."

    sudo tee /etc/apt/preferences.d/mozilla >/dev/null <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

    sudo apt update
    sudo apt install -y firefox

    # Los paquetes de idioma de Mozilla no usan el código de 2 letras a
    # secas: van por variante regional (es-es, es-ar, es-mx...), igual
    # que ya hace Debian con firefox-esr-l10n-*. "firefox-l10n-es" no
    # existe de verdad; se comprueba en tiempo de ejecución cuál sí,
    # empezando por la variante de España.
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
        echo "Aviso: no se encontró ningún paquete de idioma español disponible" \
             "(se probó: ${FIREFOX_L10N_CANDIDATES[*]}). Busca el nombre exacto con:" \
             "apt-cache search firefox-l10n"
      fi
    fi

    echo "Firefox de Mozilla instalado. Comprueba la versión con: firefox --version"
  fi
else
  echo "Se omite la sustitución de Firefox."
fi

# ----------------------------------------------------------------------
# 6. Notas finales
# ----------------------------------------------------------------------

cat <<EOF

Instalación completada.

Notas específicas de Sid:
  - Sid NO tiene equipo de seguridad dedicado: los parches de seguridad
    llegan directamente por "unstable", a través de sus mantenedores.
    Mantén el sistema actualizado con regularidad.
  - El "apt full-upgrade" en Sid no es un paso puntual: es la forma
    normal de mantener el sistema. Ejecútalo con frecuencia.
  - Si algún día quieres volver a stable, es más delicado que en Trixie:
    no es solo cambiar el sources.list, puede implicar downgrades
    forzados o reinstalar. Piénsalo como un cambio de sentido único.

Notas generales (igual que en la versión trixie):
  - fd-find se instala como binario "fdfind", no "fd". Si lo quieres
    como "fd":
      mkdir -p ~/.local/bin
      ln -s "\$(command -v fdfind)" ~/.local/bin/fd

  - Puede que haga falta reiniciar sesión (o el sistema) para que
    algunos cambios de firmware/microcode surtan efecto.

  - Si configuraste zram, comprueba su estado con:
      zramswap status
      swapon --show
    El tamaño se calculó automáticamente a partir de tu RAM total
    (${TOTAL_RAM_MB:-desconocida} MiB detectados -> ${ZRAM_SIZE_MB:-N/A} MiB de zram).

  - Si instalaste Firefox desde el repositorio de Mozilla, comprueba
    la versión con: firefox --version (debería ser una versión release,
    no "esr" en el nombre).

  - Si el script detectó y comentó contenido en /etc/apt/sources.list,
    tienes la copia original en /etc/apt/sources.list.bak.<fecha>.
EOF
