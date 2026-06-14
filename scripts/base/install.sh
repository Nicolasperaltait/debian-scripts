#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly ROOT_DIR
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/config/packages.conf"
init_ui

run apt-get update
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
  read -r -a cli <<<"$CLI_PACKAGES"
  apt_install "${cli[@]}"
else
  info "Herramientas CLI adicionales omitidas por decisión del usuario."
fi
