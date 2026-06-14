#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/debian-scripts}"
RUN_ID="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_FILE="$LOG_DIR/clamav_${RUN_ID}.log"
LOCK_FILE="/var/lock/debian-scripts-clamav.lock"

MODE="auto"      # auto|quiet|verbose
ACTION=""        # update|quick|full
TIMEOUT_SECS=""  # vacío = sin timeout

usage() {
  cat <<'EOF'
clamav_scan.sh — escaneo antivirus con ClamAV

Uso:
  sudo ./clamav_scan.sh [--quick | --full | --update] [--quiet|--verbose] [--timeout SEG]

Acciones:
  --quick     Escaneo rápido (home, /etc, /usr/local) con exclusiones típicas
  --full      Escaneo más amplio (home + dirs críticos) con exclusiones típicas
  --update    Reinicia clamav-freshclam (systemd) y sale

Salida:
  --verbose   Muestra progreso en pantalla y log
  --quiet     Solo log a archivo (ideal cron)
  (si no se especifica: verbose si hay TTY, quiet si no hay)

Control:
  --timeout SEG  Corta el scan si excede SEG segundos (ideal cron)

Notas:
  - Usa clamav-freshclam vía systemd (no freshclam manual).
  - Logs en /var/log/debian-scripts/
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: ejecutá con sudo (root requerido)." >&2
    exit 1
  fi
}

# Decide output según modo (quiet => solo log)
log() {
  local msg="[$(date +'%F %T')] $*"
  if [[ "$MODE" == "quiet" ]]; then
    echo "$msg" >>"$LOG_FILE"
  else
    echo "$msg" | tee -a "$LOG_FILE"
  fi
}

run_cmd() {
  if [[ "$MODE" == "quiet" ]]; then
    "$@" >>"$LOG_FILE" 2>&1
  else
    "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

START_TS=0
finalize() {
  local exit_code=$?
  local duration=0
  if [[ "$START_TS" -gt 0 ]]; then
    duration=$(( $(date +%s) - START_TS ))
  fi

  # Si no hizo trabajo (sin acción / lock ocupado), no ensuciar salida ni log
  if [[ "${DID_WORK:-0}" -eq 0 ]]; then
    exit "$exit_code"
  fi

  if [[ $exit_code -eq 130 ]]; then
    log "Cancelado por usuario (Ctrl+C) (duration=${duration}s)"
  elif [[ $exit_code -eq 124 ]]; then
    log "TIMEOUT: ejecución excedió ${TIMEOUT_SECS}s (exit_code=124) (duration=${duration}s)"
  elif [[ $exit_code -ne 0 ]]; then
    log "ERROR: ejecución falló (exit_code=${exit_code}) (duration=${duration}s)"
  else
    log "Fin ClamAV (duration=${duration}s)"
  fi

  log "Log: $LOG_FILE"
  exit "$exit_code"
}

trap finalize EXIT
trap 'exit 130' INT TERM

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quick|--full|--update) ACTION="${1#--}" ;;
    --quiet)   MODE="quiet" ;;
    --verbose) MODE="verbose" ;;
    --timeout)
      shift
      [[ $# -gt 0 ]] || { echo "ERROR: --timeout requiere un valor (segundos)" >&2; exit 2; }
      TIMEOUT_SECS="$1"
      [[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]] || { echo "ERROR: timeout inválido: $TIMEOUT_SECS" >&2; exit 2; }
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

need_root
mkdir -p "$LOG_DIR"
mkdir -p "$(dirname "$LOCK_FILE")"

# Auto mode: verbose si hay TTY, quiet si no (cron)
if [[ "$MODE" == "auto" ]]; then
  if [[ -t 1 ]]; then MODE="verbose"; else MODE="quiet"; fi
fi

# Caso sin ACTION:
# - En TTY: muestro help y salgo 0
# - En cron (quiet): salgo 0 sin output (no rompe cron)
if [[ -z "$ACTION" ]]; then
  if [[ "$MODE" != "quiet" ]]; then
    usage
  fi
  exit 0
fi

START_TS="$(date +%s)"

# Lock anti-doble ejecución
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  # No es error: solo evitamos doble run
  if [[ "$MODE" != "quiet" ]]; then
    echo "Otro scan en ejecución. Saliendo."
  fi
  exit 0
fi

# A partir de acá, sí consideramos que “hizo trabajo” y queremos log+finalize
DID_WORK=1

log "Inicio ClamAV (--${ACTION}) (run_id=${RUN_ID})"
log "Modo: $MODE"
log "Log: $LOG_FILE"

if [[ "$ACTION" == "update" ]]; then
  log "ClamAV: restart clamav-freshclam"
  run_cmd systemctl restart clamav-freshclam
  run_cmd systemctl --no-pager --full status clamav-freshclam
  exit 0
fi

log "ClamAV: ensure services running"
run_cmd systemctl start clamav-freshclam clamav-daemon

# Paths por acción
SCAN_PATHS=()
case "$ACTION" in
  quick) SCAN_PATHS=(/home /etc /usr/local) ;;
  full)  SCAN_PATHS=(/home /etc /usr/local /opt /srv) ;;
  *)
    echo "Acción inválida: $ACTION" >&2
    exit 2
    ;;
esac

log "ClamAV: scan paths: ${SCAN_PATHS[*]}"
log "ClamAV: running clamscan (puede tardar)."

# Exclusiones típicas
EXCLUDES=(
  "--exclude-dir=^/home/[^/]+/\\.cache"
  "--exclude-dir=^/home/[^/]+/\\.local/share/Trash"
  "--exclude-dir=^/home/[^/]+/\\.mozilla"
  "--exclude-dir=^/home/[^/]+/\\.config/Cursor"
)

# Command real (NO function) para que timeout funcione
CLAMSCAN_CMD=(clamscan -r -i --bell "${EXCLUDES[@]}" "${SCAN_PATHS[@]}")

rc=0

if [[ -n "$TIMEOUT_SECS" ]]; then
  log "ClamAV: timeout habilitado: ${TIMEOUT_SECS}s"
fi

# Ejecuta scan:
# - quiet  => no stdout/stderr (cron), todo al log
# - verbose=> replica a pantalla + log
set +e
if [[ -n "$TIMEOUT_SECS" ]]; then
  if [[ "$MODE" == "quiet" ]]; then
    timeout "$TIMEOUT_SECS" "${CLAMSCAN_CMD[@]}" >>"$LOG_FILE" 2>&1
    rc=$?
  else
    timeout "$TIMEOUT_SECS" "${CLAMSCAN_CMD[@]}" 2>&1 | tee -a "$LOG_FILE"
    rc=${PIPESTATUS[0]}
  fi
else
  if [[ "$MODE" == "quiet" ]]; then
    "${CLAMSCAN_CMD[@]}" >>"$LOG_FILE" 2>&1
    rc=$?
  else
    "${CLAMSCAN_CMD[@]}" 2>&1 | tee -a "$LOG_FILE"
    rc=${PIPESTATUS[0]}
  fi
fi
set -e

# Interpretación de clamscan:
# 0 = OK, 1 = virus encontrado, 2 = error
if [[ "$rc" -eq 1 ]]; then
  log "ALERTA: ClamAV encontró archivos infectados (clamscan_exit=1). Revisar log."
  # cron-friendly: en quiet no “falla” el job, pero deja evidencia en el log
  if [[ "$MODE" == "quiet" ]]; then
    rc=0
  fi
elif [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi

# Resumen (extraído del log)
log "ClamAV: summary (últimas líneas relevantes)"
run_cmd bash -lc "grep -E 'Infected files:|Scanned files:|Time:|Start Date:|End Date:' '$LOG_FILE' | tail -n 20 || true"

exit "$rc"