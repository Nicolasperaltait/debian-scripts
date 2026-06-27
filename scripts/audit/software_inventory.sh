#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
software_inventory.sh - inventario read-only de paquetes instalados

Uso:
  ./software_inventory.sh [--desktop xfce|lxqt|both]

Opciones:
  --desktop   Filtra y destaca candidatas de debloat para un escritorio.
              Valores: xfce, lxqt, both. Default: both.
  -h, --help  Muestra esta ayuda.

Salida:
  Ordena los paquetes instalados desde prioridad Debian más crítica a menos
  crítica: essential, required, important, standard, optional, extra y
  unknown.

Notas:
  - No modifica el sistema.
  - Requiere dpkg-query.
EOF
}

desktop="both"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --desktop)
      desktop="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Opción desconocida: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$desktop" in
  xfce|lxqt|both) ;;
  *)
    printf 'Valor inválido para --desktop: %s\n' "$desktop" >&2
    exit 2
    ;;
esac

priority_rank() {
  case "${1,,}" in
    essential) printf '0' ;;
    required) printf '1' ;;
    important) printf '2' ;;
    standard) printf '3' ;;
    optional) printf '4' ;;
    extra) printf '5' ;;
    *) printf '6' ;;
  esac
}

desktop_hint() {
  local package="$1"

  case "$desktop" in
    xfce)
      case "$package" in
        libreoffice*|thunderbird*|rhythmbox*|shotwell*|simple-scan|cheese|gnome-games*|aisleriot|four-in-a-row|gnome-mahjongg|gnome-mines|gnome-sudoku|tali|hitori|gnome-tetravex|gnome-robots|gnome-chess|xfce4-notes-plugin|mousepad|xfce4-terminal|xfce4-goodies|vim|vim-*|neovim)
          printf 'candidata XFCE'
          ;;
      esac
      ;;
    lxqt)
      case "$package" in
        libreoffice*|thunderbird*|rhythmbox*|shotwell*|simple-scan|cheese|gnome-games*|aisleriot|four-in-a-row|gnome-mahjongg|gnome-mines|gnome-sudoku|tali|hitori|gnome-tetravex|gnome-robots|gnome-chess|lxqt*|qterminal|featherpad|screengrab|qalculate-gtk|vim|vim-*|neovim)
          printf 'candidata LXQt'
          ;;
      esac
      ;;
    both)
      case "$package" in
        libreoffice*|thunderbird*|rhythmbox*|shotwell*|simple-scan|cheese|gnome-games*|aisleriot|four-in-a-row|gnome-mahjongg|gnome-mines|gnome-sudoku|tali|hitori|gnome-tetravex|gnome-robots|gnome-chess|vim|vim-*|neovim)
          printf 'candidata escritorio'
          ;;
      esac
      ;;
  esac
}

printf '%-4s  %-12s  %-34s  %-18s  %-12s  %s\n' "Rank" "Priority" "Package" "Section" "Essential" "Nota"
printf '%-4s  %-12s  %-34s  %-18s  %-12s  %s\n' "----" "--------" "------------------" "--------" "---------" "----"

dpkg-query -W -f='${Package}\t${Essential}\t${Priority}\t${Section}\n' |
  while IFS=$'\t' read -r package essential priority section; do
    [[ -n "$package" ]] || continue
    priority="${priority:-unknown}"
    section="${section:-unknown}"
    essential="${essential:-no}"

    rank="$(priority_rank "$priority")"
    note=""
    if [[ "$essential" == "yes" ]]; then
      note="no tocar"
    else
      note="$(desktop_hint "$package" || true)"
      if [[ -z "$note" ]]; then
        case "${priority,,}" in
          optional|extra) note="revisar" ;;
        esac
      fi
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$rank" "$priority" "$package" "$section" "$essential" "${note:-}"
  done |
  sort -t$'\t' -k1,1n -k2,2 -k3,3 |
  awk -F'\t' '{ printf "%-4s  %-12s  %-34s  %-18s  %-12s  %s\n", $1, $2, $3, $4, $5, $6 }'
