#!/usr/bin/env bash
# ============================================================================
# Surgemail Control & Updater (Unix)
# Version: 1.14.7 (2025-08-10)
#
# ©2025 LERCH design. All rights reserved. https://www.lerchdesign.com. DO NOT REMOVE.
#
# Changelog (embedded summary; see external CHANGELOG.md if bundled)
# v1.13.2 (2025-08-10)
#   - UPDATE: In `update` Step 6, only start SurgeMail if it's not already running
#             at the new version (install.sh typically restarts it). If running
#             but version differs, perform a controlled restart; otherwise skip start.
# v1.13.1 (2025-08-10)
#   - FIX: strong_stop() now uses `tellmail shutdown` for a clean stop.
#   - FIX: cmd_status() brace/else syntax corrected.
# v1.13.0 (2025-08-10)
#   - Added `status` (runs `tellmail status`) and `version` (runs `tellmail version`) commands.
# v1.12.4 (2025-08-10)
#   - check-update: improved parsing of "Current Release 80e"; interactive upgrade prompt.
#   - Non-interactive prints a concrete command with detected OS, or lists valid --os options.
# v1.12.3 (2025-08-10)
#   - Robust version parsing and safer comparator; interactive upgrade prompt.
# v1.12.2 (2025-08-10)
#   - Prevent silent exits in update/check-update under `set -e`.
# v1.12.1 (2025-08-10)
#   - Syntax hardening; minor fixes.
# v1.12.0 (2025-08-10)
#   - `check-update` always prints installed/latest; --auto announces action.
# v1.11.0 (2025-08-10)
#   - `stop` frees all standard mail/admin ports.
# v1.10.0 (2025-08-10)
#   - Introduced `--api` unattended installer driving (requires `expect` or `socat` on Unix).
# ============================================================================

set -euo pipefail
SCRIPT_VERSION="1.14.7"

# --- config ---

# --- GitHub self-update settings ---
GH_OWNER="${GH_OWNER:-mrlerch}"
GH_REPO="${GH_REPO:-SurgeMail-Helper}"
HELPER_VERSION="1.14.7"
SURGEMAIL_DIR="/usr/local/surgemail"
STOP_CMD="$SURGEMAIL_DIR/surgemail_stop.sh"
START_CMD="$SURGEMAIL_DIR/surgemail_start.sh"
PID_FILE="$SURGEMAIL_DIR/surgemail.pid"
ADMIN_URL="http://127.0.0.1:7025/"
CHECK_PORTS="25 465 587 110 143 993 995 7025"
VERBOSE=${VERBOSE:-0}  # 0=quiet, 1=verbose

# --- helpers ---

auth_headers() {
  local args=(-H "User-Agent: surgemail-helper/1.14.7" )
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
# Compare semantic versions vA.B.C; prints LT/EQ/GT
semver_cmp() {
  local a="${1#v}"; local b="${2#v}"
  local IFS=.
  read -r a1 a2 a3 <<<"$a"
  read -r b1 b2 b3 <<<"$b"
  a1=${a1:-0}; a2=${a2:-0}; a3=${a3:-0}
  b1=${b1:-0}; b2=${b2:-0}; b3=${b3:-0}
  if ((10#$a1<10#$b1)); then echo LT; return; fi
  if ((10#$a1>10#$b1)); then echo GT; return; fi
  if ((10#$a2<10#$b2)); then echo LT; return; fi
  if ((10#$a2>10#$b2)); then echo GT; return; fi
  if ((10#$a3<10#$b3)); then echo LT; return; fi
  if ((10#$a3>10#$b3)); then echo GT; return; fi
  echo EQ
}
die() { echo "Error: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }
vlog() { [[ "$VERBOSE" -eq 1 ]] && echo "[debug] $*"; }
need_root() { [ "$(id -u)" -eq 0 ] || die "Please run as root (sudo)."; }
have() { command -v "$1" >/dev/null 2>&1; }
is_tty() { [[ -t 0 ]] && [[ -t 1 ]]; }

cleanup() { if [[ -n "${WORKDIR:-}" && -d "$WORKDIR" ]]; then rm -rf "$WORKDIR"; fi; }
trap 'echo "Failed on line $LINENO."; cleanup' ERR INT
trap 'cleanup' EXIT

show_main_help() {
  cat <<'EOF'
Usage: surgemail <command> [options]

Commands:
  update        Download and install a specified SurgeMail version
                Options:
                  --version <ver>   e.g. 80e (NOT the full artifact name)
                  --os <target>     windows64 | windows | linux64 | linux |
                                    solaris_i64 | freebsd64 |
                                    macosx_arm64 | macosx_intel64
                  --api             API/cron mode: no prompts, auto-answers, defaults --force
                  --yes             Auto-answer installer prompts (like --api answering)
                  --force           Kill ANY processes blocking required ports at start
                  --dry-run         Simulate actions without changes
                  --verbose         Show detailed debug output
  check-update  Detect installed version and compare with latest online
                Options:
                  --os <target>     Artifact OS (auto-detected if omitted)
                  --auto            If newer exists, run 'update --api' automatically
                  --verbose         Show details
  stop          Stop SurgeMail AND free required ports (kills blockers)
  start         Start the SurgeMail server (use --force to kill blockers)
  restart       Stop then start the SurgeMail server (use --force to kill blockers)
  reload        Reload SurgeMail configuration via 'tellmail reload'
  status        Show current SurgeMail status via 'tellmail status'
  version       Show installed SurgeMail version via 'tellmail version'
  -h | --help   Show this help
EOF
}

# ---------- status & waits ----------
is_surgemail_ready() {
  if command -v tellmail >/dev/null 2>&1 && tellmail status >/dev/null 2>&1; then return 0; fi
  if [[ -f "$PID_FILE" ]]; then
    local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
  fi
  if have curl && curl -sSf -o /dev/null --max-time 2 "$ADMIN_URL" 2>/dev/null; then return 0; fi
  return 1
}
wait_for_ready()   { local t=0; local timeout="${1:-45}"; while ((t<timeout)); do is_surgemail_ready && return 0; sleep 1; t=$((t+1)); done; return 1; }
wait_for_stopped() { local t=0; local timeout="${1:-20}"; while ((t<timeout)); do ! is_surgemail_ready && return 0; sleep 1; t=$((t+1)); done; return 1; }

# ---------- stop / kill helpers ----------
strong_stop() {
  vlog "Invoking STOP_CMD: $STOP_CMD"
  "$STOP_CMD" || true
  if command -v tellmail >/dev/null 2>&1; then
    vlog "tellmail shutdown"
    tellmail shutdown >/dev/null 2>&1 || true
  fi
  if [[ -f "$PID_FILE" ]]; then
    local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      vlog "Killing PID from file: $pid"
      kill "$pid" 2>/dev/null || true
      sleep 2
      kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    fi
  fi
  # Best-effort: kill any clearly Surgemail/Startmail listeners on common ports
  if have lsof; then
    for p in $CHECK_PORTS; do
      while read -r _cmd _pid _rest; do
        case "$_cmd" in
          surgemail*|startmail*)
            vlog "Killing leftover $_cmd (pid $_pid) on port $p"
            kill "$_pid" 2>/dev/null || true
            sleep 1
            kill -0 "$_pid" 2>/dev/null && kill -9 "$_pid" 2>/dev/null || true
          ;;
        esac
      done < <(lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1, $2}')
    done
  fi
}

# List blockers: prints "pid cmd port"
list_blockers_detailed() {
  if command -v lsof >/dev/null 2>&1; then
    for p in $CHECK_PORTS; do
      lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | awk -v port="$p" 'NR>1 {print $2, $1, port}'
    done
    return 0
  elif command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | awk '
      /LISTEN/ && match($4, /:([0-9]+)$/, m) {
        port=m[1];
        if (port ~ /^(25|465|587|110|143|993|995|7025)$/) {
          proc="unknown"; pid="?";
          if (match($0,/users:\(\("([^"]+)".*pid=([0-9]+)/,a)){proc=a[1]; pid=a[2]}
          print pid, proc, port
        }
      }'
    return 0
  fi
  return 1
}

# Kill everything blocking our ports
force_kill_all_blockers() {
  local any=1
  while read -r pid cmd port; do
    any=0
    vlog "Killing blocker pid=$pid cmd=$cmd port=$port"
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    echo "[force] Killed pid $pid: $cmd (port $port)"
  done < <(list_blockers_detailed || true)
  return $any  # 0 if killed something
}

# ---------- artifact / wget / version ----------
resolve_artifact() {
  local ver="$1" os="$2" suffix ext
  case "$os" in
    windows64)      suffix="windows64";      ext="exe" ;;
    windows)        suffix="windows";        ext="exe" ;;
    linux64)        suffix="linux64";        ext="tar.gz" ;;
    linux)          suffix="linux";          ext="tar.gz" ;;
    solaris_i64)    suffix="solaris_i64";    ext="tar.gz" ;;
    freebsd64)      suffix="freebsd64";      ext="tar.gz" ;;
    macosx_arm64)   suffix="macosx_arm64";   ext="tar.gz" ;;
    macosx_intel64) suffix="macosx_intel64"; ext="tar.gz" ;;
    *) die "Unknown --os '$os'. See --help." ;;
  esac
  ARTIFACT="surgemail_${ver}_${suffix}.${ext}"
  URL="https://netwinsite.com/ftp/surgemail/${ARTIFACT}"
}

detect_wget_progress_opt() {
  have wget || die "wget is required."
  local ver_str major minor
  ver_str="$(wget --version | head -n1 | awk '{print $3}')"
  major=${ver_str%%.*}
  minor=${ver_str#*.}; minor=${minor%%.*}
  if (( ${major:-0} > 1 )) || ( (( ${major:-0} == 1 )) && (( ${minor:-0} >= 16 )) ); then
    echo "--show-progress"
  else
    echo "--progress=bar:force"
  fi
}

norm_version() {
  local s="$*"
  s="${s#*Version }"; s="${s%%,*}"
  if [[ "$s" =~ ^([0-9]+)\.([0-9]+)([A-Za-z]).* ]]; then
    printf "%d%d%s" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3],,}"
  else
    echo ""
  fi
}

pretty_from_norm() {
  local n="$1"
  if [[ "$n" =~ ^([0-9]{2})([a-z])$ ]]; then
    echo "${BASH_REMATCH[1]:0:1}.${BASH_REMATCH[1]:1:1}${BASH_REMATCH[2]}"
  else
    echo "$n"
  fi
}

# Safe comparator for normalized tokens like "80e"
cmp_versions() {
  local a="$1" b="$2"
  [[ "$a" == "$b" ]] && { echo 0; return; }
  local aN aL bN bL
  if [[ "$a" =~ ^([0-9]+)([A-Za-z])$ ]]; then
    aN="${BASH_REMATCH[1]}"; aL="${BASH_REMATCH[2],,}"
  else
    echo 0; return
  fi
  if [[ "$b" =~ ^([0-9]+)([A-Za-z])$ ]]; then
    bN="${BASH_REMATCH[1]}"; bL="${BASH_REMATCH[2],,}"
  else
    echo 0; return
  fi
  if ((10#$aN > 10#$bN)); then echo 1; return; fi
  if ((10#$aN < 10#$bN)); then echo 2; return; fi
  if [[ "$aL" > "$bL" ]]; then echo 1; return; fi
  if [[ "$aL" < "$bL" ]]; then echo 2; return; fi
  echo 0
}

detect_installed_version() {
  local out=""
  if command -v tellmail >/dev/null 2>&1; then out="$(tellmail version 2>/dev/null || true)"; fi
  [[ -n "$out" ]] || { echo ""; return; }
  norm_version "$out"
}

detect_os_target() {
  local plat=""
  if command -v tellmail >/dev/null 2>&1; then
    plat="$(tellmail version 2>/dev/null | sed -n 's/.*Platform[[:space:]]\+//p' | tr -d '\r' || true)"
  fi
  case "${plat,,}" in
    *linux_64*) echo "linux64"; return ;;
    *linux*)    echo "linux";   return ;;
    *freebsd*)  echo "freebsd64"; return ;;
    *solaris*|*sunos*) echo "solaris_i64"; return ;;
    *macosx*arm*) echo "macosx_arm64"; return ;;
    *macosx*intel*|*darwin*x86*) echo "macosx_intel64"; return ;;
    *windows*64*) echo "windows64"; return ;;
    *windows*) echo "windows"; return ;;
  esac
  local sys arch
  sys="$(uname -s 2>/dev/null || echo unknown)"
  arch="$(uname -m 2>/dev/null || echo unknown)"
  case "$sys" in
    Linux)   [[ "$arch" =~ 64 ]] && echo "linux64" || echo "linux" ;;
    FreeBSD) echo "freebsd64" ;;
    SunOS)   echo "solaris_i64" ;;
    Darwin)  [[ "$arch" == "arm64" ]] && echo "macosx_arm64" || echo "macosx_intel64" ;;
    *)       echo "" ;;
  esac
}

choose_os_menu() {
  local options=("linux64" "linux" "freebsd64" "solaris_i64" "macosx_arm64" "macosx_intel64" "windows64" "windows")
  echo "Select target OS for artifact:"
  local i=1; for o in "${options[@]}"; do echo "  $i) $o"; i=$((i+1)); done
  local sel
  while true; do
    read -rp "Enter number (1-${#options[@]}): " sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel>=1 && sel<=${#options[@]} )); then
      echo "${options[$((sel-1))]}"; return
    fi
    echo "Invalid selection."
  done
}

# ---------- subcommands ----------
cmd_check_update() {
  set +e
  local TARGET_OS="" AUTO=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --os) TARGET_OS="${2:-}"; shift 2 ;;
      --auto) AUTO=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      -h|--help) echo "Usage: surgemail check-update [--os <target>] [--auto] [--verbose]"; set -e; return 0 ;;
      *) shift ;;
    esac
  done

  local installed_pretty="" installed_norm=""
  if command -v tellmail >/dev/null 2>&1; then
    local tv; tv="$(tellmail version 2>/dev/null || true)"
    installed_pretty="$(echo "$tv" | grep -Eo '[0-9]+\.[0-9]+[A-Za-z]' | head -n1)"
    installed_norm="$(norm_version "$tv")"
  fi
  if [[ -z "$installed_pretty" && -n "$installed_norm" && "$installed_norm" =~ ^([0-9]{2})([a-z])$ ]]; then
    installed_pretty="${BASH_REMATCH[1]:0:1}.${BASH_REMATCH[1]:1:1}${BASH_REMATCH[2]}"
  fi
  [[ -n "$installed_pretty" ]] || installed_pretty="unknown"

  local html=""
  if have curl; then
    html="$(curl -fsSL https://surgemail.com/download-surgemail/ 2>/dev/null || true)"
    [[ -z "$html" ]] && html="$(curl -fsSL https://surgemail.com/knowledge-base/surgemail-change-history/ 2>/dev/null || true)"
  else
    html="$(wget -qO- https://surgemail.com/download-surgemail/ 2>/dev/null || true)"
    [[ -z "$html" ]] && html="$(wget -qO- https://surgemail.com/knowledge-base/surgemail-change-history/ 2>/dev/null || true)"
  fi

  local latest_compact="" latest_pretty="" latest_norm=""
  if [[ -n "$html" ]]; then
    local one; one="$(echo "$html" | tr '\n' ' ')"
    latest_compact="$(echo "$one" | sed -n 's/.*[Cc]urrent[[:space:]]*[Rr]elease[^0-9A-Za-z]*\([0-9][0-9][A-Za-z]\).*/\1/p' | head -n1)"
  fi
  if [[ -n "$latest_compact" ]]; then
    latest_norm="$latest_compact"
    latest_pretty="$(printf "%s.%s%s" "${latest_compact:0:1}" "${latest_compact:1:1}" "${latest_compact:2:1}")"
  else
    local tokens=()
    if [[ -n "$html" ]]; then
      while IFS= read -r tok; do tokens+=("$tok"); done < <(echo "$html" | grep -Eo '[7-9]\.[0-9]+[A-Za-z]' | sort -u)
    fi
    if (( ${#tokens[@]} > 0 )); then
      local best_norm="" best_pretty=""
      for t in "${tokens[@]}"; do
        local n; n="$(norm_version "Version $t,")"
        [[ -z "$n" ]] && continue
        if [[ -z "$best_norm" ]]; then best_norm="$n"; best_pretty="$t"
        else
          case "$(cmp_versions "$n" "$best_norm")" in 1) best_norm="$n"; best_pretty="$t" ;; esac
        fi
      done
      latest_norm="$best_norm"; latest_pretty="$best_pretty"
    fi
  fi

  if [[ -z "$latest_pretty" || -z "$latest_norm" ]]; then
    echo "Installed SurgeMail version: $installed_pretty"
    echo "Could not parse the latest stable version from the website."
    set -e; return 0
  fi

  echo "Installed SurgeMail version: $installed_pretty"
  echo "Latest stable release:       $latest_pretty"

  if [[ -z "$installed_norm" ]]; then
    echo "Note: Unable to compare versions automatically (tellmail not found or unrecognized output)."
    set -e; return 0
  fi

  case "$(cmp_versions "$installed_norm" "$latest_norm")" in
    0)
      echo "You are running the latest stable release."
      [[ "$AUTO" -eq 1 ]] && echo "[auto] No update necessary."
      set -e; return 0
      ;;
    1)
      echo "Your installed version appears newer than the published stable. (Installed=$installed_pretty, Latest=$latest_pretty)"
      set -e; return 0
      ;;
    2)
      echo "An update is available. (Installed=$installed_pretty, Latest=$latest_pretty)"
      if [[ "$AUTO" -eq 1 ]]; then
        [[ -z "$TARGET_OS" ]] && TARGET_OS="$(detect_os_target || true)"
        if [[ -z "$TARGET_OS" ]]; then
          echo "[auto] Could not determine OS. Pass --os (linux64|linux|windows64|windows|freebsd64|solaris_i64|macosx_arm64|macosx_intel64)."
          set -e; return 0
        fi
        echo "[auto] Updating to $(norm_version "Version $latest_pretty,") for OS $TARGET_OS ..."
        set -e
        exec "$0" update --version "$(norm_version "Version $latest_pretty,")" --os "$TARGET_OS" --api ${VERBOSE:+--verbose}
      else
        if [[ -t 0 && -t 1 ]]; then
          read -rp "Upgrade to $latest_pretty now? [y/N]: " ans
          if [[ "${ans,,}" == y || "${ans,,}" == yes ]]; then
            if [[ -z "$TARGET_OS" ]]; then TARGET_OS="$(detect_os_target || true)"; fi
            if [[ -z "$TARGET_OS" ]]; then TARGET_OS="$(choose_os_menu)"; fi
            echo "Starting upgrade to $latest_pretty for OS $TARGET_OS ..."
            set -e
            exec "$0" update --version "$latest_norm" --os "$TARGET_OS"
          else
            local SUGGEST_OS=""; SUGGEST_OS="$(detect_os_target || true)"
            if [[ -n "$SUGGEST_OS" ]]; then
              echo "To update later: $0 update --version $latest_norm --os $SUGGEST_OS"
            else
              echo "To update later: $0 update --version $latest_norm --os (linux64|linux|windows64|windows|freebsd64|solaris_i64|macosx_arm64|macosx_intel64)"
            fi
            set -e; return 0
          fi
        else
          local SUGGEST_OS=""; SUGGEST_OS="$(detect_os_target || true)"
          if [[ -n "$SUGGEST_OS" ]]; then
            echo "To update now: $0 update --version $latest_norm --os $SUGGEST_OS"
          else
            echo "To update now: $0 update --version $latest_norm --os (linux64|linux|windows64|windows|freebsd64|solaris_i64|macosx_arm64|macosx_intel64)"
          fi
          set -e; return 0
        fi
      fi
      ;;
  esac
  set -e; return 0
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

cmd_stop() {
  while [[ $# -gt 0 ]]; do case "$1" in --verbose) VERBOSE=1; shift ;; *) shift ;; esac; done
  need_root
  [[ -x "$STOP_CMD" ]] || die "Stop script missing: $STOP_CMD"
  echo "Requested: stop SurgeMail."
  set +e
  local was_running=1
  if is_surgemail_ready; then was_running=0; echo "Status before: running."; else echo "Status before: not running (or not healthy)."; fi
  strong_stop
  echo "Freeing required ports (25,465,587,110,143,993,995,7025)..."
  if force_kill_all_blockers; then vlog "Blockers killed during stop."; fi
  t=0; while (( t < 20 )); do if ! is_surgemail_ready; then echo "Result: SurgeMail stopped and ports freed."; set -e; return 0; fi; sleep 1; t=$((t+1)); done
  echo "Result: stop requested; made best effort to free ports."
  (( was_running != 0 )) && echo "Note: service appeared down before the stop request."
  set -e; return 0
}

cmd_start() {
  local FORCE=0; while [[ $# -gt 0 ]]; do case "$1" in --force) FORCE=1; shift ;; --verbose) VERBOSE=1; shift ;; *) shift ;; esac; done
  need_root; [[ -x "$START_CMD" ]] || die "Start script missing: $START_CMD"
  echo "Requested: start SurgeMail."
  if is_surgemail_ready; then echo "Status before: already running (or healthy). Proceeding to start anyway."; else echo "Status before: not running."; fi
  if [[ "$FORCE" -eq 1 ]]; then if force_kill_all_blockers; then vlog "Forced kill of blockers before start."; fi; fi
  if [[ $VERBOSE -eq 1 ]]; then "$START_CMD" || true; else "$START_CMD" >"${WORKDIR:-/tmp}/start.manual.out" 2>&1 || true; echo "(details: ${WORKDIR:-/tmp}/start.manual.out)"; fi
  if wait_for_ready 45; then echo "Result: SurgeMail started and is healthy."; else echo "Result: start issued, but not healthy within 45s. Check $SURGEMAIL_DIR/logs."; exit 1; fi
}

cmd_restart() {
  local FORCE=0; while [[ $# -gt 0 ]]; do case "$1" in --force) FORCE=1; shift ;; --verbose) VERBOSE=1; shift ;; *) shift ;; esac; done
  need_root; [[ -x "$STOP_CMD"  ]] || die "Stop script missing: $STOP_CMD"; [[ -x "$START_CMD" ]] || die "Start script missing: $START_CMD"
  echo "Requested: restart SurgeMail (stop → start)."
  if is_surgemail_ready; then echo "Status before: running."; else echo "Status before: not running (or not healthy)."; fi
  cmd_stop --verbose
  if [[ "$FORCE" -eq 1 ]]; then if force_kill_all_blockers; then vlog "Forced kill of blockers before restart."; fi; fi
  if [[ $VERBOSE -eq 1 ]]; then "$START_CMD" || true; else "$START_CMD" >"${WORKDIR:-/tmp}/restart.out" 2>&1 || true; echo "(details: ${WORKDIR:-/tmp}/restart.out)"; fi
  if wait_for_ready 45; then echo "Step 2/2: Started and healthy."; else echo "Step 2/2: Start issued, but not healthy within 45s."; exit 1; fi
}

cmd_reload() {
  echo "Requested: reload SurgeMail configuration."
  if command -v tellmail >/dev/null 2>&1; then
    if tellmail reload >/dev/null 2>&1; then echo "Result: configuration reload sent."; else echo "Result: 'tellmail reload' returned non-zero. Ensure service is running."; exit 1; fi
  else
    echo "Result: 'tellmail' not found in PATH. Cannot reload configuration."; exit 1
  fi
}

cmd_status() {
  echo "Requested: status"
  if command -v tellmail >/dev/null 2>&1; then
    if ! tellmail status; then
      echo "Note: 'tellmail status' returned non-zero. Service may be down or unresponsive." >&2
      return 1
    fi
  else
    echo "Result: 'tellmail' not found in PATH. Cannot query status."
    return 1
  fi
}

cmd_version() {
  echo "Requested: version"
  if ! command -v tellmail >/dev/null 2>&1; then
    echo "Result: 'tellmail' not found in PATH. Cannot query version."
    return 1
  fi
  local out
  out="$(tellmail version 2>/dev/null || true)"
  if [[ -z "$out" ]]; then
    echo "Result: 'tellmail version' produced no output."
    return 1
  fi
  echo "$out"
  local pretty=""
  pretty="$(echo "$out" | grep -Eo '[0-9]+\.[0-9]+[A-Za-z]' | head -n1)"
  if [[ -n "$pretty" ]]; then
    echo "Installed SurgeMail version (parsed): $pretty"
  fi
}


# ---------- Helper self-update ----------
smh_script_path() { readlink -f "$0" 2>/dev/null || echo "$0"; }
smh_base_dir()    { local p; p="$(dirname "$(smh_script_path)")"; dirname "$p"; }
is_git_checkout() { [[ -d "$(smh_base_dir)/.git" ]]; }

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

  local rel="$(semver_cmp "v$SCRIPT_VERSION" "$latest_v")"
  if [[ "$rel" == "LT" ]]; then
    echo "You are running SurgeMail Helper script v$SCRIPT_VERSION. The latest version is $latest_v."
    if [[ -t 0 && -t 1 ]]; then
      read -r -p "Would you like to upgrade? y/n " ans
      if [[ "${ans,,}" =~ ^y ]]; then cmd_self_update "$latest_v"; else echo "Ok, maybe next time. Thanks for using SurgeMail Helper."; fi
    else
      echo "Run: $0 self_update $latest_v"
    fi
  elif [[ "$rel" == "GT" ]]; then
    echo "Local version (v$SCRIPT_VERSION) is newer than GitHub latest ($latest_v)."
    if [[ -t 0 && -t 1 ]]; then
      read -r -p "Downgrade to $latest_v? y/n " ans
      if [[ "${ans,,}" =~ ^y ]]; then cmd_self_update "$latest_v"; else echo "Keeping current version."; fi
    fi
  else
    echo "You are running the latest SurgeMail Helper script version v$SCRIPT_VERSION"
  fi
}

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

cmd_self_update() {
  local ref="${1:-}"
  [[ -z "$ref" ]] && ref="$(latest_ref || true)"
  [[ -z "$ref" ]] && { echo "Could not determine latest release/tag/default branch from GitHub."; return 1; }

  # Determine target version if ref is branch
  local target_v="$ref"
  if [[ ! "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    local txt
    txt=$(curl -sSfL -H "User-Agent: surgemail-helper/$HELPER_VERSION" "https://raw.githubusercontent.com/$GH_OWNER/$GH_REPO/$ref/scripts/surgemail-helper.sh" 2>/dev/null || true)
    target_v=$(printf '%s\n' "$txt" | grep -Eo 'HELPER_VERSION="?([0-9]+\.[0-9]+\.[0-9]+)"?' -m1 | sed -E 's/.*"?([0-9]+\.[0-9]+\.[0-9]+)".*/v\1/')
    [[ -z "$target_v" ]] && target_v="v0.0.0"
  fi

  # Guard against unintended downgrade without prompt
  local rel="$(semver_cmp "v$SCRIPT_VERSION" "$target_v")"
  if [[ "$rel" == "GT" ]] && [[ -t 0 && -t 1 ]]; then
    echo "Requested version $target_v is older than current v$SCRIPT_VERSION."
    read -r -p "Downgrade anyway? y/n " ans
    [[ "${ans,,}" =~ ^y ]] || { echo "Aborting downgrade."; return 1; }
  fi

  if [[ -d "$(smh_base_dir)/.git" ]]; then
    ( cd "$(smh_base_dir)" && git fetch --tags && git checkout "$ref" || true && git pull --ff-only ) || { echo "Git update failed."; return 1; }
    echo "Helper updated via git to $ref"
  else
    download_and_overlay_zip "$ref" || return 1
    echo "Helper updated from ZIP to $ref"
  fi
}


# ------------- Short flags mapping -------------
if [[ "${1:-}" =~ ^- ]]; then
  case "$1" in
    -s) set -- status "${@:2}" ;;
    -r) set -- reload "${@:2}" ;;
    -u) set -- update "${@:2}" ;;
    -d) set -- diagnostics "${@:2}" ;;
    -v) set -- version "${@:2}" ;;
    -w) set -- where "${@:2}" ;;
    -h) set -- -h "${@:2}" ;;
  esac
fi

# --------------------------- Router ----------------------------
case "${1:-}" in
  update)        shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_update "$@";;
  check-update)  shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_check_update "$@";;
  stop)          shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_stop "$@";;
  start)         shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_start "$@";;
  restart)       shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_restart "$@";;
  reload)        shift || true; cmd_reload "$@";;
  status)        shift || true; cmd_status "$@";;
  version)       shift || true; cmd_version "$@";;
  -h|--help|-help|"") show_main_help ;;
  *) echo "Unknown command: $1" >&2; exit 1 ;;
esac
have_cmd() { command -v "$1" >/dev/null 2>&1; }


cmd_where() {
  local script_path base_dir smbin tell_path label bin_path resolved linkto
  script_path="$(readlink -f "$0" 2>/dev/null || echo "$0")"
  base_dir="$(dirname "$(dirname "$script_path")")"
  bin_path="$(command -v surgemail 2>/dev/null || true)"
  if [[ -n "$bin_path" ]]; then
    resolved="$(readlink -f "$bin_path" 2>/dev/null || echo "$bin_path")"
    linkto="$(readlink "$bin_path" 2>/dev/null || true)"
    if [[ "$resolved" == "$script_path" ]] || grep -qi 'surgemail-helper' <<<"$resolved"; then
      label="surgemail helper command"
    else
      label="surgemail binary"
    fi
    smbin="$bin_path ($label)"
  else
    smbin="(not found)"
  fi
  tell_path="$(command -v tellmail 2>/dev/null || true)"
  [[ -z "$tell_path" ]] && tell_path="(not found)"
  echo "helper directory           : $base_dir"
  echo "surgemail command          : $smbin"
  echo "tellmail path              : $tell_path"
  echo "SurgeMail Server directory : /usr/local/surgemail"
}


man_cmd() {
  if command -v man >/dev/null 2>&1 && [[ -r "/usr/local/share/man/man1/surgemail.1" ]]; then
    man surgemail
  else
    show_main_help
  fi
}

