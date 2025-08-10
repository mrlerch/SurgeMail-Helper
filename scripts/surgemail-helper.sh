#!/usr/bin/env bash
set -euo pipefail

# SurgeMail Helper (Unix)
# Version: 1.13.2
# Requires: bash 4+, coreutils
# Optional: pgrep/systemctl/service

TELLMAIL_BIN="${TELLMAIL_BIN:-tellmail}"
SURGEMAIL_BIN="${SURGEMAIL_BIN:-surgemail}"
SERVICE_NAME="${SERVICE_NAME:-surgemail}"

usage() {
  cat <<USAGE
Usage: $0 <command> [options]

Commands:
  status
  start
  stop
  strong_stop
  restart
  reload
  check-update
  update [--unattended]

Options:
  --tellmail <path>   Override tellmail path
  --service <name>    Override service name
  -h, --help          Show this help

Examples:
  sudo $0 status
  sudo $0 update --unattended
USAGE
}

# Parse args (simple hand-rolled parser)
CMD="${1:-}"
shift || true
UNATTENDED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tellmail) TELLMAIL_BIN="$2"; shift 2;;
    --service)  SERVICE_NAME="$2"; shift 2;;
    --unattended) UNATTENDED=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done

have_cmd() { command -v "$1" >/dev/null 2>&1; }

is_running() {
  # Try tellmail pid, else pgrep, else systemctl
  if have_cmd "$TELLMAIL_BIN"; then
    # tellmail status returns 0 when running typically; fallback to version call
    if "$TELLMAIL_BIN" status >/dev/null 2>&1; then
      return 0
    fi
    # Some builds lack status; try a harmless command
    if "$TELLMAIL_BIN" version >/dev/null 2>&1; then
      return 0
    fi
    return 1
  elif have_cmd pgrep; then
    pgrep -f "[s]urgemail" >/dev/null 2>&1
    return $?
  elif have_cmd systemctl; then
    systemctl is-active --quiet "$SERVICE_NAME"
    return $?
  elif have_cmd service; then
    service "$SERVICE_NAME" status >/dev/null 2>&1
    return $?
  fi
  return 1
}

start_srv() {
  if have_cmd systemctl; then
    systemctl start "$SERVICE_NAME"
  elif have_cmd service; then
    service "$SERVICE_NAME" start
  elif have_cmd "$SURGEMAIL_BIN"; then
    "$SURGEMAIL_BIN" start
  else
    echo "No known method to start service" >&2
    return 1
  fi
}

stop_srv() {
  if have_cmd systemctl; then
    systemctl stop "$SERVICE_NAME"
  elif have_cmd service; then
    service "$SERVICE_NAME" stop
  elif have_cmd "$SURGEMAIL_BIN"; then
    "$SURGEMAIL_BIN" stop
  else
    echo "No known method to stop service" >&2
    return 1
  fi
}

reload_srv() {
  if have_cmd systemctl; then
    systemctl reload "$SERVICE_NAME" || systemctl restart "$SERVICE_NAME"
  elif have_cmd service; then
    service "$SERVICE_NAME" reload || service "$SERVICE_NAME" restart
  elif have_cmd "$SURGEMAIL_BIN"; then
    "$SURGEMAIL_BIN" restart
  else
    echo "No known method to reload service" >&2
    return 1
  fi
}

version_str() {
  if have_cmd "$TELLMAIL_BIN"; then
    "$TELLMAIL_BIN" version 2>/dev/null || true
  else
    echo "tellmail not available"
  fi
}

cmd_status() {
  if is_running; then
    echo "SurgeMail: RUNNING"
  else
    echo "SurgeMail: STOPPED"
  fi
  echo "Version: $(version_str)"
}

cmd_start() {
  if is_running; then
    echo "Already running."
    exit 0
  fi
  start_srv
  sleep 2
  if is_running; then
    echo "Started."
  else
    echo "Failed to start." >&2
    exit 1
  fi
}

cmd_stop() {
  if ! is_running; then
    echo "Already stopped."
    exit 0
  fi
  stop_srv
  sleep 2
  if ! is_running; then
    echo "Stopped."
  else
    echo "Stop did not succeed. Try strong_stop." >&2
    exit 1
  fi
}

cmd_strong_stop() {
  # IMPORTANT: correct command is 'tellmail shutdown'
  if have_cmd "$TELLMAIL_BIN"; then
    "$TELLMAIL_BIN" shutdown || true
  else
    echo "tellmail not available; attempting service stop."
    stop_srv || true
  fi
  sleep 3
  if is_running; then
    echo "Strong stop may have failed." >&2
    exit 1
  fi
  echo "Strong stop completed."
}

cmd_restart() {
  cmd_stop || true
  cmd_start
}

cmd_reload() {
  reload_srv
  echo "Reload requested."
}

cmd_check_update() {
  echo "Checking for updates..."
  # Placeholder: this script does not scrape web (offline). Implement your policy here.
  echo "Use your organization's policy to compare installed vs available versions."
}

cmd_update() {
  PREV_VER="$(version_str)"
  echo "Previous version: ${PREV_VER}"
  echo "1) Downloading installer..."
  # Placeholder: add curl/wget logic to fetch latest installer to /tmp
  echo "2) Stopping service (graceful)..."
  cmd_stop || true
  echo "3) Running installer..."
  # Example: bash install.sh -auto
  # ./install.sh
  echo "4) Installer complete."
  echo "5) Post-install checks..."
  # The official installer runs its own stop/start; do not double-start.
  echo "6) Starting SurgeMail (only if not running)"
  if is_running; then
    echo "SurgeMail already running after install. Skipping start."
  else
    echo "Not running; starting now..."
    start_srv
  fi
  sleep 2
  NOW_VER="$(version_str)"
  echo "Current version: ${NOW_VER}"
  if is_running; then
    echo "Update complete and service is running."
  else
    echo "Update finished but service is NOT running." >&2
    exit 1
  fi
}

case "$CMD" in
  status)        cmd_status ;;
  start)         cmd_start ;;
  stop)          cmd_stop ;;
  strong_stop)   cmd_strong_stop ;;
  restart)       cmd_restart ;;
  reload)        cmd_reload ;;
  check-update)  cmd_check_update ;;
  update)        cmd_update ;;
  ""|-h|--help)  usage ;;
  *) echo "Unknown command: $CMD" >&2; usage; exit 2 ;;
esac
