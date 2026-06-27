#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR

cd "$ROOT_DIR"
sudo bash main.sh --dry-run \
  --user operador \
  --preset gui-low-resource \
  --mode gui \
  --desktop lxqt \
  --profile baja \
  --components tools,desktop,optimization,firewall,auto-updates,hardening,audit \
  --extras ssh,zsh,clamav,rkhunter \
  --nvidia audit \
  --yes
