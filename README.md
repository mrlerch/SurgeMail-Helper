# SurgeMail Helper — v1.14.6

Full drop‑in build with:
- New `is_running` (10s wait + `tellmail status` parsing)
- Fixed `start`/`stop`/`reload`/`strong_stop`
- Implemented `check_update` (prefers `tellmail status`; fallback to download page)
- `self_check_update` / `self_update` support clone vs ZIP installs
- Short flags: -s -r -u -d -v -w -h
- `man` subcommand with `docs/surgemail.1`
- No `.github/` in the package

<<<<<<< HEAD
- Unix: `scripts/surgemail-helper.sh` (install as `/usr/local/bin/surgemail` → run `surgemail <command> [options]`)
- Windows: `scripts/surgemail-helper.ps1` with `scripts/surgemail.bat` and **legacy** `scripts/surgemail-helper.bat` shims
- **No `.github/`** directory included to keep zip drop‑ins in sync with your local repo

Current helper version: **1.14.2**

## Install

### Unix/Linux
=======
Recommended install (symlink):
>>>>>>> f0175d6 (feat: command alias + self-update + startup check (v1.14.6))
```bash
sudo ln -sf /path/to/SurgeMail-Helper/scripts/surgemail-helper.sh /usr/local/bin/surgemail
```
