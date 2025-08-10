# SurgeMail Helper

Cross‑platform management helper for the SurgeMail mail server. Designed for a **simple, scriptable** way to **check status, start/stop/restart, reload, check for updates, and perform upgrades** on Linux/macOS and Windows. Includes **self‑update** for these helper scripts via GitHub.

- Unix: Bash script (`scripts/surgemail-helper.sh`) installed as `/usr/local/bin/surgemail`
- Windows: PowerShell script (`scripts/surgemail-helper.ps1`) with a `surgemail.bat` wrapper
- CI: ShellCheck (Unix) and PSScriptAnalyzer (Windows)
- Release workflow: attaches scripts as assets to GitHub Releases

Current helper version: **1.14.0**

## Install

### Unix/Linux
```bash
sudo install -m 0755 scripts/surgemail-helper.sh /usr/local/bin/surgemail
surgemail -h
surgemail status
```

### Windows
1. Put `scripts` in your PATH (e.g., `C:\Tools\SurgeMailHelper\scripts`).
2. Ensure `surgemail.bat` is alongside `surgemail-helper.ps1`.
```powershell
surgemail -Command -h
surgemail -Command status
```

## Usage

### Unix/Linux
```bash
surgemail <command> [options]
surgemail status
surgemail restart
surgemail update --unattended
surgemail self-check-update
surgemail self-update
surgemail self-update v1.14.0
```

### Windows
```powershell
surgemail -Command <command> [-Tellmail <path>] [-Service <name>] [-Unattended] [-NoSelfCheck] [-Tag <tag>]
surgemail -Command update -Unattended
surgemail -Command self-check-update
surgemail -Command self-update -Tag v1.14.0
```

## Self‑Update

Order of discovery: **releases/latest → tags → default branch**. Downloads from:
`https://raw.githubusercontent.com/mrlerch/SurgeMail-Helper/<ref>/scripts/surgemail-helper.(sh|ps1)`.

Exports `User-Agent`, and uses `GH_TOKEN` if present for rate limits. A one‑line startup self‑check prints a notice when a newer version exists (can be suppressed via `--no-selfcheck` / `-NoSelfCheck`).

## License

MIT
