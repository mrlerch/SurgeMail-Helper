# Changelog

All notable changes to this project will be documented here.

## [1.14.0] - 2025-08-10
### Added
- `self-check-update` and `self-update` for Unix and Windows.
- Startup self-update notice if a newer helper exists on GitHub.
- Windows `surgemail.bat` wrapper for `surgemail -Command ...` usage.

### Changed
- Standardized CLI: install bash script as `/usr/local/bin/surgemail` for `surgemail <command> [options]`.

## [1.13.2] - 2025-08-10
### Fixed
- `strong_stop`: corrected to `tellmail shutdown`.
### Added
- Step 6 post-install guard in `update`.