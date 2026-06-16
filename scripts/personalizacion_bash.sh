cat > ~/personalizar-bash-noc.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

BASHRC="$HOME/.bashrc"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.bashrc.bak-noc-$TS"

START_MARK="# >>> NOC BASH CUSTOM >>>"
END_MARK="# <<< NOC BASH CUSTOM <<<"

echo "=============================================================================="
echo " Personalización Bash NOC/Debian"
echo "=============================================================================="
echo "Usuario: $(whoami)"
echo "Home:    $HOME"
echo "Archivo: $BASHRC"
echo

if [[ "$(id -u)" -eq 0 ]]; then
  echo "ADVERTENCIA: estás ejecutando como root."
  echo "Esto personalizará /root/.bashrc, no el usuario operador."
  read -rp "¿Continuar igual? [s/N]: " ok
  [[ "$ok" =~ ^[sS]$ ]] || exit 1
fi

touch "$BASHRC"
cp -a "$BASHRC" "$BACKUP"

echo "Backup creado:"
echo "  $BACKUP"
echo

# Eliminar bloque anterior si existe
awk -v start="$START_MARK" -v end="$END_MARK" '
  $0 == start {skip=1; next}
  $0 == end {skip=0; next}
  skip != 1 {print}
' "$BASHRC" > "$BASHRC.tmp"

mv "$BASHRC.tmp" "$BASHRC"

cat >> "$BASHRC" <<'BASHCUSTOM'

# >>> NOC BASH CUSTOM >>>
# Personalización Bash para Debian/NOC
# Gestionado por ~/personalizar-bash-noc.sh

# Solo ejecutar en shells interactivas
case "$-" in
  *i*) ;;
  *) return ;;
esac

# Historial más útil
export HISTSIZE=50000
export HISTFILESIZE=100000
export HISTCONTROL=ignoreboth:erasedups
export HISTTIMEFORMAT="%F %T  "
shopt -s histappend
PROMPT_COMMAND="history -a; history -c; history -r; ${PROMPT_COMMAND:-}"

# Editor por defecto
export EDITOR=nano
export VISUAL=nano
export PAGER=less
export LESS="-R -F -X"

# PATH seguro: agregar sin reemplazar
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

# Colores para ls/grep
alias ls='ls --color=auto'
alias ll='ls -lah --group-directories-first'
alias la='ls -A --group-directories-first'
alias l='ls -CF --group-directories-first'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'

# Alias útiles Debian
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

# Funciones útiles
mkcd() {
  mkdir -p "$1" && cd "$1"
}

extract() {
  if [[ ! -f "$1" ]]; then
    echo "No existe el archivo: $1"
    return 1
  fi

  case "$1" in
    *.tar.bz2) tar xjf "$1" ;;
    *.tar.gz)  tar xzf "$1" ;;
    *.tar.xz)  tar xJf "$1" ;;
    *.tar)     tar xf "$1" ;;
    *.tbz2)    tar xjf "$1" ;;
    *.tgz)     tar xzf "$1" ;;
    *.zip)     unzip "$1" ;;
    *.gz)      gunzip "$1" ;;
    *.bz2)     bunzip2 "$1" ;;
    *.xz)      unxz "$1" ;;
    *.7z)      7z x "$1" ;;
    *)         echo "Formato no soportado: $1"; return 1 ;;
  esac
}

sysmini() {
  echo "===== SISTEMA ====="
  hostnamectl 2>/dev/null || true
  echo
  echo "===== KERNEL ====="
  uname -a
  echo
  echo "===== IP ====="
  ip -br addr
  echo
  echo "===== DISCO ====="
  df -hT
  echo
  echo "===== RAM ====="
  free -h
  echo
  echo "===== SERVICIOS FALLIDOS ====="
  systemctl --failed --no-pager
}

# Prompt NOC con estado, hora, usuario, host, IP y ruta
__noc_prompt() {
  local exit_code="$?"
  local status_label
  local status_color
  local reset="\[\e[0m\]"
  local green="\[\e[32m\]"
  local red="\[\e[31m\]"
  local cyan="\[\e[36m\]"
  local yellow="\[\e[33m\]"
  local blue="\[\e[34m\]"

  local ip_addr
  ip_addr="$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  [[ -n "$ip_addr" ]] || ip_addr="sin-ip"

  if [[ "$exit_code" -eq 0 ]]; then
    status_label="OK"
    status_color="$green"
  else
    status_label="ERR:$exit_code"
    status_color="$red"
  fi

  PS1="${status_color}[NOC ${status_label}]${reset} ${yellow}\A${reset} ${cyan}\u@\h${reset} ${blue}${ip_addr}${reset} \w \\$ "
}

PROMPT_COMMAND="__noc_prompt; history -a; history -c; history -r"

# <<< NOC BASH CUSTOM <<<
BASHCUSTOM

mkdir -p "$HOME/.local/bin" "$HOME/bin" "$HOME/Scripts"

echo "Personalización aplicada."
echo
echo "Para activarla ahora ejecutá:"
echo "  source ~/.bashrc"
echo
echo "Para validar:"
echo "  echo \$SHELL"
echo "  echo \$PATH"
echo "  alias | head"
echo
EOF

chmod +x ~/personalizar-bash-noc.sh
~/personalizar-bash-noc.sh
source ~/.bashrc