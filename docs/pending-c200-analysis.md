# Contexto y pendientes específicos de equipos de bajos recursos

Estado general: preset base incorporado a partir del dump técnico del
13 de junio de 2026.

Decisiones incorporadas:

- LXQt y QTerminal para uso liviano, monotarea o RDP;
- ZRAM mediante `systemd-zram-generator`;
- journald limitado;
- auditoría postinstalación;
- Gammastep 90 como módulo opcional;
- no tocar servicios críticos o de hardware de forma genérica.

Pendiente de relevamiento directo en equipos de bajos recursos reales:

- CPU, RAM, almacenamiento y swap/zram;
- servicios activos y tiempos de arranque;
- consumo y tiempos de arranque reales con LXQt;
- uso como terminal remota, estación monotarea o escritorio liviano;
- hardware requerido: audio, Bluetooth, Wi-Fi, impresión y Avahi;
- sesiones xrdp activas y política de energía esperada;
- MACs Bluetooth, interfaces Wi-Fi y dispositivos de audio;
- configuraciones locales que todavía no estén documentadas.

No trasladar configuraciones específicas a este repositorio sin sanitizarlas y
validar que sean reutilizables en Debian 12 y Debian 13.

Módulos pendientes de evidencia real:

- políticas de energía compatibles con sesiones remotas;
- Bluetooth HID pre-login;
- fallback Wi-Fi específico del hardware;
- audio USB y HDMI;
- HDMI primario/audio;
- limpieza segura de paquetes con inventario previo.
