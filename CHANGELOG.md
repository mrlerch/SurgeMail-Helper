# Changelog

## [1.15.2] - 2026-10-08
- self_update / self_check_update `--channel prerelease`: fixed. The tag lookup expected `"prerelease":true` before `"tag_name"`, but GitHub sends `tag_name` first, so it never matched ("Could not determine latest helper version from GitHub").
- `--channel prerelease` now means the newest non-draft release, pre-release or stable, so it never offers an older pre-release over a newer stable release. PowerShell matches.
- GitHub User-Agent updated (was still 1.14.12).

## [1.15.1] - 2026-10-08
- update: install Netwin **beta** builds (e.g. the 8.2a security release). Netwin publishes betas under `/ftp/surgemail/beta/`; `update` now tries stable first and falls back to beta, or goes straight to beta with `--beta`.
- update: unknown options are now rejected instead of being swallowed as the version (`--ver 82a` used to request `surgemail_--ver_linux64.tar.gz`). `--ver` is accepted as an alias for `--version`.
- update: version may be given as `8.2a` as well as `82a`.
- update: exits non-zero when the package can't be found, so callers (cron, CertForge) see the failure.
- status/start/stop/restart: SurgeMail 8.2a's `tellmail status` no longer prints "SurgeMail Version" (only the `Key ... OK` line), so the helper believed a running 8.2a server was down. Readiness now accepts the Key/Uptime lines too.
- update: after the installer, wait for its own restart to finish; never start a second SurgeMail over a live process, and never stop/start a running-but-slow server in the verify step. (On 8.2a this previously caused a duplicate start, a port-25 fight and a full outage.)
- PowerShell: same beta fallback, `--beta`, `--ver` alias, version normalisation and unknown-option check.

## [1.15.0] - 2025-09-16
- self_check_update/self_update: fixed GitHub detection errors; support channels (release/prerelease/dev), auto/quiet, git vs ZIP flows, and downgrade protection.
- added _gh_helpers.inc.sh helper script for surgemail-helper.sh
- PowerShell: applied all fixes and functionality from surgemail-helper.sh script

## [1.14.12] - 2025-08-14
- start: reduced duplicate status output; added quiet readiness probe to avoid redundant messages.
- self_check_update/self_update: fixed GitHub detection errors; support channels (release/prerelease/dev), auto/quiet, git vs ZIP flows, and downgrade protection.
- PowerShell: aligned start messaging (quieter); notes added for 1.14.12.

## [1.14.11] - 2025-08-14
- stop: fixed AWK syntax errors by rewriting `list_blockers_detailed()` to use lsof → ss → netstat → fuser fallbacks and feed clean PID/command/port lines.
- start: improved readiness detection. `is_surgemail_ready()` now waits 5s and treats “Bad Open Response” as stopped; prints clearer start messages and confirms health after start.
- PowerShell: added `Is-Running` with the same semantics; wrapped the `start` command with equivalent pre/post checks.
- Bumped HELPER_VERSION, SCRIPT_VERSION, header “Version:” and User-Agent to 1.14.11.

## [1.14.10] - 2025-08-12
- Implemented missing GitHub helper functions for self_check_update/self_update with channels.
- Default unauthenticated GitHub API; optional token via --token or $GITHUB_TOKEN/$GH_TOKEN.
- Streamlined start output to avoid redundant checks/messages.
- Updated help text in scripts to document options and token usage.

INSTALL:
Store the SurgeMail-Helper directory where you wish. IF you want to use the script globally
you may opt to cd to SurgeMail-Helper and then run the the command below.
  sudo ln -sf scripts/surgemail-helper.sh /usr/local/bin/surgemail
Please make sure that /usr/local/bin is in your executable path. If you get the following error:
  bash: surgemail: command not found
 you need to add this line below to your .bashrc file (in the user's home directory)
  export PATH="/usr/local/bin:$PATH"

## [1.14.8] - 2025-08-12
- Implemented short flags routing (-s, -r, -u, -d, -v, -w, -h) and documented them.
- Router now includes where/diagnostics/self_check_update/self_update and help aliases.
- Restored and preserved 1.13.2 `update` and `check-update` flows and helpers.
- `self_check_update` always prints feedback; `self_update` prompts on downgrade.
- `where` labels updated (surgemail helper command, SurgeMail Server directory).
- README and man page updated.

## [1.14.6] - 2025-08-11
- Implement server `check_update` via `tellmail status` with page fallback.
- Fix `is_running` with 10s wait; adjust `start`/`stop`/`reload`/`strong_stop` behavior.
- Add short flags and `man` command; implement helper `self_*` clone vs ZIP logic.

## [1.14.2] - 2025-08-10
## Fixed
- `diagnostics` now runs cleanly on hosts **without** SurgeMail installed; no syntax errors and no hard failures.
- Safer command probes (status/version checks) won’t error if `tellmail`/`surgemail`/service managers are missing.
## Improved
- Updated README with **diagnostics** documentation and examples.

## [1.14.1] - 2025-08-10
- Restored full helper with verbose diagnostics, locking & self‑update flow.
- Windows PowerShell and batch wrapper synced.

## [1.13.2] - 2025-08-10
##UPDATED
- In `update` Step 6, only start SurgeMail if it's not already running at the new version (install.sh typically restarts it). If running but version differs, perform a controlled restart; otherwise skip start.

## [1.13.1] - 2025-08-10
- FIX: strong_stop() now uses `tellmail shutdown` for a clean stop.
- FIX: cmd_status() brace/else syntax corrected.

## [1.13.0] - 2025-08-10
- Added `status` (runs `tellmail status`) and `version` (runs `tellmail version`) commands.

## [1.12.4] - 2025-08-10
- check-update: improved parsing of "Current Release 80e"; interactive upgrade prompt.
- Non-interactive prints a concrete command with detected OS, or lists valid --os options.

## [1.12.3] - 2025-08-10
- Robust version parsing and safer comparator; interactive upgrade prompt.

## [1.12.2] - 2025-08-10
- Prevent silent exits in update/check-update under `set -e`.

## [1.12.1] - 2025-08-10
- Syntax hardening; minor fixes.

## [1.12.0] - 2025-08-10
- `check-update` always prints installed/latest; --auto announces action.

## [1.11.0] - 2025-08-10)
- `stop` frees all standard mail/admin ports.

## [1.10.0] - 2025-08-10
- Introduced `--api` unattended installer driving (requires `expect` or `socat` on Unix).

## [1.6.0] - 2025-08-09
- Smoother output: pre-check common ports and summarize blockers
- Optional --verbose to stream installer/start output; otherwise capture to files
- Cleaner status messages for start/stop/restart/reload

## [1.5.0] - 2025-08-09
- API mode for update: --version <ver> (e.g., 80e) and --os <target>
- Interactive prompts when values omitted; URL building per OS family
- Windows artifacts are downloaded but not executed (manual step)

## [1.4.0] - 2025-08-09
- Health verification after start (tellmail/PID/HTTP)
- Conditional extra stop+start when initial start looks unhealthy

## [1.3.0] - 2025-08-09
- Unified single script: command router (update/stop/start/restart/reload)
- Human-friendly explanations after each command

## [1.2.1] - 2025-08-09
- Robust --dry-run flow (creates non-empty placeholder; skips strict size check)
- Avoid heredoc pitfalls; safer printing

## [1.2.0] - 2025-08-09
- Added -h/--help for update; --dry-run; wget progress auto-detect

## [1.1.0] - 2025-08-09
- Safer update flow: set -euo pipefail; sudo/root check; mktemp workspace
- URL HEAD check; tar -xzf; strict quoting; traps/cleanup

## [1.0.0] - 2025-08-09
- Initial dispatcher and basic update/start/stop hooks