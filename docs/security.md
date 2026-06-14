# Seguridad

## Flujo obligatorio

`main.sh` aplica dos etapas de seguridad:

1. `scripts/security/baseline.sh`: actualizaciones automáticas y UFW.
2. `scripts/security/hardening.sh`: AppArmor, sysctl conservador y protección
   SSH con Fail2ban cuando OpenSSH está instalado.

El hardening se ejecuta después de los extras para validar y proteger SSH si
fue seleccionado durante la misma instalación.

## Decisiones de compatibilidad

La implementación no incorpora ajustes históricos que podían romper
servicios o bloquear acceso:

- no ejecuta `ufw --force reset`;
- no abre RDP ni SSH si esos módulos no fueron seleccionados;
- no cambia `PasswordAuthentication`;
- no fuerza `net.ipv4.ip_forward = 0`;
- no deshabilita user namespaces;
- valida `sshd -t` y revierte el drop-in si la validación falla.

## Scripts operativos

```bash
sudo bash scripts/security/clamav_scan.sh --quick --verbose
sudo bash scripts/security/rkhunter_check.sh --check --verbose
sudo bash scripts/maintenance/system_maintenance.sh --upgrade --clean
sudo bash scripts/maintenance/fix_time_rtc.sh
```

Wazuh requiere parámetros explícitos:

```bash
sudo bash scripts/security/wazuh-agent.sh \
  --manager wazuh.example.internal \
  --version 4.14.5
```

## Rollback

Los archivos reemplazados se respaldan bajo
`/var/backups/debian-scripts/FECHA_HORA/RUTA_ORIGINAL`.

Para revertir:

1. restaurar el backup correspondiente en `/etc`;
2. ejecutar `sudo sysctl --system` si se revirtió el archivo sysctl;
3. ejecutar `sudo sshd -t` antes de recargar SSH;
4. recargar el servicio afectado con `sudo systemctl reload|restart SERVICIO`.
