#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"
init_ui

case "$PROFILE" in
  baja)
    zram_generator="/usr/lib/systemd/system-generators/zram-generator"
    apt_install systemd-zram-generator util-linux
    write_file /etc/systemd/zram-generator.conf '[zram0]
zram-size = min(ram / 2, 4096)
compression-algorithm = zstd
swap-priority = 100'
    write_file /etc/systemd/journald.conf.d/90-debian-scripts.conf '[Journal]
SystemMaxUse=150M
RuntimeMaxUse=50M
MaxRetentionSec=14day'
    run systemctl daemon-reload
    run systemctl stop dev-zram0.swap
    if [[ "$DRY_RUN" -eq 1 ]]; then
      run "$zram_generator" --reset-device zram0
    elif [[ -e /sys/block/zram0 ]]; then
      if swapon --noheadings --show=NAME | grep -Fxq /dev/zram0; then
        run swapoff /dev/zram0
      fi
      run "$zram_generator" --reset-device zram0
    fi
    run systemctl reset-failed systemd-zram-setup@zram0.service dev-zram0.swap
    run systemctl start dev-zram0.swap
    run systemctl is-active --quiet dev-zram0.swap
    run systemctl restart systemd-journald
    run zramctl
    run swapon --show
    run free -h
    ;;
  media)
    read -r -a packages <<<"$PROFILE_MEDIA_PACKAGES"
    apt_install "${packages[@]}"
    ;;
  alta)
    read -r -a packages <<<"$PROFILE_ALTA_PACKAGES"
    apt_install "${packages[@]}"
    ;;
  ultra)
    read -r -a packages <<<"$PROFILE_ULTRA_PACKAGES"
    apt_install "${packages[@]}"
    run systemctl enable --now preload
    ;;
  *) fail "Perfil no soportado: $PROFILE" ;;
esac
