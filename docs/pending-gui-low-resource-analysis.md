# Contexto y pendientes del preset GUI liviana

Estado general: preset base incorporado a partir del relevamiento tecnico del
13 de junio de 2026.

Decisiones incorporadas:

- LXQt y QTerminal para uso liviano, monotarea o RDP;
- ZRAM mediante `systemd-zram-generator`;
- journald limitado;
- auditoria postinstalacion;
- Gammastep 90 como modulo opcional;
- no tocar servicios criticos o de hardware de forma generica.

Pendiente de relevamiento directo en equipos reales de bajos recursos:

- CPU, RAM, almacenamiento y swap/zram;
- servicios activos y tiempos de arranque;
- consumo y tiempos de arranque reales con LXQt;
- uso como terminal remota, estacion monotarea o escritorio liviano;
- hardware requerido: audio, Bluetooth, Wi-Fi, impresion y Avahi;
- sesiones xrdp activas y politica de energia esperada;
- MACs Bluetooth, interfaces Wi-Fi y dispositivos de audio;
- configuraciones locales que todavia no esten documentadas.

No trasladar configuraciones especificas a este repositorio sin sanitizarlas y
validar que sean reutilizables en Debian 12 y Debian 13.

Modulos pendientes de evidencia real:

- politicas de energia compatibles con sesiones remotas;
- Bluetooth HID pre-login;
- fallback Wi-Fi especifico del hardware;
- audio USB y HDMI;
- HDMI primario/audio;
- limpieza segura de paquetes con inventario previo.
