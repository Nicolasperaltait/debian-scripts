#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
init_ui

START_MARK="# >>> DEBIAN BASH CUSTOM >>>"
END_MARK="# <<< DEBIAN BASH CUSTOM <<<"

apply_bash_config() {
  local user_home bashrc tmp

  if [[ "$DRY_RUN" -eq 1 ]]; then
    user_home="/home/$TARGET_USER"
    info "DRY-RUN: aplicar personalización Bash en $user_home/.bashrc"
    return 0
  fi

  user_home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$user_home" ]] || fail "No se encontró HOME para $TARGET_USER."
  bashrc="$user_home/.bashrc"

  touch "$bashrc"
  backup_file "$bashrc"

  # Eliminar bloque anterior si ya existe (idempotente)
  tmp="$(mktemp)"
  awk -v start="$START_MARK" -v end="$END_MARK" '
    $0 == start {skip=1; next}
    $0 == end   {skip=0; next}
    !skip       {print}
  ' "$bashrc" > "$tmp"

  cat >> "$tmp" <<'BASHBLOCK'

# >>> DEBIAN BASH CUSTOM >>>
# Solo ejecutar en shells interactivas
case "$-" in
  *i*) ;;
  *) return ;;
esac

# Historial ampliado y sin duplicados
export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%F %T  "
shopt -s histappend

# Editores y paginador
export EDITOR=nano
export VISUAL=nano
export PAGER=less
export LESS="-R -F -X"

# PATH seguro sin duplicados
path_add() {
  case ":$PATH:" in
    *":$1:"*) ;;
    *) PATH="$1:$PATH" ;;
  esac
}
path_add "$HOME/.local/bin"
path_add "$HOME/bin"
path_add "$HOME/Scripts"
export PATH

# Colores
alias ls='ls --color=auto'
alias ll='ls -lah --group-directories-first'
alias la='ls -A --group-directories-first'
alias l='ls -CF --group-directories-first'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Alias Debian
alias c='clear'
alias h='history'
alias ..='cd ..'
alias ...='cd ../..'
alias aptup='sudo apt update && sudo apt full-upgrade'
alias aptclean='sudo apt autoremove --purge && sudo apt autoclean'
alias ports='ss -tulpn'
alias myip='ip -br addr'
alias routeinfo='ip route && resolvectl status 2>/dev/null || true'
alias failed='systemctl --failed --no-pager'
alias jctl='journalctl -xe --no-pager'
alias dfh='df -hT'
alias duh='du -h --max-depth=1 2>/dev/null | sort -h'
alias mkdir='mkdir -pv'

# Funciones
mkcd() { mkdir -p "$1" && cd "$1"; }

extract() {
  [[ -f "$1" ]] || { echo "No existe: $1"; return 1; }
  case "$1" in
    *.tar.bz2) tar xjf "$1" ;; *.tar.gz)  tar xzf "$1" ;;
    *.tar.xz)  tar xJf "$1" ;; *.tar)     tar xf  "$1" ;;
    *.tbz2)    tar xjf "$1" ;; *.tgz)     tar xzf "$1" ;;
    *.zip)   unzip "$1"    ;; *.gz)      gunzip "$1"   ;;
    *.bz2)   bunzip2 "$1"  ;; *.xz)      unxz "$1"    ;;
    *.7z)    7z x "$1"     ;;
    *) echo "Formato no soportado: $1"; return 1 ;;
  esac
}

sysmini() {
  echo "===== SISTEMA =====";  hostnamectl 2>/dev/null || true
  echo; echo "===== KERNEL ====="; uname -a
  echo; echo "===== IP =====";    ip -br addr
  echo; echo "===== DISCO ====="; df -hT
  echo; echo "===== RAM =====";   free -h
  echo; echo "===== SERVICIOS FALLIDOS ====="; systemctl --failed --no-pager
}

# Prompt: [OK]/[FAIL] hora usuario@host IP ruta
__bash_prompt() {
  local exit_code="$?"
  local reset="\[\e[0m\]" green="\[\e[32m\]" red="\[\e[31m\]"
  local cyan="\[\e[36m\]"  yellow="\[\e[33m\]" blue="\[\e[34m\]"
  local status_label status_color ip_addr
  ip_addr="$(ip route get 1.1.1.1 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  [[ -n "$ip_addr" ]] || ip_addr="sin-ip"
  if [[ "$exit_code" -eq 0 ]]; then
    status_label="OK";   status_color="$green"
  else
    status_label="FAIL"; status_color="$red"
  fi
  PS1="${status_color}[${status_label}]${reset} ${yellow}\A${reset} ${cyan}\u@\h${reset} ${blue}${ip_addr}${reset} \w \\$ "
}

PROMPT_COMMAND="__bash_prompt; history -a; history -c; history -r"
# <<< DEBIAN BASH CUSTOM <<<
BASHBLOCK

  mv "$tmp" "$bashrc"
  chown "$TARGET_USER:$TARGET_USER" "$bashrc" 2>/dev/null || true

  mkdir -p "$user_home/.local/bin" "$user_home/bin" "$user_home/Scripts"
  chown "$TARGET_USER:$TARGET_USER" \
    "$user_home/.local" "$user_home/bin" "$user_home/Scripts" 2>/dev/null || true

  log_line "WRITE: $bashrc (personalización Bash)"
  ok "Bash configurado para $TARGET_USER"
}

apply_bash_config
