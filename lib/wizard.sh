#!/usr/bin/env bash

if [[ -z "${ROOT_DIR:-}" ]]; then
  ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fi

source "$ROOT_DIR/config/packages.conf"

checklist_to_csv() {
  awk '
    {
      gsub(/"/, "", $0)
      for (i = 1; i <= NF; i++) {
        if ($i != "") {
          if (out != "") out = out ","
          out = out $i
        }
      }
    }
    END { print out }
  '
}

choose_checklist() {
  local title="$1"
  local prompt="$2"
  shift 2

  if command -v whiptail >/dev/null 2>&1 && [[ -t 1 ]]; then
    local result
    result="$(whiptail --title "$title" --checklist "$prompt" 22 84 12 "$@" 3>&1 1>&2 2>&3)" || return 1
    printf '%s' "$result" | checklist_to_csv
    return 0
  fi

  return 1
}

wizard_user() {
  local option custom invoking_user
  invoking_user="${SUDO_USER:-}"

  if validate_username "$invoking_user" && [[ "$invoking_user" != "root" ]]; then
    option="$(choose "Usuario administrativo" \
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

wizard_virtualization() {
  local detected="${1:-baremetal}" option
  local default="n"

  [[ "$detected" != "baremetal" ]] && default="s"
  if ! confirm "¿Este Debian corre dentro de una VM? (detección: $detected)" "$default"; then
    printf 'baremetal'
    return
  fi

  if [[ "$detected" == "vmware" ]]; then
    printf 'vmware'
    return
  fi

  option="$(choose "Tipo de virtualización" "VMware" "Otra VM")"
  [[ "$option" == "1" ]] && printf 'vmware' || printf 'virtual'
}

wizard_mode() {
  local option
  option="$(choose "Paso 1 - Tipo de sistema objetivo" "CLI (servidor/terminal)" "GUI (escritorio)")"
  [[ "$option" == "1" ]] && printf 'cli' || printf 'gui'
}

wizard_desktop() {
  local recommended="${1:-xfce}" option
  info "Escritorio recomendado por perfil: $recommended" >&2
  option="$(choose "Escritorio de referencia" \
    "Usar recomendado ($recommended)" \
    "XFCE (equilibrado)" \
    "LXQt (liviano/monotarea/RDP)")"
  case "$option" in
    1) printf '%s' "$recommended" ;;
    2) printf 'xfce' ;;
    3) printf 'lxqt' ;;
  esac
}

wizard_profile() {
  local recommended="$1"
  local option
  show_profile_recommendation
  option="$(choose "Paso 2 - Perfil de recursos" \
    "Usar recomendado ($recommended)" \
    "Baja (<4 GB RAM o <=2 hilos CPU)" \
    "Media (4-8 GB RAM o 3-4 hilos CPU)" \
    "Alta (8-16 GB RAM o 5-8 hilos CPU)" \
    "Ultra (>=16 GB RAM y >8 hilos CPU)")"
  case "$option" in
    1) printf '%s' "$recommended" ;;
    2) printf 'baja' ;;
    3) printf 'media' ;;
    4) printf 'alta' ;;
    5) printf 'ultra' ;;
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

  if confirm "¿Aceptar todos los componentes con sus valores por defecto?" "s"; then
    return 0
  fi

  wizard_component INSTALL_BASE_TOOLS \
    "¿Instalar herramientas generales de administración?" "s"

  if [[ "$INSTALL_MODE" == "cli" ]]; then
    wizard_component INSTALL_CLI_TOOLS \
      "¿Instalar herramientas CLI adicionales (nano)?" "s"
  else
    INSTALL_CLI_TOOLS=0
  fi

  if [[ "$INSTALL_MODE" == "gui" ]]; then
    ENABLE_DESKTOP=1
    info "Modo GUI: se instalará o completará el escritorio $DESKTOP." >&2
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
  wizard_component ENABLE_SSH \
    "¿Instalar y habilitar OpenSSH para acceso remoto desde otra máquina?" "s" 1
  wizard_component ENABLE_AUDIT \
    "¿Ejecutar una auditoría final de salud, servicios, red y puertos?" "s"
}

wizard_apps() {
  local app_selection=""

  section "Aplicaciones GUI" >&2
  app_selection="$(choose_checklist "Aplicaciones GUI" \
    "Marcá las aplicaciones de escritorio a instalar." \
    chrome "Google Chrome (APT oficial)" OFF \
    code "Visual Studio Code (APT oficial)" OFF \
    librewolf "LibreWolf (APT oficial)" OFF \
    obsidian "Obsidian (Flatpak)" OFF \
    vlc "VLC (Flatpak)" OFF \
    bitwarden "Bitwarden (Flatpak)" OFF \
    remmina "Remmina (Flatpak)" OFF)" || true
  if [[ -n "$app_selection" ]]; then
    printf '%s' "$app_selection"
    return
  fi

  local result=()
  confirm "¿Instalar Google Chrome (APT oficial)?" "n" && result+=("chrome")
  confirm "¿Instalar Visual Studio Code (APT oficial)?" "n" && result+=("code")
  confirm "¿Instalar LibreWolf (APT oficial)?" "n" && result+=("librewolf")
  confirm "¿Instalar Obsidian (Flatpak)?" "n" && result+=("obsidian")
  confirm "¿Instalar VLC (Flatpak)?" "n" && result+=("vlc")
  confirm "¿Instalar Bitwarden (Flatpak)?" "n" && result+=("bitwarden")
  confirm "¿Instalar Remmina (Flatpak)?" "n" && result+=("remmina")
  printf '%s' "$(IFS=,; printf '%s' "${result[*]}")"
}

wizard_nvidia_policy() {
  local option

  info "GPU NVIDIA detectada: ${NVIDIA_MODEL:-NVIDIA}" >&2
  option="$(choose "NVIDIA detectada" \
    "Instalar driver recomendado" \
    "Solo auditar, no instalar")"
  if [[ "$option" == "1" ]]; then
    if confirm "¿Conocés el modelo exacto de la GPU?" "n"; then
      read -r -p "Modelo informado: " NVIDIA_USER_MODEL
    fi
    printf 'install'
  else
    printf 'audit'
  fi
}

debloat_candidates_for_desktop() {
  local list="$DEBLOAT_CANDIDATES_COMMON"
  if [[ "$DESKTOP" == "xfce" ]]; then
    list+=" $DEBLOAT_CANDIDATES_XFCE"
  elif [[ "$DESKTOP" == "lxqt" ]]; then
    list+=" $DEBLOAT_CANDIDATES_LXQT"
  fi
  printf '%s' "$list"
}

debloat_candidate_installed() {
  local package="$1"

  dpkg-query -W -f='${Status}\n' "$package" 2>/dev/null | grep -q 'install ok installed'
}

debloat_candidate_planned_by_desktop() {
  local package="$1"

  [[ "${INSTALL_MODE:-}" == "gui" && "${ENABLE_DESKTOP:-0}" -eq 1 ]] || return 1
  case "${DESKTOP:-}" in
    xfce) [[ " $DEBLOAT_CANDIDATES_XFCE " == *" $package "* ]] ;;
    lxqt) [[ " $DEBLOAT_CANDIDATES_LXQT " == *" $package "* ]] ;;
    *) return 1 ;;
  esac
}

wizard_debloat_packages() {
  local option package
  local joined=""
  local note=""
  local -a options=()
  local -a candidates=()
  local selection=""

  section "Debloat seguro" >&2
  for package in $(debloat_candidates_for_desktop); do
    if is_protected_debloat_package "$package"; then
      warn "Se omite candidato protegido de debloat: $package" >&2
      continue
    fi
    if debloat_candidate_installed "$package"; then
      note="Instalado; se audita antes de purgar"
      candidates+=("$package")
      options+=("$package" "$note" OFF)
    elif debloat_candidate_planned_by_desktop "$package"; then
      note="Puede quedar instalado por el escritorio; se audita después"
      candidates+=("$package")
      options+=("$package" "$note" OFF)
    fi
  done

  ((${#candidates[@]})) || {
    info "No hay paquetes candidatos instalados para debloat." >&2
    printf '__sin_candidatos__'
    return 0
  }

  joined="$(IFS=,; printf '%s' "${candidates[*]}")"
  info "Candidatos seguros detectados: $joined" >&2
  option="$(choose "Debloat seguro" \
    "ALL - purgar todos los candidatos tras la simulación" \
    "YES - elegir paquetes uno por uno" \
    "NO - ignorar debloat y seguir")"

  case "$option" in
    1)
      printf '__all__:%s' "$joined"
      return 0
      ;;
    3)
      printf ''
      return 0
      ;;
  esac

  selection="$(choose_checklist "Debloat seguro" \
    "Marcá paquetes para auditar con apt-get -s purge." "${options[@]}")" || true
  if [[ -n "$selection" ]]; then
    printf '__ask__:%s' "$selection"
    return
  fi

  local -a result=()
  for package in "${candidates[@]}"; do
    if confirm "¿Auditar paquete candidata a purge: $package?" "n"; then
      result+=("$package")
    fi
  done
  joined="$(IFS=,; printf '%s' "${result[*]}")"
  [[ -n "$joined" ]] && printf '__ask__:%s' "$joined"
}

wizard_extras() {
  local result=()
  local item label
  section "Módulos opcionales" >&2
  while IFS='|' read -r item label; do
    # Skip ssh if it is already managed as a main component.
    [[ "$item" == "ssh" && "${ENABLE_SSH:-1}" -eq 1 ]] && continue
    [[ "$item" == "apps" ]] && continue
    [[ "$INSTALL_MODE" == "gui" && "$item" == "debloat" ]] && continue
    if confirm "¿Instalar $label ($item)?" "n"; then result+=("$item"); fi
  done <<'EOF'
ssh|OpenSSH y regla de firewall
bluetooth|Bluetooth
flatpak|Flatpak y Flathub
apps|Aplicaciones GUI seleccionables
zsh|Zsh y personalización de terminal
fonts|Fuentes adicionales
gammastep|Control de temperatura de pantalla
omv|Montaje SMB de OMV
rdp|Escritorio remoto XRDP
clamav|ClamAV
rkhunter|Rootkit Hunter
wazuh|Agente Wazuh
maintenance|Mantenimiento APT
debloat|Debloat seguro con simulación
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
    [[ "$item" =~ ^(ssh|bluetooth|flatpak|apps|zsh|fonts|gammastep|omv|rdp|clamav|rkhunter|wazuh|maintenance|debloat|rtc)$ ]] ||
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
  printf '  Entorno:       %s\n' "$([[ "${IS_VM:-0}" -eq 1 ]] && echo "VM ($VIRTUALIZATION_TYPE)" || echo "bare metal")"
  printf '  Instalación:   %s\n' "$INSTALL_MODE"
  printf '  Escritorio:    %s\n' "$DESKTOP"
  printf '  Perfil:        %s\n' "$PROFILE"
  printf '  Extras:        %s\n' "${EXTRAS:-ninguno}"
  printf '  Apps APT:      %s\n' "${APT_APP_SELECTIONS:-ninguna}"
  printf '  Apps Flatpak:  %s\n' "${FLATPAK_APP_SELECTIONS:-ninguna}"
  if [[ -n "${APT_APP_SELECTIONS:-}" || "${NVIDIA_POLICY:-}" == "install" ]]; then
    printf '  Repos APT:     sí\n'
  else
    printf '  Repos APT:     no\n'
  fi
  printf '  NVIDIA:        %s\n' "${NVIDIA_POLICY:-sin cambios}"
  if [[ -n "${NVIDIA_USER_MODEL:-}" ]]; then
    printf '  Modelo NVIDIA: %s\n' "$NVIDIA_USER_MODEL"
  fi
  if [[ -n "${DEBLOAT_PACKAGES:-}" ]]; then
    printf '  Debloat:       %s (%s)\n' "$DEBLOAT_PACKAGES" "${DEBLOAT_STATUS:-pendiente de confirmación}"
  else
    printf '  Debloat:       %s\n' "${DEBLOAT_STATUS:-omitido}"
  fi
  printf '  Upgrade APT:   %s\n' "$([[ "$UPGRADE_SYSTEM" -eq 1 ]] && echo sí || echo no)"
  printf '  Herramientas:  %s\n' "$([[ "$INSTALL_BASE_TOOLS" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Herram. CLI:   %s\n' "$([[ "$INSTALL_CLI_TOOLS" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Instalar GUI:  %s\n' "$([[ "$ENABLE_DESKTOP" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Optimización:  %s\n' "$([[ "$ENABLE_OPTIMIZATION" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Firewall:      %s\n' "$([[ "$ENABLE_FIREWALL" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Auto-updates:  %s\n' "$([[ "$ENABLE_AUTO_UPDATES" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Hardening:     %s\n' "$([[ "$ENABLE_HARDENING" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  SSH:           %s\n' "$([[ "$ENABLE_SSH" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Auditoría:     %s\n' "$([[ "$ENABLE_AUDIT" -eq 1 ]] && echo "$enabled_text" || echo "$disabled_text")"
  printf '  Ejecución:     %s\n' "$([[ "$DRY_RUN" -eq 1 ]] && echo simulación || echo real)"
}
