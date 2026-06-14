#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"
init_ui

if [[ "${ENABLE_AUTO_UPDATES:-1}" -eq 1 ]]; then
  read -r -a auto_update_packages <<<"$AUTO_UPDATE_PACKAGES"
  apt_install "${auto_update_packages[@]}"
  write_file /etc/apt/apt.conf.d/20auto-upgrades 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";'
  run systemctl enable --now unattended-upgrades
else
  info "Actualizaciones automáticas omitidas por decisión del usuario."
fi

if [[ "${ENABLE_FIREWALL:-1}" -eq 1 ]]; then
  read -r -a firewall_packages <<<"$FIREWALL_PACKAGES"
  apt_install "${firewall_packages[@]}"

  run ufw default deny incoming
  run ufw default allow outgoing

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    ssh_source="${SSH_CONNECTION%% *}"
    info "Se preservará SSH únicamente desde la IP de la sesión activa: $ssh_source"
    run ufw limit from "$ssh_source" to any port 22 proto tcp comment "SSH sesión activa"
  elif systemctl is-active --quiet ssh 2>/dev/null; then
    warn "OpenSSH está activo, pero no hay una sesión remota detectable."
    warn "No se abrirá el firewall globalmente; seleccioná el extra ssh para definir el origen permitido."
  fi

  run ufw --force enable
else
  warn "Firewall UFW omitido por decisión explícita del usuario."
fi
