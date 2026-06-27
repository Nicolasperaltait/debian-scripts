# Debloat XFCE

Plantilla de revisión manual para depurar una instalación XFCE sin tocar el
sistema de forma automática.

## Criterio

- Revisar solo paquetes instalados.
- Marcar candidatos antes de borrar.
- No eliminar paquetes esenciales o de soporte del escritorio sin validación.

## Candidatos inici ales

Completar con los nombres exactos detectados en el equipo:

- LibreOffice: `libreoffice*`
- Editores no usados: `vim`, `vim-tiny`, `vim-common`, `vim-runtime`, `neovim`
- Juegos: `aisleriot`, `gnome-*`, `quadrapassel`, `gnome-mahjongg`, `gnome-mines`
- Utilidades opcionales: `mousepad`, `xfce4-notes-plugin`, `xfce4-goodies`
- Multimedia no usada: `rhythmbox`, `cheese`, `shotwell`
- Escaneo/impresión si no se usa: `simple-scan`, `system-config-printer`
- Comunicación no usada: `thunderbird`

## Confirmar antes de borrar

- `xfce4-panel`
- `xfce4-session`
- `xfce4-settings`
- `xfwm4`
- `lightdm`
- `network-manager-gnome`

## Resultado esperado

- Lista de candidatos aprobados.
- Lista de paquetes a conservar por dependencia.
- Orden de desinstalación con rollback.
