# Revisión de seguridad para publicación

Fecha de revisión: 14 de junio de 2026.

## Alcance

La revisión cubre el árbol activo, el historial Git, los flujos privilegiados,
las descargas externas y la información visible en un repositorio público.

## Controles aplicados

- nombres de usuarios reemplazados por valores genéricos;
- selección interactiva del usuario basada en `SUDO_USER`;
- ejemplos de red reemplazados por direcciones reservadas para documentación;
- material histórico retirado del árbol público y excluido por `.gitignore`;
- prueba automática contra nombres personales, IP privadas y secretos comunes;
- logs e informes fuera del repositorio, con permisos restringidos;
- backups centralizados fuera de `/etc`;
- validación de SSH antes de recargar;
- smoke tests sobre CLI, GUI, perfiles, hardening, ZRAM e informes.

## Riesgos aceptados

| Prioridad | Riesgo | Estado |
|---|---|---|
| Media | `apt-get upgrade -y` puede ampliar el alcance del cambio | El wizard pregunta; CLI admite `--skip-upgrade` |
| Media | UFW, auto-updates o hardening pueden omitirse | Defaults seguros, doble confirmación interactiva e informe explícito |
| Media | El extra `maintenance` puede ejecutar `apt-get autoremove -y` | Requiere confirmación específica |
| Media | OMV modifica `/etc/fstab` y guarda una credencial SMB con modo `0600` | Solo por selección explícita y con backup |
| Media | RDP abre `3389/tcp` mediante limitación UFW | Solo por selección explícita |

## Cambios recomendados

### 1. Verificación del agente Wazuh

El instalador descarga un paquete `.deb` por HTTPS desde el repositorio oficial,
pero actualmente no valida una suma SHA-256 ni una firma del artefacto antes de
ejecutar `dpkg -i`.

Recomendación: migrar al repositorio APT firmado oficial o exigir una suma
esperada obtenida desde una fuente independiente.

### 2. Separar actualización del bootstrap

El módulo base actualiza todos los paquetes instalados. Es seguro para una VM
limpia, pero aumenta tiempo, superficie de cambio y probabilidad de requerir
reinicio.

Implementado: el wizard pregunta y la CLI permite `--upgrade-system` o
`--skip-upgrade`.

### 3. Evitar `autoremove` automático

Aunque solo se ejecuta mediante el extra `maintenance`, `autoremove -y` puede
retirar paquetes que el administrador espera conservar.

Implementado: muestra `apt-get -s autoremove` y requiere una segunda
confirmación antes de aplicar la eliminación.

### 4. Historial Git

El árbol actual queda sanitizado, pero commits anteriores pueden conservar
nombres o rutas históricas. No se detectaron claves privadas, tokens ni
credenciales conocidas.

Recomendación: si se requiere eliminación completa de metadatos personales,
reescribir el historial y hacer `force push` coordinado. Esto invalida clones y
debe realizarse como una operación separada con backup.

### 5. Licencia

El repositorio es público, pero no tiene una licencia explícita.

Recomendación: elegir una licencia compatible con el objetivo del proyecto
antes de recibir contribuciones o promover reutilización externa.

## Criterio operativo

El instalador debe probarse primero con `--dry-run`, conservar acceso local a
la máquina y revisar el informe `.md` generado al finalizar. Los módulos de
infraestructura externa no deben ejecutarse con valores copiados de otro
entorno.
