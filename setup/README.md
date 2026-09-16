# setup-debian-sid.sh

Configura un sistema **Debian Unstable (Sid)** recién instalado con KDE
Plasma: repositorios en formato deb822 apuntando a `unstable`,
actualización del sistema, un set de paquetes de desarrollo/multimedia/
sistema/utilidades de disco, microcode de CPU, fuentes de Windows y de
Ubuntu, Flathub, zram y, de forma opcional según lo que confirmes o
detecte el hardware: Firefox oficial de Mozilla, el driver NVIDIA y
`switcheroo-control`. Es el complemento de `cleanup-debian-sid.sh`: este
script instala, aquel quita.

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
- [Fuentes de Windows y de Ubuntu (opcional)](#fuentes-de-windows-y-de-ubuntu-opcional)
- [Flathub](#flathub)
- [Zram automático](#zram-automático)
- [Firefox oficial de Mozilla (opcional)](#firefox-oficial-de-mozilla-opcional)
- [Driver NVIDIA (opcional)](#driver-nvidia-opcional)
- [switcheroo-control (GPU híbrida, opcional)](#switcheroo-control-gpu-híbrida-opcional)
- [Idempotencia](#idempotencia)
- [Licencia](#licencia)

---

## Qué hace

1. Comprueba `sudo`, que estés en un sistema basado en APT y que no
estés ejecutando el script como root.
2. Detecta el fabricante de CPU (Intel/AMD) para el paso de microcode.
3. Avisa si `VERSION_CODENAME` no indica `sid`/`unstable` (recuerda que
en Sid ese campo no siempre es fiable) y pide confirmación manual.
4. Si detecta contenido activo en el `/etc/apt/sources.list` clásico,
hace una copia de seguridad y lo comenta, para evitar repos
duplicados con el nuevo fichero deb822.
5. Escribe `/etc/apt/sources.list.d/debian.sources` apuntando solo a
`unstable` (sin `-security`, `-backports` ni `-updates`: ninguna de
esas suites existe de verdad para Sid en el archivo de Debian).
6. Actualiza índices (`apt update`) y, si confirmas, hace
`apt full-upgrade`.
7. Instala la lista de paquetes, agrupados en bloques independientes
(ver tabla abajo), incluyendo el microcode correspondiente a tu CPU.
8. Pregunta si instalar fuentes de Windows (`ttf-mscorefonts-installer`)
y de Ubuntu (`fonts-ubuntu`).
9. Añade el remoto de Flathub si no estaba ya configurado.
10. Propone configurar zram con un tamaño calculado automáticamente
según tu RAM, y opcionalmente ajustar `vm.swappiness`.
11. Opcionalmente, sustituye Firefox ESR por el Firefox oficial de
Mozilla, verificando la huella digital de su clave GPG y migrando
los perfiles existentes.
12. Si detecta una GPU NVIDIA por `lspci`, ofrece instalar el driver
`nvidia-open` desde el repositorio oficial CUDA de NVIDIA.
13. Si detecta 2 o más controladores de vídeo (GPU híbrida), ofrece
instalar y activar `switcheroo-control`.

## Uso

```
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

| Categoría                        | Paquetes                                                                                                                                     |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Control de versiones / descargas | `git`, `git-lfs`, `curl`, `wget`                                                                                                             |
| Compresión                       | `unzip`, `zip`, `7zip` (o `p7zip-full` si `7zip` no está disponible en tus repos)                                                            |
| Sistema / diagnóstico            | `btop`, `fastfetch`, `tree`, `jq`, `ripgrep`, `fd-find`, `pciutils`, `usbutils`, `lshw`, `dmidecode`, `inxi`, `hwinfo`, `lm-sensors`, `acpi` |
| Utilidades de disco               | `gnome-disk-utility` (gestión gráfica de discos/particiones, comando `gnome-disks`)                                                          |
| Desarrollo / compilación         | `build-essential`, `gcc`, `g++`, `make`, `cmake`, `ninja-build`, `pkg-config`, `autoconf`, `automake`, `libtool`, `openssh-client`           |
| Multimedia                       | `ffmpeg`, `gstreamer1.0-libav`, `gstreamer1.0-plugins-good/bad/ugly`, `pavucontrol`                                                          |
| Firmware                         | `firmware-linux` (metapaquete; usa `lspci -k` si prefieres algo más quirúrgico)                                                              |
| Gestión de paquetes (GUI)        | `synaptic`, `gdebi`                                                                                                                           |
| Flatpak                          | `flatpak`, `plasma-discover-backend-flatpak`                                                                                                 |
| Microcode                        | `intel-microcode` o `amd64-microcode`, según la CPU detectada                                                                                |

El paquete `7zip` es relativamente nuevo en el archivo de Debian. El
script comprueba con `apt-cache show 7zip` si está disponible en tus
repos antes de intentar instalarlo; si no lo está, usa `p7zip-full` como alternativa, para que un único paquete no encontrado no haga
fallar toda la instalación.

Los paquetes se instalan por bloques independientes: si uno falla
(típico en Sid durante transiciones de librerías), se avisa y se
continúa con el resto en vez de abortar toda la instalación.

## Microcode

Se lee `vendor_id` de `/proc/cpuinfo`:

- `GenuineIntel` → `intel-microcode`
- `AuthenticAMD` → `amd64-microcode`
- Cualquier otro valor → se avisa y no se instala ningún paquete de
microcode automáticamente.

## Fuentes de Windows y de Ubuntu (opcional)

Dos preguntas independientes:

- **Fuentes de Windows** (`ttf-mscorefonts-installer`): Arial, Times New
Roman, Courier New, etc. El paquete descarga los `.ttf` originales de
Microsoft en tiempo de instalación y requiere aceptar su licencia
(EULA). En modo `-y`, el script acepta la licencia automáticamente vía
`debconf-set-selections`; en modo interactivo puede que veas también la
pantalla de aceptación propia de `debconf`.
- **Fuentes de Ubuntu** (`fonts-ubuntu`): empaquetadas tal cual en los
repos oficiales de Debian, sin pasos adicionales.

## Flathub

Añade el remoto `flathub` si no existe ya, para poder instalar Flatpaks
desde Discover (KDE Plasma) o desde la línea de comandos.

## Zram automático

El tamaño de zram (swap comprimido en RAM) se calcula **automáticamente** a partir de la RAM total del sistema, usando la regla práctica de "la
mitad de la RAM":

| RAM total detectada | Zram configurado |
| -------------------- | ------------------ |
| 8 GB                 | 4 GB               |
| 16 GB                | 8 GB               |
| 32 GB                | 16 GB              |

El script lee `/proc/meminfo` en tiempo de ejecución, así que el cálculo
se adapta a la máquina real donde se ejecute — no hay que tocar nada a
mano. Antes de aplicarlo, te muestra la RAM detectada y el tamaño
propuesto, y sigue pidiendo confirmación como el resto de pasos. Si por
algún motivo no se puede leer `/proc/meminfo`, se omite este paso en vez
de aplicar un tamaño inválido.

Tras configurar zram, el script también ofrece ajustar `vm.swappiness` a
**130** (con confirmación aparte). Por defecto el kernel usa `60`, un
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
oficial (no distribuye la versión release por su política de marca). Si
aceptas este paso:

1. **Antes de tocar nada**, el script toma una foto de todas las
carpetas de perfil que ya existen en `~/.mozilla/firefox`. En este
punto solo puede haber perfiles de ESR (el release aún no está
instalado), así que no hace falta que el nombre de la carpeta
contenga "esr" — Firefox solo añade ese sufijo cuando detecta más de
una instalación compitiendo por el perfil por defecto.
2. Se desinstala `firefox-esr` (y `firefox-esr-l10n-es` si estaba
instalado) con `apt purge`, y se borra `/etc/firefox-esr` si queda
algo que dpkg no limpió solo.
3. Se descarga la clave GPG de Mozilla y se **verifica su huella
digital** contra el valor oficial publicado por Mozilla antes de
confiar en el repositorio. Si no coincide, el script aborta este
paso y no añade el repositorio.
4. Se añade `/etc/apt/sources.list.d/mozilla.sources` (deb822) y un pin
de prioridad 1000 para que el Firefox de Mozilla tenga preferencia
sobre cualquier paquete `firefox*` de Debian.
5. Se instala `firefox` (y opcionalmente el paquete de idioma español,
detectado dinámicamente entre `firefox-l10n-es-es`,
`firefox-l10n-es-mx` o `firefox-l10n-es-ar`, ya que Mozilla no
distribuye un paquete `firefox-l10n-es` a secas — usa variantes
regionales).
6. Si en el paso 1 se detectaron carpetas de perfil previas, se
pregunta si eliminarlas (irreversible: borra marcadores, contraseñas,
historial y extensiones de ese perfil). Si aceptas, también se limpia
`profiles.ini` quitando los bloques `[ProfileN]` correspondientes,
sin tocar `[General]` ni los bloques `[InstallXXXX]` (el mecanismo
moderno de Firefox para el perfil por defecto de cada instalación).

> **AutoFirma:** su instalador inyecta el certificado raíz directamente
> dentro de la carpeta de cada perfil de Firefox que exista en ese
> momento (vía `certutil`, en el almacén NSS del perfil). Si instalas o
> reinstalas AutoFirma **después** de este paso, el certificado va al
> perfil release nuevo sin conflicto. Si AutoFirma ya estaba instalado
> sobre un perfil ESR que este script borra, el certificado se pierde
> con esa carpeta y hay que forzar a AutoFirma a reinyectarlo con
> `sudo apt reinstall autofirma`.

## Driver NVIDIA (opcional)

Se activa solo si `lspci` detecta una GPU NVIDIA. Usa el mismo
repositorio CUDA oficial de NVIDIA (rama `debian13`, vía `cuda-keyring`)
que las versiones trixie y testing de este proyecto — NVIDIA no publica
una rama dedicada para Sid, pero `debian13` es la combinación ya probada
y en uso.

Instala `nvidia-open` (driver de código abierto), junto con librerías de
32 bits (`nvidia-driver-libs:i386`, para Steam/Proton) y
`nvidia-vaapi-driver` (aceleración de vídeo por hardware en
navegadores). Fija el repositorio NVIDIA CUDA como origen preferente
(`/etc/apt/preferences.d/nvidia-cuda`, prioridad 1000) para todo el
stack `nvidia-*`/`libnvidia-*`, evitando que APT mezcle versiones con
los paquetes nativos de Debian del mismo stack.

También:

- Deshabilita el driver `nouveau` (`/etc/modprobe.d/blacklist-nouveau.conf`).
- Configura GRUB para KMS de NVIDIA (`nvidia-drm.modeset=1`,
`nvidia-drm.fbdev=1`), con copia de seguridad de `/etc/default/grub`
antes de tocarlo.
- Habilita los servicios de suspensión/hibernación de NVIDIA si el
empaquetado los trae.

> **Limitación conocida:** `nvidia-open` solo soporta GPUs Turing en
> adelante (RTX 20xx, GTX 16xx, y más recientes). El script no
> distingue el modelo concreto, solo detecta "es NVIDIA" — en una GPU
> más antigua (GTX 10xx o anterior) este driver no cargará.

> **Secure Boot:** si está activado, el módulo de kernel de NVIDIA no
> cargará hasta que firmes la clave MOK manualmente (requiere reiniciar
> y confirmar en el MOK Manager). El script detecta y avisa, pero este
> paso queda deliberadamente **fuera** del script — ver la sección
> "Secure Boot y el driver NVIDIA" en `MANUAL.md`.

## switcheroo-control (GPU híbrida, opcional)

Se activa solo si `lspci` detecta 2 o más controladores de vídeo
(integrada + dedicada). Instala y habilita el servicio
`switcheroo-control`, necesario para que el escritorio gestione el
cambio entre GPUs. Comprueba las GPUs detectadas con `switcherooctl list`
una vez instalado.

## Idempotencia

El script se puede volver a ejecutar sin duplicar trabajo:

- No sobrescribe `/etc/apt/sources.list.d/debian.sources` si ya existe.
- Comprueba si Flathub, `cuda-keyring` o el repo de Mozilla ya están
configurados antes de añadirlos.
- Detecta si `zram-tools`, Firefox ESR o `switcheroo-control` ya están
en el estado esperado.

## Licencia

MIT
