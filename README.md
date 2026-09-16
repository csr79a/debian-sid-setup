# Debian Sid Setup

Scripts para configurar un sistema **Debian Unstable (Sid)** con KDE
Plasma: repositorios, paquetes de desarrollo/multimedia/sistema,
microcode, Flathub, zram y limpieza de apps de KDE que no uses.

Es el proyecto equivalente al de [Debian Trixie](https://github.com/csr79a/debian-trixie-setup),
adaptado a las particularidades de Sid (repos `unstable`, sin `-security` ni `-backports`, `VERSION_CODENAME` poco fiable, etc.).

> **Antes de nada:** este proyecto asume que ya tienes un sistema Debian
> instalado con los repositorios apuntando a `unstable`. No instala
> Debian por ti ni migra un sistema desde stable.

---

## Estructura del proyecto

```
proyecto debian sid/
├── MANUAL.md              ← empieza por aquí si no sabes bash
├── README.md               (este archivo)
├── setup/
│   ├── setup-debian-sid.sh
│   └── README.md            ← detalle de qué instala
└── cleanup/
    ├── cleanup-debian-sid.sh
    └── README.md            ← detalle de qué elimina
```

## Uso rápido

```
chmod +x setup/setup-debian-sid.sh cleanup/cleanup-debian-sid.sh

cd setup && ./setup-debian-sid.sh    # configuración inicial
cd ../cleanup && ./cleanup-debian-sid.sh   # limpieza de apps KDE (opcional, después)
```

Si es la primera vez que usas este proyecto, lee primero [`MANUAL.md`](https://github.com/csr79a/debian-sid-setup/blob/main/MANUAL.md) — explica paso a paso, sin asumir que sabes
bash, cómo dejar `sudo` listo y ejecutar ambos scripts con seguridad.

## Qué hace cada script

- **`setup/`** — repos deb822 apuntando solo a `unstable`, `apt full-upgrade`
opcional, microcode según CPU, paquetes de desarrollo/multimedia/sistema/
utilidades de disco, fuentes de Windows y de Ubuntu, Flathub, zram con
tamaño calculado automáticamente según tu RAM, sustitución opcional de
Firefox ESR por el Firefox oficial de Mozilla (con verificación de huella
GPG y migración de perfiles), y detección opcional de hardware para
instalar el driver NVIDIA y/o `switcheroo-control` (GPU híbrida). Detalle
completo en [`setup/README.md`](https://github.com/csr79a/debian-sid-setup/blob/main/setup/README.md).

- **`cleanup/`** — elimina, por grupos y con confirmación individual,
apps de KDE Plasma que Debian instala por defecto pero que muchos no
usan (suite PIM/Kontact, accesibilidad, Konqueror, xterm, KDE Connect,
KDE Partition Manager, e ImageMagick como grupo opcional). Detalle
completo en [`cleanup/README.md`](https://github.com/csr79a/debian-sid-setup/blob/main/cleanup/README.md).

## Licencia

MIT
