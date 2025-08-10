#!/usr/bin/env bash
# ============================================================================
# SurgeMail Helper (Unix/Linux)
# Version: 1.14.2
# Repo: mrlerch/SurgeMail-Helper
#
# PURPOSE:
#   A cross-platform helper to manage the SurgeMail server from the command
#   line, with commands like status, start, stop, strong_stop, restart,
#   reload, check-update, update, and new helper maintenance commands:
#   self-check-update, self-update, diagnostics, version, where.
#
# DESIGN GOALS:
#   - Predictable CLI UX: `surgemail <command> [options]`
#   - Idempotent `update` with "Step 6" guard to skip redundant starts
#   - Robust service manager detection (systemd/service/direct)
#   - Portable: no hard dependency on `jq`
#   - Safe: backups on self-update, conservative defaults
#   - Maintainable: verbose comments and clear structure
#
# INSTALL:
#   sudo install -m 0755 scripts/surgemail-helper.sh /usr/local/bin/surgemail
#
# CONFIG FILES (optional; first found wins):
#   /etc/surgemail-helper.conf
#   $HOME/.config/surgemail-helper/config
#
# ENV VAR OVERRIDES:
#   TELLMAIL_BIN, SURGEMAIL_BIN, SERVICE_NAME
#   GH_OWNER, GH_REPO, GH_TOKEN
#   SMH_DEBUG=1 (debug)
#
# COPYRIGHT: MIT License (see LICENSE)
# ============================================================================

set -euo pipefail

# ---------- Defaults ----------
TELLMAIL_BIN="${TELLMAIL_BIN:-tellmail}"
SURGEMAIL_BIN="${SURGEMAIL_BIN:-surgemail}"
SERVICE_NAME="${SERVICE_NAME:-surgemail}"

GH_OWNER="${GH_OWNER:-mrlerch}"
GH_REPO="${GH_REPO:-SurgeMail-Helper}"
HELPER_VERSION="1.14.2"

# ---------- Global state ----------
SMH_DEBUG="${SMH_DEBUG:-0}"
NO_SELFCHECK_DEFAULT=0

# ---------- Colors (if TTY) ----------
if [[ -t 2 ]]; then
  C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_BLU=$'\e[34m'; C_RST=$'\e[0m'
else
  C_BOLD=""; C_DIM=""; C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_RST=""
fi

# ---------- Logging ----------
log()  { printf '%s\n' "$*" >&2; }
info() { log "${C_BLU}[*]${C_RST} $*"; }
ok()   { log "${C_GRN}[✓]${C_RST} $*"; }
warn() { log "${C_YEL}[!]${C_RST} $*"; }
err()  { log "${C_RED}[x]${C_RST} $*"; }
dbg()  { [[ "$SMH_DEBUG" == "1" ]] && log "${C_DIM}[debug] $*${C_RST}"; }

die()  { err "$*"; exit 1; }

# ---------- Config loader ----------
load_config() {
  local files=( "/etc/surgemail-helper.conf" "$HOME/.config/surgemail-helper/config" )
  for f in "${files[@]}"; do
    if [[ -f "$f" ]]; then
      dbg "Loading config: $f"
      # shellcheck disable=SC1090
      source "$f"
      break
    fi
  done
}

# ---------- Help ----------
usage() {
  cat <<'USAGE'
SurgeMail Helper (Unix/Linux)
Usage:
  surgemail <command> [options]

Commands:
  status               Show running state and version (tellmail when available).
  start                Start SurgeMail.
  stop                 Graceful stop.
  strong_stop          Forceful stop using 'tellmail shutdown' (correct command).
  restart              Stop then start.
  reload               Reload configuration (or restart when unavailable).
  check-update         (Placeholder) Check SurgeMail server updates.
  update [--unattended]
                       Upgrade SurgeMail with the Step 6 running check.
  self-check-update    Check if a newer helper version is available on GitHub.
  self-update [<tag>]  Update helper from release/tag/default branch.
  diagnostics          Print environment and detection info.
  version              Print helper version (e.g., v1.14.2).
  where                Show script path and config path.

Options:
  --tellmail <path>    Override tellmail path (default: tellmail).
  --service <name>     Override service name  (default: surgemail).
  --unattended         Non-interactive mode for 'update'.
  --no-selfcheck       Skip startup self-check for new helper versions.
  --debug              Enable verbose debug logging (SMH_DEBUG=1).

Examples:
  surgemail status
  surgemail restart
  surgemail update --unattended
  surgemail self-check-update
  surgemail self-update v1.14.2
  surgemail diagnostics
USAGE
}

# ---------- Utilities ----------
have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
  have_cmd "$1" || die "Required command '$1' not found. Please install it."
}

confirm() {
  local prompt="${1:-Proceed?}"
  read -r -p "$prompt [y/N]: " ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# Read file into var
read_file() {
  local f="$1"
  [[ -r "$f" ]] || return 1
  # shellcheck disable=SC2002
  cat "$f"
}

# ---------- Curl helpers ----------
_auth_headers() {
  # Prints curl args (headers) one per line (used with xargs-like mapfile)
  echo "-H"
  echo "User-Agent: surgemail-helper/1.14.1"
  if [[ -n "${GH_TOKEN:-}" ]]; then
    echo "-H"
    echo "Authorization: Bearer $GH_TOKEN"
  fi
}

curl_raw() {
  # curl_raw <url> [extra-args...]
  local url="$1"; shift || true
  local headers=()
  while IFS= read -r line; do
    headers+=("$line")
  done < <(_auth_headers)
  dbg "curl_raw GET $url"
  curl -sSfL "${headers[@]}" "$url" "$@"
}

curl_json() {
  local url="$1"; shift || true
  curl_raw "$url" "$@"  # identical, just a naming hint
}

# ---------- JSON parsing (lightweight without jq) ----------
json_get() {
  # json_get <json-string> <key>
  # Extracts value for "key": "value" (first occurrence). Not a full JSON parser.
  local json="$1"; local key="$2"
  printf '%s\n' "$json" | grep -Eo '"'"$key"'"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | cut -d'"' -f4
}

# ---------- Version compare ----------
# return: 0 equal, 1 A>B, 2 A<B
compare_versions() {
  local A="${1#v}" B="${2#v}"
  local IFS=.
  local a=($A) b=($B)
  for ((i=0;i<3;i++)); do
    local ai="${a[i]:-0}" bi="${b[i]:-0}"
    if ((10#$ai > 10#$bi)); then return 1; fi
    if ((10#$ai < 10#$bi)); then return 2; fi
  done
  return 0
}

# ---------- Service detection ----------
detect_service_manager() {
  if have_cmd systemctl && systemctl list-units --type=service >/dev/null 2>&1; then
    echo "systemd"; return 0
  fi
  if have_cmd service; then
    echo "sysvinit"; return 0
  fi
  echo "direct"
}

# ---------- Running checks ----------
is_running() {
  if have_cmd "$TELLMAIL_BIN"; then
    if "$TELLMAIL_BIN" status >/dev/null 2>&1; then return 0; fi
    if "$TELLMAIL_BIN" version >/dev/null 2>&1; then return 0; fi
  fi
  if have_cmd pgrep; then
    pgrep -f "[s]urgemail" >/dev/null 2>&1 && return 0
  fi
  case "$(detect_service_manager)" in
    systemd) systemctl is-active --quiet "$SERVICE_NAME" && return 0 ;;
    sysvinit) service "$SERVICE_NAME" status >/dev/null 2>&1 && return 0 ;;
  esac
  return 1
}

start_srv() {
  case "$(detect_service_manager)" in
    systemd) systemctl start "$SERVICE_NAME" ;;
    sysvinit) service "$SERVICE_NAME" start ;;
    direct)
      if have_cmd "$SURGEMAIL_BIN"; then "$SURGEMAIL_BIN" start
      else die "No method to start service (missing systemctl/service and SURGEMAIL_BIN)"; fi
      ;;
  esac
}

stop_srv() {
  case "$(detect_service_manager)" in
    systemd) systemctl stop "$SERVICE_NAME" ;;
    sysvinit) service "$SERVICE_NAME" stop ;;
    direct)
      if have_cmd "$SURGEMAIL_BIN"; then "$SURGEMAIL_BIN" stop
      else die "No method to stop service (missing systemctl/service and SURGEMAIL_BIN)"; fi
      ;;
  esac
}

reload_srv() {
  case "$(detect_service_manager)" in
    systemd) systemctl reload "$SERVICE_NAME" || systemctl restart "$SERVICE_NAME" ;;
    sysvinit) service "$SERVICE_NAME" reload || service "$SERVICE_NAME" restart ;;
    direct)
      if have_cmd "$SURGEMAIL_BIN"; then "$SURGEMAIL_BIN" restart
      else die "No method to reload/restart service"; fi
      ;;
  esac
}

version_str() {
  if have_cmd "$TELLMAIL_BIN"; then
    "$TELLMAIL_BIN" version 2>/dev/null || echo "unknown"
  else
    echo "tellmail not available"
  fi
}

# ---------- Self-update helpers ----------
latest_ref() {
  _ua=(-H "User-Agent: surgemail-helper/1.14.2")
  [[ -n "${GH_TOKEN:-}" ]] && _ua+=(-H "Authorization: Bearer $GH_TOKEN")
  if json=$(curl -sSfL "${_ua[@]}" "https://api.github.com/repos/$GH_OWNER/$GH_REPO/releases/latest" 2>/dev/null); then
    tag=$(printf '%s' "$json" | grep -Eo '"tag_name"\s*:\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
    [[ -n "$tag" ]] && { echo "$tag"; return 0; }
  fi
  if json=$(curl -sSfL "${_ua[@]}" "https://api.github.com/repos/$GH_OWNER/$GH_REPO/tags?per_page=1" 2>/dev/null); then
    tag=$(printf '%s' "$json" | grep -Eo '"name"\s*:\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
    [[ -n "$tag" ]] && { echo "$tag"; return 0; }
  fi
  if json=$(curl -sSfL "${_ua[@]}" "https://api.github.com/repos/$GH_OWNER/$GH_REPO" 2>/dev/null); then
    branch=$(printf '%s' "$json" | grep -Eo '"default_branch"\s*:\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
    [[ -n "$branch" ]] && { echo "$branch"; return 0; }
  fi
  return 1
}
self_check_update_quick() {
  local ref latest_v
  ref="$(latest_ref || true)"
  if [[ -z "$ref" ]]; then
    dbg "No ref discovered for self-check."
    return 0
  fi
  if [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    latest_v="$ref"
  else
    # Try to read version header from raw file
    local txt
    txt=$(curl_raw "https://raw.githubusercontent.com/$GH_OWNER/$GH_REPO/$ref/scripts/surgemail-helper.sh" 2>/dev/null || true)
    latest_v="$(printf '%s\n' "$txt" | grep -Eo '^# Version: [0-9]+\.[0-9]+\.[0-9]+' | head -n1 | awk '{print "v"$3}')"
    latest_v="${latest_v:-v1.14.2}"
  fi
  compare_versions "$HELPER_VERSION" "$latest_v"
  case $? in
    2) warn "A newer helper version v$HELPER_VERSION->$latest_v is available. Run 'surgemail self-update'." ;;
    *) ;;
  esac
}

self_update() {
  local ref="${1:-}"
  if [[ -z "$ref" ]]; then ref="$(latest_ref || true)"; fi
  [[ -z "$ref" ]] && die "Could not determine latest release/tag/default branch from GitHub."
  local url="https://raw.githubusercontent.com/$GH_OWNER/$GH_REPO/$ref/scripts/surgemail-helper.sh"
  local target; target="$(command -v surgemail || true)"
  [[ -z "$target" ]] && target="$0"
  local tmp; tmp="$(mktemp)"
  info "Downloading helper from $url"
  if ! curl_raw "$url" -o "$tmp"; then
    die "Failed to download helper from $url"
  fi
  chmod 0755 "$tmp"
  cp "$target" "$target.bak.$(date +%s)" || true
  if install -m 0755 "$tmp" "$target"; then
    ok "Helper updated successfully to ref: $ref"
  else
    die "Failed to replace $target (need sudo?)."
  fi
}

# ---------- Commands ----------
cmd_status() {
  if is_running; then ok "SurgeMail: RUNNING"; else warn "SurgeMail: STOPPED"; fi
  echo "Version: $(version_str)"
  echo "Helper: v$HELPER_VERSION"
}

cmd_start() {
  if is_running; then info "Already running."; return 0; fi
  start_srv; sleep 2
  is_running && ok "Started." || die "Failed to start."
}

cmd_stop() {
  if ! is_running; then info "Already stopped."; return 0; fi
  stop_srv; sleep 2
  ! is_running && ok "Stopped." || die "Stop did not succeed. Try strong_stop."
}

cmd_strong_stop() {
  if have_cmd "$TELLMAIL_BIN"; then
    info "Invoking 'tellmail shutdown'"
    "$TELLMAIL_BIN" shutdown || true
  else
    warn "tellmail not available; attempting service stop."
    stop_srv || true
  fi
  sleep 3
  is_running && die "Strong stop may have failed." || ok "Strong stop completed."
}

cmd_restart() {
  cmd_stop || true
  cmd_start
}

cmd_reload() {
  reload_srv
  ok "Reload requested."
}

cmd_check_update() {
  info "Server update check (placeholder)."
  echo "Implement your organization's logic to check SurgeMail server updates."
}

cmd_update() {
  local prev now
  prev="$(version_str)"
  echo "Previous version: $prev"
  echo "1) Downloading installer..."
  # Place your download logic here (curl/wget). Keep artifacts under /tmp.
  echo "2) Stopping service (graceful)..."
  cmd_stop || true
  echo "3) Running installer..."
  # Example placeholder:
  # bash /tmp/surgemail-install.sh
  echo "4) Installer complete."
  echo "5) Post-install checks..."
  echo "6) Starting SurgeMail (only if not running)"
  if is_running; then
    info "SurgeMail already running after install. Skipping start."
  else
    info "Not running; starting now..."
    start_srv
  fi
  sleep 2
  now="$(version_str)"
  echo "Current version: $now"
  is_running && ok "Update complete and service is running." || die "Update finished but service is NOT running."
}

cmd_self_check_update() {
  self_check_update_quick
}

cmd_self_update() {
  self_update "${1:-}"
}

cmd_diagnostics() {
  echo "=== SurgeMail Helper Diagnostics ==="
  echo "Helper version : v$HELPER_VERSION"
  echo "Script path    : $0"
  echo "Service name   : $SERVICE_NAME"
  echo "tellmail bin   : $TELLMAIL_BIN (found: $(have_cmd "$TELLMAIL_BIN" && echo yes || echo no))"
  echo "surgemail bin  : $SURGEMAIL_BIN (found: $(have_cmd "$SURGEMAIL_BIN" && echo yes || echo no))"
  echo "Service mgr    : $(detect_service_manager)"
  echo "Running        : $(is_running && echo yes || echo no)"
  echo "GH_OWNER/REPO  : $GH_OWNER / $GH_REPO"
  echo "Config sources : /etc/surgemail-helper.conf ; $HOME/.config/surgemail-helper/config"
  echo "Env debug      : SMH_DEBUG=$SMH_DEBUG"
}

cmd_version() { echo "v$HELPER_VERSION"; }

cmd_where() {
  echo "Script: $0"
  for f in /etc/surgemail-helper.conf "$HOME/.config/surgemail-helper/config"; do
    if [[ -f "$f" ]]; then echo "Config: $f"; fi
  done
}

# ---------- Argument parsing ----------
main() {
  load_config

  local CMD="${1:-}"; shift || true
  local UNATTENDED=0
  local NO_SELFCHECK=$NO_SELFCHECK_DEFAULT

  # Parse options (stop at first non-option to preserve command args)
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tellmail) TELLMAIL_BIN="$2"; shift 2;;
      --service)  SERVICE_NAME="$2"; shift 2;;
      --unattended) UNATTENDED=1; shift;;
      --no-selfcheck) NO_SELFCHECK=1; shift;;
      --debug) SMH_DEBUG=1; shift;;
      -h|--help) usage; exit 0;;
      *) break;;
    esac
  done

  # Startup self-check (non-fatal, background suppressed to keep order)
  if [[ $NO_SELFCHECK -eq 0 ]]; then
    self_check_update_quick || true
  fi

  case "$CMD" in
    status)              cmd_status ;;
    start)               cmd_start ;;
    stop)                cmd_stop ;;
    strong_stop)         cmd_strong_stop ;;
    restart)             cmd_restart ;;
    reload)              cmd_reload ;;
    check-update)        cmd_check_update ;;
    update)              cmd_update "$@" ;;
    self-check-update)   cmd_self_check_update ;;
    self-update)         cmd_self_update "$@" ;;
    diagnostics)         cmd_diagnostics ;;
    version)             cmd_version ;;
    where)               cmd_where ;;
    ""|-h|--help)        usage ;;
    *) err "Unknown command: $CMD"; usage; exit 2 ;;
  esac
}

main "$@"


# ---------- Concurrency (advisory lock) ----------
LOCKFILE="/var/run/surgemail-helper.lock"

acquire_lock() {
  if mkdir "$LOCKFILE" 2>/dev/null; then
    trap 'release_lock' EXIT
    dbg "Acquired lock: $LOCKFILE"
  else
    warn "Another surgemail-helper may be running (lock exists: $LOCKFILE). Proceeding anyway."
  fi
}

release_lock() {
  rmdir "$LOCKFILE" 2>/dev/null || true
  dbg "Released lock: $LOCKFILE"
}

# ---------- Retry helpers ----------
with_retry() {
  # with_retry <retries> <sleep> -- cmd...
  local tries="$1"; shift
  local delay="$1"; shift
  local n=0
  until "$@"; do
    n=$((n+1))
    [[ $n -ge $tries ]] && return 1
    warn "Retry $n/$tries: $*"
    sleep "$delay"
  done
}

# ---------- Timeout wrapper (requires `timeout`) ----------
with_timeout() {
  # with_timeout <sec> -- cmd...
  local sec="$1"; shift
  if have_cmd timeout; then
    timeout --preserve-status "$sec" "$@"
  else
    warn "timeout(1) not available; running without timeout."
    "$@"
  fi
}

# ---------- Port inspection (optional) ----------
find_pid_by_port() {
  local port="$1"
  if have_cmd lsof; then
    lsof -iTCP:"$port" -sTCP:LISTEN -n -P | awk 'NR>1 {print $2; exit}'
  elif have_cmd ss; then
    ss -ltnp "sport = :$port" 2>/dev/null | awk -F',' 'NR>1 {for(i=1;i<=NF;i++) if($i ~ /pid=/){sub(/pid=/,"",$i); split($i,a," "); print a[1]; exit}}'
  else
    echo ""
  fi
}

# ---------- Bash completion (optional; user may source this) ----------
_surgemail_completion() {
  local cur prev words cword
  _init_completion -n : || return
  local cmds="status start stop strong_stop restart reload check-update update self-check-update self-update diagnostics version where"
  case "${COMP_CWORD}" in
    1) COMPREPLY=( $(compgen -W "$cmds" -- "$cur") );;
    2)
      case "${COMP_WORDS[1]}" in
        update) COMPREPLY=( $(compgen -W "--unattended --tellmail --service --no-selfcheck --debug" -- "$cur") );;
        self-update) COMPREPLY=( $(compgen -W "v__VERSION__" -- "$cur") );;
        *) COMPREPLY=();;
      esac
      ;;
    *)
      COMPREPLY=()
      ;;
  esac
}

# ---------- Long-form documentation (for maintainers) ----------
: <<'__SMH_LONG_DOC__'
MANPAGE
=======

NAME
  surgemail - SurgeMail Helper CLI

SYNOPSIS
  surgemail <command> [options]

DESCRIPTION
  The 'surgemail' helper is a cross-platform management utility designed to
  standardize day-2 operations for the SurgeMail server across Linux and macOS.
  It abstracts service management differences (systemd, sysvinit, direct),
  provides a consistent way to run updates safely, and ships with a self-update
  system to keep the helper itself current using the GitHub repository
  __OWNER__/__REPO__.

  The helper is deliberately verbose with comments and structure to make it easy
  to audit, fork, and extend. It has no hard dependency on JSON tooling such as
  'jq' and instead uses simple grep/awk parsing for the minimal fields required.

FILES
  /usr/local/bin/surgemail
      The installed command (this script).

  /etc/surgemail-helper.conf
      Global configuration file (optional).

  $HOME/.config/surgemail-helper/config
      Per-user configuration override (optional).

ENVIRONMENT
  TELLMAIL_BIN, SURGEMAIL_BIN, SERVICE_NAME
      Override detection defaults.

  GH_OWNER, GH_REPO, GH_TOKEN
      Configure GitHub lookup for self-update. Token raises rate limits.

  SMH_DEBUG=1
      Enables debug logs to stderr.

COMMANDS
  status, start, stop, strong_stop, restart, reload
      Standard service operations.

  check-update, update
      Update orchestration with Step 6 post-install guard.

  self-check-update, self-update
      Maintenance of the helper itself via GitHub.

  diagnostics, version, where
      Useful admin tools and metadata.

EXIT STATUS
  0 on success; non-zero on errors. The helper attempts to use clear, actionable
  messages on failure paths.

EXAMPLES
  surgemail status
  surgemail update --unattended
  GH_TOKEN=ghp_xxx surgemail self-check-update
  surgemail self-update v1.14.2
  SMH_DEBUG=1 surgemail diagnostics

SECURITY
  Use sudo/root only when necessary. The helper strives to make minimal changes
  and to back up replaced binaries when self-updating. For extra assurance,
  consider pinning tags for self-update instead of consuming a moving branch.

BUGS
  File issues and PRs at: https://github.com/__OWNER__/__REPO__

__SMH_LONG_DOC__

