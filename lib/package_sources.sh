#!/usr/bin/env bash

csv_contains() {
  local csv="${1:-}" needle="${2:-}" item
  local -a csv_items=()
  [[ -n "$csv" && -n "$needle" ]] || return 1
  IFS=',' read -r -a csv_items <<<"$csv"
  for item in "${csv_items[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

selected_apps_need_vendor_sources() {
  csv_contains "${GUI_APP_SELECTIONS:-}" "chrome" ||
    csv_contains "${GUI_APP_SELECTIONS:-}" "code" ||
    csv_contains "${GUI_APP_SELECTIONS:-}" "librewolf"
}

selected_apps_need_flatpak() {
  csv_contains "${GUI_APP_SELECTIONS:-}" "obsidian" ||
    csv_contains "${GUI_APP_SELECTIONS:-}" "vlc" ||
    csv_contains "${GUI_APP_SELECTIONS:-}" "bitwarden" ||
    csv_contains "${GUI_APP_SELECTIONS:-}" "remmina"
}

debian_sources_main_present() {
  local file
  for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -e "$file" ]] || continue
    grep -Eq '(^|[[:space:]])main($|[[:space:]])' "$file" && return 0
  done
  return 1
}

debian_sources_nonfree_present() {
  local file
  for file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    [[ -e "$file" ]] || continue
    grep -Eq '(^|[[:space:]])non-free($|[[:space:]])|(^|[[:space:]])non-free-firmware($|[[:space:]])' \
      "$file" && return 0
  done
  return 1
}

default_debian_sources_content() {
  cat <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${DEBIAN_CODENAME} ${DEBIAN_CODENAME}-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${DEBIAN_CODENAME}-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
}

default_nonfree_sources_content() {
  cat <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: ${DEBIAN_CODENAME} ${DEBIAN_CODENAME}-updates
Components: contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: ${DEBIAN_CODENAME}-security
Components: contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
}

normalize_debian_main_sources() {
  local target="/etc/apt/sources.list.d/debian.sources"
  if debian_sources_main_present; then
    return 0
  fi
  info "No se detectaron fuentes Debian con 'main'; se crearán fuentes mínimas."
  write_file "$target" "$(default_debian_sources_content)"
}

ensure_debian_nonfree_sources() {
  local target="/etc/apt/sources.list.d/debian-scripts-nonfree.sources"
  if debian_sources_nonfree_present; then
    return 0
  fi
  write_file "$target" "$(default_nonfree_sources_content)"
}

install_repo_prerequisites() {
  run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg apt-transport-https
}

download_keyring() {
  local url="$1" target="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    info "DRY-RUN: descargar clave $url -> $target"
    return 0
  fi

  backup_file "$target"
  install -d -m 0755 /etc/apt/keyrings
  log_line "WRITE: $target (keyring)"
  curl -fsSL "$url" | gpg --dearmor >"$target"
  chmod 0644 "$target"
}

ensure_google_chrome_repo() {
  local keyring="/etc/apt/keyrings/google-chrome.gpg"
  local repo_file="/etc/apt/sources.list.d/google-chrome.list"

  download_keyring "https://dl.google.com/linux/linux_signing_key.pub" "$keyring"
  write_file "$repo_file" \
    "deb [arch=amd64 signed-by=$keyring] https://dl.google.com/linux/chrome/deb/ stable main"
}

ensure_vscode_repo() {
  local keyring="/etc/apt/keyrings/packages.microsoft.gpg"
  local repo_file="/etc/apt/sources.list.d/vscode.list"

  download_keyring "https://packages.microsoft.com/keys/microsoft.asc" "$keyring"
  write_file "$repo_file" \
    "deb [arch=amd64,arm64,armhf signed-by=$keyring] https://packages.microsoft.com/repos/code stable main"
}

ensure_librewolf_repo() {
  apt_install extrepo
  run extrepo enable librewolf
  run extrepo update librewolf
}

ensure_vendor_app_sources() {
  selected_apps_need_vendor_sources || return 1
  install_repo_prerequisites

  if csv_contains "${GUI_APP_SELECTIONS:-}" "chrome"; then
    ensure_google_chrome_repo
  fi
  if csv_contains "${GUI_APP_SELECTIONS:-}" "code"; then
    ensure_vscode_repo
  fi
  if csv_contains "${GUI_APP_SELECTIONS:-}" "librewolf"; then
    ensure_librewolf_repo
  fi

  return 0
}
