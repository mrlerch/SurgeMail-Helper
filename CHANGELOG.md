# Changelog

All notable changes to this project are documented here.

## [1.14.1] - 2025-08-10
### Fixed
- Restored full, verbose Bash helper with comprehensive comments, diagnostics, and robust parsing (previous shrinkage to a minimal script has been reverted).
- Self‑update flow now consistently handles repos **without** releases by falling back to tags/default branch and shows clear messaging.
- Help text and README fully synchronized with script behavior; added examples and diagnostics command.

### Added
- Config file support (`/etc/surgemail-helper.conf`, `$HOME/.config/surgemail-helper/config`).
- `diagnostics`, `version`, and `where` commands.
- `--debug` / `-Debug` flags for detailed tracing.

### Improved
- Safer service manager detection and fallbacks.
- More resilient version comparison and JSON parsing without requiring `jq`.

## [1.14.0] - 2025-08-10
### Added
- Command alias: install the Unix helper as `/usr/local/bin/surgemail`.
- Windows wrapper: `surgemail.bat` to run the PowerShell helper as `surgemail`.
- Self‑update: `self-check-update` / `self-update` (release → tags → default branch).
- Startup self‑check prints a notice when a newer helper version exists.
- Release assets workflow to attach scripts to Releases.

### Fixed
- Avoid 404s when no GitHub release exists by falling back to tags/default branch.

## [1.13.2] - 2025-08-10
### Fixed
- `strong_stop` uses **`tellmail shutdown`** (not `tellmail stop`).

### Added
- `update` Step 6 guard to avoid double‑starting after the official installer completes.
