# AGENTS.md — Charter raíz de debian-scripts

Archivo de entrada para cualquier LLM o agente (Claude, Codex, ChatGPT, Gemini, Cursor, modelo local u otro) que trabaje en este repositorio. Leerlo completo antes de actuar. Las reglas de este archivo prevalecen sobre suposiciones del modelo.

Idioma de trabajo: español. Tono: directo, técnico, accionable.

## 0. North Star — para qué existe este repo

Bootstrap modular y auditable para dejar cualquier Debian 12/13 (VM o baremetal) lista y confiable desde una instalación limpia, con seguridad por defecto y acceso SSH siempre disponible. El objetivo de fondo es que el operador pueda correrlo en cada equipo nuevo sin configurar nada a mano y confiando en el resultado.

Regla rectora: no se agrega nada "porque sí". Todo lo que entra a este repo justifica su existencia por una razón concreta. Cambio mínimo necesario, primero estabilidad, después optimización.

## 1. Qué es / alcance

- **Es:** orquestador Bash (`main.sh`) que detecta el sistema, presenta un wizard o acepta flags CLI, y ejecuta módulos en secuencia sobre máquinas Debian reales como root (`sudo bash main.sh`). Incluye helpers reutilizables, módulos de seguridad/optimización/escritorio/extras, tests y documentación.
- **No es:** un repo de configuración de un homelab concreto. No contiene datos reales de infraestructura (IPs privadas, hostnames, credenciales), material histórico ni los scripts legacy del usuario. `legacy-source/`, `.tmp/` e `instalar-*.sh` quedan fuera del versionado (`.gitignore`).
- **Público:** el repositorio es público. Ningún archivo versionado debe contener secretos, nombres personales, IPs privadas (RFC1918) ni datos sensibles. Esto lo verifica `tests/public-safety.sh`.

## 2. Mapa del repositorio

```text
main.sh                 # Entry point: parsea args, corre wizard, llama run_module()
instalar.sh             # Launcher local one-liner (gitignored, clona y corre el wizard)
lib/
  common.sh             # UI, logging, API de reporte, backups, write_file/run
  detection.sh          # detect_system(), recommend_profile(), check_network()
  users.sh              # ensure_target_user(), validate_username()
  wizard.sh             # Todos los prompts interactivos
scripts/
  base/install.sh       # APT update/upgrade, herramientas base
  personalizacion_bash.sh  # Personalización Bash idempotente (siempre se aplica)
  security/             # baseline.sh (UFW+auto-updates+SSH), hardening.sh, clamav, rkhunter, wazuh-agent
  desktop/install.sh    # XFCE o LXQt
  optimization/apply.sh # Tuning por perfil (baja/media/alta/ultra)
  optional/install.sh   # Dispatcher de todos los --extras
  audit/                # system-health.sh, gui-low-resource.sh
  maintenance/          # Scripts de mantenimiento standalone
config/packages.conf    # Listas de paquetes consumidas por los install scripts
tests/
  smoke.sh              # Combinaciones no interactivas de flags/modos
  public-safety.sh      # Verifica ausencia de secretos, nombres personales, IPs privadas
docs/                   # security.md, profiles.md, components.md, public-security-review.md
```

## 3. Ruteo — para tarea X, ir a...

| Tipo de tarea | Carpeta / archivo | Doc de entrada |
| --- | --- | --- |
| Orquestación, flags, wizard, pasos | `main.sh`, `lib/wizard.sh` | README.md, este archivo |
| Helpers transversales (UI, log, run) | `lib/common.sh` | CLAUDE.md § Architecture |
| Seguridad (UFW, hardening, SSH) | `scripts/security/` | docs/security.md |
| Perfiles de recursos / optimización | `scripts/optimization/` | docs/profiles.md |
| Componentes y extras | `scripts/optional/`, `config/packages.conf` | docs/components.md |
| Tests / CI | `tests/` | README.md § Pruebas |
| Revisión para publicación | `tests/public-safety.sh` | docs/public-security-review.md |

## 4. Orden de lectura para una sesión nueva

1. Este archivo (AGENTS.md).
2. AGENTS.md local del módulo donde cae la tarea, si existe.
3. README.md para ubicar la tarea y la ruta real.
4. CLAUDE.md (referencia detallada de comandos y arquitectura) y la doc específica del área en `docs/`.

Si un dato no aparece en estas fuentes: S/D. No completar por suposición. Ante contradicción entre documentos, gana el de fecha más reciente.

## 5. QUE SI (permitido sin pedir permiso)

- Leer cualquier archivo del repositorio.
- Planificar, analizar, evaluar riesgos, proponer diseños, redactar borradores.
- Ejecutar comandos de solo lectura (listar, leer, `git status`, `git diff`).
- Ejecutar la validación local: `bash -n`, `shellcheck`, `tests/public-safety.sh`, `tests/smoke.sh`, y `main.sh --dry-run`.
- Editar scripts o documentación cuando la tarea lo pida explícitamente.

## 6. QUE NO (prohibido sin instrucción explícita)

- `git push`, force push, crear ramas remotas o tocar el remoto.
- `git add .` / `git add -A`; restore destructivo o reescritura de historial.
- Borrar, mover o sobrescribir archivos de forma masiva.
- Exponer o registrar secretos, tokens, claves, webhooks o credenciales.
- Inventar datos del entorno. Falta evidencia = S/D.
- Renombrar recursos existentes sin autorización y plan de migración (ver Convención de Nombres).

**Restricciones específicas de este repo (no negociables — varias las exige `tests/`):**

- `DRY_RUN=1` debe gatear toda llamada que modifique el sistema; los módulos simulan salida sin actuar.
- UFW nunca se habilita antes de validar un origen SSH seguro (`FIREWALL_SSH_SOURCE` o prompt interactivo); la regla SSH va **antes** del `deny incoming`.
- `sshd -t` debe correr antes de recargar la configuración de SSH.
- La política de entrada de UFW es restrictiva y **nunca** se resetea.
- `PasswordAuthentication` en sshd **no** se modifica.
- Firewall, auto-updates y hardening van ON por defecto; omitir cualquiera requiere acción explícita del usuario y queda registrado en el informe.
- OMV, RDP y Wazuh requieren selección explícita; nunca se agregan por defecto.
- Ningún archivo versionado lleva secretos, nombres personales, IPs privadas ni `legacy-source/`/`.tmp/`.
- Las contraseñas nunca se imprimen en logs; los archivos reemplazados bajo `/etc` se respaldan en `/var/backups/debian-scripts/`.
- Los módulos no hacen `source` de `lib/`: reciben estado solo por variables de entorno (contrato de `run_module()`).

## 7. Principios operativos no negociables

- Documentar antes de cambiar; cambios sensibles necesitan rollback escrito antes.
- Evidencia primero: un comando sin error no prueba que algo funciona.
- Cambio mínimo necesario; no encadenar cambios sin reevaluar riesgo.
- Commit descriptivo solo cuando el cambio esté validado y cerrado. No push sin autorización explícita.
- No agregar herramientas, servicios o dependencias sin justificación concreta.

## 8. Convención de nombres

Aplicar siempre la Convención de Nombres e Identificación Técnica antes de proponer nombres de recursos, repos, servicios, rutas o documentación nueva. FQDN se reserva para servicios resolubles por DNS; repos, carpetas y documentos usan nombres canónicos descriptivos en minúsculas con guiones medios.

## 9. Validación requerida por tipo de archivo

- Scripts `*.sh`: `bash -n` y `shellcheck` deben pasar; `set -Eeuo pipefail` y `#!/usr/bin/env bash` en todos.
- Cambios de flujo/flags: `tests/smoke.sh` en verde.
- Cualquier cambio en archivos versionados: `tests/public-safety.sh` en verde.
- Cambios que tocan el sistema: validar primero con `main.sh --dry-run`.

## 10. Formato de respuesta esperado

Para recomendaciones o cambios:

    ## Evaluación
    ## Riesgos
    ## Recomendación
    ## Implementación
    ## Validación
    ## Rollback (solo si se pide)
    ## Próximo paso

Comandos completos, bloques copy/paste, sin fragmentos ambiguos. No cerrar con preguntas salvo bloqueo real.

## 11. Estado actual

Última actualización: 2026-06-23.

Flujo principal validado en VM Debian 13 limpia, con rutas de prueba para Debian 12 y 13. SSH es componente base (siempre habilitado) y la personalización Bash se aplica en todos los equipos. Los módulos que dependen de infraestructura externa (OMV, Wazuh) deben revisarse con parámetros del entorno destino. El repositorio aún no declara licencia de reutilización.

## Documentos relacionados

- [README.md](./README.md) — mapa y guía de uso.
- [CLAUDE.md](./CLAUDE.md) — adaptador de arranque y referencia detallada para Claude.
- [LLM.md](./LLM.md) — adaptador de arranque para cualquier LLM.
- [docs/](./docs/) — modelo de seguridad, perfiles, componentes, revisión de publicación.
