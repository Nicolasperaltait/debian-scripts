# Debian Scripts

[![Shell validation](https://github.com/Nicolasperaltait/debian-scripts/actions/workflows/shell.yml/badge.svg)](https://github.com/Nicolasperaltait/debian-scripts/actions/workflows/shell.yml)
![Debian](https://img.shields.io/badge/Debian-12%20%7C%2013-A81D33?logo=debian&logoColor=white)
![Bash](https://img.shields.io/badge/Bash-strict%20mode-4EAA25?logo=gnubash&logoColor=white)
![Security](https://img.shields.io/badge/security-first-1f6feb)

Bootstrap modular y auditable para preparar estaciones Debian desde una
instalación limpia. La capacidad del hardware se usa como recomendación, pero
el usuario decide por separado qué herramientas, controles y ajustes instalar.

## Qué ofrece

| Área | Capacidades |
|---|---|
| Sistema | Debian 12/13, CLI o GUI, usuarios existentes o nuevos |
| Escritorio | XFCE o LXQt |
| Selección | Componentes principales y extras elegibles de forma independiente |
| VM | Detección/confirmación de VM y ajustes específicos para VMware |
| Optimización | Perfiles Baja, Media, Alta y Ultra; ZRAM solo si se selecciona |
| Seguridad | UFW, actualizaciones automáticas, AppArmor, sysctl, SSH validado y Fail2ban |
| Extras | SSH, Zsh, Flatpak, fuentes, RDP, ClamAV, RKHunter, Wazuh, OMV y más |
| Evidencia | Log completo e informe final Markdown por ejecución |
| Calidad | Sintaxis Bash, ShellCheck, smoke tests y controles de publicación |

## Inicio seguro

Cloná el repositorio:

```bash
git clone https://github.com/Nicolasperaltait/debian-scripts.git
cd debian-scripts
```

Revisá primero el plan sin modificar el sistema:

```bash
sudo bash main.sh --dry-run \
  --user operador \
  --virtualization auto \
  --preset gui-low-resource \
  --mode gui \
  --desktop lxqt \
  --profile baja \
  --components tools,desktop,optimization,firewall,auto-updates,hardening,audit \
  --extras ssh,zsh,clamav,rkhunter,apps \
  --apps obsidian,vlc \
  --nvidia audit \
  --yes
```

Después ejecutá el wizard interactivo:

```bash
sudo bash main.sh
```

El instalador muestra el plan antes de aplicar cambios y nunca reinicia el
equipo automáticamente. Los módulos críticos siempre solicitan sus parámetros
y una confirmación específica, incluso cuando el plan general usa `--yes`.

El wizard permite elegir el usuario principal y agregar tantos usuarios
adicionales como sean necesarios, cada uno como estándar o administrador. Para
automatización:

```bash
sudo bash main.sh \
  --user operador \
  --add-user auditor:standard \
  --add-user soporte:admin \
  --mode cli \
  --profile media \
  --yes
```

También pregunta si debe actualizar todos los paquetes. En automatización puede
elegirse explícitamente con `--upgrade-system` o `--skip-upgrade`.

En modo GUI, si no se indica `--desktop`, el instalador recomienda LXQt para
perfil `baja` y XFCE para perfiles `media`, `alta` o `ultra`. En modo interactivo pregunta
si Debian corre dentro de una VM; en automatización usa detección automática o
`--virtualization vmware|vm|baremetal`. Cuando detecta VMware y se selecciona
`optimization`, instala Open VM Tools, deshabilita la sincronización horaria de
VMware para evitar conflictos con NTP, activa TRIM periódico y reduce efectos
gráficos de XFCE para mejorar fluidez.

## Selección flexible

El instalador separa tres conceptos:

1. **Tipo de sistema:** CLI o GUI.
2. **Perfil:** se recomienda por RAM y CPU, usando el recurso más limitado.
3. **Componentes, extras, apps y debloat:** determinan concretamente qué se instala o audita.

Componentes principales disponibles:

```text
tools, cli-tools, desktop, optimization, firewall, auto-updates,
hardening, audit
```

Equipo potente con una instalación mínima y auditable:

```bash
sudo bash main.sh \
  --user operador \
  --mode cli \
  --profile ultra \
  --components tools,firewall,auto-updates,hardening,audit \
  --skip-upgrade \
  --yes
```

Equipo GUI existente donde no se desea reinstalar escritorio ni aplicar
optimizaciones:

```bash
sudo bash main.sh \
  --user operador \
  --mode gui \
  --desktop xfce \
  --profile alta \
  --skip-components desktop,optimization \
  --yes
```

`--components` y `--skip-components` son mutuamente excluyentes. En el wizard,
firewall, actualizaciones automáticas y hardening están recomendados; omitirlos
requiere una segunda confirmación y queda registrado en el informe.

Si OpenSSH ya está activo, el instalador exige una regla de origen antes de
habilitar UFW. En ejecuciones no interactivas, definí una IP o red CIDR segura:

```bash
sudo env FIREWALL_SSH_SOURCE=192.0.2.10/32 bash main.sh \
  --user operador --mode cli --profile media \
  --components firewall,auto-updates,hardening,audit --yes
```

`FIREWALL_SSH_SOURCE=any` conserva acceso desde cualquier origen, pero solo
debe usarse conscientemente y aplica limitación de intentos.

## Flujo principal

```text
Detección del sistema
        |
        v
Recomendaciones de hardware
        |
        v
Selección independiente y confirmación
        |
        v
APT -> componentes elegidos -> apps/debloat GUI -> extras -> auditoría opcional
        |
        v
Log completo e informe Markdown
```

## Seguridad por diseño

- Firewall, actualizaciones automáticas y hardening están activos por defecto.
- Su omisión requiere una decisión explícita y queda visible en el informe.
- UFW usa política de entrada restrictiva y no se resetea.
- SSH se valida con `sshd -t` antes de recargar su configuración.
- No se modifica `PasswordAuthentication`.
- OMV, RDP, Wazuh y mantenimiento requieren selección explícita.
- SSH y RDP preguntan qué IP o red puede acceder antes de abrir el firewall.
- Una sesión SSH activa conserva únicamente la IP remota detectada, no una
  apertura global.
- OMV solicita servidor, share, usuario, dominio y contraseña oculta.
- Las contraseñas no se imprimen en los logs.
- Los archivos reemplazados se respaldan en `/var/backups/debian-scripts/`.
- Los logs quedan protegidos en el HOME del usuario que invocó `sudo`.
- `legacy-source/` está excluido del repositorio y no forma parte del flujo.

El script usa privilegios administrativos y modifica paquetes, servicios,
firewall y archivos bajo `/etc`. Ejecutalo primero con `--dry-run` y mantené
acceso local a la máquina durante la primera instalación.

## Informe final

Cada ejecución genera:

```text
~/debian-scripts-logs/install_FECHA_HORA.ID.log
~/debian-scripts-logs/install_FECHA_HORA.ID.md
```

El informe también se imprime en la terminal:

```text
| Categoría       | Componente                     | Estado   |
|-----------------|--------------------------------|----------|
| Seguridad       | Hardening reforzado            | Aplicado |
| Personalización | Zsh y modificación de terminal | Aplicado |
| Seguridad       | ClamAV bajo demanda            | Aplicado |
| Validación      | Auditoría final del sistema    | Correcto |
```

## Preset para bajos recursos

`gui-low-resource` recomienda GUI, LXQt, perfil Baja y auditoría final. Ya no
sobrescribe elecciones explícitas: también puede usarse con CLI, otro perfil o
sin optimización. Cuando se selecciona la combinación recomendada, configura
QTerminal, ZRAM y límites conservadores de `journald`.

No deshabilita automáticamente NetworkManager, impresión, Bluetooth, Avahi,
SSH ni XRDP.

## Apps, NVIDIA y debloat

- En `gui`, el wizard muestra siempre la selección de aplicaciones de escritorio con prioridad APT.
- Chrome y VS Code usan repositorios APT del proveedor; LibreWolf se habilita por `extrepo`.
- Obsidian, VLC, Bitwarden y Remmina usan Flatpak solo cuando se seleccionan.
- Si se detecta NVIDIA, el wizard exige una decisión explícita antes de instalar drivers.
- En `gui`, el wizard muestra siempre debloat seguro; primero inventario y simulación `apt-get -s purge`.

## Pruebas

```bash
bash tests/public-safety.sh
bash tests/smoke.sh
```

La integración continua valida:

- sintaxis Bash;
- ShellCheck;
- ausencia de material histórico versionado;
- ausencia de secretos conocidos, nombres personales e IP privadas;
- combinaciones CLI/GUI y perfiles de recursos;
- selección exacta y exclusión de componentes;
- hardening, ZRAM, auditoría y generación de informes.

## Documentación

- [Modelo de seguridad](docs/security.md)
- [Perfiles de recursos](docs/profiles.md)
- [Selección de componentes](docs/components.md)
- [Debloat XFCE](docs/debloat-xfce.md)
- [Debloat LXQt](docs/debloat-lxqt.md)
- [Preset GUI liviana - pendientes y validación](docs/pending-gui-low-resource-analysis.md)
- [Revisión para publicación](docs/public-security-review.md)

## Estado del proyecto

El flujo principal está validado en una VM Debian 13 limpia y dispone de rutas
de prueba para Debian 12 y Debian 13. Los módulos que dependen de
infraestructura externa deben revisarse con parámetros del entorno destino.

El repositorio aún no declara una licencia de reutilización. Antes de aceptar
contribuciones externas se debe elegir y publicar una licencia explícita.
