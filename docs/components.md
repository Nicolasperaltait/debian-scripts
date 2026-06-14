# Selección de componentes

El instalador separa la capacidad del hardware de la instalación efectiva. Un
equipo con muchos recursos puede recibir una configuración mínima, y un equipo
limitado puede conservar todos los controles de seguridad.

## Componentes principales

| Identificador | Alcance | Predeterminado |
|---|---|---|
| `tools` | Herramientas generales de administración | Sí |
| `cli-tools` | `vim-tiny` y `tmux` | Sí en modo CLI |
| `desktop` | Instalación o ampliación de XFCE/LXQt | Sí en modo GUI |
| `optimization` | Ajustes y paquetes asociados al perfil | Sí |
| `firewall` | UFW con entrada denegada por defecto | Sí |
| `auto-updates` | Actualizaciones automáticas de seguridad | Sí |
| `hardening` | AppArmor, sysctl conservador y protección SSH | Sí |
| `audit` | Estado de memoria, swap, disco, servicios, red y puertos | bajos recursos o selección explícita |

La actualización de índices APT se ejecuta como preparación común porque los
componentes seleccionados pueden necesitar instalar paquetes. La actualización
completa del sistema se controla por separado con `--upgrade-system` y
`--skip-upgrade`.

## Selección exacta

```bash
sudo bash main.sh \
  --user operador \
  --mode cli \
  --profile alta \
  --components tools,firewall,auto-updates,hardening,audit \
  --yes
```

Todo componente no listado queda omitido.

## Exclusiones

```bash
sudo bash main.sh \
  --user operador \
  --mode gui \
  --desktop xfce \
  --profile alta \
  --skip-components desktop,optimization \
  --yes
```

Se mantienen los valores predeterminados salvo las exclusiones indicadas.

## Seguridad

En el wizard, desactivar `firewall`, `auto-updates` o `hardening` muestra una
advertencia y solicita una segunda confirmación. La CLI acepta la omisión
cuando fue expresada mediante `--components` o `--skip-components`.

Los extras SSH y RDP instalan UFW como dependencia propia antes de agregar
reglas, incluso si el componente de firewall base fue omitido.

## Informe final

El informe Markdown registra componentes aplicados, simulados u omitidos. Esto
permite distinguir entre un error de instalación y una exclusión voluntaria.
