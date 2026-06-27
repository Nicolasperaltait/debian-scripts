#!/usr/bin/env bash

DEBIAN_VERSION=""
DEBIAN_CODENAME=""
ARCH=""
RAM_MB=0
CPU_THREADS=0
DISK_FREE_GB=0
IS_VM=0
VIRTUALIZATION_TYPE="baremetal"
NVIDIA_PRESENT=0
NVIDIA_MODEL=""

set_virtualization_type() {
  local value="${1:-auto}"

  case "$value" in
    auto) return 0 ;;
    baremetal)
      IS_VM=0
      VIRTUALIZATION_TYPE="baremetal"
      ;;
    vm|virtual)
      IS_VM=1
      VIRTUALIZATION_TYPE="virtual"
      ;;
    vmware)
      IS_VM=1
      VIRTUALIZATION_TYPE="vmware"
      ;;
    *)
      fail "Virtualización inválida: $value"
      ;;
  esac
}

detect_virtualization() {
  local detected product sys_vendor

  if [[ "${DEBIAN_SCRIPTS_TEST:-0}" == "1" ]]; then
    if [[ "${TEST_IS_VM:-0}" == "1" ]]; then
      IS_VM=1
      VIRTUALIZATION_TYPE="${TEST_VIRTUALIZATION_TYPE:-virtual}"
    else
      IS_VM=0
      VIRTUALIZATION_TYPE="baremetal"
    fi
    return
  fi

  if command -v systemd-detect-virt >/dev/null 2>&1 &&
    systemd-detect-virt --vm --quiet; then
    detected="$(systemd-detect-virt --vm 2>/dev/null || true)"
    IS_VM=1
    VIRTUALIZATION_TYPE="${detected:-virtual}"
    return
  fi

  product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
  sys_vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)"
  case "${product} ${sys_vendor}" in
    *VMware*|*VMWARE*)
      IS_VM=1
      VIRTUALIZATION_TYPE="vmware"
      ;;
    *VirtualBox*|*KVM*|*QEMU*|*Hyper-V*)
      IS_VM=1
      VIRTUALIZATION_TYPE="virtual"
      ;;
    *)
      IS_VM=0
      VIRTUALIZATION_TYPE="baremetal"
      ;;
  esac
}

detect_nvidia() {
  local line

  if [[ "${DEBIAN_SCRIPTS_TEST:-0}" == "1" ]]; then
    NVIDIA_PRESENT="${TEST_NVIDIA_PRESENT:-0}"
    NVIDIA_MODEL="${TEST_NVIDIA_MODEL:-NVIDIA test adapter}"
    [[ "$NVIDIA_PRESENT" -eq 1 ]] || NVIDIA_MODEL=""
    return
  fi

  line=""
  if command -v lspci >/dev/null 2>&1; then
    line="$(lspci -nn 2>/dev/null | grep -Ei 'VGA|3D|Display' | grep -i 'NVIDIA' | head -1 || true)"
  fi

  if [[ -n "$line" ]]; then
    NVIDIA_PRESENT=1
    NVIDIA_MODEL="$line"
  else
    NVIDIA_PRESENT=0
    NVIDIA_MODEL=""
  fi
}

detect_system() {
  if [[ "${DEBIAN_SCRIPTS_TEST:-0}" == "1" ]]; then
    DEBIAN_VERSION="${TEST_DEBIAN_VERSION:-13}"
    DEBIAN_CODENAME="${TEST_DEBIAN_CODENAME:-trixie}"
    ARCH="${TEST_ARCH:-amd64}"
    RAM_MB="${TEST_RAM_MB:-8192}"
    CPU_THREADS="${TEST_CPU_THREADS:-4}"
    DISK_FREE_GB="${TEST_DISK_FREE_GB:-40}"
    detect_virtualization
    detect_nvidia
    return
  fi

  [[ -r /etc/os-release ]] || fail "No se encontró /etc/os-release."
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "debian" ]] || fail "Sistema no soportado: ${ID:-desconocido}."

  DEBIAN_VERSION="${VERSION_ID%%.*}"
  DEBIAN_CODENAME="${VERSION_CODENAME:-S/D}"
  ARCH="$(dpkg --print-architecture)"
  RAM_MB="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
  CPU_THREADS="$(getconf _NPROCESSORS_ONLN)"
  DISK_FREE_GB="$(df -Pk / | awk 'NR==2 {printf "%d", $4/1024/1024}')"
  detect_virtualization
  detect_nvidia
}

check_platform() {
  [[ "$DEBIAN_VERSION" =~ ^(12|13)$ ]] ||
    fail "Solo se soportan Debian 12 y 13. Detectado: $DEBIAN_VERSION."
  if [[ "${DEBIAN_SCRIPTS_TEST:-0}" == "1" ]]; then
    ((DISK_FREE_GB >= 4)) || fail "Se requieren al menos 4 GB libres."
    return
  fi
  command -v apt-get >/dev/null || fail "apt-get no está disponible."
  command -v dpkg >/dev/null || fail "dpkg no está disponible."
  ((DISK_FREE_GB >= 4)) || fail "Se requieren al menos 4 GB libres."
}

check_network() {
  if [[ "$DRY_RUN" -eq 1 || "${DEBIAN_SCRIPTS_TEST:-0}" == "1" ]]; then
    return
  fi
  getent ahosts deb.debian.org >/dev/null 2>&1 ||
    fail "No se pudo resolver deb.debian.org. Revisá red y DNS."
}

require_root_or_reexec() {
  if [[ "${DEBIAN_SCRIPTS_TEST:-0}" == "1" || "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  if [[ "$EUID" -ne 0 ]]; then
    command -v sudo >/dev/null || fail "Ejecutá como root; sudo no está instalado."
    info "Solicitando privilegios administrativos..."
    exec sudo -E bash "$ROOT_DIR/main.sh" "$@"
  fi
}

recommend_profile() {
  if ((RAM_MB < 8192 || CPU_THREADS <= 2)); then
    printf 'baja'
  elif ((RAM_MB < 16384 || CPU_THREADS < 6)); then
    printf 'media'
  elif ((RAM_MB < 32768 || CPU_THREADS < 8)); then
    printf 'alta'
  else
    printf 'ultra'
  fi
}

recommend_desktop() {
  if ((RAM_MB < 4096)); then
    printf 'lxqt'
  else
    printf 'xfce'
  fi
}

show_system_summary() {
  section "Sistema detectado"
  printf '  Debian:    %s (%s)\n' "$DEBIAN_VERSION" "$DEBIAN_CODENAME"
  printf '  Arquitectura: %s\n' "$ARCH"
  printf '  RAM:       %s MB\n' "$RAM_MB"
  printf '  CPU:       %s hilos\n' "$CPU_THREADS"
  printf '  Disco:     %s GB libres\n' "$DISK_FREE_GB"
  printf '  Entorno:   %s\n' "$([[ "$IS_VM" -eq 1 ]] && printf 'VM (%s)' "$VIRTUALIZATION_TYPE" || printf 'bare metal')"
  if [[ "$NVIDIA_PRESENT" -eq 1 ]]; then
    printf '  GPU:       %s\n' "$NVIDIA_MODEL"
  fi
}
