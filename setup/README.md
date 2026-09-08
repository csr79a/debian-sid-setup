# setup-debian-sid.sh

Configura un sistema **Debian Unstable (Sid)** recién instalado con KDE
Plasma: repositorios en formato deb822 apuntando a `unstable`,
actualización del sistema, un set de paquetes de desarrollo/multimedia/
sistema, microcode de CPU, Flathub, zram y (opcional) Firefox oficial de
Mozilla. Es el complemento de `cleanup-debian-sid.sh`: este script
instala, aquel quita.

> Este script **no instala Debian** ni migra un sistema de stable a Sid.
> Asume que ya tienes un Debian funcionando con los repos apuntando a
> unstable.

---

## Índice

- [Qué hace](#qué-hace)
- [Uso](#uso)
- [Repositorios](#repositorios)
- [Paquetes que instala](#paquetes-que-instala)
- [Microcode](#microcode)
- [Flathub](#flathub)
- [Zram automático](#zram-automático)
- [Firefox oficial de Mozilla (opcional)](#firefox-oficial-de-mozilla-opcional)
- [Idempotencia](#idempotencia)
- [Licencia](#licencia)

---

## Qué hace

1. Comprueba `sudo`, que estés en un sistema basado en APT y que no
   estés ejecutando el script como root.
2. Avisa si `VERSION_CODENAME` no indica `sid`/`unstable` (recuerda que
   en Sid ese campo no siempre es fiable) y pide confirmación manual.
3. Si detecta contenido activo en el `/etc/apt/sources.list` clásico,
   hace una copia de seguridad y lo comenta, para evitar repos
   duplicados con el nuevo fichero deb822.
4. Escribe `/etc/apt/sources.list.d/debian.sources` apuntando solo a
   `unstable` (sin `-security`, `-backports` ni `-updates`: ninguna de
   esas suites existe de verdad para Sid en el archivo de Debian).
5. Actualiza índices (`apt update`) y, si confirmas, hace
   `apt full-upgrade`.
6. Detecta el fabricante de CPU (Intel/AMD) e instala el paquete de
   microcode correspondiente.
7. Instala la lista de paquetes (ver tabla abajo).
8. Añade el remoto de Flathub si no estaba ya configurado.
9. Propone configurar zram con un tamaño calculado automáticamente
   según tu RAM (ver sección dedicada).
10. Opcionalmente, sustituye Firefox ESR por el Firefox oficial de
    Mozilla, verificando la huella digital de su clave GPG antes de
    confiar en el repositorio.

## Uso

```bash
chmod +x setup-debian-sid.sh

# Modo interactivo (recomendado la primera vez)
./setup-debian-sid.sh

# Modo no interactivo: asume "sí" en todas las confirmaciones
./setup-debian-sid.sh -y

# Ayuda
./setup-debian-sid.sh -h
```

> No lo ejecutes con `curl ... | bash` sin `-y`: las confirmaciones
> necesitan una entrada de terminal interactiva.

## Repositorios

Formato deb822, en `/etc/apt/sources.list.d/debian.sources`:

```
Types: deb
URIs: https://deb.debian.org/debian
Suites: unstable
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
```

A diferencia de la versión para Trixie, aquí no hay suites de
`-security`, `-backports` ni `-updates`: en Sid los fixes de seguridad
llegan directamente por `unstable`, `unstable` ya es, por definición, lo
más nuevo del archivo, y `unstable-updates` no existe como suite real
(no tiene sentido un canal de actualizaciones puntuales para una rama
que ya es rolling).

## Paquetes que instala

| Categoría | Paquetes |
|---|---|
| Control de versiones / descargas | `git`, `git-lfs`, `curl`, `wget` |
| Compresión | `unzip`, `zip`, `7zip` (o `p7zip-full` si `7zip` no está disponible en tus repos) |
| Sistema / diagnóstico | `btop`, `fastfetch`, `tree`, `jq`, `ripgrep`, `fd-find`, `pciutils`, `usbutils`, `lshw`, `dmidecode`, `inxi`, `hwinfo`, `lm-sensors`, `acpi` |
| Desarrollo / compilación | `build-essential`, `gcc`, `g++`, `make`, `cmake`, `ninja-build`, `pkg-config`, `autoconf`, `automake`, `libtool`, `openssh-client` |
| Multimedia | `ffmpeg`, `gstreamer1.0-libav`, `gstreamer1.0-plugins-good/bad/ugly`, `pavucontrol` |
| Firmware | `firmware-linux` (metapaquete; usa `lspci -k` si prefieres algo más quirúrgico) |
| Gestión de paquetes (GUI) | `synaptic`, `gdebi` |
| Flatpak | `flatpak`, `plasma-discover-backend-flatpak` |
| Microcode | `intel-microcode` o `amd64-microcode`, según la CPU detectada |

El paquete `7zip` es relativamente nuevo en el archivo de Debian. El
script comprueba con `apt-cache show 7zip` si está disponible en tus
repos antes de intentar instalarlo; si no lo está, usa `p7zip-full`
como alternativa, para que un único paquete no encontrado no haga
fallar toda la instalación.

## Microcode

Se lee `vendor_id` de `/proc/cpuinfo`:

- `GenuineIntel` → `intel-microcode`
- `AuthenticAMD` → `amd64-microcode`
- Cualquier otro valor → se avisa y no se instala ningún paquete de
  microcode automáticamente.

## Flathub

Añade el remoto `flathub` si no existe ya, para poder instalar Flatpaks
desde Discover (KDE Plasma) o desde la línea de comandos.

## Zram automático

El tamaño de zram (swap comprimido en RAM) se calcula **automáticamente**
a partir de la RAM total del sistema, usando la regla práctica de "la
mitad de la RAM":

| RAM total detectada | Zram configurado |
|---|---|
| 8 GB  | 4 GB  |
| 16 GB | 8 GB  |
| 32 GB | 16 GB |

El script lee `/proc/meminfo` en tiempo de ejecución, así que el cálculo
se adapta a la máquina real donde se ejecute — no hay que tocar nada a
mano. Antes de aplicarlo, te muestra la RAM detectada y el tamaño
propuesto, y sigue pidiendo confirmación como el resto de pasos. Si por
algún motivo no se puede leer `/proc/meminfo`, se omite este paso en vez
de aplicar un tamaño inválido.

Tras configurar zram, el script también ofrece ajustar `vm.swappiness`
a **130** (con confirmación aparte). Por defecto el kernel usa `60`, un
valor pensado para cuando el swap vive en disco: el kernel espera a que
la RAM esté casi llena antes de usarlo, porque escribir en disco es
lento. Con zram el "swap" vive comprimido en la propia RAM, mucho más
rápido, así que conviene un valor más alto (el rango habitual
recomendado con zram es 130-180) para que el kernel mande antes las
páginas frías al zram y deje más RAM libre real para caché y procesos
activos. El ajuste se guarda de forma persistente en
`/etc/sysctl.d/99-zram-swappiness.conf`.

## Firefox oficial de Mozilla (opcional)

Debian, incluso en Sid, solo empaqueta `firefox-esr` en su archivo
oficial. Si aceptas este paso:

1. Se desinstala `firefox-esr` (y `firefox-esr-l10n-es` si estaba
   instalado).
2. Se descarga la clave GPG de Mozilla y se **verifica su huella
   digital** contra el valor oficial publicado por Mozilla antes de
   confiar en el repositorio. Si no coincide, el script aborta este
   paso y no añade el repositorio.
3. Se añade `/etc/apt/sources.list.d/mozilla.sources` (deb822) y un pin
   de prioridad 1000 para que el Firefox de Mozilla tenga preferencia
   sobre cualquier paquete `firefox*` de Debian.
4. Se instala `firefox` (y opcionalmente el paquete de idioma español,
   detectado dinámicamente entre `firefox-l10n-es-es`, `firefox-l10n-es-mx`
   o `firefox-l10n-es-ar`, ya que Mozilla no distribuye un paquete
   `firefox-l10n-es` a secas — usa variantes regionales).

## Idempotencia

El script se puede volver a ejecutar sin duplicar trabajo:

- No sobrescribe `/etc/apt/sources.list.d/debian.sources` si ya existe.
- Comprueba si Flathub ya está configurado antes de añadirlo.
- Detecta si `zram-tools` o Firefox ESR ya están en el estado esperado.

## Licencia

MIT
