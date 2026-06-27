#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"
init_ui

configure_xfce_vm_fluidity() {
  local home helper desktop_file

  [[ "${INSTALL_MODE:-}" == "gui" && "${DESKTOP:-}" == "xfce" ]] || return 0

  write_file /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml '<?xml version="1.0" encoding="UTF-8"?>

<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
  </property>
</channel>'

  if [[ "$DRY_RUN" -eq 1 ]]; then
    home="/home/${TARGET_USER:-operador}"
  else
    home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  fi
  [[ -n "$home" ]] || fail "No se encontró HOME para $TARGET_USER."

  helper="$home/.local/bin/debian-scripts-xfce-vm-tuning"
  desktop_file="$home/.config/autostart/debian-scripts-xfce-vm-tuning.desktop"

  run install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" \
    "$home/.local/bin" "$home/.config/autostart"
  write_file "$helper" '#!/usr/bin/env bash
set -Eeuo pipefail

if command -v xfconf-query >/dev/null 2>&1; then
  xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
fi'
  run chmod 0755 "$helper"
  run chown "$TARGET_USER:$TARGET_USER" "$helper"

  write_file "$desktop_file" "[Desktop Entry]
Type=Application
Version=1.0
Name=Debian Scripts XFCE VM tuning
Comment=Disable XFCE compositing inside virtual machines
Exec=$helper
Terminal=false
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-XFCE-Autostart-Override=true"
  run chmod 0644 "$desktop_file"
  run chown "$TARGET_USER:$TARGET_USER" "$desktop_file"
}

apply_vm_tuning() {
  local -a packages=()

  [[ "${IS_VM:-0}" -eq 1 ]] || return 0

  section "Ajustes para VM"
  apt_install util-linux
  write_file /etc/sysctl.d/80-debian-scripts-vm.conf 'vm.swappiness = 10
vm.vfs_cache_pressure = 100'
  run sysctl --system
  run systemctl enable --now fstrim.timer

  if [[ "${VIRTUALIZATION_TYPE:-virtual}" == "vmware" ]]; then
    if [[ "${INSTALL_MODE:-}" == "gui" ]]; then
      read -r -a packages <<<"$VMWARE_GUI_PACKAGES"
    else
      read -r -a packages <<<"$VMWARE_CLI_PACKAGES"
    fi
    apt_install "${packages[@]}"
    run systemctl enable --now open-vm-tools.service
    if [[ "$DRY_RUN" -eq 1 ]] || command -v vmware-toolbox-cmd >/dev/null 2>&1; then
      run vmware-toolbox-cmd timesync disable
    else
      warn "vmware-toolbox-cmd no está disponible; no se pudo deshabilitar timesync de VMware."
    fi
  fi

  configure_xfce_vm_fluidity
}

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

apply_vm_tuning
