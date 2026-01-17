# Debian Scripts

Colección de scripts para administración y automatización en sistemas Debian.

Este repositorio está orientado a:
- mantenimiento del sistema
- automatización de tareas recurrentes
- buenas prácticas de scripting en Bash

## Estructura del repositorio

- `scripts/backup/`        Scripts de backup y retención
- `scripts/maintenance/`   Actualizaciones, limpieza y checks
- `scripts/network/`       Diagnóstico y herramientas de red
- `scripts/security/`      Hardening básico y auditorías
- `docs/`                  Documentación de uso y setup

## Convenciones

- Bash strict mode (`set -euo pipefail`)
- Logs con timestamp
- Validación de dependencias y rutas
