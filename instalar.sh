#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="https://github.com/Nicolasperaltait/debian-scripts.git"
TARGET_DIR="debian-scripts"

sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends git

if [[ ! -d "$TARGET_DIR/.git" ]]; then
  git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"

echo
echo "=== Debian Scripts Bootstrapper ==="
echo "El wizard te guiará por todas las opciones."
echo "SSH quedará habilitado por defecto."
echo

sudo bash main.sh
