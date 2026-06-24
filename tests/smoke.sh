#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ROOT_DIR

run_case() {
  local mode="$1"
  local desktop="$2"
  local profile="$3"
  local user="$4"
  local output log_dir session_log report_file answers

  output="$(mktemp)"
  log_dir="$(mktemp -d)"
  answers=$'1\n192.0.2.10/32\n'
  if [[ "$mode" == "gui" && "$desktop" == "xfce" && "$profile" == "baja" ]]; then
    answers=$'s\n1\n192.0.2.10/32\n'
  fi
  trap 'rm -f "$output"; rm -rf "$log_dir"' RETURN

  DEBIAN_SCRIPTS_TEST=1 \
    DEBIAN_SCRIPTS_LOG_DIR="$log_dir" \
    TEST_DEBIAN_VERSION=13 \
    TEST_RAM_MB=8192 \
    TEST_CPU_THREADS=4 \
    NO_COLOR=1 \
    bash "$ROOT_DIR/main.sh" \
      --dry-run \
      --user "$user" \
      --mode "$mode" \
      ${desktop:+--desktop "$desktop"} \
      --profile "$profile" \
      --extras ssh,zsh \
      --yes >"$output" 2>&1 <<<"$answers"

  grep -q "Instalación finalizada" "$output"
  grep -q "DRY-RUN" "$output"
  grep -q "Hardening reforzado" "$output"
  grep -q "99-debian-hardening.conf" "$output"
  grep -q "sshd-hardening.local" "$output"
  session_log="$(find "$log_dir" -maxdepth 1 -type f -name 'debian-scripts-dry-run.*.log' -print -quit)"
  [[ -n "$session_log" ]]
  grep -q "Instalación finalizada" "$session_log"
  grep -q "Hardening reforzado" "$session_log"
  grep -Fq "Log: $session_log" "$output"
  report_file="${session_log%.log}.md"
  [[ -f "$report_file" ]]
  grep -q '^# Informe de instalación Debian Scripts$' "$report_file"
  grep -Eq '^\| Seguridad +\| Hardening reforzado +\| Simulado +\|$' "$report_file"
  grep -Eq '^\| Seguridad +\| OpenSSH servidor +\| Simulado +\|$' "$report_file"
  grep -Eq '^\| Seguridad +\| Claves SSH autorizadas +\| Simulado +\|$' "$report_file"
  grep -Eq '^\| Personalización +\| Configuración Bash +\| Simulado +\|$' "$report_file"
  grep -Eq '^\| Personalización +\| Zsh y modificación de terminal +\| Simulado +\|$' \
    "$report_file"
  grep -Fq "Informe Markdown: $report_file" "$output"
  grep -q '| Categoría' "$output"
  ! grep -q "ufw --force reset" "$output"
  ! grep -q "password=" "$output"
}

for profile in baja media alta ultra; do
  run_case cli "" "$profile" usuario_cli
  run_case gui xfce "$profile" usuario_gui
  run_case gui lxqt "$profile" operador
done

if DEBIAN_SCRIPTS_TEST=1 NO_COLOR=1 bash "$ROOT_DIR/main.sh" \
  --dry-run --user 'Usuario Invalido' --mode cli --profile media --yes \
  >/dev/null 2>&1; then
  echo "ERROR: se aceptó un usuario inválido" >&2
  exit 1
fi

if DEBIAN_SCRIPTS_TEST=1 NO_COLOR=1 bash "$ROOT_DIR/main.sh" \
  --dry-run --user root --mode cli --profile media --yes \
  >/dev/null 2>&1; then
  echo "ERROR: se aceptó el usuario reservado 'root'" >&2
  exit 1
fi

if DEBIAN_SCRIPTS_TEST=1 NO_COLOR=1 bash "$ROOT_DIR/main.sh" \
  --dry-run --user operador --mode gui --profile baja --yes \
  >/dev/null 2>&1; then
  echo "ERROR: --yes aceptó GUI sin escritorio" >&2
  exit 1
fi

multi_user_output="$(mktemp)"
DEBIAN_SCRIPTS_TEST=1 \
  TEST_DEBIAN_VERSION=13 \
  TEST_RAM_MB=8192 \
  TEST_CPU_THREADS=4 \
  NO_COLOR=1 \
  bash "$ROOT_DIR/main.sh" \
    --dry-run \
    --user operador \
    --add-user auditor:standard \
    --add-user soporte:admin \
    --mode cli \
    --profile media \
    --yes >"$multi_user_output" 2>&1
grep -q 'DRY-RUN: crear usuario auditor con rol standard' "$multi_user_output"
grep -q 'DRY-RUN: crear usuario soporte con rol admin' "$multi_user_output"
grep -q 'auditor (standard)' "$multi_user_output"
grep -q 'soporte (admin)' "$multi_user_output"
rm -f "$multi_user_output"

if DEBIAN_SCRIPTS_TEST=1 NO_COLOR=1 bash "$ROOT_DIR/main.sh" \
  --dry-run --user operador --add-user operador:admin \
  --mode cli --profile media --yes >/dev/null 2>&1; then
  echo "ERROR: se aceptó un usuario adicional duplicado" >&2
  exit 1
fi

skip_upgrade_output="$(mktemp)"
DEBIAN_SCRIPTS_TEST=1 TEST_DEBIAN_VERSION=13 TEST_RAM_MB=8192 \
  TEST_CPU_THREADS=4 NO_COLOR=1 \
  bash "$ROOT_DIR/main.sh" --dry-run --user operador --mode cli \
  --profile media --skip-upgrade --yes >"$skip_upgrade_output" 2>&1
grep -q 'Actualización completa omitida por decisión del usuario.' "$skip_upgrade_output"
! grep -q 'apt-get upgrade -y' "$skip_upgrade_output"
rm -f "$skip_upgrade_output"

components_output="$(mktemp)"
DEBIAN_SCRIPTS_TEST=1 TEST_DEBIAN_VERSION=13 TEST_RAM_MB=32768 \
  TEST_CPU_THREADS=8 NO_COLOR=1 \
  bash "$ROOT_DIR/main.sh" --dry-run --user operador --mode gui \
  --desktop xfce --profile ultra --components tools,audit \
  --skip-upgrade --yes >"$components_output" 2>&1
grep -q 'Herramientas:  sí' "$components_output"
grep -q 'Instalar GUI:  no' "$components_output"
grep -q 'Optimización:  no' "$components_output"
grep -q 'Firewall:      no' "$components_output"
grep -q 'Hardening:     no' "$components_output"
grep -q 'Auditoría:     sí' "$components_output"
grep -q 'Auditoría final del sistema' "$components_output"
grep -Eq '^\| Seguridad +\| Hardening reforzado +\| Omitido +\|$' "$components_output"
! grep -q 'xfce4-goodies' "$components_output"
! grep -q 'systemctl enable --now preload' "$components_output"
! grep -q 'ufw default deny incoming' "$components_output"
rm -f "$components_output"

firewall_only_output="$(mktemp)"
DEBIAN_SCRIPTS_TEST=1 TEST_DEBIAN_VERSION=13 TEST_RAM_MB=16384 \
  TEST_CPU_THREADS=6 NO_COLOR=1 \
  bash "$ROOT_DIR/main.sh" --dry-run --user operador --mode cli \
  --profile alta --components firewall --skip-upgrade --yes \
  >"$firewall_only_output" 2>&1
grep -q 'Firewall:      sí' "$firewall_only_output"
grep -q 'Auto-updates:  no' "$firewall_only_output"
grep -q 'apt-get install -y --no-install-recommends ufw' "$firewall_only_output"
! grep -Eq 'apt-get install .*unattended-upgrades' "$firewall_only_output"
! grep -Eq 'apt-get install .*apparmor' "$firewall_only_output"
rm -f "$firewall_only_output"

skip_components_output="$(mktemp)"
DEBIAN_SCRIPTS_TEST=1 TEST_DEBIAN_VERSION=13 TEST_RAM_MB=32768 \
  TEST_CPU_THREADS=8 NO_COLOR=1 \
  bash "$ROOT_DIR/main.sh" --dry-run --user operador --mode gui \
  --desktop xfce --profile ultra --skip-components desktop,optimization \
  --skip-upgrade --yes >"$skip_components_output" 2>&1
grep -q 'Instalar GUI:  no' "$skip_components_output"
grep -q 'Optimización:  no' "$skip_components_output"
grep -q 'Firewall:      sí' "$skip_components_output"
grep -q 'Hardening:     sí' "$skip_components_output"
! grep -q 'xfce4-goodies' "$skip_components_output"
! grep -q 'systemctl enable --now preload' "$skip_components_output"
rm -f "$skip_components_output"

if DEBIAN_SCRIPTS_TEST=1 NO_COLOR=1 bash "$ROOT_DIR/main.sh" \
  --dry-run --user operador --mode cli --profile media \
  --components tools,desconocido --yes >/dev/null 2>&1; then
  echo "ERROR: se aceptó un componente principal inválido" >&2
  exit 1
fi

if DEBIAN_SCRIPTS_TEST=1 NO_COLOR=1 bash "$ROOT_DIR/main.sh" \
  --dry-run --user operador --mode cli --profile media \
  --components tools --skip-components audit --yes >/dev/null 2>&1; then
  echo "ERROR: se aceptaron --components y --skip-components juntos" >&2
  exit 1
fi

wizard_users_output="$(mktemp)"
printf 's\nauditor\n1\ns\nsoporte\n2\nn\n' |
  NO_COLOR=1 bash -c '
    source "'"$ROOT_DIR"'/lib/common.sh"
    source "'"$ROOT_DIR"'/lib/users.sh"
    source "'"$ROOT_DIR"'/lib/wizard.sh"
    init_ui
    TARGET_USER=operador
    ADDITIONAL_USERS=()
    wizard_additional_users
    printf "%s\n" "${ADDITIONAL_USERS[@]}"
  ' >"$wizard_users_output" 2>&1
grep -q '^auditor:standard$' "$wizard_users_output"
grep -q '^soporte:admin$' "$wizard_users_output"
rm -f "$wizard_users_output"

wizard_security_output="$(mktemp)"
printf 'n\ns\n' |
  NO_COLOR=1 bash -c '
    source "'"$ROOT_DIR"'/lib/common.sh"
    source "'"$ROOT_DIR"'/lib/wizard.sh"
    init_ui
    ENABLE_FIREWALL=1
    wizard_component ENABLE_FIREWALL "Firewall" "s" 1
    printf "ENABLE_FIREWALL=%s\n" "$ENABLE_FIREWALL"
  ' >"$wizard_security_output" 2>&1
grep -q '^ENABLE_FIREWALL=0$' "$wizard_security_output"
grep -q 'reduce la postura de seguridad' "$wizard_security_output"
rm -f "$wizard_security_output"

wizard_components_output="$(mktemp)"
# Inputs (GUI mode, no cli-tools prompt):
#   n=tools, n=desktop, n=optimization, n=firewall, s=confirm-skip-firewall,
#   ""=auto-updates(default s), n=hardening, n=confirm-skip-hardening,
#   ""=ssh(default s), ""=audit(default s)
printf 'n\nn\nn\nn\ns\n\nn\nn\n\n\n' |
  NO_COLOR=1 bash -c '
    source "'"$ROOT_DIR"'/lib/common.sh"
    source "'"$ROOT_DIR"'/lib/wizard.sh"
    init_ui
    INSTALL_MODE=gui
    DESKTOP=xfce
    PROFILE=ultra
    INSTALL_BASE_TOOLS=1
    INSTALL_CLI_TOOLS=0
    ENABLE_DESKTOP=1
    ENABLE_OPTIMIZATION=1
    ENABLE_FIREWALL=1
    ENABLE_AUTO_UPDATES=1
    ENABLE_HARDENING=1
    ENABLE_SSH=1
    ENABLE_AUDIT=0
    wizard_components
    printf "%s:%s:%s:%s:%s:%s:%s:%s:%s\n" \
      "$INSTALL_BASE_TOOLS" "$INSTALL_CLI_TOOLS" "$ENABLE_DESKTOP" \
      "$ENABLE_OPTIMIZATION" "$ENABLE_FIREWALL" "$ENABLE_AUTO_UPDATES" \
      "$ENABLE_HARDENING" "$ENABLE_SSH" "$ENABLE_AUDIT"
  ' >"$wizard_components_output" 2>&1
grep -q '^0:0:0:0:0:1:1:1:1$' "$wizard_components_output"
rm -f "$wizard_components_output"

critical_output="$(mktemp)"
critical_bin="$(mktemp -d)"
trap 'rm -f "$critical_output"; rm -rf "$critical_bin"' EXIT
printf '1\n192.0.2.10/32\n' |
  DRY_RUN=1 TARGET_USER=operador INSTALL_MODE=cli PROFILE=media NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/optional/install.sh" ssh >"$critical_output" 2>&1
grep -q 'ufw limit from 192.0.2.10/32 to any port 22 proto tcp' "$critical_output"
grep -q 'ufw --force enable' "$critical_output"
ssh_rule_line="$(grep -n 'ufw limit from 192.0.2.10/32 to any port 22 proto tcp' "$critical_output" | cut -d: -f1)"
default_deny_line="$(grep -n 'ufw default deny incoming' "$critical_output" | cut -d: -f1)"
((ssh_rule_line < default_deny_line))

printf '1\n192.0.2.0/24\n' |
  DRY_RUN=1 TARGET_USER=operador INSTALL_MODE=gui DESKTOP=lxqt PROFILE=media NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/optional/install.sh" rdp >"$critical_output" 2>&1
grep -q 'ufw limit from 192.0.2.0/24 to any port 3389 proto tcp' "$critical_output"
grep -q 'ufw --force enable' "$critical_output"
rdp_rule_line="$(grep -n 'ufw limit from 192.0.2.0/24 to any port 3389 proto tcp' "$critical_output" | cut -d: -f1)"
default_deny_line="$(grep -n 'ufw default deny incoming' "$critical_output" | cut -d: -f1)"
((rdp_rule_line < default_deny_line))

printf 'omv.example.test\ndatos\nusuario\nWORKGROUP\ns\n' |
  DRY_RUN=1 TARGET_USER=operador INSTALL_MODE=gui PROFILE=media NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/optional/install.sh" omv >"$critical_output" 2>&1
grep -q 'DRY-RUN: configurar //omv.example.test/datos' "$critical_output"

printf 'wazuh.example.test\n4.14.5\ns\n' |
  DRY_RUN=1 TARGET_USER=operador INSTALL_MODE=cli PROFILE=media ARCH=amd64 NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/optional/install.sh" wazuh >"$critical_output" 2>&1
grep -q -- '--manager wazuh.example.test --version 4.14.5' "$critical_output"

printf 's\ns\nn\n' |
  DRY_RUN=1 TARGET_USER=operador INSTALL_MODE=cli PROFILE=media NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/optional/install.sh" maintenance >"$critical_output" 2>&1
grep -q 'apt-get upgrade -y' "$critical_output"
grep -q 'apt-get clean' "$critical_output"
! grep -q 'apt-get autoremove -y' "$critical_output"

printf 's\nn\nn\nn\n' |
  DRY_RUN=1 TARGET_USER=operador INSTALL_MODE=gui PROFILE=media NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/optional/install.sh" apps >"$critical_output" 2>&1
grep -q 'flatpak install -y flathub org.videolan.VLC' "$critical_output"

cat >"$critical_bin/timedatectl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  show) printf 'UTC\n' ;;
  list-timezones) printf 'UTC\nAmerica/Argentina/Buenos_Aires\n' ;;
esac
EOF
chmod +x "$critical_bin/timedatectl"
printf '\ns\n' |
  PATH="$critical_bin:$PATH" DRY_RUN=1 TARGET_USER=operador \
  INSTALL_MODE=cli PROFILE=media NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/optional/install.sh" rtc >"$critical_output" 2>&1
grep -q 'timedatectl set-timezone UTC' "$critical_output"

rm -f "$critical_output"
rm -rf "$critical_bin"

ssh_baseline_output="$(mktemp)"
SSH_CONNECTION='192.0.2.25 50000 192.0.2.50 22' DRY_RUN=1 NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/security/baseline.sh" >"$ssh_baseline_output" 2>&1
grep -q 'ufw limit from 192.0.2.25 to any port 22 proto tcp' "$ssh_baseline_output"
! grep -q 'ufw limit OpenSSH' "$ssh_baseline_output"
rm -f "$ssh_baseline_output"

ssh_baseline_output="$(mktemp)"
ssh_baseline_bin="$(mktemp -d)"
cat >"$ssh_baseline_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "is-active" && "${3:-}" == "ssh" ]]
EOF
chmod +x "$ssh_baseline_bin/systemctl"
PATH="$ssh_baseline_bin:$PATH" FIREWALL_SSH_SOURCE='192.0.2.0/24' \
  DRY_RUN=1 NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/security/baseline.sh" >"$ssh_baseline_output" 2>&1
grep -q 'ufw limit from 192.0.2.0/24 to any port 22 proto tcp' "$ssh_baseline_output"
grep -q 'ufw --force enable' "$ssh_baseline_output"
ssh_rule_line="$(grep -n 'ufw limit from 192.0.2.0/24 to any port 22 proto tcp' "$ssh_baseline_output" | cut -d: -f1)"
default_deny_line="$(grep -n 'ufw default deny incoming' "$ssh_baseline_output" | cut -d: -f1)"
((ssh_rule_line < default_deny_line))

if PATH="$ssh_baseline_bin:$PATH" DRY_RUN=1 NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/security/baseline.sh" </dev/null \
  >"$ssh_baseline_output" 2>&1; then
  echo "ERROR: UFW se activó sin una regla SSH en modo no interactivo" >&2
  exit 1
fi
grep -q 'Se rechazó activar UFW sin una regla SSH' "$ssh_baseline_output"
! grep -q 'ufw --force enable' "$ssh_baseline_output"
rm -f "$ssh_baseline_output"
rm -rf "$ssh_baseline_bin"

for debian_version in 12 13; do
  c200_output="$(mktemp)"
  DEBIAN_SCRIPTS_TEST=1 \
    TEST_DEBIAN_VERSION="$debian_version" \
    TEST_RAM_MB=2048 \
    TEST_CPU_THREADS=2 \
    NO_COLOR=1 \
    bash "$ROOT_DIR/main.sh" \
      --dry-run \
      --user operador \
      --preset gui-low-resource \
      --mode cli \
      --profile ultra \
      --components tools,optimization,audit \
      --yes >"$c200_output" 2>&1

  grep -q "Preset:        gui-low-resource" "$c200_output"
  grep -q "Instalación:   cli" "$c200_output"
  grep -q "Escritorio:    ninguno" "$c200_output"
  grep -q "Perfil:        ultra" "$c200_output"
  grep -q "Las recomendaciones no reemplazan tus selecciones" "$c200_output"
  grep -q "systemctl enable --now preload" "$c200_output"
  grep -q "Auditoría final del sistema" "$c200_output"
  ! grep -q "lxqt-core" "$c200_output"
  ! grep -q "systemd-zram-generator" "$c200_output"
  if grep -q "disable --now bluetooth" "$c200_output"; then
    echo "ERROR: bajos recursos intenta deshabilitar Bluetooth" >&2
    exit 1
  fi
  if grep -q "disable --now avahi-daemon" "$c200_output"; then
    echo "ERROR: bajos recursos intenta deshabilitar Avahi" >&2
    exit 1
  fi
  if grep -q "disable --now cups" "$c200_output"; then
    echo "ERROR: bajos recursos intenta deshabilitar impresión" >&2
    exit 1
  fi
  rm -f "$c200_output"
done

c200_recommended_output="$(mktemp)"
DEBIAN_SCRIPTS_TEST=1 TEST_DEBIAN_VERSION=13 TEST_RAM_MB=2048 \
  TEST_CPU_THREADS=2 NO_COLOR=1 \
  bash "$ROOT_DIR/main.sh" --dry-run --user operador \
  --preset gui-low-resource --mode gui --desktop lxqt --profile baja \
  --components desktop,optimization,audit --extras gammastep --yes \
  >"$c200_recommended_output" 2>&1
grep -q 'lxqt-core' "$c200_recommended_output"
grep -q 'systemd-zram-generator' "$c200_recommended_output"
grep -q 'zram-generator.conf' "$c200_recommended_output"
grep -q 'gammastep-toggle-90' "$c200_recommended_output"
grep -q 'Auditoría final del sistema' "$c200_recommended_output"
rm -f "$c200_recommended_output"

for active_file in \
  scripts/maintenance/fix_time_rtc.sh \
  scripts/maintenance/system_maintenance.sh \
  scripts/security/clamav_scan.sh \
  scripts/security/rkhunter_check.sh \
  scripts/security/hardening.sh \
  scripts/security/wazuh-agent.sh; do
  [[ -f "$ROOT_DIR/$active_file" ]] || {
    echo "ERROR: falta archivo crítico activo: $active_file" >&2
    exit 1
  }
done

hardening_script="$ROOT_DIR/scripts/security/hardening.sh"
for forbidden_pattern in \
  'ufw --force reset' \
  'net.ipv4.ip_forward[[:space:]]*=' \
  'kernel.unprivileged_userns_clone[[:space:]]*=' \
  '^[[:space:]]*PasswordAuthentication[[:space:]]+no'; do
  if grep -Eq "$forbidden_pattern" "$hardening_script"; then
    echo "ERROR: hardening contiene ajuste prohibido: $forbidden_pattern" >&2
    exit 1
  fi
done

if grep -Rqs '\.bak\.\$(date' "$ROOT_DIR/lib" "$ROOT_DIR/scripts"; then
  echo "ERROR: se detectaron backups adyacentes a archivos de configuración" >&2
  exit 1
fi
grep -q '/var/backups/debian-scripts/' "$ROOT_DIR/lib/common.sh"
grep -q 'fail "La auditoría detectó unidades systemd fallidas."' \
  "$ROOT_DIR/scripts/audit/system-health.sh"

bash "$ROOT_DIR/tests/public-safety.sh"

audit_bin="$(mktemp -d)"
audit_output="$(mktemp)"
trap 'rm -rf "$audit_bin"; rm -f "$audit_output"' EXIT
for command_name in free swapon zramctl lsblk systemctl nmcli ss; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$audit_bin/$command_name"
  chmod +x "$audit_bin/$command_name"
done
PATH="$audit_bin:$PATH" NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/audit/gui-low-resource.sh" >"$audit_output" 2>&1
grep -q '\[ OK \] No hay unidades systemd fallidas.' "$audit_output"

wazuh_output="$(DRY_RUN=1 bash "$ROOT_DIR/scripts/security/wazuh-agent.sh" \
  --manager wazuh.example.internal --version 4.14.5)"
grep -q "DRY-RUN: descargar" <<<"$wazuh_output"
grep -q "manager=wazuh.example.internal" <<<"$wazuh_output"

if grep -Rqs '10\.10\.30\.10' \
  "$ROOT_DIR/scripts" "$ROOT_DIR/docs" "$ROOT_DIR/README.md"; then
  echo "ERROR: se detectó la IP privada Wazuh en contenido publicable" >&2
  exit 1
fi

# Gap 1: DRY-RUN con SSH_PUBKEY menciona authorized_keys
ssh_pubkey_output="$(mktemp)"
SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeySmoke test@example.com" \
  ENABLE_SSH=1 ENABLE_FIREWALL=0 ENABLE_AUTO_UPDATES=0 \
  DRY_RUN=1 TARGET_USER=operador NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/security/baseline.sh" >"$ssh_pubkey_output" 2>&1
grep -q 'authorized_keys' "$ssh_pubkey_output"
rm -f "$ssh_pubkey_output"

# Gap 1: DRY-RUN sin SSH_PUBKEY también menciona authorized_keys
ssh_nokey_output="$(mktemp)"
ENABLE_SSH=1 ENABLE_FIREWALL=0 ENABLE_AUTO_UPDATES=0 \
  DRY_RUN=1 TARGET_USER=operador NO_COLOR=1 \
  bash "$ROOT_DIR/scripts/security/baseline.sh" >"$ssh_nokey_output" 2>&1
grep -q 'authorized_keys' "$ssh_nokey_output"
rm -f "$ssh_nokey_output"

# Gap 2: Idempotencia del awk-guard de personalizacion_bash.sh
idem_start='# >>> DEBIAN BASH CUSTOM >>>'
idem_end='# <<< DEBIAN BASH CUSTOM <<<'
idem_bashrc="$(mktemp)"
# Simular que el bloque ya existe en .bashrc (primera ejecución hipotética)
printf '# contenido previo\n%s\nalias test=true\n%s\n' "$idem_start" "$idem_end" >"$idem_bashrc"
# Aplicar el filtro awk exactamente como lo hace personalizacion_bash.sh
idem_tmp="$(mktemp)"
awk -v start="$idem_start" -v end="$idem_end" '
  $0 == start {skip=1; next}
  $0 == end   {skip=0; next}
  !skip       {print}
' "$idem_bashrc" >"$idem_tmp"
# Agregar el bloque de nuevo (simular segunda escritura)
printf '%s\nalias test=true\n%s\n' "$idem_start" "$idem_end" >>"$idem_tmp"
# Contenido anterior debe estar preservado y el bloque aparecer exactamente una vez
grep -q '# contenido previo' "$idem_tmp"
idem_count="$(grep -c "$idem_start" "$idem_tmp")"
[[ "$idem_count" -eq 1 ]] || {
  printf 'ERROR: awk-guard falló — bloque duplicado (%s veces)\n' "$idem_count" >&2
  rm -f "$idem_bashrc" "$idem_tmp"; exit 1
}
rm -f "$idem_bashrc" "$idem_tmp"

echo "Smoke tests: OK"
