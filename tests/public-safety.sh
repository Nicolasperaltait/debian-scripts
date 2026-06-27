#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR
cd "$ROOT_DIR"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

private_names='(nico''las|admin''lab)'
if git grep -I -n -i -E \
  -e "(^|[^[:alnum:]_])${private_names}([^[:alnum:]_]|$)" -- .; then
  fail "se detectaron nombres personales en archivos públicos"
fi

if git grep -I -n -E \
  -e '10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' \
  -e '192\.168\.[0-9]{1,3}\.[0-9]{1,3}' \
  -e '172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}' -- .; then
  fail "se detectaron direcciones RFC1918 en archivos públicos"
fi

if git grep -I -n -E \
  -e '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----' \
  -e 'ghp_[A-Za-z0-9]{30,}' \
  -e 'github_pat_[A-Za-z0-9_]{30,}' \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'AIza[0-9A-Za-z_-]{30,}' \
  -e 'https://hooks\.slack\.com/services/' -- .; then
  fail "se detectó un patrón compatible con secretos"
fi

if [[ -n "$(git ls-files legacy-source)" ]]; then
  fail "legacy-source no debe contener archivos versionados"
fi

if ! git check-ignore -q legacy-source/archivo-local; then
  fail "legacy-source debe permanecer excluido por .gitignore"
fi

sanitized_matches="$(git grep -I -n -i -E -e 'c200|c240|lenovo c200' -- . || true)"
sanitized_matches="$(printf '%s\n' "$sanitized_matches" | grep -v '^tests/public-safety.sh:' || true)"
if [[ -n "$sanitized_matches" ]]; then
  printf '%s\n' "$sanitized_matches"
  fail "se detectaron referencias no sanitizadas de hardware específico"
fi

echo "Public safety checks: OK"
