# Changelog

All notable changes to this project will be documented in this file.

## [1.13.2] - 2025-08-10
### Fixed
- `strong_stop`: corrected command to **`tellmail shutdown`** (previously used invalid `tellmail stop`).

### Added
- `update` Step 6 post-install guard:
  - Detects if SurgeMail is already running after installer’s built-in stop/start.
  - Verifies availability of `tellmail` and reads the **newly installed version** via `tellmail version`.
  - Only starts SurgeMail if it is not already running.
  - Prints both *previous* and *current* versions when possible.

### Improved
- Clearer status messaging and exit codes for CI/cron usage.
- Script layout refined for cross-platform parity.