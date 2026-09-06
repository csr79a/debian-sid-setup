# Manual — Scripts de configuración para Debian Unstable (Sid)

Este manual explica, paso a paso y desde cero, cómo preparar tu sistema y
ejecutar los dos scripts de este proyecto:

- **`setup/setup-debian-sid.sh`** — configura repos apuntando a unstable,
  actualiza el sistema e instala un set de paquetes de desarrollo/
  multimedia/sistema. Ver `setup/README.md` para el detalle de qué instala.
- **`cleanup/cleanup-debian-sid.sh`** — elimina aplicaciones de KDE Plasma
  que no usas. Ver `cleanup/README.md` para el detalle de qué elimina.

No hace falta que sepas bash para seguir estos pasos.

> **Antes de usar este proyecto:** estos scripts asumen que ya tienes un
> sistema Debian instalado con los repositorios apuntando a `unstable`
> (por ejemplo, siguiendo el método recomendado por la wiki de Debian:
> instalar stable mínimo y luego cambiar los repos a unstable, o
> instalar directamente con el mini.iso eligiendo el mirror
> "sid - unstable"). Este proyecto no instala Debian por ti ni te pasa
> de stable a Sid — solo configura un sistema que ya está en Sid.

---

## 1. Antes de nada: deja `sudo` listo

Ambos scripts usan `sudo` para las tareas que requieren privilegios de
administrador (instalar/quitar paquetes, escribir en `/etc`). Debian **no**
siempre configura `sudo` automáticamente:

- Si al instalar Debian **dejaste en blanco** la contraseña de `root`,
  `sudo` ya debería estar listo para tu usuario.
- Si le **pusiste contraseña a `root`** (lo más habitual), Debian no
  instala `sudo` ni añade tu usuario a ningún grupo, aunque hayas
  instalado el escritorio completo con KDE Plasma.

Para comprobarlo, abre una terminal (Konsole) y ejecuta:

```bash
sudo -v
```

- Si te pide **tu contraseña de usuario** (no la de root) y no da error,
  ya está listo — puedes saltarte el resto de esta sección.
- Si da error de tipo *"sudo: command not found"* o *"no está en el
  fichero sudoers"*, sigue estos pasos una única vez:

```bash
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

Ambos scripts comprueban esto por ti al arrancar (existencia de `sudo` y
`sudo -v`) y se detienen con un mensaje claro si algo falta, en vez de
fallar a mitad de instalación.

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

```bash
mkdir -p ~/Proyectos
cd ~/Proyectos
# copia aquí la carpeta "proyecto debian sid" completa (USB, git clone, scp, lo que uses)
```

Por defecto, los archivos que copies **no tienen permiso de ejecución** —
es una medida de seguridad de Linux: un `.sh` no se ejecuta como programa
solo por tener esa extensión. Hay que dárselo explícitamente:

```bash
chmod +x setup/setup-debian-sid.sh
chmod +x cleanup/cleanup-debian-sid.sh
```

`chmod +x` añade el permiso "ejecutable" (execute) al archivo, para tu
usuario, el grupo y otros. Puedes comprobar que se aplicó con:

```bash
ls -l setup/setup-debian-sid.sh
# -rwxr-xr-x ...   ← las "x" indican que ya es ejecutable
```

---

## 3. Ejecutar los scripts

Siempre desde la carpeta donde están (o indicando la ruta), **nunca como
root directamente**:

```bash
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
antes de cada paso importante (`[y/N]` — escribe `y` y Enter para
confirmar, cualquier otra cosa o Enter vacío para rechazar). Cuando
`sudo` necesite tu contraseña, te la pedirá en el momento; es tu
contraseña de usuario normal, no la de `root`.

### Modo no interactivo (`-y`)

Si ya revisaste el script y confías en él, puedes saltarte todas las
confirmaciones con `-y`:

```bash
./setup/setup-debian-sid.sh -y
./cleanup/cleanup-debian-sid.sh -y
```

**Recomendación:** la primera vez que uses cada script, hazlo sin `-y`,
lee lo que te va preguntando y lo que `apt` te muestra antes de aceptar.
Una vez que confías en que hace lo que esperas en tu sistema, ya puedes
usar `-y` en ejecuciones futuras.

### Ayuda

Ambos scripts aceptan `-h`/`--help` para ver un resumen rápido de sus
opciones sin ejecutar nada:

```bash
./setup/setup-debian-sid.sh -h
./cleanup/cleanup-debian-sid.sh -h
```

---

## 4. Sobre el zram automático

`setup-debian-sid.sh` calcula el tamaño del zram (swap comprimido en
RAM) automáticamente a partir de la RAM total de tu equipo, usando la
regla práctica de "la mitad de la RAM":

| RAM total | Zram configurado |
|---|---|
| 8 GB  | 4 GB  |
| 16 GB | 8 GB  |
| 32 GB | 16 GB |

No hace falta indicar nada a mano: el script lee `/proc/meminfo` en el
momento de ejecutarse y calcula el valor para tu máquina concreta. Antes
de aplicarlo te muestra la RAM detectada y el tamaño propuesto, y sigue
pidiendo confirmación como el resto de pasos.

---

## 5. Orden recomendado

1. Deja `sudo` listo (paso 1).
2. Asegúrate de que el sistema ya apunta a unstable (ver aviso al
   principio de este manual).
3. Ejecuta `setup-debian-sid.sh` para partir de repos y paquetes base
   consistentes.
4. Cuando lleves un tiempo usando el sistema y tengas claro qué apps de
   KDE no usas, ejecuta `cleanup-debian-sid.sh`.
5. Prueba siempre primero en una máquina virtual si vas a cambiar algo
   del script o no estás seguro de qué se va a eliminar — más aún en
   Sid, donde un `full-upgrade` puede mover muchos paquetes de golpe.

---

## 6. Si algo sale mal

- Los mensajes de error de estos scripts están pensados para decirte
  **qué revisar** (normalmente, este manual o el README correspondiente).
- `apt` nunca elimina nada sin mostrarte antes el resumen completo de la
  transacción (a menos que uses `-y`), así que siempre puedes cancelar
  con `Ctrl+C` o respondiendo que no, antes de que se aplique.
- Ninguno de los dos scripts es destructivo de forma irreversible: los
  paquetes se pueden reinstalar (`sudo apt install <paquete>`) y, si
  usaste `apt remove` en vez de `--purge`, tu configuración debería
  seguir intacta.
- Ten en cuenta que en Sid, a diferencia de Trixie, no hay un camino
  sencillo de "vuelta atrás" a stable si algo sale realmente mal a nivel
  de sistema — la recuperación normal es restaurar un snapshot/backup
  previo, no simplemente revertir el sources.list.
