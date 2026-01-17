#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Uso: sudo ./rkhunter_check.sh"
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: ejecutá con sudo." >&2
  exit 1
fi

rkhunter --update
rkhunter --check
