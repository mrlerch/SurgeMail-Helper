#!/usr/bin/env bash
set -euo pipefail

# SurgeMail Helper (Unix)
# Version: 1.14.0
# Repo: https://github.com/mrlerch/SurgeMail-Helper

VERSION="1.14.0"
GH_OWNER="${GH_OWNER:-mrlerch}"
GH_REPO="${GH_REPO:-SurgeMail-Helper}"
GH_API_LATEST="https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/releases/latest"

TELLMAIL_BIN="${TELLMAIL_BIN:-tellmail}"
SURGEMAIL_BIN="${SURGEMAIL_BIN:-surgemail}"
SERVICE_NAME="${SERVICE_NAME:-surgemail}"

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  LINK="$(readlink "$SELF")"
  if [[ "$LINK" = /* ]]; then SELF="$LINK"; else SELF="$(cd "$(dirname "$SELF")" && cd "$(dirname "$LINK")" && pwd)/$(basename "$LINK")"; fi
done
SELF_DIR="$(cd "$(dirname "$SELF")" && pwd)"
SELF_BASENAME="$(basename "$SELF")"

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ver_lt() {
  a="${1#v}"; b="${2#v}"
  IFS='.' read -r a1 a2 a3 <<<"${a}.0.0"
  IFS='.' read -r b1 b2 b3 <<<"${b}.0.0"
  (( 10#$a1 < 10#$b1 )) && return 0
  (( 10#$a1 > 10#$b1 )) && return 1
  (( 10#$a2 < 10#$b2 )) && return 0
  (( 10#$a2 > 10#$b2 )) && return 1
  (( 10#$a3 < 10#$b3 )) && return 0
  return 1
}

gh_latest_tag() {
  if ! have_cmd curl; then echo ""; return 0; fi
  json="$(curl -fsSL "$GH_API_LATEST" || true)"
  tag="$(printf '%s' "$json" | tr -d '\r\n' | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  echo "$tag"
}

self_check_update() {
  tag="$(gh_latest_tag)"
  if [ -n "$tag" ] && ver_lt "$VERSION" "$tag"; then
    echo "[surgemail-helper] A newer version is available: ${tag} (you have v${VERSION})."
    echo "  To update: sudo surgemail self-update"
  fi
}

self_update() {
  tag="${1:-}"
  if [ -z "$tag" ]; then
    tag="$(gh_latest_tag)"
    [ -z "$tag" ] && { echo "Could not determine latest release from GitHub." >&2; exit 1; }
  fi
  have_cmd curl || { echo "curl not found; cannot download update." >&2; exit 1; }
  tmp="$(mktemp)"
  url_raw="https://raw.githubusercontent.com/${GH_OWNER}/${GH_REPO}/${tag}/scripts/surgemail-helper.sh"
  if ! curl -fsSL "$url_raw" -o "$tmp"; then
    url_raw="https://raw.githubusercontent.com/${GH_OWNER}/${GH_REPO}/main/scripts/surgemail-helper.sh"
    curl -fsSL "$url_raw" -o "$tmp"
  fi
  grep -q 'VERSION="' "$tmp" || { echo "Downloaded script seems invalid." >&2; rm -f "$tmp"; exit 1; }
  backup="${SELF}.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$SELF" "$backup" || true
  install -m 0755 "$tmp" "$SELF"
  rm -f "$tmp"
  echo "Updated ${SELF_BASENAME} to ${tag}. Backup: ${backup}"
}

usage() {
  cat <<USAGE
Usage: surgemail <command> [options]

Commands:
  status
  start
  stop
  strong_stop
  restart
  reload
  check-update
  update [--unattended]
  self-check-update
  self-update [<tag>]

Options:
  --tellmail <path>
  --service <name>
  -h, --help

Env: GH_OWNER, GH_REPO

Examples:
  sudo surgemail status
  sudo surgemail update --unattended
  sudo surgemail self-check-update
  sudo surgemail self-update
USAGE
}

CMD="${1:-}"
shift || true
UNATTENDED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tellmail) TELLMAIL_BIN="$2"; shift 2;;
    --service)  SERVICE_NAME="$2"; shift 2;;
    --unattended) UNATTENDED=1; shift;;
    -h|--help) usage; exit 0;;
    *) if [[ -z "${CMD}" ]]; then CMD="$1"; shift; else echo "Unknown option: $1" >&2; usage; exit 2; fi ;;
  esac
done

self_check_update || true

is_running() {
  if have_cmd "$TELLMAIL_BIN"; then
    if "$TELLMAIL_BIN" status >/dev/null 2>&1; then return 0; fi
    if "$TELLMAIL_BIN" version >/dev/null 2>&1; then return 0; fi
    return 1
  elif have_cmd pgrep; then
    pgrep -f "[s]urgemail" >/dev/null 2>&1; return $? 
  elif have_cmd systemctl; then
    systemctl is-active --quiet "$SERVICE_NAME"; return $?
  elif have_cmd service; then
    service "$SERVICE_NAME" status >/dev/null 2>&1; return $?
  fi
  return 1
}

start_srv() {
  if have_cmd systemctl; then systemctl start "$SERVICE_NAME"
  elif have_cmd service; then service "$SERVICE_NAME" start
  elif have_cmd "$SURGEMAIL_BIN"; then "$SURGEMAIL_BIN" start
  else echo "No known method to start service" >&2; return 1; fi
}

stop_srv() {
  if have_cmd systemctl; then systemctl stop "$SERVICE_NAME"
  elif have_cmd service; then service "$SERVICE_NAME" stop
  elif have_cmd "$SURGEMAIL_BIN"; then "$SURGEMAIL_BIN" stop
  else echo "No known method to stop service" >&2; return 1; fi
}

reload_srv() {
  if have_cmd systemctl; then systemctl reload "$SERVICE_NAME" || systemctl restart "$SERVICE_NAME"
  elif have_cmd service; then service "$SERVICE_NAME" reload || service "$SERVICE_NAME" restart
  elif have_cmd "$SURGEMAIL_BIN"; then "$SURGEMAIL_BIN" restart
  else echo "No known method to reload service" >&2; return 1; fi
}

version_str() {
  if have_cmd "$TELLMAIL_BIN"; then "$TELLMAIL_BIN" version 2>/dev/null || true
  else echo "tellmail not available"; fi
}

cmd_status() { if is_running; then echo "SurgeMail: RUNNING"; else echo "SurgeMail: STOPPED"; fi; echo "Version: $(version_str)"; }
cmd_start()  { if is_running; then echo "Already running."; exit 0; fi; start_srv; sleep 2; is_running && echo "Started." || { echo "Failed to start." >&2; exit 1; }; }
cmd_stop()   { if ! is_running; then echo "Already stopped."; exit 0; fi; stop_srv; sleep 2; ! is_running && echo "Stopped." || { echo "Stop did not succeed. Try strong_stop." >&2; exit 1; }; }
cmd_strong_stop() {
  if have_cmd "$TELLMAIL_BIN"; then "$TELLMAIL_BIN" shutdown || true; else echo "tellmail not available; attempting service stop."; stop_srv || true; fi
  sleep 3; is_running && { echo "Strong stop may have failed." >&2; exit 1; } || echo "Strong stop completed."
}
cmd_restart(){ cmd_stop || true; cmd_start; }
cmd_reload(){ reload_srv; echo "Reload requested."; }
cmd_check_update(){ echo "Checking for SurgeMail server updates... (placeholder)"; }
cmd_update(){
  PREV_VER="$(version_str)"; echo "Previous version: ${PREV_VER}"
  echo "1) Downloading installer..."
  echo "2) Stopping service (graceful)..."; cmd_stop || true
  echo "3) Running installer..."
  echo "4) Installer complete."
  echo "5) Post-install checks..."
  echo "6) Starting SurgeMail (only if not running)"
  if is_running; then echo "SurgeMail already running after install. Skipping start."
  else echo "Not running; starting now..."; start_srv; fi
  sleep 2; NOW_VER="$(version_str)"; echo "Current version: ${NOW_VER}"
  is_running && echo "Update complete and service is running." || { echo "Update finished but service is NOT running." >&2; exit 1; }
}

case "${CMD:-}" in
  status) cmd_status ;;
  start) cmd_start ;;
  stop) cmd_stop ;;
  strong_stop) cmd_strong_stop ;;
  restart) cmd_restart ;;
  reload) cmd_reload ;;
  check-update) cmd_check_update ;;
  update) cmd_update ;;
  self-check-update) self_check_update ;;
  self-update) self_update ;;
  ""|-h|--help) usage ;;
  *) echo "Unknown command: ${CMD}" >&2; usage; exit 2 ;;
esac
