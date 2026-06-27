#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR

# shellcheck source=lib/common.sh
source "$ROOT_DIR/lib/common.sh"
# shellcheck source=lib/detection.sh
source "$ROOT_DIR/lib/detection.sh"
# shellcheck source=lib/users.sh
source "$ROOT_DIR/lib/users.sh"
# shellcheck source=lib/wizard.sh
source "$ROOT_DIR/lib/wizard.sh"
# shellcheck source=lib/package_sources.sh
source "$ROOT_DIR/lib/package_sources.sh"

TARGET_USER=""
ADDITIONAL_USERS=()
PRESET=""
VIRTUALIZATION_SELECTION="auto"
INSTALL_MODE=""
DESKTOP=""
PROFILE=""
EXTRAS=""
GUI_APP_SELECTIONS=""
APT_APP_SELECTIONS=""
FLATPAK_APP_SELECTIONS=""
NVIDIA_POLICY=""
NVIDIA_USER_MODEL=""
DEBLOAT_PACKAGES=""
DEBLOAT_STATUS="omitido"
UPGRADE_SYSTEM=1
COMPONENTS_ONLY=""
COMPONENTS_SKIP=""
COMPONENTS_ONLY_SET=0
COMPONENTS_SKIP_SET=0
INSTALL_BASE_TOOLS=1
INSTALL_CLI_TOOLS=0
ENABLE_SECURITY_BASELINE=1
ENABLE_FIREWALL=1
ENABLE_AUTO_UPDATES=1
ENABLE_DESKTOP=0
ENABLE_OPTIMIZATION=1
ENABLE_HARDENING=1
ENABLE_SSH=1
ENABLE_AUDIT=0
ASSUME_YES=0
CURRENT_STEP=0
TOTAL_STEPS=1
RECOVERABLE_FAILURES_FILE=""
RECOVERABLE_STEP_FAILED=0

usage() {
  cat <<'EOF'
Uso:
  sudo bash main.sh [opciones]

Opciones:
  --dry-run              Muestra acciones sin modificar el sistema
  --user NOMBRE          Usuario objetivo
  --add-user USUARIO:ROL Usuario adicional; ROL es admin o standard.
                         Se puede repetir.
  --preset general|gui-low-resource
                         GUI liviana recomienda LXQt + perfil baja
  --virtualization auto|baremetal|vm|vmware
                         Entorno destino; auto detecta y el wizard confirma
  --mode cli|gui         Tipo de instalación
  --desktop xfce|lxqt    Escritorio para modo GUI
  --profile baja|media|alta|ultra
  --apps LISTA           Apps GUI separadas por coma (chrome,code,librewolf,obsidian,vlc,bitwarden,remmina)
  --nvidia install|audit Política para GPU NVIDIA detectada
  --debloat-packages LISTA
                         Paquetes separados por coma para auditar/purgar con debloat seguro
  --components LISTA     Selección exacta de componentes principales
  --skip-components LISTA
                         Componentes principales que se deben omitir
  --extras LISTA         Módulos separados por coma
  --upgrade-system       Actualiza todos los paquetes antes del bootstrap
  --skip-upgrade         No ejecuta apt-get upgrade
  --yes                  Confirma el plan (requiere todas las opciones)
  -h, --help             Muestra esta ayuda

Extras:
  ssh, bluetooth, flatpak, apps, zsh, fonts, gammastep, omv, rdp,
  clamav, rkhunter, wazuh, maintenance, debloat, rtc

Componentes principales:
  tools, cli-tools, desktop, optimization, firewall, auto-updates,
  hardening, ssh, audit
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --user) TARGET_USER="${2:-}"; shift 2 ;;
      --add-user) ADDITIONAL_USERS+=("${2:-}"); shift 2 ;;
      --preset) PRESET="${2:-}"; shift 2 ;;
      --virtualization) VIRTUALIZATION_SELECTION="${2:-}"; shift 2 ;;
      --mode) INSTALL_MODE="${2:-}"; shift 2 ;;
      --desktop) DESKTOP="${2:-}"; shift 2 ;;
      --profile) PROFILE="${2:-}"; shift 2 ;;
      --apps) GUI_APP_SELECTIONS="${2:-}"; shift 2 ;;
      --nvidia) NVIDIA_POLICY="${2:-}"; shift 2 ;;
      --debloat-packages) DEBLOAT_PACKAGES="${2:-}"; shift 2 ;;
      --components)
        COMPONENTS_ONLY="${2:-}"
        COMPONENTS_ONLY_SET=1
        shift 2
        ;;
      --skip-components)
        COMPONENTS_SKIP="${2:-}"
        COMPONENTS_SKIP_SET=1
        shift 2
        ;;
      --extras) EXTRAS="${2:-}"; shift 2 ;;
      --upgrade-system) UPGRADE_SYSTEM=1; shift ;;
      --skip-upgrade) UPGRADE_SYSTEM=0; shift ;;
      --yes) ASSUME_YES=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) fail "Argumento desconocido: $1" ;;
    esac
  done
}

set_component_state() {
  local component="$1"
  local state="$2"

  case "$component" in
    tools) INSTALL_BASE_TOOLS="$state" ;;
    cli-tools) INSTALL_CLI_TOOLS="$state" ;;
    desktop) ENABLE_DESKTOP="$state" ;;
    optimization) ENABLE_OPTIMIZATION="$state" ;;
    firewall) ENABLE_FIREWALL="$state" ;;
    auto-updates) ENABLE_AUTO_UPDATES="$state" ;;
    hardening) ENABLE_HARDENING="$state" ;;
    ssh) ENABLE_SSH="$state" ;;
    audit) ENABLE_AUDIT="$state" ;;
    *) fail "Componente principal inválido: $component" ;;
  esac
}

apply_component_list() {
  local list="$1"
  local state="$2"
  local component
  local -a components=()

  [[ "$list" == "none" ]] && return 0
  [[ -n "$list" ]] || fail "La lista de componentes no puede estar vacía."
  IFS=',' read -r -a components <<<"$list"
  for component in "${components[@]}"; do
    set_component_state "$component" "$state"
  done
}

set_component_defaults() {
  INSTALL_BASE_TOOLS=1
  INSTALL_CLI_TOOLS=0
  ENABLE_FIREWALL=1
  ENABLE_AUTO_UPDATES=1
  ENABLE_DESKTOP=0
  ENABLE_OPTIMIZATION=1
  ENABLE_HARDENING=1
  ENABLE_SSH=1
  ENABLE_AUDIT=0

  if [[ "$INSTALL_MODE" == "cli" ]]; then
    INSTALL_CLI_TOOLS=1
  fi
  if [[ "$INSTALL_MODE" == "gui" ]]; then
    ENABLE_DESKTOP=1
  fi
  if [[ "$PRESET" == "gui-low-resource" ]]; then
    ENABLE_AUDIT=1
  fi
}

apply_component_selection() {
  set_component_defaults

  [[ "$COMPONENTS_ONLY_SET" -eq 0 || "$COMPONENTS_SKIP_SET" -eq 0 ]] ||
    fail "Usá --components o --skip-components, no ambos."

  if [[ "$INSTALL_MODE" != "gui" && "$COMPONENTS_ONLY_SET" -eq 1 &&
    ",$COMPONENTS_ONLY," == *,desktop,* ]]; then
    fail "El componente desktop requiere --mode gui."
  fi

  if [[ "$COMPONENTS_ONLY_SET" -eq 1 ]]; then
    INSTALL_BASE_TOOLS=0
    INSTALL_CLI_TOOLS=0
    ENABLE_FIREWALL=0
    ENABLE_AUTO_UPDATES=0
    ENABLE_DESKTOP=0
    ENABLE_OPTIMIZATION=0
    ENABLE_HARDENING=0
    ENABLE_SSH=0
    ENABLE_AUDIT=0
    apply_component_list "$COMPONENTS_ONLY" 1
  elif [[ "$COMPONENTS_SKIP_SET" -eq 1 ]]; then
    apply_component_list "$COMPONENTS_SKIP" 0
  fi

  [[ "$INSTALL_MODE" == "gui" ]] || ENABLE_DESKTOP=0
  if [[ "$ENABLE_FIREWALL" -eq 1 || "$ENABLE_AUTO_UPDATES" -eq 1 || "$ENABLE_SSH" -eq 1 ]]; then
    ENABLE_SECURITY_BASELINE=1
  else
    ENABLE_SECURITY_BASELINE=0
  fi
}

validate_selection() {
  local spec username role
  local -A seen_users=()

  validate_username "$TARGET_USER" || fail "Usuario inválido: $TARGET_USER"
  [[ "$PRESET" =~ ^(general|gui-low-resource)$ ]] ||
    fail "Preset inválido: $PRESET"
  [[ "$VIRTUALIZATION_SELECTION" =~ ^(auto|baremetal|vm|virtual|vmware)$ ]] ||
    fail "Virtualización inválida: $VIRTUALIZATION_SELECTION"
  [[ "$INSTALL_MODE" =~ ^(cli|gui)$ ]] || fail "Modo inválido: $INSTALL_MODE"
  [[ "$PROFILE" =~ ^(baja|media|alta|ultra)$ ]] || fail "Perfil inválido: $PROFILE"
  [[ -z "$NVIDIA_POLICY" || "$NVIDIA_POLICY" =~ ^(install|audit)$ ]] ||
    fail "Política NVIDIA inválida: $NVIDIA_POLICY"

  if [[ "$INSTALL_MODE" == "gui" ]]; then
    [[ "$DESKTOP" =~ ^(xfce|lxqt)$ ]] || fail "Escritorio inválido: $DESKTOP"
  else
    DESKTOP="ninguno"
    [[ -z "$GUI_APP_SELECTIONS" ]] || fail "--apps requiere --mode gui."
  fi

  validate_extras "$EXTRAS"
  validate_app_selections "$GUI_APP_SELECTIONS"
  classify_app_selections

  if [[ "$ENABLE_DESKTOP" -eq 1 && "$INSTALL_MODE" != "gui" ]]; then
    fail "El componente desktop requiere --mode gui."
  fi

  if [[ "$ASSUME_YES" -eq 1 && "$NVIDIA_PRESENT" -eq 1 && -z "$NVIDIA_POLICY" ]]; then
    fail "NVIDIA detectada: definí --nvidia install|audit para ejecución no interactiva."
  fi
  if [[ "$ASSUME_YES" -eq 1 && ",$EXTRAS," == *,apps,* && -z "$GUI_APP_SELECTIONS" ]]; then
    fail "El extra apps requiere --apps en modo no interactivo."
  fi
  if [[ "$ASSUME_YES" -eq 1 && ",$EXTRAS," == *,debloat,* && -z "$DEBLOAT_PACKAGES" ]]; then
    fail "El extra debloat requiere --debloat-packages en modo no interactivo."
  fi
  if [[ ",$EXTRAS," == *,debloat,* && -z "$DEBLOAT_PACKAGES" ]]; then
    fail "El extra debloat requiere al menos un paquete candidato."
  fi

  seen_users["$TARGET_USER"]=1
  for spec in "${ADDITIONAL_USERS[@]}"; do
    IFS=: read -r username role <<<"$spec"
    validate_username "$username" || fail "Usuario adicional inválido: $username"
    [[ "$role" =~ ^(admin|standard)$ ]] ||
      fail "Rol inválido para $username: ${role:-vacío}. Usá admin o standard."
    [[ -z "${seen_users[$username]:-}" ]] ||
      fail "Usuario repetido en el plan: $username"
    seen_users["$username"]=1
  done

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    [[ -n "$TARGET_USER" && -n "$INSTALL_MODE" && -n "$PROFILE" ]] ||
      fail "--yes requiere --user, --mode y --profile."
  fi
}

validate_app_selections() {
  local value="${1:-}" item
  [[ -z "$value" ]] && return 0
  IFS=',' read -r -a items <<<"$value"
  for item in "${items[@]}"; do
    [[ "$item" =~ ^(chrome|code|librewolf|obsidian|vlc|bitwarden|remmina)$ ]] ||
      fail "Aplicación GUI inválida: $item"
  done
}

classify_app_selections() {
  local item
  local -a apt_apps=()
  local -a flatpak_apps=()
  local -a gui_apps=()

  APT_APP_SELECTIONS=""
  FLATPAK_APP_SELECTIONS=""
  [[ -n "$GUI_APP_SELECTIONS" ]] || return 0

  IFS=',' read -r -a gui_apps <<<"$GUI_APP_SELECTIONS"
  for item in "${gui_apps[@]}"; do
    case "$item" in
      chrome|code|librewolf) apt_apps+=("$item") ;;
      obsidian|vlc|bitwarden|remmina) flatpak_apps+=("$item") ;;
    esac
  done

  APT_APP_SELECTIONS="$(IFS=,; printf '%s' "${apt_apps[*]}")"
  FLATPAK_APP_SELECTIONS="$(IFS=,; printf '%s' "${flatpak_apps[*]}")"
}

csv_add_unique() {
  local current="${1:-}" item="$2"

  [[ ",$current," == *,"$item",* ]] && { printf '%s' "$current"; return; }
  if [[ -n "$current" ]]; then
    printf '%s,%s' "$current" "$item"
  else
    printf '%s' "$item"
  fi
}

csv_remove_item() {
  local current="${1:-}" item="$2" value
  local -a values=()
  local -a kept=()

  [[ -n "$current" ]] || return 0
  IFS=',' read -r -a values <<<"$current"
  for value in "${values[@]}"; do
    [[ "$value" == "$item" || -z "$value" ]] && continue
    kept+=("$value")
  done
  printf '%s' "$(IFS=,; printf '%s' "${kept[*]}")"
}

run_module() {
  local label="$1"
  local script="$2"
  shift 2

  CURRENT_STEP=$((CURRENT_STEP + 1))
  progress_bar "$CURRENT_STEP" "$TOTAL_STEPS" "$label"
  section "$label"
  if DRY_RUN="$DRY_RUN" LOG_FILE="$LOG_FILE" TARGET_USER="$TARGET_USER" \
    PRESET="$PRESET" INSTALL_MODE="$INSTALL_MODE" DESKTOP="$DESKTOP" PROFILE="$PROFILE" \
    EXTRAS="$EXTRAS" UPGRADE_SYSTEM="$UPGRADE_SYSTEM" \
    ASSUME_YES="$ASSUME_YES" RECOVERABLE_FAILURES_FILE="$RECOVERABLE_FAILURES_FILE" \
    GUI_APP_SELECTIONS="$GUI_APP_SELECTIONS" \
    APT_APP_SELECTIONS="$APT_APP_SELECTIONS" \
    FLATPAK_APP_SELECTIONS="$FLATPAK_APP_SELECTIONS" \
    NVIDIA_PRESENT="$NVIDIA_PRESENT" NVIDIA_MODEL="$NVIDIA_MODEL" \
    NVIDIA_POLICY="$NVIDIA_POLICY" NVIDIA_USER_MODEL="$NVIDIA_USER_MODEL" \
    DEBLOAT_PACKAGES="$DEBLOAT_PACKAGES" DEBLOAT_STATUS="$DEBLOAT_STATUS" \
    INSTALL_BASE_TOOLS="$INSTALL_BASE_TOOLS" INSTALL_CLI_TOOLS="$INSTALL_CLI_TOOLS" \
    ENABLE_FIREWALL="$ENABLE_FIREWALL" ENABLE_AUTO_UPDATES="$ENABLE_AUTO_UPDATES" \
    ENABLE_SSH="$ENABLE_SSH" SSH_PUBKEY="${SSH_PUBKEY:-}" \
    ARCH="$ARCH" DEBIAN_VERSION="$DEBIAN_VERSION" RAM_MB="$RAM_MB" CPU_THREADS="$CPU_THREADS" \
    IS_VM="$IS_VM" VIRTUALIZATION_TYPE="$VIRTUALIZATION_TYPE" \
    bash "$script" "$@"; then
    ok "$label"
  else
    error "$label"
    return 1
  fi
}

run_module_recoverable() {
  local label="$1"
  shift

  RECOVERABLE_STEP_FAILED=0
  if run_module "$label" "$@"; then
    return 0
  fi
  RECOVERABLE_STEP_FAILED=1
  continue_after_recoverable_failure "$label" ||
    fail "Operación cancelada por fallo en $label."
  warn "Se continúa sin completar: $label"
}

report_recoverable_failures() {
  local failure

  [[ -n "$RECOVERABLE_FAILURES_FILE" && -s "$RECOVERABLE_FAILURES_FILE" ]] || return 0
  while IFS= read -r failure; do
    [[ -n "$failure" ]] || continue
    report_add "Alertas" "$failure" "Falló / continuado"
  done < <(sort -u "$RECOVERABLE_FAILURES_FILE")
}

report_optional_modules() {
  local extra component category
  local -a extras=()

  IFS=',' read -r -a extras <<<"$EXTRAS"
  for extra in "${extras[@]}"; do
    case "$extra" in
      ssh)
        [[ "${ENABLE_SSH:-0}" -eq 0 ]] || continue
        category="Seguridad"; component="OpenSSH y protección UFW"
        ;;
      bluetooth) category="Hardware"; component="Bluetooth" ;;
      flatpak) category="Aplicaciones"; component="Flatpak y repositorio Flathub" ;;
      apps)
        if [[ -n "$APT_APP_SELECTIONS" ]]; then
          report_add "Aplicaciones" "Apps APT: $APT_APP_SELECTIONS"
        fi
        if [[ -n "$FLATPAK_APP_SELECTIONS" ]]; then
          report_add "Aplicaciones" "Apps Flatpak: $FLATPAK_APP_SELECTIONS"
        fi
        continue
        ;;
      zsh) category="Personalización"; component="Zsh y modificación de terminal" ;;
      fonts) category="Personalización"; component="Fuentes de escritorio y terminal" ;;
      gammastep) category="Personalización"; component="Control de pantalla Gammastep" ;;
      omv) category="Almacenamiento"; component="Montaje SMB de OMV" ;;
      rdp) category="Acceso remoto"; component="Escritorio remoto XRDP" ;;
      clamav)
        category="Seguridad"
        if [[ "$PROFILE" == "baja" ]]; then
          component="ClamAV bajo demanda"
        else
          component="ClamAV con servicios activos"
        fi
        ;;
      rkhunter) category="Seguridad"; component="Rootkit Hunter" ;;
      wazuh) category="Seguridad"; component="Agente Wazuh" ;;
      maintenance) category="Mantenimiento"; component="Actualización y limpieza APT" ;;
      debloat) category="Mantenimiento"; component="Debloat seguro (${DEBLOAT_PACKAGES:-sin selección})" ;;
      rtc) category="Sistema"; component="Hora, NTP y RTC" ;;
      *) continue ;;
    esac
    report_add "$category" "$component"
  done
}

main() {
  local recommended recommended_desktop user_spec additional_user additional_role _ssh_home audit_status

  parse_args "$@"
  init_ui
  trap cleanup_ui EXIT
  trap 'error "Instalación interrumpida."; exit 130' INT TERM
  trap 'error "Fallo en línea ${LINENO}: ${BASH_COMMAND}"' ERR

  require_root_or_reexec "$@"
  init_log
  start_session_log
  RECOVERABLE_FAILURES_FILE="${LOG_FILE%.log}.recoverable"
  : >"$RECOVERABLE_FAILURES_FILE"
  chmod 0640 "$RECOVERABLE_FAILURES_FILE" 2>/dev/null || true
  export RECOVERABLE_FAILURES_FILE
  print_banner
  detect_system
  check_platform
  check_network

  if [[ "$VIRTUALIZATION_SELECTION" != "auto" ]]; then
    set_virtualization_type "$VIRTUALIZATION_SELECTION"
  elif [[ "$ASSUME_YES" -eq 0 ]]; then
    set_virtualization_type "$(wizard_virtualization "$VIRTUALIZATION_TYPE")"
  fi
  show_system_summary

  if [[ -z "$PRESET" ]]; then
    PRESET="general"
  fi

  if [[ "$PRESET" == "gui-low-resource" ]]; then
    info "Preset GUI liviana: se recomienda LXQt, perfil baja y auditoría final."
    info "Las recomendaciones no reemplazan tus selecciones."
  fi

  if [[ -z "$INSTALL_MODE" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      fail "--yes requiere --mode."
    fi
    INSTALL_MODE="$(wizard_mode)"
  fi

  recommended="$(recommend_profile)"
  if [[ -z "$PROFILE" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      fail "--yes requiere --profile."
    fi
    PROFILE="$(wizard_profile "$recommended")"
  fi

  recommended_desktop="$(recommend_desktop)"
  if [[ "$INSTALL_MODE" == "gui" && -z "$DESKTOP" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      DESKTOP="$recommended_desktop"
      info "Escritorio seleccionado por perfil: $DESKTOP."
    else
      DESKTOP="$(wizard_desktop "$recommended_desktop")"
    fi
  fi

  if [[ -z "$TARGET_USER" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      fail "--yes requiere --user."
    fi
    TARGET_USER="$(wizard_user)"
  fi

  if [[ "$ASSUME_YES" -eq 0 ]]; then
    wizard_additional_users
    wizard_system_upgrade
  fi

  if [[ "$NVIDIA_PRESENT" -eq 1 && -z "$NVIDIA_POLICY" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      fail "NVIDIA detectada: definí --nvidia install|audit para ejecución no interactiva."
    fi
    NVIDIA_POLICY="$(wizard_nvidia_policy)"
  fi

  if [[ "$INSTALL_MODE" == "gui" && "$RAM_MB" -lt 4096 && "$DESKTOP" == "xfce" ]]; then
    warn "Con menos de 4 GB de RAM se recomienda LXQt."
    if confirm "¿Cambiar a LXQt?" "s"; then
      DESKTOP="lxqt"
    fi
  fi

  apply_component_selection
  if [[ "$ASSUME_YES" -eq 0 ]]; then
    wizard_components
    if [[ "$ENABLE_FIREWALL" -eq 1 || "$ENABLE_AUTO_UPDATES" -eq 1 || "$ENABLE_SSH" -eq 1 ]]; then
      ENABLE_SECURITY_BASELINE=1
    else
      ENABLE_SECURITY_BASELINE=0
    fi
  fi

  if [[ -z "$EXTRAS" && "$ASSUME_YES" -eq 0 ]]; then
    EXTRAS="$(wizard_extras)"
  fi

  if [[ "$INSTALL_MODE" == "gui" && -z "$GUI_APP_SELECTIONS" && "$ASSUME_YES" -eq 0 ]]; then
    GUI_APP_SELECTIONS="$(wizard_apps)"
  fi
  classify_app_selections
  if [[ ( -z "$DEBLOAT_PACKAGES" && "$ASSUME_YES" -eq 0 ) &&
    ( "$INSTALL_MODE" == "gui" || ",$EXTRAS," == *,debloat,* ) ]]; then
    DEBLOAT_PACKAGES="$(wizard_debloat_packages)"
    case "$DEBLOAT_PACKAGES" in
      __sin_candidatos__)
        DEBLOAT_PACKAGES=""
        DEBLOAT_STATUS="sin candidatos"
        EXTRAS="$(csv_remove_item "$EXTRAS" "debloat")"
        ;;
      "")
        DEBLOAT_STATUS="omitido"
        ;;
      *)
        DEBLOAT_STATUS="pendiente de simulación"
        ;;
    esac
  fi
  if [[ -n "$GUI_APP_SELECTIONS" ]]; then
    EXTRAS="$(csv_add_unique "$EXTRAS" "apps")"
  fi
  if [[ -n "$DEBLOAT_PACKAGES" ]]; then
    [[ "$DEBLOAT_STATUS" == "omitido" ]] && DEBLOAT_STATUS="pendiente de simulación"
    EXTRAS="$(csv_add_unique "$EXTRAS" "debloat")"
  fi

  validate_selection
  show_plan

  if [[ "$ASSUME_YES" -eq 0 ]]; then
    confirm "¿Aplicar este plan?" "n" || {
      warn "Operación cancelada sin cambios."
      exit 0
    }
  fi

  TOTAL_STEPS=2
  [[ "$ENABLE_SECURITY_BASELINE" -eq 1 ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$ENABLE_DESKTOP" -eq 1 ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$ENABLE_OPTIMIZATION" -eq 1 ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ -n "$EXTRAS" ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$ENABLE_HARDENING" -eq 1 ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
  [[ "$ENABLE_AUDIT" -eq 1 ]] && TOTAL_STEPS=$((TOTAL_STEPS + 1))

  ensure_target_user "$TARGET_USER"
  report_add "Usuarios" "$TARGET_USER (principal, administrador)"
  if ((${#ADDITIONAL_USERS[@]})); then
    ensure_additional_users "${ADDITIONAL_USERS[@]}"
    for user_spec in "${ADDITIONAL_USERS[@]}"; do
      IFS=: read -r additional_user additional_role <<<"$user_spec"
      report_add "Usuarios" "$additional_user ($additional_role)"
    done
  fi
  run_module "Preparación APT y herramientas" "$ROOT_DIR/scripts/base/install.sh"
  report_add "Sistema" "Índices de paquetes APT"
  if selected_apps_need_vendor_sources || [[ "$NVIDIA_POLICY" == "install" ]]; then
    report_add "Sistema" "Repositorios APT adicionales"
  fi
  if [[ "$INSTALL_BASE_TOOLS" -eq 1 ]]; then
    report_add "Sistema" "Herramientas generales de administración"
  else
    report_add "Sistema" "Herramientas generales de administración" "Omitido"
  fi
  if [[ "$INSTALL_CLI_TOOLS" -eq 1 ]]; then
    report_add "Sistema" "Herramientas CLI adicionales"
  else
    report_add "Sistema" "Herramientas CLI adicionales" "Omitido"
  fi
  if [[ "$UPGRADE_SYSTEM" -eq 1 ]]; then
    report_add "Sistema" "Actualización completa de paquetes"
  else
    report_add "Sistema" "Actualización completa de paquetes" "Omitido"
  fi

  run_module_recoverable "Personalización Bash" "$ROOT_DIR/scripts/personalizacion_bash.sh"
  if [[ "$RECOVERABLE_STEP_FAILED" -eq 1 ]]; then
    report_add "Personalización" "Configuración Bash" "Falló / continuado"
  else
    report_add "Personalización" "Configuración Bash"
  fi

  if [[ "$ENABLE_SECURITY_BASELINE" -eq 1 ]]; then
    run_module "Seguridad base" "$ROOT_DIR/scripts/security/baseline.sh"
  fi
  if [[ "$ENABLE_FIREWALL" -eq 1 ]]; then
    report_add "Seguridad" "Firewall UFW"
  else
    report_add "Seguridad" "Firewall UFW" "Omitido"
  fi
  if [[ "$ENABLE_AUTO_UPDATES" -eq 1 ]]; then
    report_add "Seguridad" "Actualizaciones automáticas"
  else
    report_add "Seguridad" "Actualizaciones automáticas" "Omitido"
  fi
  if [[ "$ENABLE_SSH" -eq 1 ]]; then
    report_add "Seguridad" "OpenSSH servidor"
    if [[ "$DRY_RUN" -eq 1 ]]; then
      report_add "Seguridad" "Claves SSH autorizadas" "Simulado"
    else
      _ssh_home="$(getent passwd "$TARGET_USER" | cut -d: -f6 2>/dev/null || echo "")"
      if [[ -n "$_ssh_home" && -s "$_ssh_home/.ssh/authorized_keys" ]]; then
        report_add "Seguridad" "Claves SSH autorizadas" "Configuradas"
      else
        report_add "Seguridad" "Claves SSH autorizadas" "SIN CLAVE"
      fi
    fi
  else
    report_add "Seguridad" "OpenSSH servidor" "Omitido"
  fi

  if [[ "$ENABLE_DESKTOP" -eq 1 ]]; then
    run_module_recoverable "Escritorio $DESKTOP" "$ROOT_DIR/scripts/desktop/install.sh"
    if [[ "$RECOVERABLE_STEP_FAILED" -eq 1 ]]; then
      report_add "Entorno gráfico" "Escritorio ${DESKTOP^^}" "Falló / continuado"
    else
      report_add "Entorno gráfico" "Escritorio ${DESKTOP^^}"
      # shellcheck disable=SC2034
      REBOOT_REQUIRED=1
    fi
  else
    report_add "Entorno gráfico" "Instalación de escritorio" "Omitido"
  fi

  if [[ "$NVIDIA_PRESENT" -eq 1 ]]; then
    report_add "Hardware" "NVIDIA (${NVIDIA_POLICY:-audit})"
  fi

  if [[ "$ENABLE_OPTIMIZATION" -eq 1 ]]; then
    run_module_recoverable "Optimización perfil $PROFILE" "$ROOT_DIR/scripts/optimization/apply.sh"
    if [[ "$RECOVERABLE_STEP_FAILED" -eq 1 ]]; then
      report_add "Optimización" "Ajustes del perfil $PROFILE" "Falló / continuado"
    else
      report_add "Optimización" "Ajustes del perfil $PROFILE"
    fi
    if [[ "$IS_VM" -eq 1 && "$RECOVERABLE_STEP_FAILED" -eq 0 ]]; then
      report_add "Optimización" "Ajustes para VM ($VIRTUALIZATION_TYPE)"
    fi
  else
    report_add "Optimización" "Ajustes del perfil $PROFILE" "Omitido"
  fi

  if [[ -n "$EXTRAS" ]]; then
    run_module_recoverable "Módulos opcionales" "$ROOT_DIR/scripts/optional/install.sh" "$EXTRAS"
    report_optional_modules
  fi

  if [[ "$ENABLE_HARDENING" -eq 1 ]]; then
    run_module "Hardening reforzado" "$ROOT_DIR/scripts/security/hardening.sh"
    report_add "Seguridad" "Hardening reforzado"
  else
    report_add "Seguridad" "Hardening reforzado" "Omitido"
  fi

  if [[ "$ENABLE_AUDIT" -eq 1 ]]; then
    run_module_recoverable "Auditoría final del sistema" \
      "$ROOT_DIR/scripts/audit/system-health.sh"
    if [[ "$RECOVERABLE_STEP_FAILED" -eq 1 ]]; then
      audit_status="Falló / continuado"
    elif [[ "$DRY_RUN" -eq 1 ]]; then
      audit_status="Simulado"
    else
      audit_status="Correcto"
    fi
    report_add "Validación" "Auditoría final del sistema" "$audit_status"
  else
    report_add "Validación" "Auditoría final del sistema" "Omitido"
  fi

  report_recoverable_failures
  final_summary
}

main "$@"
