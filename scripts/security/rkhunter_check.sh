#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
umask 077

readonly SCRIPT_NAME="rkhunter_check"
readonly LOG_DIR="/var/log/${SCRIPT_NAME}"
readonly LOCK_FILE="/var/lock/${SCRIPT_NAME}.lock"
readonly CONF_FILE="/etc/${SCRIPT_NAME}.conf"

# Defaults (overrideables por /etc/rkhunter_check.conf)
QUIET=0
VERBOSE=0
DRY_RUN=0
DO_INSTALL=0
DO_UPDATE=1
DO_CHECK=1
DO_PROPUPD=0
TIMEOUT_SECS=0
NO_COLOR=1
RETAIN_DAYS=30

# Operación: por defecto, si falla --update no aborta el resto (ideal cron).
STRICT_UPDATE=0

usage() {
  cat <<'EOF'
Uso:
  sudo ./rkhunter_check.sh [opciones]

Modo por defecto:
  - Si hay TTY (terminal): verbose
  - Si NO hay TTY (cron/systemd): quiet + log

Opciones:
  --install            Instala rkhunter si no está instalado (apt-get)
  --update             Ejecuta rkhunter --update (default: sí)
  --no-update          No ejecuta update
  --check              Ejecuta rkhunter --check  (default: sí)
  --no-check           No ejecuta check
  --propupd            Ejecuta rkhunter --propupd (baseline)
  --timeout SEC        Corta el check si excede SEC (ideal cron)
  --retain-days N      Borra logs con más de N días (default: 30)
  --quiet              Solo log a archivo
  --verbose            Muestra progreso en pantalla + log
  --dry-run            No ejecuta; solo muestra lo que haría
  --color              Fuerza colores (default: sin colores)
  --strict-update       Si falla --update, aborta (default: no)
  -h, --help           Ayuda

Ejemplos:
  sudo ./rkhunter_check.sh
  sudo ./rkhunter_check.sh --install
  sudo ./rkhunter_check.sh --timeout 900 --retain-days 14
  sudo ./rkhunter_check.sh --no-update --check --timeout 1200
  sudo ./rkhunter_check.sh --propupd --no-update --verbose
EOF
}

ts() { date '+%F %T'; }

log_init() {
  mkdir -p "$LOG_DIR"
  RUN_TS="$(date +%F_%H-%M-%S)"
  LOG_FILE="${LOG_DIR}/run_${RUN_TS}.log"
  : >"$LOG_FILE"
}

log() {
  local msg="[$(ts)] $*"
  if [[ "$QUIET" -eq 1 ]]; then
    echo "$msg" >>"$LOG_FILE"
  else
    echo "$msg" | tee -a "$LOG_FILE"
  fi
}

die() {
  log "ERROR: $*"
  exit 1
}

on_err() {
  local exit_code=$?
  log "Fallo (exit=$exit_code) en línea ${BASH_LINENO[0]}: ${BASH_COMMAND}"
  log "Log: $LOG_FILE"
  exit "$exit_code"
}
trap on_err ERR

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Ejecutá con sudo/root."
}

load_conf() {
  if [[ -f "$CONF_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONF_FILE"
  fi
}

acquire_lock() {
  mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    # Evita doble ejecución (cron)
    exit 0
  fi
}

auto_mode_if_not_set() {
  # Si el usuario no especificó quiet/verbose, auto-detectamos
  if [[ "$QUIET" -eq 0 && "$VERBOSE" -eq 0 ]]; then
    if [[ -t 1 ]]; then
      VERBOSE=1
    else
      QUIET=1
    fi
  fi
  # Si ambos se setean, gana quiet (más seguro para cron)
  if [[ "$QUIET" -eq 1 ]]; then
    VERBOSE=0
  fi
}

fmt_cmd() {
  # Render seguro/legible del comando sin depender de IFS
  local out=""
  local a
  for a in "$@"; do
    out+=$(printf '%q ' "$a")
  done
  printf '%s' "${out% }"
}

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: $(fmt_cmd "$@")"
    return 0
  fi

  log "RUN: $(fmt_cmd "$@")"
  if [[ "$QUIET" -eq 1 ]]; then
    "$@" >>"$LOG_FILE" 2>&1
  else
    # En interactivo, mostramos salida y también logueamos
    "$@" 2>&1 | tee -a "$LOG_FILE"
  fi
}

ensure_rkhunter() {
  if command -v rkhunter >/dev/null 2>&1; then
    return 0
  fi

  if [[ "$DO_INSTALL" -eq 1 ]]; then
    log "rkhunter no está instalado. Instalando (apt-get)..."
    run_cmd env DEBIAN_FRONTEND=noninteractive apt-get update -y
    run_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y rkhunter
  else
    die "rkhunter no está instalado. Solución: sudo apt-get install -y rkhunter  (o ejecutá con --install)."
  fi

  command -v rkhunter >/dev/null 2>&1 || die "Se intentó instalar rkhunter pero sigue sin estar disponible."
}

rkhunter_common_opts() {
  local -a opts=()
  [[ "$NO_COLOR" -eq 1 ]] && opts+=(--nocolors)
  opts+=(--sk) # no pausa interactiva
  # Si no verbose, warnings-only para logs limpios
  [[ "$VERBOSE" -eq 0 ]] && opts+=(--rwo)
  printf '%s\0' "${opts[@]}"
}

cleanup_old_logs() {
  # Borra logs viejos; no falla si no hay nada que borrar
  find "$LOG_DIR" -maxdepth 1 -type f -name 'run_*.log' -mtime +"$RETAIN_DAYS" -print -delete >>"$LOG_FILE" 2>&1 || true
}

require_timeout_if_needed() {
  if [[ "$TIMEOUT_SECS" -gt 0 ]]; then
    command -v timeout >/dev/null 2>&1 || die "Se pidió --timeout pero 'timeout' no está disponible (paquete coreutils)."
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install) DO_INSTALL=1; shift ;;
      --update) DO_UPDATE=1; shift ;;
      --no-update) DO_UPDATE=0; shift ;;
      --check) DO_CHECK=1; shift ;;
      --no-check) DO_CHECK=0; shift ;;
      --propupd) DO_PROPUPD=1; shift ;;
      --timeout)
        TIMEOUT_SECS="${2:-}"; [[ "$TIMEOUT_SECS" =~ ^[0-9]+$ ]] || die "--timeout requiere un número (segundos)"
        shift 2
        ;;
      --retain-days)
        RETAIN_DAYS="${2:-}"; [[ "$RETAIN_DAYS" =~ ^[0-9]+$ ]] || die "--retain-days requiere un número"
        shift 2
        ;;
      --quiet) QUIET=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --color) NO_COLOR=0; shift ;;
      --strict-update) STRICT_UPDATE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "Argumento desconocido: $1 (usá --help)" ;;
    esac
  done

  require_root
  load_conf
  auto_mode_if_not_set
  log_init
  acquire_lock

  log "Inicio ${SCRIPT_NAME} | log=$LOG_FILE | mode=$([[ "$QUIET" -eq 1 ]] && echo quiet || echo verbose)"
  cleanup_old_logs

  ensure_rkhunter
  require_timeout_if_needed

  local update_failed=0

  if [[ "$DO_UPDATE" -eq 1 ]]; then
    log "rkhunter --update"
    if ! run_cmd rkhunter --update; then
      update_failed=1
      log "WARN: rkhunter --update falló. Continuo (default). Ver /var/log/rkhunter.log para detalle."
      if [[ "$STRICT_UPDATE" -eq 1 ]]; then
        die "Modo --strict-update: abortando por fallo en --update."
      fi
    fi
  fi

  if [[ "$DO_PROPUPD" -eq 1 ]]; then
    log "rkhunter --propupd (actualiza baseline de propiedades)"
    # Nota: propupd puede ejecutarse aunque update haya fallado.
    run_cmd rkhunter --propupd
  fi

  if [[ "$DO_CHECK" -eq 1 ]]; then
    local -a opts=()
    while IFS= read -r -d '' o; do opts+=("$o"); done < <(rkhunter_common_opts)

    if [[ "$TIMEOUT_SECS" -gt 0 ]]; then
      log "rkhunter --check (timeout=${TIMEOUT_SECS}s)"
      run_cmd timeout --preserve-status "$TIMEOUT_SECS" rkhunter --check "${opts[@]}"
    else
      log "rkhunter --check"
      run_cmd rkhunter --check "${opts[@]}"
    fi
  fi

  if [[ "$update_failed" -eq 1 ]]; then
    log "Fin ${SCRIPT_NAME} con WARN: update fallido (revisar /var/log/rkhunter.log)."
  else
    log "OK - Fin ${SCRIPT_NAME}"
  fi
}

main "$@"
