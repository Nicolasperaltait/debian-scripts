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
  ssh_source=""
  read -r -a firewall_packages <<<"$FIREWALL_PACKAGES"
  apt_install "${firewall_packages[@]}"

  if ssh_source="$(current_ssh_source)"; then
    info "Se preservará SSH únicamente desde la IP de la sesión activa: $ssh_source"
    run ufw limit from "$ssh_source" to any port 22 proto tcp comment "SSH sesión activa"
  elif systemctl is-active --quiet ssh 2>/dev/null; then
    warn "OpenSSH está activo, pero no hay una sesión remota detectable."
    if [[ -n "${FIREWALL_SSH_SOURCE:-}" ]]; then
      ssh_source="$FIREWALL_SSH_SOURCE"
      [[ "$ssh_source" == "any" ]] ||
        validate_firewall_source "$ssh_source" ||
        fail "FIREWALL_SSH_SOURCE no contiene una IP o red CIDR válida."
    elif [[ -t 0 || "${DEBIAN_SCRIPTS_TEST:-0}" == "1" ]]; then
      ssh_source="$(choose_firewall_source "SSH" 1)"
    else
      fail "Se rechazó activar UFW sin una regla SSH. Definí FIREWALL_SSH_SOURCE=IP/CIDR o ejecutá de forma interactiva."
    fi

    [[ "$ssh_source" != "cancel" ]] ||
      fail "Firewall cancelado antes de activarse para evitar bloquear SSH."
    if [[ "$ssh_source" == "any" ]]; then
      run ufw limit OpenSSH
    else
      run ufw limit from "$ssh_source" to any port 22 proto tcp comment "SSH restringido"
    fi
  fi

  run ufw default deny incoming
  run ufw default allow outgoing
  run ufw --force enable
else
  warn "Firewall UFW omitido por decisión explícita del usuario."
fi
