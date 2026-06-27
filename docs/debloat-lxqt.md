# Debloat LXQt

Plantilla de revisión manual para depurar una instalación LXQt sin tocar el
sistema de forma automática.

## Criterio

- Revisar solo paquetes instalados.
- Marcar candidatos antes de borrar.
- No eliminar paquetes esenciales o de soporte del escritorio sin validación.

## Candidatos iniciales

Completar con los nombres exactos detectados en el equipo:

- LibreOffice: `libreoffice*`
- Editores no usados: `vim`, `vim-tiny`, `vim-common`, `vim-runtime`, `neovim`
- Juegos: `aisleriot`, `gnome-*`, `quadrapassel`, `gnome-mahjongg`, `gnome-mines`
- Utilidades opcionales: `featherpad`, `screengrab`
- Multimedia no usada: `rhythmbox`, `cheese`, `shotwell`
- Escaneo/impresión si no se usa: `simple-scan`, `system-config-printer`
- Comunicación no usada: `thunderbird`
- App extras que no uses: `lximage-qt`, `qpdfview`, `qalculate-gtk`

## Confirmar antes de borrar

- `lxqt-core`
- `lxqt-panel`
- `lxqt-session`
- `pcmanfm-qt`
- `openbox`
- `qterminal`
- `sddm` o el display manager elegido
- `network-manager-gnome`

## Resultado esperado

- Lista de candidatos aprobados.
- Lista de paquetes a conservar por dependencia.
- Orden de desinstalación con rollback.
