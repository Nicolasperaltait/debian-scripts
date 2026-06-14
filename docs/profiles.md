# Perfiles de recursos

El wizard recomienda el perfil usando RAM y cantidad de hilos de CPU. El
usuario siempre puede cambiar la recomendación. El perfil no decide qué
componentes se instalan: solo modifica el comportamiento de aquellos que el
usuario seleccionó.

| Perfil | Criterio orientativo | Comportamiento |
|---|---|---|
| Baja | Menos de 8 GB o hasta 2 hilos | Si se elige optimización: ZRAM y logs limitados; ClamAV sin daemon |
| Media | 8-15 GB y al menos 4 hilos | Si se elige optimización: utilidades equilibradas |
| Alta | 16-31 GB y al menos 6 hilos | Si se elige optimización: utilidades adicionales |
| Ultra | 32 GB o más y al menos 8 hilos | Si se elige optimización: utilidades completas y preload |

Para equipos de recursos bajos, monotarea o usados principalmente como cliente
RDP, se recomienda LXQt.

La detección toma como límite el componente más débil. No se aplican
parámetros de kernel experimentales.

## Preset bajos recursos

`gui-low-resource` recomienda GUI LXQt, perfil Baja y auditoría
postinstalación, pero no fuerza esas elecciones. Si se selecciona
`optimization` con perfil Baja, utiliza `systemd-zram-generator`, disponible
en Debian 12 y Debian 13.

No toca automáticamente NetworkManager, `systemd-resolved`, impresión,
Bluetooth, Avahi, SSH, xrdp, suspensión ni hibernación.
