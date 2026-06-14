#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR

source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"
init_ui

readonly SYSCTL_FILE="/etc/sysctl.d/99-debian-hardening.conf"
readonly SSHD_DROPIN="/etc/ssh/sshd_config.d/99-debian-hardening.conf"
readonly FAIL2BAN_JAIL="/etc/fail2ban/jail.d/sshd-hardening.local"

ssh_is_selected_or_installed() {
  [[ -x /usr/sbin/sshd ]] ||
    command -v sshd >/dev/null 2>&1 ||
    [[ ",${EXTRAS:-}," == *,ssh,* ]]
}

install_security_packages() {
  local packages=()
  read -r -a packages <<<"$SECURITY_HARDENING_PACKAGES"
  apt_install "${packages[@]}"

  if ssh_is_selected_or_installed; then
    read -r -a packages <<<"$SSH_HARDENING_PACKAGES"
    apt_install "${packages[@]}"
  fi
}

configure_kernel_hardening() {
  write_file "$SYSCTL_FILE" '# Conservative Debian workstation/server hardening.
# Routing and unprivileged user namespaces are intentionally left unchanged.
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 1
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2'

  run sysctl --system
}

configure_apparmor() {
  run systemctl enable --now apparmor
  if ! run aa-status; then
    warn "AppArmor fue habilitado, pero aa-status devolvió advertencias."
  fi
}

install_validated_sshd_dropin() {
  local content backup="" temp
  content='# Conservative SSH hardening. Password authentication is unchanged.
PermitRootLogin no
MaxAuthTries 3
MaxSessions 5
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
X11Forwarding no'

  if [[ "$DRY_RUN" -eq 1 ]]; then
    write_file "$SSHD_DROPIN" "$content"
    info "DRY-RUN: validar sshd -t y recargar el servicio SSH"
    return 0
  fi

  install -d -m 0755 "$(dirname "$SSHD_DROPIN")"
  temp="$(mktemp)"
  printf '%s\n' "$content" >"$temp"

  if [[ -e "$SSHD_DROPIN" ]]; then
    backup_file "$SSHD_DROPIN"
    backup="$LAST_BACKUP_FILE"
  fi

  install -m 0644 "$temp" "$SSHD_DROPIN"
  rm -f "$temp"

  if ! /usr/sbin/sshd -t; then
    error "La validación sshd -t falló; se revierte el drop-in."
    if [[ -n "$backup" ]]; then
      cp -a "$backup" "$SSHD_DROPIN"
    else
      rm -f "$SSHD_DROPIN"
    fi
    fail "Hardening SSH no aplicado."
  fi

  if systemctl is-active --quiet ssh; then
    run systemctl reload ssh
  elif systemctl is-active --quiet sshd; then
    run systemctl reload sshd
  else
    info "OpenSSH no está activo; el drop-in validado queda listo para su próximo inicio."
  fi
}

configure_ssh_protection() {
  if ! ssh_is_selected_or_installed; then
    info "OpenSSH no está instalado ni seleccionado; se omite SSH/Fail2ban."
    return 0
  fi

  install_validated_sshd_dropin
  write_file "$FAIL2BAN_JAIL" '[sshd]
enabled = true
backend = systemd
port = ssh
maxretry = 5
findtime = 10m
bantime = 1h'
  run systemctl enable --now fail2ban
}

main() {
  install_security_packages
  configure_kernel_hardening
  configure_apparmor
  configure_ssh_protection
}

main "$@"
