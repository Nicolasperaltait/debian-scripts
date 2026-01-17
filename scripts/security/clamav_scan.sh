#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-/var/log/debian-scripts}"
LOG_FILE="$LOG_DIR/clamav_$(date +%Y-%m-%d_%H-%M-%S).log"

usage() {
  cat <<'EOF'
clamav_scan.sh — actualización y escaneo ClamAV

Uso:
  sudo ./clamav_scan.sh --update
  sudo ./clamav_scan.sh --scan-home [--yes]
  sudo ./clamav_scan.sh --full-scan

Opciones:
  --update     Actualiza firmas (freshclam) y asegura servicios
  --scan-home  Escanea /home (pide confirmación salvo --yes)
  --full-scan  Escaneo más amplio (home del usuario + /tmp /etc /usr/local)
  --yes        No preguntar (para automatización)
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

UPDATE=0
SCAN_HOME=0
FULL=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update) UPDATE=1 ;;
    --scan-home) SCAN_HOME=1 ;;
    --full-scan) FULL=1 ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Opción desconocida: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

need_root
mkdir -p "$LOG_DIR"

log "Inicio ClamAV"

if [[ $UPDATE -eq 1 ]]; then
  log "ClamAV: stop freshclam"
  systemctl stop clamav-freshclam || true
  log "ClamAV: freshclam update"
  freshclam | tee -a "$LOG_FILE"
  log "ClamAV: start services"
  systemctl start clamav-freshclam || true
  systemctl start clamav-daemon || true
fi

if [[ $SCAN_HOME -eq 1 ]]; then
  if [[ $ASSUME_YES -ne 1 ]]; then
    read -r -p "¿Ejecutar clamscan recursivo en /home? (y/n): " confirm
    [[ "$confirm" == "y" ]] || { log "Cancelado por el usuario."; exit 0; }
  fi
  log "Scan: clamscan -r /home"
  clamscan -r /home | tee -a "$LOG_FILE"
fi

if [[ $FULL -eq 1 ]]; then
  log "Scan: freshclam (por seguridad)"
  freshclam | tee -a "$LOG_FILE"
  log "Scan: clamscan -r --bell -i /home /tmp /etc /usr/local"
  clamscan -r --bell -i /home /tmp /etc /usr/local | tee -a "$LOG_FILE"
fi

log "Fin ClamAV"
