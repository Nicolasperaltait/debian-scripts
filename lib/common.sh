#!/usr/bin/env bash

DRY_RUN="${DRY_RUN:-0}"
LOG_FILE="${LOG_FILE:-}"
REBOOT_REQUIRED=0
SESSION_LOGGING="${SESSION_LOGGING:-0}"
LAST_BACKUP_FILE="${LAST_BACKUP_FILE:-}"
REPORT_FILE="${REPORT_FILE:-}"
REPORT_CATEGORIES=()
REPORT_COMPONENTS=()
REPORT_STATUSES=()

init_ui() {
  if [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_BLUE=""; C_CYAN=""
    C_GREEN=""; C_YELLOW=""; C_RED=""
  fi
}

cleanup_ui() { printf '%s' "${C_RESET:-}"; }

choose() {
  local prompt="$1"
  shift
  local options=("$@")
  local answer index

  while true; do
    printf '\n%s%s%s\n' "$C_BOLD" "$prompt" "$C_RESET" >&2
    for index in "${!options[@]}"; do
      printf '  %s%d)%s %s\n' "$C_CYAN" "$((index + 1))" "$C_RESET" "${options[$index]}" >&2
    done
    read -r -p "> " answer
    [[ "$answer" =~ ^[0-9]+$ ]] || { warn "Ingresá un número válido."; continue; }
    ((answer >= 1 && answer <= ${#options[@]})) || { warn "Opción fuera de rango."; continue; }
    printf '%s' "$answer"
    return
  done
}

confirm() {
  local prompt="$1"
  local default="${2:-n}"
  local suffix="[s/N]" answer
  [[ "$default" == "s" ]] && suffix="[S/n]"
  read -r -p "$prompt $suffix " answer
  answer="${answer:-$default}"
  [[ "$answer" =~ ^[sS]$ ]]
}

validate_firewall_source() {
  local value="${1:-}" address prefix octet
  local -a octets=()

  address="${value%/*}"
  [[ "$value" == */* ]] && prefix="${value##*/}" || prefix=""

  if [[ "$address" == *:* ]]; then
    [[ "$address" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
    [[ -z "$prefix" || ("$prefix" =~ ^[0-9]+$ && "$prefix" -le 128) ]]
    return
  fi

  IFS=. read -r -a octets <<<"$address"
  ((${#octets[@]} == 4)) || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ && "$octet" -le 255 ]] || return 1
  done
  [[ -z "$prefix" || ("$prefix" =~ ^[0-9]+$ && "$prefix" -le 32) ]]
}

current_ssh_source() {
  local connection="${SSH_CONNECTION:-${SSH_CLIENT:-}}" source

  [[ -n "$connection" ]] || return 1
  source="${connection%% *}"
  validate_firewall_source "$source" || return 1
  printf '%s' "$source"
}

choose_firewall_source() {
  local service="$1"
  local allow_cancel="${2:-0}"
  local option source current_source
  local -a options=(
    "Restringir a una IP o red CIDR (recomendado)"
    "Permitir cualquier origen con limitación de intentos"
  )

  if [[ "$service" == "SSH" ]] && current_source="$(current_ssh_source)"; then
    info "Conexión SSH actual detectada desde: $current_source" >&2
  fi
  [[ "$allow_cancel" -eq 1 ]] &&
    options+=("Cancelar antes de activar el firewall")

  option="$(choose "Acceso de red para $service" "${options[@]}")"
  if [[ "$option" == "1" ]]; then
    while true; do
      read -r -p "IP o red CIDR permitida (ej. 192.0.2.10/32): " source
      validate_firewall_source "$source" && { printf '%s' "$source"; return; }
      warn "Ingresá una dirección IP o red CIDR válida."
    done
  fi
  if [[ "$option" == "2" ]]; then
    warn "$service quedará accesible desde cualquier origen."
    confirm "¿Confirmás esta exposición?" "n" ||
      fail "Configuración de $service cancelada."
    printf 'any'
    return
  fi

  printf 'cancel'
}

print_banner() {
  printf '%s\n' "${C_CYAN}${C_BOLD}"
  printf '  ╔══════════════════════════════════════════════╗\n'
  printf '  ║       DEBIAN WORKSTATION BOOTSTRAPPER       ║\n'
  printf '  ║        Debian 12 / Debian 13 Wizard          ║\n'
  printf '  ╚══════════════════════════════════════════════╝\n'
  printf '%s\n' "${C_RESET}"
}

section() {
  printf '\n%s%s==> %s%s\n' "$C_BLUE" "$C_BOLD" "$*" "$C_RESET"
}

progress_bar() {
  local current="$1"
  local total="$2"
  local label="$3"
  local width=30
  local filled=$((current * width / total))
  local empty=$((width - filled))
  local percent=$((current * 100 / total))
  printf '\n%s[' "$C_DIM"
  printf '%*s' "$filled" '' | tr ' ' '#'
  printf '%*s' "$empty" '' | tr ' ' '.'
  printf '] %3d%% %s%s\n' "$percent" "$label" "$C_RESET"
}

info() { printf '%s[INFO]%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok() { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
error() { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
fail() { error "$*"; exit 1; }

log_line() {
  [[ -n "$LOG_FILE" ]] || return 0
  if [[ "$SESSION_LOGGING" -eq 1 ]]; then
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >&3
  else
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
  fi
}

init_log() {
  local log_dir log_kind log_user log_group log_home

  if [[ "${DEBIAN_SCRIPTS_TEST:-0}" == "1" ]]; then
    log_dir="${DEBIAN_SCRIPTS_LOG_DIR:-${TMPDIR:-/tmp}}"
    mkdir -p "$log_dir"
    log_kind="$([[ "$DRY_RUN" -eq 1 ]] && printf 'dry-run' || printf 'install')"
    LOG_FILE="$(mktemp "$log_dir/debian-scripts-${log_kind}.XXXXXX.log")"
  else
    log_user="${SUDO_USER:-$(id -un)}"
    getent passwd "$log_user" >/dev/null ||
      fail "No se pudo determinar el usuario propietario del log: $log_user"
    log_group="$(id -gn "$log_user")"
    log_home="$(getent passwd "$log_user" | cut -d: -f6)"
    [[ -n "$log_home" ]] || fail "No se encontró HOME para el usuario del log: $log_user"

    log_dir="$log_home/debian-scripts-logs"
    if [[ "$EUID" -eq 0 ]]; then
      install -d -m 0750 -o root -g "$log_group" "$log_dir"
    else
      install -d -m 0750 "$log_dir"
    fi
    log_kind="$([[ "$DRY_RUN" -eq 1 ]] && printf 'dry-run' || printf 'install')"
    LOG_FILE="$(mktemp "$log_dir/${log_kind}_$(date +%F_%H-%M-%S).XXXXXX.log")"
    chmod 0640 "$LOG_FILE"
    if [[ "$EUID" -eq 0 ]]; then
      chown "root:$log_group" "$LOG_FILE"
    fi
  fi

  export LOG_FILE
}

start_session_log() {
  [[ -n "$LOG_FILE" ]] || fail "El log debe inicializarse antes de capturar la sesión."
  [[ "$SESSION_LOGGING" -eq 0 ]] || return 0
  exec 3>>"$LOG_FILE"
  SESSION_LOGGING=1
  export SESSION_LOGGING
  exec > >(tee -a /dev/fd/3) 2>&1
}

quote_cmd() {
  local arg out=""
  for arg in "$@"; do out+="$(printf '%q' "$arg") "; done
  printf '%s' "${out% }"
}

run() {
  log_line "RUN: $(quote_cmd "$@")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: $(quote_cmd "$@")"
    return 0
  fi
  "$@"
}

backup_file() {
  local file="$1" backup_root backup
  LAST_BACKUP_FILE=""
  [[ -e "$file" ]] || return 0
  backup_root="/var/backups/debian-scripts/$(date +%F_%H%M%S_%N)"
  backup="$backup_root/${file#/}"
  run install -d -m 0700 "$(dirname "$backup")"
  run cp -a -- "$file" "$backup"
  LAST_BACKUP_FILE="$backup"
  info "Backup: $backup"
}

write_file() {
  local target="$1"
  local content="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: escribir $target"
    return 0
  fi
  backup_file "$target"
  install -d -m 0755 "$(dirname "$target")"
  printf '%s\n' "$content" >"$target"
  log_line "WRITE: $target"
}

apt_install() {
  (($#)) || return 0
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

mark_reboot_required() {
  REBOOT_REQUIRED=1
  export REBOOT_REQUIRED
}

report_add() {
  local category="$1"
  local component="$2"
  local status="${3:-}"

  if [[ -z "$status" ]]; then
    status="$([[ "$DRY_RUN" -eq 1 ]] && printf 'Simulado' || printf 'Aplicado')"
  fi
  REPORT_CATEGORIES+=("$category")
  REPORT_COMPONENTS+=("$component")
  REPORT_STATUSES+=("$status")
}

write_install_report() {
  local execution mode_detail reboot_status generated_at
  local category_width=9 component_width=10 status_width=6
  local index category component status
  local header_category="Categoría" header_component="Componente" header_status="Estado"

  REPORT_FILE="${LOG_FILE%.log}.md"
  execution="$([[ "$DRY_RUN" -eq 1 ]] && printf 'Simulación' || printf 'Real')"
  mode_detail="$INSTALL_MODE"
  [[ "$INSTALL_MODE" == "gui" ]] && mode_detail+=" ($DESKTOP)"
  reboot_status="$([[ "$REBOOT_REQUIRED" -eq 1 ]] && printf 'Recomendado' || printf 'No requerido')"
  generated_at="$(date '+%F %T %Z')"

  for index in "${!REPORT_CATEGORIES[@]}"; do
    category="${REPORT_CATEGORIES[$index]}"
    component="${REPORT_COMPONENTS[$index]}"
    status="${REPORT_STATUSES[$index]}"
    ((${#category} > category_width)) && category_width=${#category}
    ((${#component} > component_width)) && component_width=${#component}
    ((${#status} > status_width)) && status_width=${#status}
  done

  {
    printf '# Informe de instalación Debian Scripts\n\n'
    printf -- '- **Fecha:** %s\n' "$generated_at"
    printf -- '- **Usuario objetivo:** `%s`\n' "$TARGET_USER"
    printf -- '- **Ejecución:** %s\n' "$execution"
    printf -- '- **Preset:** `%s`\n' "${PRESET:-general}"
    printf -- '- **Modo:** %s\n' "$mode_detail"
    printf -- '- **Perfil:** `%s`\n' "$PROFILE"
    printf -- '- **Reinicio:** %s\n\n' "$reboot_status"
    printf '| %s' "$header_category"
    printf '%*s' "$((category_width - ${#header_category}))" ''
    printf ' | %s' "$header_component"
    printf '%*s' "$((component_width - ${#header_component}))" ''
    printf ' | %s' "$header_status"
    printf '%*s' "$((status_width - ${#header_status}))" ''
    printf ' |\n'
    printf "|-%s-|-%s-|-%s-|\n" \
      "$(printf '%*s' "$category_width" '' | tr ' ' '-')" \
      "$(printf '%*s' "$component_width" '' | tr ' ' '-')" \
      "$(printf '%*s' "$status_width" '' | tr ' ' '-')"
    for index in "${!REPORT_CATEGORIES[@]}"; do
      category="${REPORT_CATEGORIES[$index]}"
      component="${REPORT_COMPONENTS[$index]}"
      status="${REPORT_STATUSES[$index]}"
      printf '| %s' "$category"
      printf '%*s' "$((category_width - ${#category}))" ''
      printf ' | %s' "$component"
      printf '%*s' "$((component_width - ${#component}))" ''
      printf ' | %s' "$status"
      printf '%*s' "$((status_width - ${#status}))" ''
      printf ' |\n'
    done
    printf '\n## Evidencia\n\n'
    printf -- '- Log completo: `%s`\n' "$LOG_FILE"
  } >"$REPORT_FILE"

  chmod 0640 "$REPORT_FILE"
  if [[ "$EUID" -eq 0 ]]; then
    chown --reference="$LOG_FILE" "$REPORT_FILE"
  fi
  export REPORT_FILE
}

final_summary() {
  write_install_report
  section "Instalación finalizada - Resumen"
  cat "$REPORT_FILE"
  printf '\n'
  info "Log: $LOG_FILE"
  info "Informe Markdown: $REPORT_FILE"
  if [[ "$REBOOT_REQUIRED" -eq 1 ]]; then
    warn "Se recomienda reiniciar manualmente."
  else
    info "No se programó ningún reinicio automático."
  fi
}
