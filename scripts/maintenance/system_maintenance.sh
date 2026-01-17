#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/debian-scripts}"
RUN_ID="$(date +%Y-%m-%d_%H-%M-%S)"
LOG_FILE="$LOG_DIR/system_maintenance_${RUN_ID}.log"

usage() {
  cat <<'EOF'
system_maintenance.sh — mantenimiento básico Debian

Uso:
  sudo ./system_maintenance.sh [--install] [--upgrade] [--clean] [--all] [--quiet|--verbose]

Opciones:
  --install   Instala dependencias base (ufw, clamav, clamav-daemon)
  --upgrade   Ejecuta apt-get update && apt-get upgrade -y
  --clean     Ejecuta apt-get clean && apt-get autoremove -y
  --all       Ejecuta install + upgrade + clean

Salida:
  --verbose   Muestra progreso en pantalla + log a archivo (útil en terminal). (default si hay TTY)
  --quiet     No muestra nada en pantalla; solo log a archivo (ideal cron). (default sin TTY)

Notas:
  - Requiere ejecución como root (sudo).
  - Log en /var/log/debian-scripts por defecto (configurable con LOG_DIR).
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: ejecutá con sudo (root requerido)." >&2
    exit 1
  fi
}

# Determina si hay terminal interactiva
is_tty() {
  [[ -t 1 ]]
}

# Logger: siempre escribe a archivo; opcionalmente también a pantalla
VERBOSE=1
log() {
  local msg="[$(date +'%F %T')] $*"
  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "$msg" | tee -a "$LOG_FILE"
  else
    echo "$msg" >> "$LOG_FILE"
  fi
}

# Para capturar comandos largos: siempre al log; a pantalla solo si verbose
run_cmd() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    "$@" 2>&1 | tee -a "$LOG_FILE"
  else
    "$@" >> "$LOG_FILE" 2>&1
  fi
}

APT_INSTALL=0
APT_UPGRADE=0
APT_CLEAN=0

# Defaults según contexto: si NO hay TTY (cron), quiet.
if is_tty; then
  VERBOSE=1
else
  VERBOSE=0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) APT_INSTALL=1 ;;
    --upgrade) APT_UPGRADE=1 ;;
    --clean)   APT_CLEAN=1 ;;
    --all)     APT_INSTALL=1; APT_UPGRADE=1; APT_CLEAN=1 ;;
    --verbose) VERBOSE=1 ;;
    --quiet)   VERBOSE=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

need_root
mkdir -p "$LOG_DIR"

START_EPOCH="$(date +%s)"
log "Inicio mantenimiento Debian (run_id=${RUN_ID})"
log "Modo: $([[ "$VERBOSE" -eq 1 ]] && echo 'verbose' || echo 'quiet')"

# Evita prompts interactivos en apt-get
export DEBIAN_FRONTEND=noninteractive

if [[ $APT_UPGRADE -eq 1 ]]; then
  log "APT: update"
  run_cmd apt-get update
  log "APT: upgrade -y"
  run_cmd apt-get upgrade -y
fi

if [[ $APT_INSTALL -eq 1 ]]; then
  log "APT: install ufw clamav clamav-daemon"
  run_cmd apt-get install -y ufw clamav clamav-daemon
fi

if [[ $APT_CLEAN -eq 1 ]]; then
  log "APT: clean"
  run_cmd apt-get clean
  log "APT: autoremove -y"
  run_cmd apt-get autoremove -y
fi

END_EPOCH="$(date +%s)"
DUR="$((END_EPOCH - START_EPOCH))"
log "Fin mantenimiento Debian (duration=${DUR}s)"
log "Log: ${LOG_FILE}"
