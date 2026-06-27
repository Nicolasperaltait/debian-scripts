# Perfiles de recursos

El wizard recomienda el perfil usando RAM y cantidad de hilos de CPU. El
usuario siempre puede cambiar la recomendación. El perfil no decide qué
componentes se instalan: solo modifica el comportamiento de aquellos que el
usuario seleccionó.

| Perfil | RAM | CPU | Comportamiento |
|---|---|---|---|
| Baja | Menos de 4 GB | Hasta 2 hilos | Si se elige optimización: ZRAM y logs limitados; ClamAV sin daemon |
| Media | 4 GB a menos de 8 GB | 3 a 4 hilos | Si se elige optimización: utilidades equilibradas |
| Alta | 8 GB a menos de 16 GB | 5 a 8 hilos | Si se elige optimización: utilidades adicionales |
| Ultra | 16 GB o más | Más de 8 hilos | Si se elige optimización: utilidades completas y preload |

Para modo GUI, el instalador recomienda escritorio según perfil cuando el usuario
no indicó uno explícitamente: `baja` usa LXQt; `media`, `alta` y `ultra` usan
XFCE.

La detección toma como límite el componente más débil. No se aplican
parámetros de kernel experimentales.

## Preset GUI Liviana

`gui-low-resource` recomienda GUI LXQt, perfil Baja y auditoría
postinstalación, pero no fuerza esas elecciones. Si se selecciona
`optimization` con perfil Baja, utiliza `systemd-zram-generator`, disponible
en Debian 12 y Debian 13.

No toca automáticamente NetworkManager, `systemd-resolved`, impresión,
Bluetooth, Avahi, SSH, xrdp, suspensión ni hibernación.

## VM y VMware

El wizard pregunta si Debian corre dentro de una VM y la CLI acepta
`--virtualization auto|baremetal|vm|vmware`. Si se selecciona `optimization` en
una VM, aplica ajustes conservadores: `vm.swappiness=10`, TRIM periódico y,
para VMware, Open VM Tools. En VMware deshabilita la sincronización horaria de
VMware para dejar la hora bajo control de NTP/systemd y, si el escritorio es
XFCE, deja el compositor desactivado para mejorar fluidez.
