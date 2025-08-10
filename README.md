# SurgeMail Helper

Cross‑platform management helper for SurgeMail with **simple CLI**, **robust diagnostics**, **service control**, and **self‑update** for the helper itself.

- Unix: `scripts/surgemail-helper.sh` (install as `/usr/local/bin/surgemail` → run `surgemail <command> [options]`)
- Windows: `scripts/surgemail-helper.ps1` with `scripts/surgemail.bat` and **legacy** `scripts/surgemail-helper.bat` shims
- **No `.github/`** directory included to keep zip drop‑ins in sync with your local repo

Current helper version: **1.14.4**

## Install

### Unix/Linux
```bash
sudo install -m 0755 scripts/surgemail-helper.sh /usr/local/bin/surgemail
surgemail -h
surgemail diagnostics
```

### Windows
Place the `scripts` folder on PATH (e.g., `C:\Tools\SurgeMailHelper\scripts`). Both shims work:

```powershell
surgemail -Command -h
surgemail-helper -Command diagnostics   # legacy shim name
```

## Usage — Unix
```bash
surgemail <command> [options]

# examples
surgemail status
surgemail restart
surgemail update --unattended
surgemail self-check-update
surgemail self-update
surgemail self-update v1.14.2
surgemail diagnostics
```

Options:
- `--tellmail <path>`  | `--service <name>` | `--unattended` | `--no-selfcheck`

## Usage — Windows
```powershell
surgemail -Command <command> [-Tellmail <path>] [-Service <name>] [-Unattended] [-NoSelfCheck] [-Tag <tag>]
surgemail -Command self-check-update
surgemail -Command self-update -Tag v1.14.2
surgemail -Command diagnostics
```

## Diagnostics
`diagnostics` is **safe on machines without SurgeMail**. It never hard‑fails and prints:
- helper version, script path
- service name, service manager (systemd/service/direct or Windows Service)
- `tellmail` / `surgemail` discovery (found yes/no)
- running state (best effort)
- GH owner/repo for self‑update
- config search paths
- debug flag

## Self‑Update
Looks up **releases/latest → tags → default branch**, then fetches:
`https://raw.githubusercontent.com/mrlerch/SurgeMail-Helper/<ref>/scripts/surgemail-helper.(sh|ps1)`

- Sets `User-Agent`; honors `GH_TOKEN`
- Startup self‑check prints a one‑line notice if a newer helper exists (suppress via `--no-selfcheck` / `-NoSelfCheck`)

## License
Root includes your **LICENSE** and a copy of **Mozilla Public License 2.0 (MPL)** (file named exactly `Mozilla Public License 2.0 (MPL)`).
