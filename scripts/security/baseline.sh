#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"
init_ui

# Install and start SSH before UFW configuration so that the firewall
# source detection below can observe the running service.
if [[ "${ENABLE_SSH:-1}" -eq 1 ]]; then
  apt_install openssh-server
  run systemctl enable --now ssh

  if [[ -z "${TARGET_USER:-}" ]]; then
    : # Sin usuario objetivo definido (ej. baseline standalone): omitir gestión de claves.
  elif [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: verificar authorized_keys para $TARGET_USER"
  else
    _ssh_home="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "")"
    if [[ -n "$_ssh_home" ]]; then
      _auth_keys="$_ssh_home/.ssh/authorized_keys"
      if [[ -s "$_auth_keys" ]]; then
        _key_count="$(grep -cE '^(ssh-|ecdsa-sha2-|sk-)' "$_auth_keys" 2>/dev/null || echo 0)"
        ok "authorized_keys: $_key_count clave(s) existente(s) para $TARGET_USER — no se modifica."
      else
        _pubkey="${SSH_PUBKEY:-}"
        if [[ -z "$_pubkey" && -t 0 && "${DEBIAN_SCRIPTS_TEST:-0}" != "1" ]]; then
          info "No hay claves en authorized_keys para $TARGET_USER."
          if confirm "¿Querés agregar tu clave SSH pública ahora?" "s"; then
            read -r -p "Pegá tu clave pública (ssh-ed25519 AAAA... o similar): " _pubkey
          fi
        fi
        if [[ -n "$_pubkey" && "$_pubkey" =~ ^(ssh-|ecdsa-sha2-|sk-) ]]; then
          install -d -m 0700 "$_ssh_home/.ssh"
          chown "$TARGET_USER:$TARGET_USER" "$_ssh_home/.ssh" 2>/dev/null || true
          printf '%s\n' "$_pubkey" >>"$_auth_keys"
          chmod 600 "$_auth_keys"
          chown "$TARGET_USER:$TARGET_USER" "$_auth_keys" 2>/dev/null || true
          log_line "WRITE: $_auth_keys (clave SSH pública)"
          ok "Clave SSH pública agregada a authorized_keys de $TARGET_USER"
        else
          [[ -n "$_pubkey" ]] && warn "La clave provista no parece válida (debe comenzar con ssh-, ecdsa- o sk-)."
          warn "Sin claves en authorized_keys para $TARGET_USER — el acceso SSH requerirá autenticación por contraseña."
        fi
      fi
    fi
  fi
fi

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

  # Verify sshd is reachable after firewall activation.
  if [[ "${ENABLE_SSH:-1}" -eq 1 ]] || systemctl is-active --quiet ssh 2>/dev/null; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      info "DRY-RUN: verificar que sshd escucha en puerto 22"
    elif ss -tlnp 2>/dev/null | grep -q ':22 '; then
      ok "SSH escuchando en puerto 22"
    else
      warn "UFW activo pero sshd no está escuchando en puerto 22"
    fi
  fi
else
  warn "Firewall UFW omitido por decisión explícita del usuario."
fi
