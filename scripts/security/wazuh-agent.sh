#!/usr/bin/env bash
set -Eeuo pipefail

MANAGER=""
VERSION=""
DRY_RUN="${DRY_RUN:-0}"

usage() {
  cat <<'EOF'
Uso:
  sudo bash wazuh-agent.sh --manager IP_O_DNS --version X.Y.Z [--dry-run]
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --manager) MANAGER="${2:-}"; shift 2 ;;
    --version) VERSION="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Argumento desconocido: $1" ;;
  esac
done

[[ "$MANAGER" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "Manager Wazuh inválido."
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Versión Wazuh inválida."

if [[ "$DRY_RUN" -ne 1 && "${EUID}" -ne 0 ]]; then
  fail "Ejecutá este script con sudo/root."
fi

ARCH="${ARCH:-$(dpkg --print-architecture 2>/dev/null || printf 'amd64')}"
DEB_FILE="wazuh-agent_${VERSION}-1_${ARCH}.deb"
DOWNLOAD_URL="https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/${DEB_FILE}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf 'DRY-RUN: descargar %s\n' "$DOWNLOAD_URL"
  printf 'DRY-RUN: instalar agente con manager=%s\n' "$MANAGER"
  exit 0
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

wget --https-only --output-document "$TEMP_DIR/$DEB_FILE" "$DOWNLOAD_URL"
WAZUH_MANAGER="$MANAGER" dpkg -i "$TEMP_DIR/$DEB_FILE"
systemctl daemon-reload
systemctl enable --now wazuh-agent
systemctl --no-pager --full status wazuh-agent
