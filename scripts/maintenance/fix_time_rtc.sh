#!/usr/bin/env bash
set -euo pipefail

# fix-time-rtc.sh
# - Setea timezone (default: America/Argentina/Buenos_Aires)
# - Configura RTC en UTC (RTC in local TZ: no)
# - Ajusta reloj del sistema y sincroniza hwclock
# - Hace backups antes de tocar config persistente
#
# Uso:
#   ./fix-time-rtc.sh
#   ./fix-time-rtc.sh "America/Argentina/Buenos_Aires"
#   TARGET_TZ="America/Argentina/Buenos_Aires" ./fix-time-rtc.sh

TARGET_TZ="${1:-${TARGET_TZ:-America/Argentina/Buenos_Aires}}"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    exec sudo -E bash "$0" "$@"
  fi
}

log() {
  printf '%s\n' "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

validate_timezone() {
  if ! timedatectl list-timezones | grep -Fxq "$TARGET_TZ"; then
    fail "Timezone invalida: '$TARGET_TZ'. Proba con: timedatectl list-timezones | grep -i argentina"
  fi
}

backup_configs() {
  local ts backup_dir
  ts="$(date +%F_%H%M%S)"
  backup_dir="/var/backups/timefix-${ts}"
  mkdir -p "$backup_dir"
  chmod 700 "$backup_dir"

  # Backup de /etc/localtime y /etc/adjtime (si existen)
  if [[ -e /etc/localtime ]]; then
    cp -a /etc/localtime "${backup_dir}/localtime.bak"
  fi
  if [[ -f /etc/adjtime ]]; then
    cp -a /etc/adjtime "${backup_dir}/adjtime.bak"
  fi

  log "Backup creado en: $backup_dir"
}

get_current_tz() {
  timedatectl show -p Timezone --value 2>/dev/null || true
}

get_rtc_local_flag() {
  # Devuelve "yes" o "no" cuando está disponible
  timedatectl show -p LocalRTC --value 2>/dev/null || true
}

ensure_ntp() {
  # Si el sistema usa systemd-timesyncd, esto lo enciende.
  # No toca NetworkManager (solo habilita NTP via timedatectl).
  timedatectl set-ntp true >/dev/null 2>&1 || true

  if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-timesyncd\.service'; then
    systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || true
  fi
}

apply_timezone() {
  local cur_tz
  cur_tz="$(get_current_tz)"
  if [[ "$cur_tz" != "$TARGET_TZ" ]]; then
    log "Cambiando timezone: '$cur_tz' -> '$TARGET_TZ'"
    timedatectl set-timezone "$TARGET_TZ"
  else
    log "Timezone ya correcto: $TARGET_TZ"
  fi
}

apply_rtc_utc() {
  local localrtc
  localrtc="$(get_rtc_local_flag)"

  # LocalRTC: 0 = RTC en UTC; 1 = RTC en hora local
  if [[ "$localrtc" == "1" ]]; then
    log "Cambiando RTC a UTC (LocalRTC: 1 -> 0) y ajustando reloj del sistema..."
    timedatectl set-local-rtc 0 --adjust-system-clock
  else
    log "RTC ya en UTC (LocalRTC: $localrtc)"
  fi

  # Sincroniza el hardware clock con el system clock
  hwclock --systohc
}

post_checks() {
  log ""
  log "=== POST-CHECK: timedatectl ==="
  timedatectl status

  log ""
  log "=== POST-CHECK: hwclock ==="
  hwclock --show || true

  log ""
  log "=== POST-CHECK: journal (local) ==="
  journalctl -b -n 5 --no-pager -o short-iso || true

  log ""
  log "=== POST-CHECK: journal (UTC) ==="
  journalctl -b -n 5 --no-pager -o short-iso --utc || true

  log ""
  log "Listo. Si ves +00:00 en logs, es UTC (normal). En local deberías ver -03:00."
}

main() {
  need_root "$@"
  validate_timezone
  backup_configs
  ensure_ntp
  apply_timezone
  apply_rtc_utc
  post_checks
}

main "$@"
