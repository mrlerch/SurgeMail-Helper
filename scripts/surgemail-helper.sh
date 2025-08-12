#!/usr/bin/env bash
# SurgeMail Helper (Unix/macOS)
# Version: 1.14.6
# Repo: mrlerch/SurgeMail-Helper
# License: see LICENSE and "Mozilla Public License 2.0 (MPL)"

set -euo pipefail

TELLMAIL_BIN="${TELLMAIL_BIN:-tellmail}"
SERVICE_NAME="${SERVICE_NAME:-surgemail}"
GH_OWNER="${GH_OWNER:-mrlerch}"
GH_REPO="${GH_REPO:-SurgeMail-Helper}"
HELPER_VERSION="1.14.6"
SMH_DEBUG="${SMH_DEBUG:-0}"

# --- config ---
SURGEMAIL_DIR="/usr/local/surgemail"
STOP_CMD="$SURGEMAIL_DIR/surgemail_stop.sh"
START_CMD="$SURGEMAIL_DIR/surgemail_start.sh"
PID_FILE="$SURGEMAIL_DIR/surgemail.pid"
ADMIN_URL="https://127.0.0.1:7025/"
CHECK_PORTS="25 465 587 110 143 993 995 7025"
VERBOSE=${VERBOSE:-0}  # 0=quiet, 1=verbose

# --- helpers ---
log() { printf "%s\n" "$*"; }
info() { printf "[*] %s\n" "$*"; }
ok()   { printf "[OK] %s\n" "$*"; }
warn() { printf "[!] %s\n" "$*" >&2; }
die()  { printf "[X] %s\n" "$*" >&2; exit 1; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "Please run as root (sudo)."; }
is_tty() { [[ -t 0 ]] && [[ -t 1 ]]; }
vlog() { [[ "$VERBOSE" -eq 1 ]] && echo "[debug] $*"; }

# Service manager detection
service_mgr="direct"
if have_cmd systemctl; then service_mgr="systemd"
elif have_cmd service; then service_mgr="service"
fi

# ---- GitHub helpers ----
auth_headers() {
  local args=(-H "User-Agent: surgemail-helper/1.14.6")
  if [[ -n "${GH_TOKEN:-}" ]]; then args+=(-H "Authorization: Bearer $GH_TOKEN"); fi
  printf '%s\n' "${args[@]}"
}
curl_json() {
  local url="$1"; shift || true
  local headers; mapfile -t headers < <(auth_headers)
  curl -sSfL "${headers[@]}" "$url" "$@"
}
latest_ref() {
  local json tag branch
  if json=$(curl_json "https://api.github.com/repos/$GH_OWNER/$GH_REPO/releases/latest" 2>/dev/null); then
    tag=$(printf '%s' "$json" | grep -Eo '"tag_name"\s*:\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
    [[ -n "$tag" ]] && printf "%s\n" "$tag" && return 0
  fi
  if json=$(curl_json "https://api.github.com/repos/$GH_OWNER/$GH_REPO/tags?per_page=1" 2>/dev/null); then
    tag=$(printf '%s' "$json" | grep -Eo '"name"\s*:\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
    [[ -n "$tag" ]] && printf "%s\n" "$tag" && return 0
  fi
  if json=$(curl_json "https://api.github.com/repos/$GH_OWNER/$GH_REPO" 2>/dev/null); then
    branch=$(printf '%s' "$json" | grep -Eo '"default_branch"\s*:\s*"[^"]+"' | head -n1 | cut -d'"' -f4)
    [[ -n "$branch" ]] && printf "%s\n" "$branch" && return 0
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

# ---- Path helpers ----
smh_script_path() { readlink -f "$0" 2>/dev/null || echo "$0"; }
smh_base_dir()    { local p; p="$(dirname "$(smh_script_path)")"; dirname "$p"; }
is_git_checkout() { [[ -d "$(smh_base_dir)/.git" ]] ; }

# ---- Version parsing helpers ----
parse_running_ver() {
  # input: "SurgeMail Version 8.0e-1, Built ..."
  awk '
    /SurgeMail Version/ {
      for (i=1;i<=NF;i++) if ($i=="Version") {v=$(i+1); break}
      gsub(",", "", v)
      gsub("\\.", "", v)   # 8.0e-1 -> 80e-1
      sub("-.*$", "", v)   # 80e-1 -> 80e
      print v
    }' <<<"$1"
}
parse_latest_from_status() {
  sed -n 's/.*Newer release version available - \([0-9][0-9][a-z]\).*/\1/p' <<<"$1"
}
fetch_latest_from_page() {
  local html
  html="$(curl -sSfL -H "User-Agent: surgemail-helper/$HELPER_VERSION" "https://surgemail.com/download-surgemail/" || true)"
  sed -n 's/.*Current Release <b>\([0-9][0-9][a-z]\)<\/b>.*/\1/p' <<<"$html" | head -n1
}
cmp_surgemail_ver() {
  # compare A vs B like 80e vs 80g; echo -1 if A<B, 0 eq, 1 if A>B
  local A="$1" B="$2"
  local an="${A%[a-z]}" al="${A##*[0-9]}"
  local bn="${B%[a-z]}" bl="${B##*[0-9]}"
  if ((10#${an} < 10#${bn})); then echo -1; return; fi
  if ((10#${an} > 10#${bn})); then echo 1; return; fi
  if [[ "$al" < "$bl" ]]; then echo -1; elif [[ "$al" > "$bl" ]]; then echo 1; else echo 0; fi
}

# ---- is_running (10s wait + tellmail status) ----
is_running() {
  echo "Checking status..."
  sleep 10
  if have_cmd "$TELLMAIL_BIN"; then
    local out
    out="$("$TELLMAIL_BIN" status 2>&1 || true)"
    if printf "%s" "$out" | grep -qE '^SurgeMail Version [0-9]+\.[0-9]+[a-z]'; then
      return 0
    fi
    if printf "%s" "$out" | grep -q 'Bad Open Response'; then
      return 1
    fi
  fi
  if have_cmd pgrep && pgrep -f "[s]urgemail" >/dev/null 2>&1; then return 0; fi
  if [[ "$service_mgr" == "systemd" ]] && systemctl is-active --quiet "$SERVICE_NAME"; then return 0; fi
  if [[ "$service_mgr" == "service" ]] && service "$SERVICE_NAME" status >/dev/null 2>&1; then return 0; fi
  return 1
}

# ---- Commands ----
usage() {
cat <<'USAGE'
SurgeMail Helper
Usage:
  surgemail <command> [options]

Commands:
  status | -s           Show SurgeMail server status (tellmail status).
  start                 Start SurgeMail.
  stop                  Stop SurgeMail (graceful shutdown).
  strong_stop           Same as stop for now; reserved for future behavior.
  restart               Stop then start.
  reload | -r           Reload configuration (tellmail reload).
  check_update          Check for newer SurgeMail server version and prompt.
  update | -u           Update SurgeMail server (interactive or unattended).
  self_check_update     Check for newer helper script and prompt to update.
  self_update           Update the helper script folder (git clone or ZIP).
  diagnostics | -d      Print environment/report.
  version | -v          Print SurgeMail server version (tellmail version) + helper version.
  where | -w            Show helper dir, surgemail server dir, tellmail path.
  man                   Show man page (if installed), else help.
  help | -h             Show this help.

Options:
  --tellmail <path>     Override tellmail path.
  --service <name>      Override service name (default: surgemail).
  --no-selfcheck        Skip startup self-check.
USAGE
}

cmd_status() {
  if have_cmd "$TELLMAIL_BIN"; then
    "$TELLMAIL_BIN" status || true
  else
    if is_running; then echo "SurgeMail: RUNNING"; else echo "SurgeMail: STOPPED"; fi
  fi
}
cmd_version() {
  if have_cmd "$TELLMAIL_BIN"; then "$TELLMAIL_BIN" version || true; else echo "tellmail not available"; fi
  echo "Helper: v$HELPER_VERSION"
}
cmd_where() {
  local script_path smbin tell_path
  script_path="$(smh_script_path)"
  if command -v surgemail >/dev/null 2>&1; then smbin="$(command -v surgemail)"; else smbin="(not found)"; fi
  tell_path="$(command -v "$TELLMAIL_BIN" 2>/dev/null || true)"
  [[ -z "$tell_path" ]] && tell_path="(not found)"
  echo "helper directory         : $(smh_base_dir)"
  echo "surgemail binary         : $smbin"
  echo "tellmail path            : $tell_path"
  echo "default server directory : /usr/local/surgemail"
}
cmd_reload() {
  if have_cmd "$TELLMAIL_BIN"; then
    "$TELLMAIL_BIN" reload || true
    echo "SurgMail server configurations reloaded."
  else
    echo "SurgMail server configurations reload failed. SurgeMail server not running."
  fi
}
cmd_stop() {
  if have_cmd "$TELLMAIL_BIN"; then
    "$TELLMAIL_BIN" shutdown || true
  elif [[ "$service_mgr" == "systemd" ]]; then
    systemctl stop "$SERVICE_NAME" || true
  elif [[ "$service_mgr" == "service" ]]; then
    service "$SERVICE_NAME" stop || true
  else
    /usr/local/surgemail/surgemail_stop.sh || true
  fi
  sleep 1
  if ! is_running; then echo "Stopped."; else echo "Stop did not fully succeed. You can try: surgemail strong_stop" >&2; exit 1; fi
}
cmd_strong_stop() {
  if have_cmd "$TELLMAIL_BIN"; then
    info "Invoking 'tellmail shutdown'"
    "$TELLMAIL_BIN" shutdown || true
  else
    warn "tellmail not available; not running."
    if [[ "$service_mgr" == "systemd" ]]; then
      systemctl stop "$SERVICE_NAME" || true
    elif [[ "$service_mgr" == "service" ]]; then
      service "$SERVICE_NAME" stop || true
    else
      /usr/local/surgemail/surgemail_stop.sh || true
    fi
  fi
  sleep 1
  if is_running; then die "Not running."; else ok "Strong stop completed."; fi
}
cmd_start() {
  if [[ "$service_mgr" == "systemd" ]]; then
    systemctl start "$SERVICE_NAME"
  elif [[ "$service_mgr" == "service" ]]; then
    service "$SERVICE_NAME" start
  else
    /usr/local/surgemail/surgemail_start.sh || true
  fi
  sleep 1
  if is_running; then echo "Started."; else echo "Failed to start." >&2; exit 1; fi
}
cmd_restart() { cmd_stop || true; cmd_start; }

# ---- Server update check ----
cmd_check_update() {
  local out run_v latest_v
  if ! have_cmd "$TELLMAIL_BIN"; then
    echo "tellmail is not available; SurgeMail may not be running. Cannot determine running version."
    return 1
  fi
  out="$("$TELLMAIL_BIN" status 2>&1 || true)"
  run_v="$(parse_running_ver "$out")"
  latest_v="$(parse_latest_from_status "$out")"
  if [[ -z "$latest_v" ]]; then
    latest_v="$(fetch_latest_from_page)"
  fi
  if [[ -z "$run_v" || -z "$latest_v" ]]; then
    echo "Could not determine versions (running='$run_v', latest='$latest_v')."
    return 1
  fi
  case "$(cmp_surgemail_ver "$run_v" "$latest_v")" in
    -1)
      echo "There is a newer SurgeMail Server version available. Version $latest_v. You are running $run_v."
      read -r -p "Would you like to upgrade it? y/n " ans
      if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
        cmd_update "$latest_v"
      else
        echo "Ok, maybe next time. Exiting."
      fi
      ;;
     0)
      echo "You are running the latest SurgeMail Server version. Version $latest_v. Exiting."
      ;;
     1)
      echo "Your running version ($run_v) is newer than the current stable ($latest_v)."
      ;;
  esac
}

# ---- Self-update (helper script) ----
download_and_overlay_zip() {
  local ref="$1"
  local tmpzip tmpdir basedir
  basedir="$(smh_base_dir)"
  tmpzip="$(mktemp)"
  tmpdir="$(mktemp -d)"
  local url="https://github.com/$GH_OWNER/$GH_REPO/archive/refs/heads/$ref.zip"
  if [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    url="https://github.com/$GH_OWNER/$GH_REPO/archive/refs/tags/$ref.zip"
  fi
  curl -sSfL -H "User-Agent: surgemail-helper/$HELPER_VERSION" "$url" -o "$tmpzip" || { echo "Download failed: $url"; return 1; }
  unzip -oq "$tmpzip" -d "$tmpdir"
  local inner
  inner="$(find "$tmpdir" -maxdepth 1 -type d | tail -n +2 | head -n1)"
  cp -a "$inner"/. "$basedir"/
}

cmd_self_check_update() {
  local ref latest_v txt
  ref="$(latest_ref || true)"
  if [[ -z "$ref" ]]; then
    echo "Could not determine latest helper version from GitHub."
    return 0
  fi
  if [[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    latest_v="$ref"
  else
    txt=$(curl -sSfL -H "User-Agent: surgemail-helper/$HELPER_VERSION" "https://raw.githubusercontent.com/$GH_OWNER/$GH_REPO/$ref/scripts/surgemail-helper.sh" 2>/dev/null || true)
    latest_v=$(printf '%s\n' "$txt" | grep -Eo 'HELPER_VERSION="?([0-9]+\.[0-9]+\.[0-9]+)"?' -m1 | sed -E 's/.*"?([0-9]+\.[0-9]+\.[0-9]+)".*/v\1/')
  fi
  [[ -z "$latest_v" ]] && latest_v="v0.0.0"

  compare_versions "v$HELPER_VERSION" "$latest_v"
  case $? in
    2)
      echo "You are running SurgeMail Helper script v$HELPER_VERSION. The latest version is $latest_v."
      read -r -p "Would you like to upgrade? y/n " ans
      if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
        cmd_self_update "$latest_v"
      else
        echo "Ok, maybe next time. Thanks for using SurgeMail Helper."
      fi
      ;;
    0|1)
      echo "You are running the latest SurgeMail Helper script version v$HELPER_VERSION"
      ;;
  esac
}

cmd_self_update() {
  local ref="${1:-}"
  [[ -z "$ref" ]] && ref="$(latest_ref || true)"
  [[ -z "$ref" ]] && { echo "Could not determine latest release/tag/default branch from GitHub."; return 1; }

  if is_git_checkout; then
    ( cd "$(smh_base_dir)" && git fetch --tags && git checkout "$ref" || true && git pull --ff-only ) || { echo "Git update failed."; return 1; }
    echo "Helper updated via git to $ref"
  else
    download_and_overlay_zip "$ref" || return 1
    echo "Helper updated from ZIP to $ref"
  fi
}

cmd_update() {
  set +e
  local DRY_RUN=0 VERSION="" TARGET_OS="" FORCE=0 API=0 AUTO_YES=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) DRY_RUN=1; shift ;;
      --version) VERSION="${2:-}"; shift 2 ;;
      --os)      TARGET_OS="${2:-}"; shift 2 ;;
      --force)   FORCE=1; shift ;;
      --api)     API=1; AUTO_YES=1; FORCE=1; shift ;;
      --yes)     AUTO_YES=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      -h|--help) show_main_help; set -e; return 0 ;;
      *) if [[ -z "$VERSION" ]]; then VERSION="$1"; shift; continue; fi
         if [[ -z "$TARGET_OS" ]]; then TARGET_OS="$1"; shift; continue; fi
         shift ;;
    esac
  done

  need_root
  [[ -x "$STOP_CMD"  ]] || { echo "Stop script not found/executable: $STOP_CMD"; set -e; return 0; }
  [[ -x "$START_CMD" ]] || { echo "Start script not found/executable: $START_CMD"; set -e; return 0; }

  if [[ -z "$VERSION" ]]; then
    if (( API==1 )); then echo "--api requires --version <ver>"; set -e; return 0; fi
    read -rp "Enter SurgeMail version (e.g. 80e) or leave blank to exit: " VERSION
    [[ -n "$VERSION" ]] || { echo -e "\nExiting SurgeMail update without change.\n"; set -e; return 0; }
  fi
  if [[ -z "$TARGET_OS" ]]; then
    TARGET_OS="$(detect_os_target || true)"
    if [[ -z "$TARGET_OS" ]]; then
      if (( API==1 )); then echo "--api requires --os when OS cannot be auto-detected"; set -e; return 0; fi
      TARGET_OS="$(choose_os_menu)"
    fi
  fi

  resolve_artifact "$VERSION" "$TARGET_OS"
  local FILENAME="$ARTIFACT"
  local PROG_OPT; PROG_OPT="$(detect_wget_progress_opt)"
  vlog "Using wget progress option: $PROG_OPT"

  echo -e "\n1) Checking availability: $URL"
  wget --spider -q "$URL"
  if [[ $? -ne 0 ]]; then echo "Package not found at: $URL (check version/OS)."; set -e; return 0; fi

  WORKDIR="$(mktemp -d -t surgemail-update-XXXXXXXX)"
  echo "Using temp dir: $WORKDIR"
  cd "$WORKDIR"

  echo -e "\n2) Downloading: $URL"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ $VERBOSE -eq 1 ]]; then
      wget $PROG_OPT "$URL" -O "$FILENAME"; rc=$?
    else
      wget $PROG_OPT "$URL" -O "$FILENAME" >/dev/null 2>&1; rc=$?
    fi
    if [[ $rc -ne 0 ]]; then echo "wget failed"; set -e; return 0; fi
  else
    echo "[dry-run] wget $PROG_OPT \"$URL\" -O \"$FILENAME\""
    printf 'placeholder\n' > "$FILENAME"
  fi

  if [[ "$DRY_RUN" -eq 0 ]]; then
    if [[ ! -s "$FILENAME" ]]; then echo "Downloaded file is empty: $FILENAME"; set -e; return 0; fi
  fi
  local size; size="$(du -h -- "$FILENAME" | awk '{print $1}')"
  echo "Download OK: $FILENAME ($size)"

  if [[ "$FILENAME" == *.exe ]]; then
    echo -e "\n3) Detected Windows artifact (.exe)"
    echo "This Unix script does not execute Windows installers."
    echo "Saved file: $WORKDIR/$FILENAME"
    set -e; return 0
  fi

  echo -e "\n3) Extracting archive"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    tar -xzf "$FILENAME"
    if [[ $? -ne 0 ]]; then echo "Extraction failed."; set -e; return 0; fi
  else
    echo "[dry-run] tar -xzf \"$FILENAME\""
    mkdir -p mtemp
  fi
  [[ -d "mtemp" ]] || { echo "Expected 'mtemp' directory after extraction."; set -e; return 0; }

  echo -e "\n4) Stopping SurgeMail"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    set -e; cmd_stop ${VERBOSE:+--verbose}; set +e
  else
    echo "[dry-run] strong_stop + free ports"
  fi

  echo -e "\n5) Running installer"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    cd mtemp
    [[ -x "./install.sh" ]] || { echo "install.sh not found or not executable in mtemp/"; set -e; return 0; }

    if (( AUTO_YES==1 )); then
      if have expect; then
        cat > "$WORKDIR/auto_install.exp" <<'EXP'
#!/usr/bin/expect -f
set timeout 600
log_user 1
spawn ./install.sh
set exit_code 0
expect {
  -re {(?i)Do you wish to upgrade.*\[[yY]\]\?} { send -- "y\r"; exp_continue }
  -re {(?i)agree.*license.*\[[yY]\]\?}         { send -- "y\r"; exp_continue }
  eof { set st [wait]; set exit_code [lindex $st 3] }
  timeout { puts "TIMEOUT waiting for installer prompts."; exit 124 }
}
exit $exit_code
EXP
        chmod 0755 "$WORKDIR/auto_install.exp"
        "$WORKDIR/auto_install.exp"; istat=$?
      elif have socat; then
        printf "y\ny\n" | socat - "EXEC:./install.sh,pty,ctty,setsid"; istat=$?
      else
        echo "--api/--yes requires 'expect' or 'socat' to drive the installer without a TTY. Install one: apt-get install -y expect (or: socat)."
        set -e; return 0
      fi
    else
      ./install.sh; istat=$?
    fi
    if [[ $istat -ne 0 ]]; then echo "Installation failed or exited with status $istat."; set -e; return 0; fi
  else
    echo "[dry-run] (cd mtemp && ./install.sh) (auto-answers in --api/--yes mode)"
  fi

  # --------------------- Step 6: Start **only if needed** ---------------------
  echo -e "\n6) Start/Verify SurgeMail"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    set -e
    # Determine what version we expect after install, and what is currently reported.
    local expected_norm="$VERSION"
    local current_norm=""; local current_pretty=""
    if command -v tellmail >/dev/null 2>&1; then
      local tv; tv="$(tellmail version 2>/dev/null || true)"
      current_norm="$(norm_version "$tv")"
      if [[ -n "$current_norm" ]]; then current_pretty="$(pretty_from_norm "$current_norm")"; fi
    fi

    if is_surgemail_ready && [[ -n "$current_norm" ]]; then
      if [[ "$current_norm" == "$expected_norm" ]]; then
        echo "SurgeMail is already running at the expected version (${current_pretty}). Skipping explicit start."
      else
        echo "SurgeMail is running but reports version ${current_pretty} (expected $(pretty_from_norm "$expected_norm"))."
        echo "Performing a controlled restart to load the new version..."
        "$STOP_CMD" || true
        wait_for_stopped 20 || true
        if [[ $VERBOSE -eq 1 ]]; then "$START_CMD" || true; else "$START_CMD" >"$WORKDIR/start_fix.out" 2>&1 || true; echo "(details: $WORKDIR/start_fix.out)"; fi
      fi
    else
      echo "SurgeMail is not running (or not healthy). Starting now..."
      if [[ $VERBOSE -eq 1 ]]; then
        "$START_CMD" || true
      else
        "$START_CMD" >"$WORKDIR/start.out" 2>&1 || true
        echo "(details: $WORKDIR/start.out)"
      fi
    fi
    set +e
  else
    echo "[dry-run] would check tellmail status/version and start only if needed"
  fi
  # ---------------------------------------------------------------------------

  echo -e "\n6.1) Verifying SurgeMail startup"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    set -e
    if wait_for_ready 45; then
      echo "SurgeMail looks healthy."
    else
      echo "Service not healthy yet; performing extra stop + start..."
      "$STOP_CMD" || true
      if wait_for_stopped 20; then echo "Confirmed SurgeMail has stopped (extra cycle)."; fi
      if [[ $VERBOSE -eq 1 ]]; then "$START_CMD" || true; else "$START_CMD" >"$WORKDIR/start2.out" 2>&1 || true; echo "(details: $WORKDIR/start2.out)"; fi
      echo "Re-checking service health..."
      if wait_for_ready 45; then
        echo "SurgeMail is healthy after extra stop/start."
      else
        echo "SurgeMail failed to reach a healthy state after extra stop/start. Check logs in $SURGEMAIL_DIR/logs."
      fi
    fi
    set +e
  else
    echo "[dry-run] verify health; extra stop/start if needed"
  fi

  echo -e "\nAll done. Surgemail script v${SCRIPT_VERSION}. Updated to version ${VERSION} (OS: ${TARGET_OS}).\n"
  set -e; return 0
}

cmd_diagnostics() {
  local script_path; script_path="$(smh_script_path)"
  local t_found="no"; have_cmd "$TELLMAIL_BIN" && t_found="yes"
  local running="no"; is_running && running="yes"
  echo "=== SurgeMail Helper Diagnostics ==="
  printf "Helper version : v%s\n" "$HELPER_VERSION"
  printf "Script path    : %s\n" "$script_path"
  printf "Service name   : %s\n" "$SERVICE_NAME"
  printf "tellmail bin   : %s (found: %s)\n" "$TELLMAIL_BIN" "$t_found"
  printf "Service mgr    : %s\n" "$service_mgr"
  printf "Running        : %s\n" "$running"
  printf "GH_OWNER/REPO  : %s / %s\n" "$GH_OWNER" "$GH_REPO"
  printf "Helper base    : %s\n" "$(smh_base_dir)"
}

man_cmd() {
  if command -v man >/dev/null 2>&1 && [[ -r "/usr/local/share/man/man1/surgemail.1" ]]; then
    man surgemail
  else
    usage
  fi
}

# ---- Parse args ----
CMD="${1:-}"; shift || true
NO_SELFCHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tellmail) TELLMAIL_BIN="$2"; shift 2;;
    --service)  SERVICE_NAME="$2"; shift 2;;
    --no-selfcheck) NO_SELFCHECK=1; shift;;
    -s) CMD="status"; shift;;
    -r) CMD="reload"; shift;;
    -u) CMD="update"; shift;;
    -d) CMD="diagnostics"; shift;;
    -v) CMD="version"; shift;;
    -w) CMD="where"; shift;;
    -h) CMD="help"; shift;;
    *) break;;
  esac
done

case "$CMD" in
  status)             cmd_status ;;
  start)              cmd_start ;;
  stop)               cmd_stop ;;
  strong_stop)        cmd_strong_stop ;;
  restart)            cmd_restart ;;
  reload)             cmd_reload ;;
  check_update)       cmd_check_update ;;
  update)             cmd_update "$@" ;;
  self_check_update)  cmd_self_check_update ;;
  self_update)        cmd_self_update "$@" ;;
  diagnostics)        cmd_diagnostics ;;
  version)            cmd_version ;;
  where)              cmd_where ;;
  man)                man_cmd ;;
  ""|help)            usage ;;
  *)                  echo "Unknown command: $CMD"; usage; exit 2 ;;
esac
