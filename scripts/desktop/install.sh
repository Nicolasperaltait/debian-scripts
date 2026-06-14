#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"
init_ui

case "$DESKTOP" in
  xfce)
    read -r -a packages <<<"$XFCE_PACKAGES"
    apt_install "${packages[@]}"
    ;;
  lxqt)
    read -r -a packages <<<"$LXQT_PACKAGES"
    apt_install "${packages[@]}"
    ;;
  *) fail "Escritorio no soportado: $DESKTOP" ;;
esac

run systemctl enable NetworkManager
run systemctl enable lightdm
