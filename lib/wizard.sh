#!/usr/bin/env bash

wizard_user() {
  local option custom invoking_user
  invoking_user="${SUDO_USER:-}"

  if validate_username "$invoking_user" && [[ "$invoking_user" != "root" ]]; then
    option="$(choose "Paso 1/6 - Usuario administrativo" \
      "Usar usuario actual ($invoking_user)" \
      "Indicar otro usuario")"
    [[ "$option" == "1" ]] && { printf '%s' "$invoking_user"; return; }
  fi

  while true; do
    read -r -p "Nombre del usuario: " custom
    validate_username "$custom" && { printf '%s' "$custom"; return; }
    warn "Usá minúsculas, números, guion o guion bajo; máximo 32 caracteres."
  done
}

wizard_additional_users() {
  local username role_option role spec
  local -A selected=()

  selected["$TARGET_USER"]=1
  while confirm "¿Querés crear o configurar otro usuario?" "n"; do
    while true; do
      read -r -p "Nombre del usuario adicional: " username
      if ! validate_username "$username"; then
        warn "Usá minúsculas, números, guion o guion bajo; máximo 32 caracteres."
        continue
      fi
      if [[ -n "${selected[$username]:-}" ]]; then
        warn "Ese usuario ya está incluido en el plan."
        continue
      fi
      break
    done

    role_option="$(choose "Rol para $username" \
      "Usuario estándar" \
      "Administrador con sudo")"
    [[ "$role_option" == "1" ]] && role="standard" || role="admin"
    spec="$username:$role"
    ADDITIONAL_USERS+=("$spec")
    selected["$username"]=1
    ok "Usuario agregado al plan: $username ($role)"
  done
}

wizard_system_upgrade() {
  if confirm "¿Actualizar todos los paquetes instalados antes del bootstrap?" "s"; then
    UPGRADE_SYSTEM=1
  else
    UPGRADE_SYSTEM=0
  fi
}

wizard_preset() {
  local option
  option="$(choose "Escenario del equipo (solo recomendaciones)" \
    "General" \
    "hardware de bajos recursos (recomienda LXQt, perfil baja y auditoría)")"
  [[ "$option" == "1" ]] && printf 'general' || printf 'gui-low-resource'
}

wizard_mode() {
  local option
  option="$(choose "Tipo de sistema objetivo" "CLI (servidor/terminal)" "GUI (escritorio)")"
  [[ "$option" == "1" ]] && printf 'cli' || printf 'gui'
}

wizard_desktop() {
  local option
  option="$(choose "Escritorio de referencia" "XFCE (equilibrado)" "LXQt (liviano/monotarea/RDP)")"
  [[ "$option" == "1" ]] && printf 'xfce' || printf 'lxqt'
}

wizard_profile() {
  local recommended="$1"
  local option
  info "Perfil recomendado por hardware: $recommended" >&2
  option="$(choose "Perfil de recursos (no determina qué componentes instalar)" \
    "Usar recomendado ($recommended)" \
    "Ultra" \
    "Alta" \
    "Media" \
    "Baja")"
  case "$option" in
    1) printf '%s' "$recommended" ;;
    2) printf 'ultra' ;;
    3) printf 'alta' ;;
    4) printf 'media' ;;
    5) printf 'baja' ;;
  esac
}

wizard_component() {
  local variable="$1"
  local prompt="$2"
  local default="${3:-n}"
  local security_critical="${4:-0}"
  local enabled=0

  if confirm "$prompt" "$default"; then
    enabled=1
  elif [[ "$security_critical" -eq 1 ]]; then
    warn "Omitir este control reduce la postura de seguridad del sistema."
    if ! confirm "¿Confirmás que querés omitirlo?" "n"; then
      info "Se conserva habilitado por seguridad."
      enabled=1
    fi
  fi

  printf -v "$variable" '%d' "$enabled"
}

wizard_components() {
  section "Componentes principales" >&2
  info "El perfil recomienda ajustes; cada componente se decide por separado." >&2

  wizard_component INSTALL_BASE_TOOLS \
    "¿Instalar herramientas generales de administración?" "s"

  if [[ "$INSTALL_MODE" == "cli" ]]; then
    wizard_component INSTALL_CLI_TOOLS \
      "¿Instalar herramientas CLI adicionales (vim-tiny y tmux)?" "s"
  else
    INSTALL_CLI_TOOLS=0
  fi

  if [[ "$INSTALL_MODE" == "gui" ]]; then
    wizard_component ENABLE_DESKTOP \
      "¿Instalar o completar el escritorio $DESKTOP?" "s"
  else
    ENABLE_DESKTOP=0
  fi

  wizard_component ENABLE_OPTIMIZATION \
    "¿Aplicar los ajustes del perfil $PROFILE?" "s"
  wizard_component ENABLE_FIREWALL \
    "¿Configurar y habilitar UFW con entrada denegada por defecto?" "s" 1
  wizard_component ENABLE_AUTO_UPDATES \
    "¿Configurar actualizaciones automáticas de seguridad?" "s" 1
  wizard_component ENABLE_HARDENING \
    "¿Aplicar hardening conservador (AppArmor, sysctl y protección SSH)?" "s" 1
  wizard_component ENABLE_AUDIT \
    "¿Ejecutar una auditoría final de salud, servicios, red y puertos?" "s"
}

wizard_extras() {
  local result=()
  local item label
  section "Módulos opcionales" >&2
  while IFS='|' read -r item label; do
    if confirm "¿Instalar $label ($item)?" "n"; then result+=("$item"); fi
  done <<'EOF'
ssh|OpenSSH y regla de firewall
bluetooth|Bluetooth
flatpak|Flatpak y Flathub
apps|Aplicaciones Flatpak seleccionables
zsh|Zsh y personalización de terminal
fonts|Fuentes adicionales
gammastep|Control de temperatura de pantalla
omv|Montaje SMB de OMV
rdp|Escritorio remoto XRDP
clamav|ClamAV
rkhunter|Rootkit Hunter
wazuh|Agente Wazuh
maintenance|Mantenimiento APT
rtc|Zona horaria, NTP y RTC
EOF
  local joined
  joined="$(IFS=,; printf '%s' "${result[*]}")"
  printf '%s' "$joined"
}

validate_extras() {
  local value="${1:-}"
  local item
  [[ -z "$value" ]] && return 0
  IFS=',' read -r -a items <<<"$value"
  for item in "${items[@]}"; do
    [[ "$item" =~ ^(ssh|bluetooth|flatpak|apps|zsh|fonts|gammastep|omv|rdp|clamav|rkhunter|wazuh|maintenance|rtc)$ ]] ||
      fail "Módulo opcional inválido: $item"
  done
}

show_plan() {
  local spec username role
  local enabled_text="sí" disabled_text="no"
  section "Plan de instalación"
  printf '  Usuario:       %s\n' "$TARGET_USER"
  if ((${#ADDITIONAL_USERS[@]})); then
    printf '  Adicionales:\n'
    for spec in "${ADDITIONAL_USERS[@]}"; do
      IFS=: read -r username role <<<"$spec"
      printf '    - %s (%s)\n' "$username" "$role"
    done
  else
    printf '  Adicionales:   ninguno\n'
  fi
  printf '  Preset:        %s\n' "$PRESET"
  printf '  Instalación:   %s\n' "$INSTALL_MODE"
  printf '  Escritorio:    %s\n' "$DESKTOP"
  printf '  Perfil:        %s\n' "$PROFILE"
  printf '  Extras:        %s\n' "${EXTRAS:-ninguno}"
  printf '  Upgrade APT:   %s\n' "$([[ "$UPGRADE_SYSTEM" -eq 1 ]] && echo sí || echo no)"
  printf '  Herramientas:  %s\n' "$([[ "$INSTALL_BASE_TOOLS" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Herram. CLI:   %s\n' "$([[ "$INSTALL_CLI_TOOLS" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Instalar GUI:  %s\n' "$([[ "$ENABLE_DESKTOP" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Optimización:  %s\n' "$([[ "$ENABLE_OPTIMIZATION" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Firewall:      %s\n' "$([[ "$ENABLE_FIREWALL" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Auto-updates:  %s\n' "$([[ "$ENABLE_AUTO_UPDATES" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Hardening:     %s\n' "$([[ "$ENABLE_HARDENING" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Auditoría:     %s\n' "$([[ "$ENABLE_AUDIT" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Ejecución:     %s\n' "$([[ "$DRY_RUN" -eq 1 ]] && echo simulación || echo real)"
}
