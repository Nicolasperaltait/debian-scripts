#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/package_sources.sh"
source "$ROOT_DIR/config/packages.conf"
init_ui

normalize_debian_main_sources
if [[ "${NVIDIA_PRESENT:-0}" -eq 1 && "${NVIDIA_POLICY:-}" == "install" ]]; then
  ensure_debian_nonfree_sources
fi

run apt-get update
if selected_apps_need_vendor_sources; then
  ensure_vendor_app_sources
  run apt-get update
fi
if [[ "${UPGRADE_SYSTEM:-1}" -eq 1 ]]; then
  run env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
else
  info "Actualización completa omitida por decisión del usuario."
fi

if [[ "${INSTALL_BASE_TOOLS:-1}" -eq 1 ]]; then
  read -r -a base <<<"$BASE_PACKAGES"
  apt_install "${base[@]}"
else
  info "Herramientas base omitidas por decisión del usuario."
fi

if [[ "${INSTALL_CLI_TOOLS:-0}" -eq 1 ]]; then
  case "${DEBIAN_VERSION:-}" in
    12) read -r -a cli <<<"$CLI_PACKAGES_DEBIAN_12" ;;
    13) read -r -a cli <<<"$CLI_PACKAGES_DEBIAN_13" ;;
    *) read -r -a cli <<<"$CLI_PACKAGES" ;;
  esac
  apt_install "${cli[@]}"
else
  info "Herramientas CLI adicionales omitidas por decisión del usuario."
fi

if [[ "${NVIDIA_PRESENT:-0}" -eq 1 && "${NVIDIA_POLICY:-}" == "install" ]]; then
  if [[ "${INSTALL_MODE:-cli}" == "gui" ]]; then
    read -r -a nvidia_packages <<<"$NVIDIA_GUI_PACKAGES"
  else
    read -r -a nvidia_packages <<<"$NVIDIA_BASE_PACKAGES"
  fi
  apt_install "${nvidia_packages[@]}"
fi
