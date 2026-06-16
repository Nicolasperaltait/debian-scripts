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

TARGET_USER=""
ADDITIONAL_USERS=()
PRESET=""
INSTALL_MODE=""
DESKTOP=""
PROFILE=""
EXTRAS=""
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
                         bajos recursos recomienda GUI + LXQt + perfil baja
  --mode cli|gui         Tipo de instalación
  --desktop xfce|lxqt    Escritorio para modo GUI
  --profile baja|media|alta|ultra
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
  clamav, rkhunter, wazuh, maintenance, rtc

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
      --mode) INSTALL_MODE="${2:-}"; shift 2 ;;
      --desktop) DESKTOP="${2:-}"; shift 2 ;;
      --profile) PROFILE="${2:-}"; shift 2 ;;
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
  [[ "$INSTALL_MODE" =~ ^(cli|gui)$ ]] || fail "Modo inválido: $INSTALL_MODE"
  [[ "$PROFILE" =~ ^(baja|media|alta|ultra)$ ]] || fail "Perfil inválido: $PROFILE"

  if [[ "$INSTALL_MODE" == "gui" ]]; then
    [[ "$DESKTOP" =~ ^(xfce|lxqt)$ ]] || fail "Escritorio inválido: $DESKTOP"
  else
    DESKTOP="ninguno"
  fi

  validate_extras "$EXTRAS"

  if [[ "$ENABLE_DESKTOP" -eq 1 && "$INSTALL_MODE" != "gui" ]]; then
    fail "El componente desktop requiere --mode gui."
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
    INSTALL_BASE_TOOLS="$INSTALL_BASE_TOOLS" INSTALL_CLI_TOOLS="$INSTALL_CLI_TOOLS" \
    ENABLE_FIREWALL="$ENABLE_FIREWALL" ENABLE_AUTO_UPDATES="$ENABLE_AUTO_UPDATES" \
    ENABLE_SSH="$ENABLE_SSH" \
    ARCH="$ARCH" DEBIAN_VERSION="$DEBIAN_VERSION" \
    bash "$script" "$@"; then
    ok "$label"
  else
    error "$label"
    return 1
  fi
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
      apps) category="Aplicaciones"; component="Aplicaciones Flatpak" ;;
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
      rtc) category="Sistema"; component="Hora, NTP y RTC" ;;
      *) continue ;;
    esac
    report_add "$category" "$component"
  done
}

main() {
  local recommended user_spec additional_user additional_role

  parse_args "$@"
  init_ui
  trap cleanup_ui EXIT
  trap 'error "Instalación interrumpida."; exit 130' INT TERM
  trap 'error "Fallo en línea ${LINENO}: ${BASH_COMMAND}"' ERR

  require_root_or_reexec "$@"
  init_log
  start_session_log
  print_banner
  detect_system
  check_platform
  check_network
  show_system_summary

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

  if [[ -z "$PRESET" ]]; then
    if [[ "$ASSUME_YES" -eq 1 ]]; then
      PRESET="general"
    else
      PRESET="$(wizard_preset)"
    fi
  fi

  if [[ "$PRESET" == "gui-low-resource" ]]; then
    info "Escenario bajos recursos: se recomienda GUI, LXQt, perfil baja y auditoría final."
    info "Las recomendaciones no reemplazan tus selecciones."
  fi

  if [[ "$ASSUME_YES" -eq 1 ]]; then
    [[ -n "$TARGET_USER" && -n "$INSTALL_MODE" && -n "$PROFILE" ]] ||
      fail "--yes requiere --user, --mode y --profile."
    if [[ "$INSTALL_MODE" == "gui" && -z "$DESKTOP" ]]; then
      fail "--yes con modo GUI requiere --desktop."
    fi
  fi

  if [[ -z "$INSTALL_MODE" ]]; then
    INSTALL_MODE="$(wizard_mode)"
  fi
  if [[ "$INSTALL_MODE" == "gui" && -z "$DESKTOP" ]]; then
    DESKTOP="$(wizard_desktop)"
  fi

  recommended="$(recommend_profile)"
  [[ "$PRESET" == "gui-low-resource" ]] && recommended="baja"
  if [[ -z "$PROFILE" ]]; then
    PROFILE="$(wizard_profile "$recommended")"
  fi

  if [[ "$INSTALL_MODE" == "gui" && "$PROFILE" == "baja" && "$DESKTOP" == "xfce" ]]; then
    warn "Para recursos bajos se recomienda LXQt."
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

  run_module "Personalización Bash" "$ROOT_DIR/scripts/personalizacion_bash.sh"
  report_add "Personalización" "Configuración Bash"

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
  else
    report_add "Seguridad" "OpenSSH servidor" "Omitido"
  fi

  if [[ "$ENABLE_DESKTOP" -eq 1 ]]; then
    run_module "Escritorio $DESKTOP" "$ROOT_DIR/scripts/desktop/install.sh"
    report_add "Entorno gráfico" "Escritorio ${DESKTOP^^}"
    REBOOT_REQUIRED=1
  else
    report_add "Entorno gráfico" "Instalación de escritorio" "Omitido"
  fi

  if [[ "$ENABLE_OPTIMIZATION" -eq 1 ]]; then
    run_module "Optimización perfil $PROFILE" "$ROOT_DIR/scripts/optimization/apply.sh"
    report_add "Optimización" "Ajustes del perfil $PROFILE"
  else
    report_add "Optimización" "Ajustes del perfil $PROFILE" "Omitido"
  fi

  if [[ -n "$EXTRAS" ]]; then
    run_module "Módulos opcionales" "$ROOT_DIR/scripts/optional/install.sh" "$EXTRAS"
    report_optional_modules
  fi

  if [[ "$ENABLE_HARDENING" -eq 1 ]]; then
    run_module "Hardening reforzado" "$ROOT_DIR/scripts/security/hardening.sh"
    report_add "Seguridad" "Hardening reforzado"
  else
    report_add "Seguridad" "Hardening reforzado" "Omitido"
  fi

  if [[ "$ENABLE_AUDIT" -eq 1 ]]; then
    run_module "Auditoría final del sistema" \
      "$ROOT_DIR/scripts/audit/system-health.sh"
    report_add "Validación" "Auditoría final del sistema" \
      "$([[ "$DRY_RUN" -eq 1 ]] && printf 'Simulado' || printf 'Correcto')"
  else
    report_add "Validación" "Auditoría final del sistema" "Omitido"
  fi

  final_summary
}

main "$@"
