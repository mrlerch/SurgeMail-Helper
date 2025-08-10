#!/usr/bin/env bash
set -euo pipefail
# SurgeMail Helper (Unix) - v1.14.0
# Repo: mrlerch/SurgeMail-Helper

TELLMAIL_BIN="${TELLMAIL_BIN:-tellmail}"
SURGEMAIL_BIN="${SURGEMAIL_BIN:-surgemail}"
SERVICE_NAME="${SERVICE_NAME:-surgemail}"

GH_OWNER="${GH_OWNER:-mrlerch}"
GH_REPO="${GH_REPO:-SurgeMail-Helper}"
HELPER_VERSION="1.14.0"

usage() {
  cat <<'USAGE'
SurgeMail Helper
Usage:
  surgemail <command> [options]

Commands:
  status              Show running state and version.
  start               Start SurgeMail.
  stop                Graceful stop.
  strong_stop         Forceful stop using 'tellmail shutdown'.
  restart             Stop then start.
  reload              Reload configuration (or restart when unavailable).
  check-update        (Placeholder) Check SurgeMail server updates.
  update [--unattended]
                      Upgrade SurgeMail with a Step 6 running check.
  self-check-update   Check if a newer helper version is available.
  self-update [<tag>] Update helper from GitHub (release/tag/default branch).
  -h, --help          Show this help.

Options:
  --tellmail <path>   Override tellmail path.
  --service <name>    Override service name (default: surgemail).
  --unattended        Non-interactive mode for 'update'.
  --no-selfcheck      Skip startup self-check.
USAGE
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

_auth_headers() {
  local args=(-H "User-Agent: surgemail-helper/1.14.0")
  if [[ -n "${GH_TOKEN:-}" ]]; then args+=(-H "Authorization: Bearer $GH_TOKEN"); fi
  printf '%s\n' "${args[@]}"
}

curl_json() {
  local url="$1"
  local headers
  mapfile -t headers < <(_auth_headers)
  curl -sSfL "${headers[@]}" "$url"
}

latest_ref() {
  if json=$(curl_json "https://api.github.com/repos/$GH_OWNER/$GH_REPO/releases/latest" 2>/dev/null); then
    tag=$(printf '%s' "$json" | grep -Eo '"tag_name"\s*:\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
    [[ -n "$tag" ]] && echo "$tag" && return 0
  fi
  if json=$(curl_json "https://api.github.com/repos/$GH_OWNER/$GH_REPO/tags?per_page=1" 2>/dev/null); then
    tag=$(printf '%s' "$json" | grep -Eo '"name"\s*:\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
    [[ -n "$tag" ]] && echo "$tag" && return 0
  fi
  if json=$(curl_json "https://api.github.com/repos/$GH_OWNER/$GH_REPO" 2>/dev/null); then
    branch=$(printf '%s' "$json" | grep -Eo '"default_branch"\s*:\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
    [[ -n "$branch" ]] && echo "$branch" && return 0
  fi
  return 1
}

compare_versions() {
  local a b IFS=.
  a=(${1#v}); b=(${2#v})
  for ((i=0;i<3;i++)); do
    local ai=${a[i]:-0} bi=${b[i]:-0}
    if ((10#${ai} > 10#${bi})); then return 1; fi
    if ((10#${ai} < 10#${bi})); then return 2; fi
  done
  return 0
}

is_running() {
  if have_cmd "$TELLMAIL_BIN"; then
    "$TELLMAIL_BIN" status >/dev/null 2>&1 && return 0
    "$TELLMAIL_BIN" version >/dev/null 2>&1 && return 0
  elif have_cmd pgrep; then
    pgrep -f "[s]urgemail" >/dev/null 2>&1 && return 0
  elif have_cmd systemctl; then
    systemctl is-active --quiet "$SERVICE_NAME" && return 0
  elif have_cmd service; then
    service "$SERVICE_NAME" status >/dev/null 2>&1 && return 0
  fi
  return 1
}

start_srv() { if have_cmd systemctl; then systemctl start "$SERVICE_NAME"; elif have_cmd service; then service "$SERVICE_NAME" start; elif have_cmd "$SURGEMAIL_BIN"; then "$SURGEMAIL_BIN" start; else echo "No method to start service" >&2; return 1; fi }
stop_srv()  { if have_cmd systemctl; then systemctl stop "$SERVICE_NAME";  elif have_cmd service; then service "$SERVICE_NAME" stop;  elif have_cmd "$SURGEMAIL_BIN"; then "$SURGEMAIL_BIN" stop;  else echo "No method to stop service" >&2; return 1; fi }
reload_srv(){ if have_cmd systemctl; then systemctl reload "$SERVICE_NAME" || systemctl restart "$SERVICE_NAME"; elif have_cmd service; then service "$SERVICE_NAME" reload || service "$SERVICE_NAME" restart; elif have_cmd "$SURGEMAIL_BIN"; then "$SURGEMAIL_BIN" restart; else echo "No method to reload service" >&2; return 1; fi }

version_str() { if have_cmd "$TELLMAIL_BIN"; then "$TELLMAIL_BIN" version 2>/dev/null || true; else echo "tellmail not available"; fi }

cmd_status() { if is_running; then echo "SurgeMail: RUNNING"; else echo "SurgeMail: STOPPED"; fi; echo "Version: $(version_str)"; echo "Helper: v$HELPER_VERSION"; }
cmd_start()  { if is_running; then echo "Already running."; exit 0; fi; start_srv; sleep 2; is_running && echo "Started." || { echo "Failed to start." >&2; exit 1; } }
cmd_stop()   { if ! is_running; then echo "Already stopped."; exit 0; fi; stop_srv; sleep 2; ! is_running && echo "Stopped." || { echo "Stop did not succeed. Try strong_stop." >&2; exit 1; } }
cmd_strong_stop() { if have_cmd "$TELLMAIL_BIN"; then "$TELLMAIL_BIN" shutdown || true; else stop_srv || true; fi; sleep 3; is_running && { echo "Strong stop may have failed." >&2; exit 1; } || echo "Strong stop completed." }
cmd_restart(){ cmd_stop || true; cmd_start; }
cmd_reload() { reload_srv; echo "Reload requested."; }
cmd_check_update() { echo "Server update check: (placeholder)"; }

cmd_update() {
  local prev now
  prev="$(version_str)"; echo "Previous version: $prev"
  echo "1) Downloading installer..."
  echo "2) Stopping service (graceful)..."; cmd_stop || true
  echo "3) Running installer... (hook here)"
  echo "4) Installer complete."
  echo "5) Post-install checks..."
  echo "6) Starting SurgeMail (only if not running)"
  if is_running; then echo "SurgeMail already running after install. Skipping start."; else echo "Not running; starting now..."; start_srv; fi
  sleep 2
  now="$(version_str)"; echo "Current version: $now"
  if is_running; then echo "Update complete and service is running."; else echo "Update finished but service is NOT running." >&2; exit 1; fi
}

cmd_self_check_update() {
  local ref latest_v
  ref="$(latest_ref || true)"
  [[ -z "$ref" ]] && { echo "Could not determine latest ref from GitHub."; return 0; }
  if [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then latest_v="$ref"; else
    local txt
    txt=$(curl -sSfL -H "User-Agent: surgemail-helper/1.14.0" "https://raw.githubusercontent.com/$GH_OWNER/$GH_REPO/$ref/scripts/surgemail-helper.sh" 2>/dev/null || echo "")
    latest_v=$(printf '%s\n' "$txt" | grep -Eo '^# SurgeMail Helper.*v[0-9]+\.[0-9]+\.[0-9]+' -m1 | grep -Eo 'v[0-9]+\.[0-9]+\.[0-9]+')
    [[ -z "$latest_v" ]] && latest_v="v0.0.0"
  fi
  compare_versions "$HELPER_VERSION" "$latest_v"
  case $? in
    2) echo "A newer helper version v$HELPER_VERSION->$latest_v is available. Run 'surgemail self-update'." ;;
    *) ;;
  esac
}

cmd_self_update() {
  local ref="${1:-}"
  [[ -z "$ref" ]] && ref="$(latest_ref || true)"
  [[ -z "$ref" ]] && { echo "Could not determine latest release/tag/default branch from GitHub." >&2; exit 1; }
  local url="https://raw.githubusercontent.com/$GH_OWNER/$GH_REPO/$ref/scripts/surgemail-helper.sh"
  local target="$(command -v surgemail || true)"; [[ -z "$target" ]] && target="$0"
  local tmp; tmp="$(mktemp)"
  if ! curl -sSfL -H "User-Agent: surgemail-helper/1.14.0" "$url" -o "$tmp"; then
    echo "Failed to download helper from $url" >&2; exit 1
  fi
  chmod 0755 "$tmp"
  cp "$target" "$target.bak.$(date +%s)" || true
  install -m 0755 "$tmp" "$target" || { echo "Failed to replace $target (need sudo?)." >&2; exit 1; }
  echo "Helper updated successfully to ref: $ref"
}

CMD="${1:-}"; shift || true
UNATTENDED=0; NO_SELFCHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tellmail) TELLMAIL_BIN="$2"; shift 2;;
    --service)  SERVICE_NAME="$2"; shift 2;;
    --unattended) UNATTENDED=1; shift;;
    --no-selfcheck) NO_SELFCHECK=1; shift;;
    -h|--help) usage; exit 0;;
    *) break;;
  esac
done

[[ $NO_SELFCHECK -eq 0 ]] && ( cmd_self_check_update || true ) >/dev/null 2>&1 || true

case "$CMD" in
  status) cmd_status ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  strong_stop) cmd_strong_stop ;;
  restart) cmd_restart ;;
  reload) cmd_reload ;;
  check-update) cmd_check_update ;;
  update) cmd_update "$@" ;;
  self-check-update) cmd_self_check_update ;;
  self-update) cmd_self_update "$@" ;;
  ""|-h|--help) usage ;;
  *) echo "Unknown command: $CMD" >&2; usage; exit 2 ;;
esac
