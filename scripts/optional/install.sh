#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"
init_ui

EXTRA_LIST="${1:-}"

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

choose_firewall_source() {
  local service="$1"
  local option source current_source

  if [[ "$service" == "SSH" && -n "${SSH_CONNECTION:-}" ]]; then
    current_source="${SSH_CONNECTION%% *}"
    info "Conexión SSH actual detectada desde: $current_source" >&2
  fi

  option="$(choose "Acceso de red para $service" \
    "Restringir a una IP o red CIDR (recomendado)" \
    "Permitir cualquier origen con limitación de intentos")"
  if [[ "$option" == "1" ]]; then
    while true; do
      read -r -p "IP o red CIDR permitida (ej. 192.0.2.10/32): " source
      validate_firewall_source "$source" && { printf '%s' "$source"; return; }
      warn "Ingresá una dirección IP o red CIDR válida."
    done
  fi

  warn "$service quedará accesible desde cualquier origen."
  confirm "¿Confirmás esta exposición?" "n" ||
    fail "Configuración de $service cancelada."
  printf 'any'
}

prepare_remote_firewall() {
  apt_install ufw
  run ufw default deny incoming
  run ufw default allow outgoing
}

install_ssh() {
  local source
  source="$(choose_firewall_source "SSH")"
  apt_install openssh-server
  prepare_remote_firewall
  run systemctl enable --now ssh
  if [[ "$source" == "any" ]]; then
    run ufw limit OpenSSH
  else
    run ufw limit from "$source" to any port 22 proto tcp comment "SSH restringido"
  fi
  run ufw --force enable
}

install_bluetooth() {
  apt_install bluetooth bluez blueman rfkill
  run systemctl enable --now bluetooth
}

install_flatpak() {
  apt_install flatpak
  run flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
}

install_apps() {
  local app
  local -a apps=()

  install_flatpak
  for app in $FLATPAK_APPS; do
    confirm "¿Instalar $app?" "n" && apps+=("$app")
  done
  ((${#apps[@]})) || fail "No se seleccionaron aplicaciones Flatpak."
  run flatpak install -y flathub "${apps[@]}"
}

install_zsh() {
  apt_install zsh zsh-autosuggestions zsh-syntax-highlighting
  local home
  if [[ "$DRY_RUN" -eq 1 ]]; then
    home="/home/$TARGET_USER"
  else
    home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  fi
  [[ -n "$home" ]] || fail "No se encontró HOME para $TARGET_USER."
  write_file "$home/.zshrc" 'autoload -Uz compinit && compinit
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh 2>/dev/null || true
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null || true
PROMPT="%F{cyan}%n@%m%f:%F{blue}%~%f %# "'
  run chown "$TARGET_USER:$TARGET_USER" "$home/.zshrc"
  run chsh -s /usr/bin/zsh "$TARGET_USER"
}

install_fonts() {
  apt_install fonts-dejavu fonts-liberation fonts-noto fonts-noto-color-emoji \
    fonts-firacode fonts-hack-ttf fonts-jetbrains-mono fonts-font-awesome
  run fc-cache -f
}

install_gammastep() {
  [[ "$INSTALL_MODE" == "gui" ]] || fail "Gammastep requiere instalación GUI."
  apt_install gammastep libnotify-bin

  local home script desktop
  if [[ "$DRY_RUN" -eq 1 ]]; then
    home="/home/$TARGET_USER"
  else
    home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  fi
  [[ -n "$home" ]] || fail "No se encontró HOME para $TARGET_USER."

  script="$home/.local/bin/gammastep-toggle-90"
  desktop="$home/Desktop/Gammastep-90.desktop"

  write_file "$script" '#!/usr/bin/env bash
set -Eeuo pipefail

if pgrep -x gammastep >/dev/null; then
  pkill -x gammastep
  notify-send "Gammastep" "Desactivado" 2>/dev/null || true
  exit 0
fi

nohup gammastep -O 4500 -b 0.90:0.90 >/tmp/gammastep-90.log 2>&1 &
notify-send "Gammastep" "Activado al 90%" 2>/dev/null || true'

  write_file "$desktop" "[Desktop Entry]
Type=Application
Name=Gammastep 90
Comment=Activar o desactivar filtro de pantalla al 90%
Exec=$script
Terminal=false
Categories=Utility;"

  run chmod 0755 "$script" "$desktop"
  run chown -R "$TARGET_USER:$TARGET_USER" "$home/.local" "$home/Desktop"
}

install_omv() {
  local server share smb_user smb_domain mount_point creds home bookmark_file bookmark_line
  read -r -p "Servidor OMV (IP o DNS): " server
  read -r -p "Share SMB: " share
  read -r -p "Usuario SMB: " smb_user
  read -r -p "Dominio SMB [WORKGROUP]: " smb_domain
  smb_domain="${smb_domain:-WORKGROUP}"
  [[ "$server" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "Servidor OMV inválido."
  [[ "$share" =~ ^[A-Za-z0-9._-]+$ ]] || fail "Share inválido."

  section "Confirmación OMV"
  printf '  Servidor: %s\n  Share: %s\n  Usuario: %s\n  Dominio: %s\n' \
    "$server" "$share" "$smb_user" "$smb_domain"
  confirm "¿Crear el montaje persistente y modificar /etc/fstab?" "n" ||
    fail "Configuración OMV cancelada."

  apt_install cifs-utils smbclient
  if [[ "$INSTALL_MODE" == "gui" ]]; then
    apt_install gvfs-backends gvfs-fuse
  fi
  mount_point="/mnt/omv/$share"
  creds="/etc/samba/credentials/omv-${share,,}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: configurar //$server/$share en $mount_point"
    return
  fi

  local smb_pass
  read -r -s -p "Contraseña SMB: " smb_pass
  printf '\n'
  install -d -m 0700 /etc/samba/credentials
  install -d -m 0750 -o "$TARGET_USER" -g "$TARGET_USER" "$mount_point"
  backup_file "$creds"
  printf 'username=%s\npassword=%s\ndomain=%s\n' "$smb_user" "$smb_pass" "$smb_domain" >"$creds"
  chmod 0600 "$creds"
  unset smb_pass

  backup_file /etc/fstab
  grep -Eq "[[:space:]]${mount_point}[[:space:]]+cifs[[:space:]]" /etc/fstab ||
    printf '//%s/%s %s cifs credentials=%s,uid=%s,gid=%s,vers=3.0,_netdev,nofail,x-systemd.automount 0 0\n' \
      "$server" "$share" "$mount_point" "$creds" \
      "$(id -u "$TARGET_USER")" "$(id -g "$TARGET_USER")" >>/etc/fstab
  run systemctl daemon-reload

  if [[ "$INSTALL_MODE" == "gui" ]]; then
    home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    [[ -n "$home" ]] || fail "No se encontró HOME para $TARGET_USER."
    bookmark_file="$home/.config/gtk-3.0/bookmarks"
    bookmark_line="file://${mount_point} OMV-${share}"
    install -d -m 0755 -o "$TARGET_USER" -g "$TARGET_USER" "$(dirname "$bookmark_file")"
    if [[ -e "$bookmark_file" ]]; then
      backup_file "$bookmark_file"
    else
      touch "$bookmark_file"
    fi
    grep -vF "file://${mount_point}" "$bookmark_file" >"${bookmark_file}.tmp" || true
    printf '%s\n' "$bookmark_line" >>"${bookmark_file}.tmp"
    mv "${bookmark_file}.tmp" "$bookmark_file"
    chown "$TARGET_USER:$TARGET_USER" "$bookmark_file"
  fi
}

install_rdp() {
  [[ "$INSTALL_MODE" == "gui" ]] || fail "RDP requiere instalación GUI."
  local source
  source="$(choose_firewall_source "RDP")"
  apt_install xrdp xorgxrdp
  prepare_remote_firewall
  local session="startlxqt"
  [[ "$DESKTOP" == "xfce" ]] && session="startxfce4"
  local home
  if [[ "$DRY_RUN" -eq 1 ]]; then
    home="/home/$TARGET_USER"
  else
    home="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  fi
  write_file "$home/.xsession" "$session"
  run chown "$TARGET_USER:$TARGET_USER" "$home/.xsession"
  run systemctl enable --now xrdp
  if [[ "$source" == "any" ]]; then
    run ufw limit 3389/tcp
  else
    run ufw limit from "$source" to any port 3389 proto tcp comment "RDP restringido"
  fi
  run ufw --force enable
}

install_clamav() {
  apt_install clamav clamav-freshclam
  if [[ "$PROFILE" != "baja" ]]; then
    apt_install clamav-daemon
    run systemctl enable --now clamav-freshclam clamav-daemon
  else
    info "Perfil baja: ClamAV queda disponible bajo demanda, sin daemon."
  fi
}

install_rkhunter() { apt_install rkhunter; }

install_wazuh() {
  local manager version
  read -r -p "Wazuh Manager (IP o DNS): " manager
  read -r -p "Versión del agente (ej. 4.14.5): " version
  [[ "$manager" =~ ^[A-Za-z0-9._:-]+$ ]] || fail "Manager inválido."
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Versión inválida."
  printf '  Manager: %s\n  Versión: %s\n' "$manager" "$version"
  confirm "¿Instalar y habilitar el agente Wazuh?" "n" ||
    fail "Instalación Wazuh cancelada."
  run env ARCH="${ARCH:-amd64}" bash "$ROOT_DIR/scripts/security/wazuh-agent.sh" \
    --manager "$manager" --version "$version"
}

run_maintenance() {
  local selected=0

  if confirm "¿Actualizar índices y paquetes instalados?" "s"; then
    run apt-get update
    run env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    selected=1
  fi
  if confirm "¿Limpiar la caché de paquetes descargados?" "s"; then
    run apt-get clean
    selected=1
  fi
  if confirm "¿Revisar paquetes candidatos a autoremove?" "n"; then
    run apt-get -s autoremove
    if confirm "¿Aplicar la eliminación mostrada?" "n"; then
      run apt-get autoremove -y
      selected=1
    fi
  fi
  [[ "$selected" -eq 1 ]] || fail "No se seleccionaron tareas de mantenimiento."
}

fix_rtc() {
  local current_timezone timezone
  current_timezone="$(timedatectl show --property=Timezone --value 2>/dev/null || printf 'UTC')"
  read -r -p "Zona horaria [$current_timezone]: " timezone
  timezone="${timezone:-$current_timezone}"
  timedatectl list-timezones | grep -Fxq "$timezone" ||
    fail "Zona horaria inválida: $timezone"
  confirm "¿Configurar zona $timezone, RTC en UTC y NTP activo?" "s" ||
    fail "Configuración horaria cancelada."
  run timedatectl set-timezone "$timezone"
  run timedatectl set-local-rtc 0 --adjust-system-clock
  run timedatectl set-ntp true
}

IFS=',' read -r -a extras <<<"$EXTRA_LIST"
for extra in "${extras[@]}"; do
  section "Extra: $extra"
  case "$extra" in
    ssh) install_ssh ;;
    bluetooth) install_bluetooth ;;
    flatpak) install_flatpak ;;
    apps) install_apps ;;
    zsh) install_zsh ;;
    fonts) install_fonts ;;
    gammastep) install_gammastep ;;
    omv) install_omv ;;
    rdp) install_rdp ;;
    clamav) install_clamav ;;
    rkhunter) install_rkhunter ;;
    wazuh) install_wazuh ;;
    maintenance) run_maintenance ;;
    rtc) fix_rtc ;;
    *) fail "Extra no soportado: $extra" ;;
  esac
done
