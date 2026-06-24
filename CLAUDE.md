# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Authority and startup (governance)

[AGENTS.md](./AGENTS.md) is the authority of this repository. This file does not create independent rules nor relax those in AGENTS.md; it adds the detailed command/architecture reference for Claude. Startup order for a new session:

1. [README.md](./README.md) — locate the task and the real path.
2. [AGENTS.md](./AGENTS.md) — mandatory rules and non-negotiable security constraints.
3. Local `AGENTS.md` of the relevant module, if any.
4. This file and the area-specific docs under [docs/](./docs/).
5. `git status --short` before any change.

On conflict, AGENTS.md wins. See also [LLM.md](./LLM.md) for non-Claude agents.

## What this repo is

Modular Bash bootstrap for Debian 12/13. A single entry point (`main.sh`) orchestrates detection, a wizard or CLI flags, and runs modules in sequence. Targets are real Debian machines; scripts must run as root via `sudo bash main.sh`.

## Commands

**Validate syntax and run tests (CI equivalent):**
```bash
find . -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n
find . -type f -name '*.sh' -print0 | xargs -0 shellcheck
bash tests/public-safety.sh
bash tests/smoke.sh
```

**Dry-run the full wizard non-interactively:**
```bash
sudo bash main.sh --dry-run \
  --user operador --preset gui-low-resource \
  --mode gui --desktop lxqt --profile baja \
  --components tools,desktop,optimization,firewall,auto-updates,hardening,audit \
  --extras ssh,zsh,clamav,rkhunter --yes
```

**Interactive wizard:**
```bash
sudo bash main.sh
```

## Architecture

```
main.sh                   # Entry point: parses args, runs wizard, calls run_module()
lib/
  common.sh               # UI helpers (color, confirm, choose, progress_bar), logging, report API
  detection.sh            # detect_system(), recommend_profile(), check_network()
  users.sh                # ensure_target_user(), validate_username()
  wizard.sh               # All interactive prompts (wizard_user, wizard_mode, etc.)
scripts/
  base/install.sh         # APT update/upgrade, base tools
  security/baseline.sh    # UFW + unattended-upgrades
  security/hardening.sh   # sysctl, AppArmor, Fail2ban, SSH hardening
  desktop/install.sh      # XFCE or LXQt
  optimization/apply.sh   # Profile-based tuning (baja/media/alta/ultra)
  optional/install.sh     # Dispatcher for all --extras (ssh, zsh, flatpak, rdp, etc.)
  audit/system-health.sh  # Post-install audit
  audit/gui-low-resource.sh  # gui-low-resource preset audit
  maintenance/            # Standalone maintenance scripts
config/packages.conf      # Package lists consumed by install scripts
tests/
  smoke.sh                # Non-interactive flag/mode combinations
  public-safety.sh        # Checks for secrets, personal data, private IPs in tracked files
instalar-*.sh             # One-liner bootstrap launcher (clones repo and runs wizard)
```

**`run_module()` contract:** each module is called as a subprocess with all state passed as environment variables (`DRY_RUN`, `LOG_FILE`, `TARGET_USER`, `PROFILE`, `EXTRAS`, `ARCH`, `DEBIAN_VERSION`, etc.). Modules must not `source` lib files themselves — they receive state only through env vars.

## Shell conventions

- All scripts: `set -Eeuo pipefail`, `#!/usr/bin/env bash`
- ShellCheck config: `.shellcheckrc` disables SC1090, SC1091, SC2154
- `DRY_RUN=1` must gate every system-modifying call; modules simulate output without acting
- Passwords are never printed to logs; files replaced under `/etc` are backed up to `/var/backups/debian-scripts/`
- Logs go to `~/debian-scripts-logs/` (relative to the invoking user's HOME, not root's)
- `--components` and `--skip-components` are mutually exclusive
- UFW must never be enabled before validating a safe SSH source (`FIREWALL_SSH_SOURCE` env var or interactive prompt)
- `sshd -t` must run before reloading SSH configuration

## Security constraints to preserve

- Firewall, auto-updates, and hardening default ON; skipping any requires explicit user action and is recorded in the final report
- UFW policy is restrictive-input and must never be reset
- `PasswordAuthentication` in sshd must not be modified
- OMV, RDP, Wazuh require explicit selection — never added by default
- `legacy-source/` and `.tmp/` must never be committed to tracked history (`public-safety.sh` enforces this)

## Git closure

After a task produces real changes and the applicable validation passes, create a descriptive
local commit for that task. Review the staged set first: it must contain only the task's paths.
In a dirty worktree, stage exact paths and leave pre-existing changes out; never use `git add .`
or `git add -A`. Do not commit when there are no changes, validation fails, or the scope cannot
be isolated safely; report the blocker. Never push without explicit user authorization.
