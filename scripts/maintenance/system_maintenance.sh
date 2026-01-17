#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/debian-scripts}"
LOG_FILE="$LOG_DIR/system_maintenance_$(date +%Y-%m-%d_%H-%M-%S).log"

usage() {
  cat <<'EOF'
system_maintenance.sh — mantenimiento básico Debian

Uso:
  sudo ./system_maintenance.sh [--install] [--upgrade] [--clean] [--all]

Opciones:
  --install   Instala dependencias base (ufw, clamav, clamav-daemon)
  --upgrade   Ejecuta apt update && apt upgrade -y
  --clean     Ejecuta apt clean && apt autoremove -y
  --all       Ejecuta install + upgrade + clean

Notas:
  - Requiere ejecución como root (sudo).
  - Log en /var/log/debian-scripts por defecto.
EOF
}

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: ejecutá con sudo (root requerido)." >&2
    exit 1
  fi
}

log() {
  echo "[$(date +'%F %T')] $*" | tee -a "$LOG_FILE"
}

APT_INSTALL=0
APT_UPGRADE=0
APT_CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) APT_INSTALL=1 ;;
    --upgrade) APT_UPGRADE=1 ;;
    --clean)   APT_CLEAN=1 ;;
    --all)     APT_INSTALL=1; APT_UPGRADE=1; APT_CLEAN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

need_root
mkdir -p "$LOG_DIR"

log "Inicio mantenimiento Debian"

if [[ $APT_UPGRADE -eq 1 ]]; then
  log "APT: update"
  apt update | tee -a "$LOG_FILE"
  log "APT: upgrade -y"
  apt upgrade -y | tee -a "$LOG_FILE"
fi

if [[ $APT_INSTALL -eq 1 ]]; then
  log "APT: install ufw clamav clamav-daemon"
  apt install -y ufw clamav clamav-daemon | tee -a "$LOG_FILE"
fi

if [[ $APT_CLEAN -eq 1 ]]; then
  log "APT: clean"
  apt clean | tee -a "$LOG_FILE"
  log "APT: autoremove -y"
  apt autoremove -y | tee -a "$LOG_FILE"
fi

log "Fin mantenimiento Debian"
