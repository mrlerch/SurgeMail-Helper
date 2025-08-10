# SurgeMail Helper

Cross‑platform management helper for the SurgeMail mail server. Designed for a **simple, scriptable** way to **check status, start/stop/restart, reload, check for updates, and perform upgrades** on Linux/macOS and Windows. Includes **self‑update** for these helper scripts via GitHub and a startup self‑check that politely tells you when a new helper version is available.

- Unix: Bash script (`scripts/surgemail-helper.sh`) installed as `/usr/local/bin/surgemail`
- Windows: PowerShell script (`scripts/surgemail-helper.ps1`) with a `surgemail.bat` wrapper
- CI: ShellCheck (Unix) and PSScriptAnalyzer (Windows)
- Release workflow: attaches scripts as assets to GitHub Releases

Current helper version: **1.14.1**

---

## Install

### Unix/Linux
```bash
sudo install -m 0755 scripts/surgemail-helper.sh /usr/local/bin/surgemail

# verify
surgemail -h
surgemail status
```

Optional config file locations (first found wins):
- `/etc/surgemail-helper.conf`
- `$HOME/.config/surgemail-helper/config`

### Windows
1. Put the `scripts` folder somewhere on your PATH (e.g., `C:\Tools\SurgeMailHelper\scripts`).
2. Ensure `surgemail.bat` sits next to `surgemail-helper.ps1` so you can run `surgemail` from any PowerShell/Command Prompt.

```powershell
surgemail -Command -h
surgemail -Command status
```

---

## Usage

### Unix/Linux
```bash
surgemail <command> [options]

# examples
surgemail status
surgemail restart
surgemail update --unattended
surgemail self-check-update
surgemail self-update
surgemail self-update v1.14.1
surgemail diagnostics
```

### Windows
```powershell
surgemail -Command <command> [-Tellmail <path>] [-Service <name>] [-Unattended] [-NoSelfCheck] [-Tag <tag>]

# examples
surgemail -Command restart
surgemail -Command update -Unattended
surgemail -Command self-check-update
surgemail -Command self-update -Tag v1.14.1
surgemail -Command diagnostics
```

---

## Commands

- `status` — Show running state and version (`tellmail version` when available).
- `start` — Start SurgeMail via `systemctl`/`service` (Unix) or Windows Service.
- `stop` — Graceful stop.
- `strong_stop` — Forceful stop using **`tellmail shutdown`**.
- `restart` — Stop then start.
- `reload` — Reload service (restart if reload unsupported).
- `check-update` — Placeholder for checking SurgeMail **server** updates (non-helper).
- `update` — Orchestrated upgrade with **Step 6 guard** (don’t double‑start if installer already started).
- `self-check-update` — Check GitHub for a newer **helper** version.
- `self-update [<tag>]` — Update helper from **releases → tags → default branch**.
- `diagnostics` — Print environment, paths, and service manager detection.
- `version` — Print helper version and exit.
- `where` — Show script and config locations.

### Options

**Unix/Linux:**
- `--tellmail <path>` — Override `tellmail` path.
- `--service <name>` — Override service name (default: `surgemail`).
- `--unattended` — Non‑interactive mode for the `update` command.
- `--no-selfcheck` — Skip the startup self‑update check.
- `--debug` — Verbose logs to stderr.

**Windows:**
- `-Tellmail <path>` — Override tellmail path.
- `-Service <name>` — Override service name (default: `surgemail`).
- `-Unattended` — Non‑interactive mode for the `update` command.
- `-NoSelfCheck` — Skip startup self‑update check.
- `-Tag <tag>` — Optional tag for `self-update`.
- `-Debug` — Verbose output.

---

## Self‑Update Flow

1. Try **Latest Release** → 2. **Most recent Tag** → 3. **Default Branch**.  
2. Download via `raw.githubusercontent.com/mrlerch/SurgeMail-Helper/<ref>/scripts/surgemail-helper.(sh|ps1)`  
3. Replace the helper atomically (backup kept with timestamp suffix).  
4. Startup self‑check prints a one‑liner if a newer helper exists. Suppress with `--no-selfcheck` / `-NoSelfCheck`.

> The helper sends a `User-Agent`; if rate‑limited, set `GH_TOKEN` for authenticated requests.

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

---

## License

MIT — see [LICENSE](LICENSE).
