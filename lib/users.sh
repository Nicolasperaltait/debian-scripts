#!/usr/bin/env bash

validate_username() {
  local name="${1:-}"
  [[ "$name" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || return 1
  case "$name" in
    root|bin|daemon|adm|lp|sync|shutdown|halt|mail|operator|games|ftp|nobody|\
    www-data|backup|list|irc|gnats|man|proxy|news|uucp|sshd|systemd-network|\
    systemd-resolve|messagebus|_apt|systemd-timesync|ntp|dnsmasq)
      return 1 ;;
  esac
}

set_user_password() {
  local username="$1"
  local pass1 pass2

  while true; do
    read -r -s -p "Contraseña para $username: " pass1
    printf '\n'
    read -r -s -p "Confirmar contraseña: " pass2
    printf '\n'
    [[ -n "$pass1" ]] || { warn "La contraseña no puede estar vacía."; continue; }
    [[ "$pass1" == "$pass2" ]] || { warn "Las contraseñas no coinciden."; continue; }
    printf '%s:%s\n' "$username" "$pass1" | chpasswd
    unset pass1 pass2
    break
  done
}

ensure_target_user() {
  local username="$1"
  validate_username "$username" || fail "Usuario inválido: $username"

  if id "$username" >/dev/null 2>&1; then
    info "Se reutilizará el usuario existente: $username"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      run usermod -aG sudo "$username"
    else
      info "DRY-RUN: usermod -aG sudo $username"
    fi
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: crear usuario $username con HOME, Bash y grupo sudo"
    return
  fi

  run useradd --create-home --shell /bin/bash --groups sudo "$username"
  set_user_password "$username"
  ok "Usuario administrativo creado: $username"
}

ensure_additional_users() {
  local spec username role

  for spec in "$@"; do
    IFS=: read -r username role <<<"$spec"
    validate_username "$username" || fail "Usuario adicional inválido: $username"
    [[ "$role" =~ ^(admin|standard)$ ]] ||
      fail "Rol inválido para $username: $role"

    if id "$username" >/dev/null 2>&1; then
      info "Se reutilizará el usuario adicional existente: $username"
      if [[ "$role" == "admin" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
          info "DRY-RUN: usermod -aG sudo $username"
        else
          run usermod -aG sudo "$username"
        fi
      else
        info "No se quitarán grupos existentes a $username."
      fi
      continue
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
      info "DRY-RUN: crear usuario $username con rol $role"
      continue
    fi

    if [[ "$role" == "admin" ]]; then
      run useradd --create-home --shell /bin/bash --groups sudo "$username"
    else
      run useradd --create-home --shell /bin/bash "$username"
    fi
    set_user_password "$username"
    ok "Usuario creado: $username ($role)"
  done
}
