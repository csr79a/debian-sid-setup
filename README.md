# Debian Sid Setup

Scripts para configurar un sistema **Debian Unstable (Sid)** con KDE
Plasma: repositorios, paquetes de desarrollo/multimedia/sistema/OCR,
microcode, Flathub, zram y limpieza de apps de KDE que no uses.

Es el proyecto equivalente al de [Debian Trixie](https://github.com/csr79a/debian-trixie-setup),
adaptado a las particularidades de Sid (repos `unstable`, sin `-security` ni `-backports`, `VERSION_CODENAME` poco fiable, etc.).

> **Antes de nada:** este proyecto asume que ya tienes un sistema Debian
> instalado con los repositorios apuntando a `unstable`. No instala
> Debian por ti ni migra un sistema desde stable. Si algún repositorio de
> Debian apunta a otra suite (trixie, testing, stable...), `setup-debian-sid.sh`
> se detiene: no convierte suites automáticamente.

Versiones documentadas: `setup-debian-sid.sh` 1.3.0 y `cleanup-debian-sid.sh` 1.1.0.

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

Ambos scripts te van preguntando con pantallas de confirmación
(`whiptail`, que instalan solos si falta). La primera vez, úsalos sin
`-y`: el modo `-y` acepta todo automáticamente, incluidas operaciones
irreversibles (ver el detalle en `setup/README.md`).

Si es la primera vez que usas este proyecto, lee primero [`MANUAL.md`](https://github.com/csr79a/debian-sid-setup/blob/main/MANUAL.md) — explica paso a paso, sin asumir que sabes
bash, cómo dejar `sudo` listo y ejecutar ambos scripts con seguridad.

## Qué hace cada script

- **`setup/`** — comprueba que todos los repositorios de Debian apunten
solo a `unstable`/`sid` (si no, se detiene, también con `-y`), escribe
los repos en formato deb822, `apt full-upgrade` opcional, microcode según
CPU, paquetes de desarrollo/multimedia/sistema/utilidades de disco/OCR
(Tesseract), fuentes de Windows y de Ubuntu, Flathub, zram con tamaño
calculado automáticamente según tu RAM (y `vm.swappiness` opcional),
sustitución opcional de Firefox ESR por el Firefox oficial de Mozilla
(con verificación de huella GPG; instala Firefox primero y solo si eso
funciona elimina ESR y sus perfiles), y detección opcional de hardware
para instalar el driver NVIDIA y/o `switcheroo-control` (GPU híbrida).
Detalle completo en
[`setup/README.md`](https://github.com/csr79a/debian-sid-setup/blob/main/setup/README.md).

- **`cleanup/`** — elimina, por grupos y con confirmación individual,
apps de KDE Plasma que Debian instala por defecto pero que muchos no
usan (suite PIM/Kontact, accesibilidad, Konqueror, xterm, KDE Connect,
KDE Partition Manager, e ImageMagick como grupo opcional). Detalle
completo en [`cleanup/README.md`](https://github.com/csr79a/debian-sid-setup/blob/main/cleanup/README.md).

## Licencia

MIT
