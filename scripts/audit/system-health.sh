#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
init_ui

capture() {
  local label="$1"
  shift
  section "$label"
  log_line "AUDIT: $(quote_cmd "$@")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN AUDIT: $(quote_cmd "$@")"
    return
  fi
  if ! "$@"; then
    warn "Auditoría no disponible: $(quote_cmd "$@")"
  fi
}

capture "Memoria" free -h
capture "Swap" swapon --show
capture "ZRAM" zramctl
capture "Almacenamiento" lsblk -o NAME,ROTA,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL

section "Servicios fallidos"
log_line "AUDIT: systemctl --failed --no-legend --plain --no-pager"
if [[ "$DRY_RUN" -eq 1 ]]; then
  info "DRY-RUN AUDIT: systemctl --failed --no-legend --plain --no-pager"
else
  failed_units="$(systemctl --failed --no-legend --plain --no-pager)"
  if [[ -n "$failed_units" ]]; then
    printf '%s\n' "$failed_units"
    fail "La auditoría detectó unidades systemd fallidas."
  fi
  ok "No hay unidades systemd fallidas."
fi

if command -v nmcli >/dev/null 2>&1 || [[ "$DRY_RUN" -eq 1 ]]; then
  capture "Red NetworkManager" nmcli device status
fi

if command -v ss >/dev/null 2>&1 || [[ "$DRY_RUN" -eq 1 ]]; then
  capture "Puertos remotos" ss -tulpen
fi
