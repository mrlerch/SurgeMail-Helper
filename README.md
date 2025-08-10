# SurgeMail Helper

Cross‑platform management helper for the SurgeMail mail server. Designed for operators who want a **simple, scriptable** way to **check status, start/stop/restart, reload, check for updates, and perform upgrades** on Linux/macOS and Windows systems.

- Unix: Bash script (`scripts/surgemail-helper.sh`)
- Windows: PowerShell script (`scripts/surgemail-helper.ps1`) + wrappers
- CI: ShellCheck (Unix) and PSScriptAnalyzer (Windows) workflows

> Current script version: **1.14.0**

---

## Table of Contents
1. Features
2. Requirements
3. Quick Start
4. Command Reference
5. Configuration
6. How Updates Work (Step 6 Guard)
7. Service Control Notes
8. Logging & Exit Codes
9. Troubleshooting
10. Security Notes
11. CI / Linting
12. Versioning
13. Roadmap: Self‑update via GitHub
14. Contributing
15. License
16. FAQ

---

## Features

- **Status & Version**: Uses `tellmail status`/`tellmail version` when available.
- **Start/Stop/Restart/Reload** across Unix/Windows.
- **Strong Stop**: `tellmail shutdown` (correct command).
- **Check-Update (placeholder)** for SurgeMail server.
- **Update** with **Step 6 guard** (don’t double‑start after installer).
- **Self‑update (helper)**: `self-check-update` and `self-update` using GitHub Releases (`mrlerch/SurgeMail-Helper`).
- **Startup notice** if a newer helper version exists.
- **Cron/Automation-Friendly** output & exit codes.

---

## Requirements

### Unix (Linux/macOS)
- Bash 4+, `curl`
- `systemctl` or `service` preferred
- `tellmail` in PATH for best results
- Root/sudo for service and upgrades

### Windows
- PowerShell 7+ recommended
- Admin shell for service control
- `surgemail` Windows Service (configurable name)

---

## Quick Start

### Get the scripts
Clone or download, then:

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

### Typical upgrade flow
**Unix**
```bash
sudo scripts/surgemail-helper.sh update --unattended
```
**Windows**
```powershell
surgemail -Command update -Unattended
```

---

## Command Reference

### Unix usage (after install to PATH)
```bash
surgemail <command> [options]
```
### Windows usage
```powershell
surgemail -Command <command> [-Tellmail <path>] [-Service <name>] [-Unattended]
```

### Commands
- `status`, `start`, `stop`, `strong_stop`, `restart`, `reload`
- `check-update`, `update`
- `self-check-update`, `self-update`

### Options (Unix)
- `--tellmail <path>`, `--service <name>`, `--unattended`

### Options (Windows)
- `-Tellmail <path>`, `-Service <name>`, `-Unattended`

---

## Configuration

Env vars (Unix):
- `TELLMAIL_BIN`, `SURGEMAIL_BIN`, `SERVICE_NAME`
- `GH_OWNER`, `GH_REPO` for self‑update (defaults: `mrlerch`, `SurgeMail-Helper`)

---

## How Updates Work (Step 6 Guard)

Installer typically stop/starts. We check if running **after** install and only start if needed. We also print previous/current versions.

---

## Install as `surgemail` command

### Unix/Linux
```bash
sudo install -m 0755 scripts/surgemail-helper.sh /usr/local/bin/surgemail
surgemail status
```
### Windows
Add `scripts` folder to PATH. Use:
- `scripts\surgemail.bat` → calls the PS script
- `scripts\surgemail-helper.ps1`

Then:
```powershell
surgemail -Command status
surgemail -Command self-check-update
```

---

## Self‑update (helper script)

Check and update **this helper** against GitHub Releases (`mrlerch/SurgeMail-Helper`).

```bash
surgemail self-check-update
sudo surgemail self-update
```

Point to a different repo:
```bash
export GH_OWNER=myorg
export GH_REPO=SurgeMail-Helper
surgemail self-check-update
```

---

## CI / Linting

- ShellCheck for the bash script
- PSScriptAnalyzer for the PS script

---

## Versioning

Semantic versioning. Current: **1.14.0**.

---

## Roadmap: Self‑update via GitHub

Self‑update implemented as described. Future: checksum/signature verification and pre-release channels.

---

## License

MIT — see LICENSE.

---

## FAQ

**Q: Why `tellmail shutdown`?** Because it’s the correct forceful stop command; `tellmail stop` is invalid.