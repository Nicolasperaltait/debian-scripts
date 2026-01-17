# Setup — Debian Scripts

Este documento describe los requisitos y pasos iniciales para usar los scripts
de este repositorio en sistemas Debian.

---

## Sistemas soportados

- Debian 11 / 12
- Derivados compatibles (Ubuntu, Proxmox, etc.)

---

## Requisitos generales

- Acceso a root (ejecución con `sudo`)
- Paquetes base:
  - apt
  - bash
  - coreutils

Algunos scripts requieren herramientas adicionales (se instalan automáticamente
o se indican en el README del script).

---

## Clonar el repositorio

```bash
git clone https://github.com/Nicolasperaltait/debian-scripts.git
cd debian-scripts
