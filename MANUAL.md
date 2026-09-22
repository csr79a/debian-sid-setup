# Manual — Scripts de configuración para Debian Unstable (Sid)

Este manual explica, paso a paso y desde cero, cómo preparar tu sistema y
ejecutar los dos scripts de este proyecto:

- **`setup/setup-debian-sid.sh`** — configura repos apuntando a unstable,
actualiza el sistema e instala un set de paquetes de desarrollo/
multimedia/sistema/utilidades de disco/OCR, fuentes, y ofrece Firefox
oficial, driver NVIDIA y `switcheroo-control` según lo que confirmes o
detecte el hardware. Ver `setup/README.md` para el detalle de qué instala.
- **`cleanup/cleanup-debian-sid.sh`** — elimina aplicaciones de KDE Plasma
que no usas. Ver `cleanup/README.md` para el detalle de qué elimina.

No hace falta que sepas bash para seguir estos pasos.

Versiones documentadas: `setup-debian-sid.sh` 1.2.1 y `cleanup-debian-sid.sh` 1.1.0.

> **Antes de usar este proyecto:** estos scripts asumen que ya tienes un
> sistema Debian instalado con los repositorios apuntando a `unstable` (por ejemplo, siguiendo el método recomendado por la wiki de Debian:
> instalar stable mínimo y luego cambiar los repos a unstable, o
> instalar directamente con el mini.iso eligiendo el mirror
> "sid - unstable"). Este proyecto no instala Debian por ti ni te pasa
> de stable a Sid — solo configura un sistema que ya está en Sid.
>
> Si algún repositorio de Debian de tu sistema apunta a otra suite
> (trixie, testing, stable, bookworm...), `setup-debian-sid.sh` **se
> detiene** con un mensaje que lista las entradas conflictivas, incluso
> con `-y`. No las convierte por ti: corrígelas o desactívalas a mano y
> vuelve a ejecutarlo.

---

## 1. Antes de nada: deja `sudo` listo

Ambos scripts usan `sudo` para las tareas que requieren privilegios de
administrador (instalar/quitar paquetes, escribir en `/etc`). Debian **no** siempre configura `sudo` automáticamente:

- Si al instalar Debian **dejaste en blanco** la contraseña de `root`,
`sudo` ya debería estar listo para tu usuario.
- Si le **pusiste contraseña a `root`** (lo más habitual), Debian no
instala `sudo` ni añade tu usuario a ningún grupo, aunque hayas
instalado el escritorio completo con KDE Plasma.

Para comprobarlo, abre una terminal (Konsole) y ejecuta:

```
sudo -v
```

- Si te pide **tu contraseña de usuario** (no la de root) y no da error,
ya está listo — puedes saltarte el resto de esta sección.
- Si da error de tipo *"sudo: command not found"* o *"no está en el
fichero sudoers"*, sigue estos pasos una única vez:

```
# 1. Entra como root (te pedirá la contraseña de root)
su -

# 2. Instala sudo
apt update
apt install sudo

# 3. Añade tu usuario normal al grupo sudo (sustituye TU_USUARIO)
usermod -aG sudo TU_USUARIO

# 4. Sal de la sesión de root
exit
```

Después, **cierra sesión y vuelve a entrar** (o reinicia) para que el
cambio de grupo se aplique, y confirma con `groups` que `sudo` aparece en
la lista.

Ambos scripts comprueban esto por ti al arrancar (que no los ejecutes
como root, que el sistema use APT, la existencia de `sudo` y `sudo -v`) y
se detienen con un mensaje claro si algo falta, en vez de fallar a mitad
de instalación.

---

## 2. Descargar/copiar los scripts y darles permiso de ejecución

Los archivos que necesitas están en esta misma entrega, organizados así:

```
proyecto debian sid/
├── MANUAL.md              (este archivo)
├── README.md
├── setup/
│   ├── setup-debian-sid.sh
│   └── README.md
└── cleanup/
    ├── cleanup-debian-sid.sh
    └── README.md
```

Copia toda la carpeta a tu sistema, por ejemplo:

```
mkdir -p ~/Proyectos
cd ~/Proyectos
# copia aquí la carpeta "proyecto debian sid" completa (USB, git clone, scp, lo que uses)
```

Por defecto, los archivos que copies **no tienen permiso de ejecución** —
es una medida de seguridad de Linux: un `.sh` no se ejecuta como programa
solo por tener esa extensión. Hay que dárselo explícitamente:

```
chmod +x setup/setup-debian-sid.sh
chmod +x cleanup/cleanup-debian-sid.sh
```

`chmod +x` añade el permiso "ejecutable" (execute) al archivo, para tu
usuario, el grupo y otros. Puedes comprobar que se aplicó con:

```
ls -l setup/setup-debian-sid.sh
# -rwxr-xr-x ...   ← las "x" indican que ya es ejecutable
```

---

## 3. Ejecutar los scripts

Siempre desde la carpeta donde están (o indicando la ruta), **nunca como
root directamente**:

```
# Configuración inicial del sistema (asume que ya apuntas a unstable)
cd setup
./setup-debian-sid.sh
cd ..

# Limpieza de apps de KDE que no usas (ejecútalo después, cuando quieras)
cd cleanup
./cleanup-debian-sid.sh
cd ..
```

El `./` al principio le dice a la terminal "ejecuta el archivo que está
aquí, en esta carpeta" (por seguridad, Linux no busca automáticamente
programas en la carpeta actual).

Los dos scripts son **interactivos por defecto**: te van preguntando
antes de cada paso importante con **pantallas de confirmación**
(`whiptail`): una ventana con los botones *Sí* y *No*. Se elige con las
flechas o el tabulador y se confirma con Enter. Si `whiptail` no está
instalado (algo posible en un Debian mínimo), el propio script lo instala
antes de mostrar nada. El progreso de `apt` y del resto de comandos largos
se sigue mostrando como texto normal en la terminal. Cuando `sudo`
necesite tu contraseña, te la pedirá en el momento; es tu contraseña de
usuario normal, no la de `root`.

### Modo no interactivo (`-y`)

Si ya revisaste el script y confías en él, puedes saltarte todas las
confirmaciones con `-y`:

```
./setup/setup-debian-sid.sh -y
./cleanup/cleanup-debian-sid.sh -y
```

**Ojo: `-y` acepta TODO, incluidas operaciones irreversibles.** En
`setup-debian-sid.sh`, eso incluye:

- comentar el contenido activo de `/etc/apt/sources.list` (con copia de
seguridad previa);
- eliminar Firefox ESR, `/etc/firefox-esr` y **todos** sus perfiles y
datos (`~/.mozilla/firefox`), sin vuelta atrás;
- modificar GRUB, initramfs y otras configuraciones del sistema (NVIDIA,
zram, sysctl);
- aceptar automáticamente la licencia de las fuentes de Windows y
silenciar todos los avisos de `debconf` durante las instalaciones.

En `cleanup-debian-sid.sh`, `-y` confirma todos los grupos, sin mostrar
los avisos de las pantallas (por ejemplo, el de KDE Partition Manager
sin GNOME Disk Utility). La pregunta de `apt autoremove` del final sigue
apareciendo aunque uses `-y`.

Lo único que `-y` **no** se salta son las comprobaciones críticas: si tus
repositorios de Debian no apuntan a Sid, `setup-debian-sid.sh` se
detiene igualmente.

**Recomendación:** la primera vez que uses cada script, hazlo sin `-y`,
lee lo que te va preguntando y lo que `apt` te muestra antes de aceptar.
Una vez que confías en que hace lo que esperas en tu sistema, ya puedes
usar `-y` en ejecuciones futuras.

### Ayuda

Ambos scripts aceptan `-h`/`--help` para ver un resumen rápido de sus
opciones sin ejecutar nada:

```
./setup/setup-debian-sid.sh -h
./cleanup/cleanup-debian-sid.sh -h
```

---

## 4. Sobre el zram automático

`setup-debian-sid.sh` calcula el tamaño del zram (swap comprimido en
RAM) automáticamente a partir de la RAM total de tu equipo, usando la
regla práctica de "la mitad de la RAM":

| RAM total | Zram configurado |
| ----------- | ------------------- |
| 8 GB        | 4 GB                |
| 16 GB       | 8 GB                |
| 32 GB       | 16 GB               |

No hace falta indicar nada a mano: el script lee `/proc/meminfo` en el
momento de ejecutarse y calcula el valor para tu máquina concreta. Antes
de aplicarlo te muestra la RAM detectada y el tamaño propuesto, y sigue
pidiendo confirmación como el resto de pasos. Si ya tenías configurado
`/etc/default/zramswap`, hace una copia de seguridad (`.bak.<fecha>`)
antes de modificarlo.

Después ofrece, con una pregunta aparte, ajustar `vm.swappiness` a 130,
un valor más adecuado cuando el swap vive comprimido en RAM. Se guarda en
`/etc/sysctl.d/99-zram-swappiness.conf`.

---

## 5. Sobre la migración de Firefox y AutoFirma

Si aceptas sustituir Firefox ESR por el Firefox oficial de Mozilla, el
script **elimina Firefox ESR y todos sus datos** (`~/.mozilla/firefox`
completo: marcadores, contraseñas, historial, extensiones) y deja que el
Firefox nuevo empiece con un perfil limpio. No se migra nada.

La pantalla de confirmación de ese paso te avisa de que es irreversible;
**no hay una segunda pregunta** sobre los perfiles. Con `-y`, se acepta
automáticamente.

El script ordena las operaciones para que un fallo no te deje sin
navegador: primero descarga y verifica la clave de Mozilla y configura
su repositorio, después intenta instalar Firefox normal de verdad
(`apt install -y firefox`, sin fiarse de comprobaciones indirectas como
`apt-cache policy`, que pueden dar un falso negativo aunque la
instalación real funcione), y **solo si esa instalación tiene éxito**
elimina ESR. Si algo falla antes de ese punto, ESR y sus perfiles no se
tocan. Si ESR ya no estaba instalado cuando ejecutas el script (por
ejemplo, en una segunda ejecución), tampoco se borra ningún perfil.

Esto importa si usas **AutoFirma** (firma electrónica): su instalador no
guarda el certificado en un sitio propio, lo inyecta directamente dentro
de la carpeta de cada perfil de Firefox que exista en ese momento. Por
eso el **orden en que hagas las cosas en una instalación nueva importa**:

- **Orden recomendado:** ejecuta `setup-debian-sid.sh` primero (que deja
un único perfil de Firefox release, sin rastro de ESR) e instala
AutoFirma **al final**. El certificado se inyecta directo en el perfil
correcto, sin ningún paso extra.
- **Si AutoFirma ya estaba instalado antes** de correr el script (con el
certificado ya inyectado en el perfil viejo de ESR), al borrar esa
carpeta el certificado desaparece con ella. El Firefox nuevo no lo
tendrá hasta que fuerces a AutoFirma a reinyectarlo:

```
sudo apt reinstall autofirma
```

---

## 6. Secure Boot / NVIDIA

Si `setup-debian-sid.sh` detecta una GPU NVIDIA y aceptas instalar el
driver, el script instala `nvidia-open` y configura GRUB para KMS
automáticamente. Antes de preguntarte, comprueba el estado de Secure Boot
y te lo muestra en la propia pantalla de confirmación (activado,
desactivado, sistema sin UEFI o desconocido).

Si tu sistema tiene **Secure Boot activado**, hay un paso más que el
script **no** hace por ti, porque requiere interacción manual delante del
equipo. El script te lo recuerda con avisos al instalar y en el resumen
final:

1. El módulo de kernel de NVIDIA (`nvidia-open`, compilado vía DKMS) no
carga con Secure Boot activo hasta que su clave se registre en el
Machine Owner Key (MOK) store del firmware.
2. **Antes de reiniciar**, asegúrate de que la clave está en cola para
registrarse. Si la instalación de DKMS te pidió una contraseña, ya lo
está. Con `-y`, los avisos de `debconf` se silencian, así que puede
que no te la pidiera: en ese caso importa la clave tú mismo:

```
sudo mokutil --import /var/lib/dkms/mok.pub
```

   (Te pedirá que inventes una contraseña de un solo uso. Esa ruta
   puede variar según tu versión de DKMS.)
3. Al reiniciar, aparecerá la pantalla azul **MOK Management**
(`mokutil`/`shim`) automáticamente:
   - Elige **"Enroll MOK"** → **"Continue"** → **"Yes"**.
   - Escribe la contraseña que definiste en el paso anterior (o la que
     te pidió la instalación del paquete DKMS de NVIDIA; revisa el log
     de `apt install` de ese paso si no la recuerdas).
   - Confirma y deja que el sistema arranque normalmente.
4. Verifica que el módulo cargó correctamente con:

```
nvidia-smi
```

Si Secure Boot está desactivado, no necesitas nada de esto: el driver
carga sin más tras reiniciar. Puedes comprobar el estado de Secure Boot
en cualquier momento con:

```
mokutil --sb-state
```

Al terminar la instalación de NVIDIA, en modo interactivo el script te
pregunta si quieres reiniciar ahora. Si tienes Secure Boot activado,
elige "Reiniciar después" y completa antes el paso 2 de arriba.

---

## 7. Orden recomendado

1. Deja `sudo` listo (paso 1).
2. Asegúrate de que el sistema ya apunta a unstable y de que ninguna
entrada de repositorios de Debian usa otra suite (ver aviso al
principio de este manual).
3. Ejecuta `setup-debian-sid.sh` para partir de repos y paquetes base
consistentes.
4. Si usas AutoFirma, instálalo/reinstálalo **después** de este paso
(ver sección 5).
5. Si instalaste el driver NVIDIA y tienes Secure Boot activado, sigue
la sección 6 antes de dar por terminada la instalación.
6. Cuando lleves un tiempo usando el sistema y tengas claro qué apps de
KDE no usas, ejecuta `cleanup-debian-sid.sh`.
7. Prueba siempre primero en una máquina virtual si vas a cambiar algo
del script o no estás seguro de qué se va a eliminar — más aún en
Sid, donde un `full-upgrade` puede mover muchos paquetes de golpe.

---

## 8. Si algo sale mal

- Los mensajes de error de estos scripts están pensados para decirte
**qué revisar** (normalmente, este manual o el README correspondiente).
- `apt` nunca elimina nada sin mostrarte antes el resumen completo de la
transacción (a menos que uses `-y`), así que siempre puedes cancelar
con `Ctrl+C` o respondiendo que no, antes de que se aplique.
- Si un grupo de paquetes falla durante `setup-debian-sid.sh` (algo
típico en Sid durante transiciones de librerías), el script avisa, sigue
con el resto y lista al final los grupos que hay que reintentar a mano.
- Ninguno de los dos scripts es destructivo de forma irreversible a
nivel de paquetes: se pueden reinstalar (`sudo apt install <paquete>`)
y, si usaste `apt remove` en vez de `--purge` en cleanup, tu
configuración debería seguir intacta. La única excepción irreversible
es el borrado de Firefox ESR y de `~/.mozilla/firefox` (sección 5 de
este manual), que ocurre si confirmas esa pantalla o si usas `-y`. Los
cambios en `/etc/apt/sources.list`, `/etc/default/grub` y
`/etc/default/zramswap` sí dejan una copia de seguridad con la fecha en
el nombre.
- Ten en cuenta que en Sid, a diferencia de Trixie, no hay un camino
sencillo de "vuelta atrás" a stable si algo sale realmente mal a nivel
de sistema — la recuperación normal es restaurar un snapshot/backup
previo, no simplemente revertir el sources.list.
