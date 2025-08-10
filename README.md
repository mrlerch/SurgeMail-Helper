# SurgeMail Helper

Cross‑platform management helper for the SurgeMail mail server. Designed for operators who want a **simple, scriptable** way to **check status, start/stop/restart, reload, check for updates, and perform upgrades** on Linux/macOS and Windows systems.

- Unix: Bash script (`scripts/surgemail-helper.sh`)
- Windows: PowerShell script (`scripts/surgemail-helper.ps1`) + Batch shim (`scripts/surgemail-helper.bat`)
- CI: ShellCheck (Unix) and PSScriptAnalyzer (Windows) workflows

> Current script version: **1.13.2**

---

## Table of Contents
1. [Features](#features)
2. [Requirements](#requirements)
3. [Quick Start](#quick-start)
4. [Command Reference](#command-reference)
5. [Configuration](#configuration)
6. [How Updates Work (Step 6 Guard)](#how-updates-work-step-6-guard)
7. [Service Control Notes](#service-control-notes)
8. [Logging & Exit Codes](#logging--exit-codes)
9. [Troubleshooting](#troubleshooting)
10. [Security Notes](#security-notes)
11. [CI / Linting](#ci--linting)
12. [Versioning](#versioning)
13. [Roadmap: Self‑Update via GitHub](#roadmap-selfupdate-via-github)
14. [Contributing](#contributing)
15. [License](#license)
16. [FAQ](#faq)

---

## Features

- **Status & Version**: Uses `tellmail status`/`tellmail version` when available to confirm running state and display the installed SurgeMail version.
- **Start/Stop/Restart/Reload**: Works with `systemctl`/`service` on Unix or Windows Services on Windows.
- **Strong Stop**: Uses the *correct* command `tellmail shutdown` for a forceful stop when needed.
- **Check-Update (placeholder)**: Hook to your preferred update discovery logic.
- **Update**: Coordinates a graceful stop, runs the official installer, and **only starts** the service if it isn’t already running after the installer completes (the installer typically performs its own stop/start). Prints previous and current versions when possible.
- **Cron/Automation-Friendly**: Predictable output and exit codes; suitable for CI or scheduled tasks.

---

## Requirements

### Unix (Linux/macOS)
- Bash 4+
- `systemctl` or `service` (preferred but not strictly required)
- `tellmail` available in `PATH` for best results (script can still function without it but version/status checks are limited)
- Sudo/root for service control and upgrades

### Windows
- PowerShell 7+ recommended (script runs best under `pwsh`)
- Windows Service named `surgemail` (configurable)
- Administrator shell for service control and upgrades

---

## Quick Start

### Get the scripts
Clone or download this repository, then:

**Unix**
```bash
chmod +x scripts/surgemail-helper.sh
sudo scripts/surgemail-helper.sh status
```

**Windows (PowerShell 7+)**
```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\surgemail-helper.ps1 -Command status
```

### Typical upgrade flow (Unix)
```bash
sudo scripts/surgemail-helper.sh update --unattended
```

### Typical upgrade flow (Windows)
```powershell
.\scripts\surgemail-helper.ps1 -Command update -Unattended
```

> The `update` command includes a **post‑install running check** so you don’t accidentally double‑start SurgeMail if the official installer already restarted it.

---

## Command Reference

### Unix
```bash
scripts/surgemail-helper.sh <command> [options]
```

### Windows
```powershell
.\scripts\surgemail-helper.ps1 -Command <command> [-Tellmail <path>] [-Service <name>] [-Unattended]
```

### Commands
- `status` — Show running state and version (`tellmail version` when available).
- `start` — Start SurgeMail via `systemctl`, `service`, or direct binary fallback on Unix; Windows Service on Windows.
- `stop` — Graceful stop.
- `strong_stop` — Forceful stop using `tellmail shutdown` (correct command).
- `restart` — Stop then start.
- `reload` — Reload service (or restart if reload is not available on the platform).
- `check-update` — Placeholder for your update discovery logic.
- `update` — Orchestrated upgrade with a **Step 6 guard** to avoid double‑starting.

### Options (Unix)
- `--tellmail <path>` — Override `tellmail` binary path.
- `--service <name>` — Override service name (default: `surgemail`).
- `--unattended` — Non‑interactive mode for automation.

### Options (Windows)
- `-Tellmail <path>` — Override tellmail path.
- `-Service <name>` — Override service name (default: `surgemail`).
- `-Unattended` — Non‑interactive mode for automation.

---

## Configuration

You can configure behavior using:
- **Command‑line flags** (see above)
- **Environment variables** (Unix):
  - `TELLMAIL_BIN` — Path to `tellmail` (default: `tellmail`)
  - `SURGEMAIL_BIN` — Path to `surgemail` binary (if direct start/stop fallback is needed)
  - `SERVICE_NAME` — Service name (default: `surgemail`)

Examples:
```bash
TELLMAIL_BIN=/opt/surgemail/tellmail SERVICE_NAME=surgemail sudo scripts/surgemail-helper.sh status
sudo scripts/surgemail-helper.sh --tellmail /usr/local/surge/tellmail --service surgemail restart
```

---

## How Updates Work (Step 6 Guard)

The official SurgeMail installer (`install.sh`) **already performs a stop/start**. To avoid a redundant start (and service churn), our `update` command includes **Step 6**:

1. Run installer.
2. **Check if SurgeMail is running** (prefers `tellmail status`/`version`, falls back to `pgrep`/`systemctl`/`service` on Unix, Windows Service status on Windows).
3. If **running**, **skip** starting it again.
4. If **not running**, start it with the appropriate service mechanism.
5. Print previous and current versions when available.

This makes upgrades **idempotent** and safer in automation.

---

## Service Control Notes

- On **Linux**, the script prefers `systemctl`, then `service`, then a direct binary fallback.
- On **macOS**, `launchctl` isn’t directly used; prefer running SurgeMail as a service via a supported method or keep the binary in the foreground and control with `tellmail`.
- On **Windows**, the Service name defaults to `surgemail`. If yours differs, set `-Service <name>`.

---

## Logging & Exit Codes

- Successful operations return **0**.
- Non‑fatal issues may print warnings and still return **0**.
- Failures return **non‑zero** (commonly **1** or **2** for bad usage/unknown command).

You can redirect output to a log file for automation:
```bash
sudo scripts/surgemail-helper.sh update --unattended | tee -a /var/log/surgemail-helper.log
```

---

## Troubleshooting

- **`tellmail` not found**:
  - Install or add it to `PATH`, or provide `--tellmail /path/to/tellmail`.
- **Service does not start/stop**:
  - Verify the service name with `systemctl status surgemail` (Linux) or `Get-Service surgemail` (Windows). Override with `--service`/`-Service`.
- **Permission denied**:
  - Ensure you run as root/Administrator for service control and upgrades.
- **After upgrade, version didn’t change**:
  - Check that the installer actually applied an update and that you’re reading the correct `tellmail` instance in `PATH`.

---

## Security Notes

- Run upgrades from a trusted source and verify installer signatures/checksums where supported.
- Prefer least privilege where possible; however, service control typically requires elevated privileges.
- Avoid placing secrets in command lines or environment variables.

---

## CI / Linting

- **ShellCheck** lints the Unix script on pushes/PRs that touch `scripts/*.sh`.
- **PSScriptAnalyzer** analyzes the PowerShell script on pushes/PRs that touch `scripts/*.ps1`.

---

## Versioning

This project uses **semantic versioning**:
- **MAJOR**: incompatible API/behavior changes
- **MINOR**: backwards‑compatible functionality
- **PATCH**: backwards‑compatible bug fixes

Current release: **1.13.2**

---

## Roadmap: Self‑Update via GitHub

We will add an **auto‑update for the helper scripts themselves** (not SurgeMail). The plan:

1. **Discover latest release** on GitHub via API:
   - Endpoint: `https://api.github.com/repos/<OWNER>/<REPO>/releases/latest`
   - Extract the `tag_name` (e.g., `v1.13.3`) and compare to the local script’s version.
2. **Compare versions**:
   - Normalize tags to `MAJOR.MINOR.PATCH`, compare numerically.
3. **Download assets**:
   - For Unix: `curl` the latest script or archived zip; verify checksum if provided.
   - For Windows: `Invoke‑RestMethod`/`Invoke‑WebRequest` to fetch the `.ps1` or zip.
4. **Apply update safely**:
   - Write to a temp file, back up current script, replace atomically, preserve permissions, and print a success message.
5. **Flags**:
   - `self-check-update` — Print available update (no changes).
   - `self-update` — Apply the update (with `--unattended` support).
6. **Config**:
   - Environment variables or flags to set `OWNER`/`REPO` if not embedded.
   - Optional **signed release** verification (future).

> We will implement this next, keeping zero external dependencies (parse JSON using PowerShell’s native parser on Windows; use `grep/sed` or `awk` on Unix, optionally using `jq` when present).

---

## Contributing

1. Fork and create a feature branch.
2. Make changes with clear, small commits.
3. Ensure scripts pass ShellCheck/PSScriptAnalyzer.
4. Open a PR with a concise description and testing notes.

---

## License

MIT — see [LICENSE](LICENSE).

---

## FAQ

**Q: Why does `strong_stop` use `tellmail shutdown`?**  
A: That’s the correct forceful stop command for SurgeMail; `tellmail stop` is not valid.

**Q: Can I run this without `tellmail` in PATH?**  
A: Yes, but version/status checks may be limited. Provide the path via `--tellmail` for best results.

**Q: Does the `update` command fetch the installer automatically?**  
A: The scaffolding is in place; you can plug in your organization’s fetch policy (e.g., curl to SurgeMail’s download site). The Step 6 guard already ensures we don’t double‑start the service.