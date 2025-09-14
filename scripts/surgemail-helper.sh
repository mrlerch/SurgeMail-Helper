#!/usr/bin/env bash
# Always run under bash
if [ -z "$BASH_VERSION" ]; then exec /usr/bin/env bash "$0" "$@"; fi
set -euo pipefail

# Source GitHub helpers (kept separate to avoid brace collisions in main file)
# shellcheck source=_gh_helpers.inc.sh
# Resolve this script's real directory (follow symlinks)
if command -v readlink >/dev/null 2>&1; then
  SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
else
  # Fallback: manually resolve symlinks
  SCRIPT_PATH="${BASH_SOURCE[0]}"
  while [ -h "$SCRIPT_PATH" ]; do
    DIR="$(cd -P "$(dirname -- "$SCRIPT_PATH")" && pwd)"
    LINK="$(readlink -- "$SCRIPT_PATH")" || break
    [[ "$LINK" != /* ]] && SCRIPT_PATH="$DIR/$LINK" || SCRIPT_PATH="$LINK"
  done
fi
SCRIPT_DIR="$(cd -P "$(dirname -- "$SCRIPT_PATH")" && pwd)"

# Source helpers from the real script directory
# shellcheck source=_gh_helpers.inc.sh
. "$SCRIPT_DIR/_gh_helpers.inc.sh"

# --- helpers: project path, git check, http download, and zip overlay ---

# Absolute project root (parent of the scripts dir where this file lives)
project_root() {
  # Requires SCRIPT_DIR already set by your header symlink-resolution code
  ( cd "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd )
}

# Do we have a git checkout at project root?
have_git_checkout() {
  [ -d "$(project_root)/.git" ]
}

# Download a URL to a given file (supports GH_TOKEN/GITHUB_TOKEN for private repos)
http_download() {
  # $1=url $2=dest_file
  local url="$1" out="$2" ua="surgemail-helper/1.14.12"
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$token" ]; then
      curl -fSL -o "$out" -H "User-Agent: $ua" -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$url"
    else
      curl -fSL -o "$out" -H "User-Agent: $ua" -H "Accept: application/vnd.github+json" "$url"
    fi
  else
    if [ -n "$token" ]; then
      wget -O "$out" --header="User-Agent: $ua" --header="Authorization: Bearer $token" --header="Accept: application/vnd.github+json" "$url"
    else
      wget -O "$out" --header="User-Agent: $ua" --header="Accept: application/vnd.github+json" "$url"
    fi
  fi
}

# Build a GitHub zip URL for a ref (branch or tag)
gh_zip_url_for_ref() {
  # $1 = owner (default GH_OWNER), $2 = repo (default GH_REPO), $3 = ref (branch/tag)
  local owner="${1:-${GH_OWNER:-mrlerch}}" repo="${2:-${GH_REPO:-SurgeMail-Helper}}" ref="${3:-}"
  [ -n "$ref" ] || return 1
  # e.g. https://api.github.com/repos/OWNER/REPO/zipball/REF
  printf "https://api.github.com/repos/%s/%s/zipball/%s" "$owner" "$repo" "$ref"
}

# Overlay a downloaded zip (branch/tag) onto the project root
overlay_zip_to_root() {
  # $1 = ref (branch or tag)
  local ref="$1"
  local root; root="$(project_root)"
  local tmpdir zipfile
  tmpdir="$(mktemp -d)"; zipfile="$tmpdir/update.zip"

  local url; url="$(gh_zip_url_for_ref "${GH_OWNER:-mrlerch}" "${GH_REPO:-SurgeMail-Helper}" "$ref")" || {
    echo "Invalid ref for zip overlay." >&2; rm -rf "$tmpdir"; return 1; }

  echo "Downloading ZIP for ref '$ref'..."
  if ! http_download "$url" "$zipfile"; then
    echo "Failed to download ZIP from GitHub." >&2
    rm -rf "$tmpdir"; return 1
  fi

  # Unzip to temp; take first top-level dir as payload
  local unpack="$tmpdir/unpack"
  mkdir -p "$unpack"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zipfile" -d "$unpack"
  else
    if command -v busybox >/dev/null 2>&1; then busybox unzip "$zipfile" -d "$unpack" >/dev/null; else
      echo "Need 'unzip' (or busybox) to extract." >&2
      rm -rf "$tmpdir"; return 1
    fi
  fi

  # Find the top-level folder created by GitHub zipball
  local payload
  payload="$(find "$unpack" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  if [ -z "$payload" ]; then
    echo "ZIP payload not found." >&2
    rm -rf "$tmpdir"; return 1
  fi

  echo "Overlaying files onto project root: $root"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete-after --exclude=".git/" "$payload"/ "$root"/
  else
    (cd "$payload" && tar cf - .) | (cd "$root" && tar xpf -)
  fi

  rm -rf "$tmpdir"
  echo "ZIP overlay complete."
}
# --- end helpers ---


# --- TEMP: early diagnostics command (runs before anything else) ---
if [ "${1:-}" = "debug-gh" ]; then
  set +e
  echo "has_curl: $([ -n "$(command -v curl 2>/dev/null)" ] && echo yes || echo no)"
  echo "has_wget: $([ -n "$(command -v wget 2>/dev/null)" ] && echo yes || echo no)"
  echo "has_git:  $([ -n "$(command -v git  2>/dev/null)" ] && echo yes || echo no)"
  echo "latest_release: $(gh_latest_release_tag)"
  echo "first_prerelease: $(gh_first_prerelease_tag)"
  echo "default_branch: $(gh_default_branch)"
  exit 0
fi
# --- /TEMP ---

# ============================================================================
# SurgeMail Helper: Control & Updater (Unix)
# Version: 1.14.12 (2025-09-14)
#
# ©2025 LERCH design. All rights reserved. https://www.lerchdesign.com. DO NOT REMOVE.
#
# SurgeMail Helper — v1.14.12
#
# INSTALL:
# Store the SurgeMail-Helper directory where you wish. IF you want to use the script globally
# you may opt to cd to SurgeMail-Helper and then run the the command below.
#   sudo ln -sf scripts/surgemail-helper.sh /usr/local/bin/surgemail
# Please make sure that /usr/local/bin is in your executable path. If you get the following error:
#   bash: surgemail: command not found
# you need to add this line below to your .bashrc file (in the user's home directory)
#   export PATH="/usr/local/bin:$PATH"
#
# See CHANGELOG.md for details. Use symlink install:
# Changelog (embedded summary; see external CHANGELOG.md if bundled)
# v1.14.12 (- Implemented GitHub helpers for self_check_update/self_update (release/prerelease/dev).
#   - Default unauthenticated GitHub API with optional token via --token or $GITHUB_TOKEN/$GH_TOKEN.
#   - Streamlined start output (single pre-check and single final result).
#   - Help updated to document channels and token usage.
#   # v1.14.10 (- Implemented GitHub helpers for self_check_update/self_update (release/prerelease/dev).
#   - Default unauthenticated GitHub API with optional token via --token or $GITHUB_TOKEN/$GH_TOKEN.
#   - Streamlined start output (single pre-check and single final result).
#   - Help updated to document channels and token usage.
# v1.14.8 (2025-08-12)
#   - Implemented short flags routing (-s, -r, -u, -d, -v, -w, -h) and documented them.
#   - Router now includes where/diagnostics/self_check_update/self_update and help aliases.
#   - Restored and preserved 1.13.2 `update` and `check-update` flows and helpers.
#   - `self_check_update` always prints feedback; `self_update` prompts on downgrade.
#   - `where` labels updated (surgemail helper command, SurgeMail Server directory).
#   - README and man page updated.
# v1.14.6 (2025-08-11)
#   - Implement server `check_update` via `tellmail status` with page fallback.
#   - Fix `is_running` with 10s wait; adjust `start`/`stop`/`reload`/`strong_stop` behavior.
#   - Add short flags and `man` command; implement helper `self_*` clone vs ZIP logic.
# v1.14.2 (2025-08-10)
# Fixed
#   - `diagnostics` now runs cleanly on hosts **without** SurgeMail installed; no syntax errors and no hard failures.
#   - Safer command probes (status/version checks) won’t error if `tellmail`/`surgemail`/service managers are missing.
# Improved
#   - Updated README with **diagnostics** documentation and examples.
# v1.14.1 (2025-08-10)
#   - Restored full helper with verbose diagnostics, locking & self‑update flow.
#   - Windows PowerShell and batch wrapper synced.
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
# v1.6.0 (2025-08-09)
#   - Smoother output: pre-check common ports and summarize blockers
#   - Optional --verbose to stream installer/start output; otherwise capture to files
#   - Cleaner status messages for start/stop/restart/reload
# v1.5.0 (2025-08-09)
#   - API mode for update: --version <ver> (e.g., 80e) and --os <target>
#   - Interactive prompts when values omitted; URL building per OS family
#   - Windows artifacts are downloaded but not executed (manual step)
# v1.4.0 (2025-08-09)
#   - Health verification after start (tellmail/PID/HTTP)
#   - Conditional extra stop+start when initial start looks unhealthy
# v1.3.0 (2025-08-09)
#   - Unified single script: command router (update/stop/start/restart/reload)
#   - Human-friendly explanations after each command
# v1.2.1 (2025-08-09)
#   - Robust --dry-run flow (creates non-empty placeholder; skips strict size check)
#   - Avoid heredoc pitfalls; safer printing
# v1.2.0 (2025-08-09)
#   - Added -h/--help for update; --dry-run; wget progress auto-detect
# v1.1.0 (2025-08-09)
#   - Safer update flow: set -euo pipefail; sudo/root check; mktemp workspace
#   - URL HEAD check; tar -xzf; strict quoting; traps/cleanup
# v1.0.0 (2025-08-09)
#   - Initial dispatcher and basic update/start/stop hooks
# ============================================================================

set -euo pipefail
HELPER_VERSION="1.14.12"
SCRIPT_VERSION="1.14.12"

# --- config ---
SURGEMAIL_DIR="/usr/local/surgemail"
STOP_CMD="$SURGEMAIL_DIR/surgemail_stop.sh"
START_CMD="$SURGEMAIL_DIR/surgemail_start.sh"
PID_FILE="$SURGEMAIL_DIR/surgemail.pid"
ADMIN_URL="http://127.0.0.1:7025/"
CHECK_PORTS="25 465 587 110 143 993 995 7025"
VERBOSE=${VERBOSE:-0}  # 0=quiet, 1=verbose

# --- helpers ---
# ---- GitHub helpers for self-update ----
GH_OWNER="{GH_OWNER:-mrlerch}"
GH_REPO="{GH_REPO:-SurgeMail-Helper}"
smh_script_path() { readlink -f "$0" 2>/dev/null || echo "$0"; }
smh_base_dir()    { local p; p="$(dirname "$(smh_script_path)")"; dirname "$p"; }
is_git_checkout() { [[ -d "$(smh_base_dir)/.git" ]] ; }
auth_headers() {
  local args=(-H "User-Agent: surgemail-helper/1.14.12")
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

die() { echo "Error: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }
vlog() { [[ "$VERBOSE" -eq 1 ]] && echo "[debug] $*"; }
need_root() { [ "$(id -u)" -eq 0 ] || die "Please run as root (sudo)."; }

# Fallback help so we never crash if show_main_help is referenced before it's defined.
# (Safe to keep even if you later add a richer help below; the router just calls this.)
if ! declare -F show_main_help >/dev/null 2>&1; then
  show_main_help() {
  cat <<'EOF'
Usage: surgemail <command> [options]

Commands:
  -u | update       Download and install a specified SurgeMail version
                    Options:
                      --version <ver>   e.g. 80e (NOT the full artifact name)
                      --os <target>     windows64 | windows | linux64 | linux |
                                        solaris_i64 | freebsd64 |
                                        macosx_arm64 | macosx_intel64
                      --api             requires --version, no prompts, auto-answers, --force
                      --yes             Auto-answer installer prompts with y
                      --force           Kill ANY processes blocking required ports at start
                      --dry-run         Simulate actions without changes
                      --verbose         Show detailed debug output
  check-update      Detect installed version and compare with latest online
                    Options:
                      --os <target>     Artifact OS (auto-detected if omitted)
                      --auto            If newer exists, run 'update --api' automatically.
                                        Triggers the update --api with latest version.
                                        Use this when setting up your scheduled run with cron
                                        crontab -e
                                        (* * * * * is place holder. user your own schedule)
                                        * * * * * /usr/local/bin/surgemail check-update --auto          
                      --verbose         Show details
  self_check_update Checks for newer ServerMail Helper script version and prompt to update.
                    Format:
                      surgemail self_check_update [--channel <release|prerelease|dev>] [--auto] [--quiet] [--token <gh_token>] 
                    Options:
                      --auto            Eliminates prompts in self_check_update. 
                                        Use this in your cron job.
                      --channel         Options are:
                                        reelase
                                        prerelease
                                        dev
                                        If not set it defaults to release.
                      --token <gh_token>
  self_update       Update the ServerMail Helper script folder (git clone or ZIP).
                    Format:
                      surgemail self_update [--channel <release|prerelease|dev>] [--auto] [--token <gh_token>]
                    Options:
                      --auto            Eliminates prompts in self_check_update. 
                                        Use this in your cron job.
                      --channel         Options are:
                                        reelase
                                        prerelease
                                        dev
                                        If not set it defaults to release.
                      --token <gh_token>
  stop              Stop SurgeMail AND free required ports (kills blockers)
  start             Start the SurgeMail server (use --force to kill blockers)
  restart           Stop then start the SurgeMail server (use --force to kill blockers)
  -r | reload       Reload SurgeMail configuration via 'tellmail reload'
  -s | status       Show current SurgeMail status via 'tellmail status'
  -v | version      Show installed SurgeMail version via 'tellmail version'
  -w | where        Show helper dir, surgemail server dir, tellmail path.
  -d | diagnostics  Print environment/report.
  -h | --help       Show this help
  man               Show man page (if installed), else help.
EOF
}
fi


# ---------- status & waits ----------
is_surgemail_ready() {
  echo "Checking status..."
  sleep 1
  local _tell="${TELLMAIL_BIN:-tellmail}"
  if ! command -v "$_tell" >/dev/null 2>&1; then
    if [[ -f "$PID_FILE" ]]; then
      local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
      [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
    fi
    have curl && curl -sSf -o /dev/null --max-time 2 "$ADMIN_URL" 2>/dev/null && return 0
    return 1
  fi
  local out
  out="$("$_tell" status 2>/dev/null || true)"
  if echo "$out" | grep -q "Bad Open Response"; then
    return 1
  fi
  if echo "$out" | grep -q "SurgeMail Version"; then
    return 0
  fi
  return 1
}

is_surgemail_ready_quiet() {
  local _tell="${TELLMAIL_BIN:-tellmail}"
  if command -v "$_tell" >/dev/null 2>&1; then
    local out; out="$("$_tell" status 2>/dev/null || true)"
    [[ "$out" == *"Bad Open Response"* ]] && return 1
    [[ "$out" == *"SurgeMail Version"* ]] && return 0
  fi
  if [[ -f "$PID_FILE" ]]; then
    local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
  fi
  have curl && curl -sSf -o /dev/null --max-time 2 "$ADMIN_URL" 2>/dev/null && return 0
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
      sleep 1
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
      lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $2, $1, '"'"'"$p"'"'"'}'
    done
    return 0
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | while read -r line; do
      case "$line" in
        *LISTEN*)
          port="${line##*:}"; port="${port%% *}"
          case "$port" in 25|465|587|110|143|993|995|7025)
            pid="$(printf "%s\n" "$line" | sed -n 's/.*pid=\([0-9][0-9]*\).*/\1/p' | head -n1)"
            proc="$(printf "%s\n" "$line" | sed -n 's/.*users:(("\{0,1\}\([^"]*\).*/\1/p' | head -n1)"
            [ -z "$proc" ] && proc="unknown"
            [ -z "$pid" ] && pid="?"
            echo "$pid" "$proc" "$port"
          ;;
          esac
        ;;
      esac
    done
    return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -ltnp 2>/dev/null | while read -r line; do
      case "$line" in
        *LISTEN*)
          port="${line##*:}"; port="${port%% *}"
          case "$port" in 25|465|587|110|143|993|995|7025)
            pid="$(printf "%s\n" "$line" | awk '{print $7}' | cut -d/ -f1)"
            [ -z "$pid" ] && pid="?"
            proc="unknown"
            echo "$pid" "$proc" "$port"
          ;;
          esac
        ;;
      esac
    done
    return 0
  fi
  if command -v fuser >/dev/null 2>&1; then
    for p in $CHECK_PORTS; do
      fuser -n tcp "$p" 2>/dev/null | tr ' ' '\n' | while read -r pid; do
        [ -n "$pid" ] && echo "$pid unknown $p"
      done
    done
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
      debug-gh)
        shift || true
        echo "has_curl: $(command -v curl >/dev/null 2>&1 && echo yes || echo no)"
        echo "has_wget: $(command -v wget >/dev/null 2>&1 && echo yes || echo no)"
        echo "has_git:  $(command -v git  >/dev/null 2>&1 && echo yes || echo no)"
        echo "latest_release: $(gh_latest_release_tag)"
        echo "first_prerelease: $(gh_first_prerelease_tag)"
        echo "default_branch: $(gh_default_branch)"
        ;;

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
  echo "Requested: stop SurgeMail server."
  set +e
  local was_running=1
  if is_surgemail_ready; then was_running=0; echo "Status before: SurgeMail server running."; else echo "Status before: SurgeMail server not running (or not healthy)."; fi
  strong_stop
  echo "Freeing required ports (25,465,587,110,143,993,995,7025)..."
  if force_kill_all_blockers; then vlog "Blockers killed during stop."; fi
  t=0; while (( t < 20 )); do if ! is_surgemail_ready; then echo "Result: SurgeMail server stopped and ports freed."; set -e; return 0; fi; sleep 1; t=$((t+1)); done
  echo "Result: SurgeMail server stop requested; made best effort to free ports."
  (( was_running != 0 )) && echo "Note: SurgeMail server appeared down before the stop request."
  set -e; return 0
}

cmd_start() {
  if is_surgemail_ready; then
    echo "SurgeMail server is already running (or healthy). Proceeding to start anyway."
  else
    echo "SurgeMail server is currently stopped. Proceeding to start server."
  fi

  local FORCE=0; while [[ $# -gt 0 ]]; do case "$1" in --force) FORCE=1; shift ;; --verbose) VERBOSE=1; shift ;; *) shift ;; esac; done
  need_root; [[ -x "$START_CMD" ]] || die "Start script missing: $START_CMD"
  echo "Requested: start SurgeMail server."
  if is_surgemail_ready; then echo "Status before: already running (or healthy). Proceeding to start anyway."; else echo "Status before: not running."; fi
  if [[ "$FORCE" -eq 1 ]]; then if force_kill_all_blockers; then vlog "Forced kill of blockers before start."; fi; fi
  if [[ $VERBOSE -eq 1 ]]; then "$START_CMD" || true; else "$START_CMD" >"${WORKDIR:-/tmp}/start.manual.out" 2>&1 || true; echo "(details: ${WORKDIR:-/tmp}/start.manual.out)"; fi
  if wait_for_ready 45; then echo "Result: SurgeMail server started and is healthy."; else echo "Result: SurgeMail server start issued, but not healthy within 45s. Check $SURGEMAIL_DIR/logs."; exit 1; fi

  #sleep 1
  #if is_surgemail_ready; then
  #  echo "Result: SurgeMail Server started and is healthy."
  #else
  #  echo "Result: start SurgeMail Server issued, but not running/healthy. Check $SURGEMAIL_DIR/logs."
  #fi
}

cmd_restart() {
  local FORCE=0; while [[ $# -gt 0 ]]; do case "$1" in --force) FORCE=1; shift ;; --verbose) VERBOSE=1; shift ;; *) shift ;; esac; done
  need_root; [[ -x "$STOP_CMD"  ]] || die "Stop script missing: $STOP_CMD"; [[ -x "$START_CMD" ]] || die "Start script missing: $START_CMD"
  echo "Requested: restart SurgeMail server (stop → start)."
  if is_surgemail_ready; then echo "Status before: SurgeMail server running."; else echo "Status before: SurgeMail server not running (or not healthy)."; fi
  cmd_stop --verbose
  if [[ "$FORCE" -eq 1 ]]; then if force_kill_all_blockers; then vlog "Forced kill of blocked ports before restart."; fi; fi
  if [[ $VERBOSE -eq 1 ]]; then "$START_CMD" || true; else "$START_CMD" >"${WORKDIR:-/tmp}/restart.out" 2>&1 || true; echo "(details: ${WORKDIR:-/tmp}/restart.out)"; fi
  if wait_for_ready 45; then echo "Step 2/2: SurgeMail server started and healthy."; else echo "Step 2/2: SurgeMail server start issued, but not healthy within 45s."; exit 1; fi
}

cmd_reload() {
  echo "Requested: reload SurgeMail server configuration."
  if command -v tellmail >/dev/null 2>&1; then
    if tellmail reload >/dev/null 2>&1; then echo "Result: SurgeMail server configuration reload sent."; else echo "Result: 'tellmail reload' returned non-zero. Ensure SurgeMail server is running."; exit 1; fi
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
    echo "Result: 'tellmail' not found in PATH. Cannot query SurgeMail server version."
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
    echo "Installed SurgeMail server version (parsed): $pretty"
  fi
  echo "SurgeMail Helper script: v$HELPER_VERSION"
}


cmd_where() {
  local script_path smcmd tell_path server_dir
  script_path="$(readlink -f "$0" 2>/dev/null || echo "$0")"
  if command -v surgemail >/dev/null 2>&1; then smcmd="$(command -v surgemail)"; else smcmd="(not found)"; fi
  tell_path="$(command -v tellmail 2>/dev/null || true)"
  [[ -z "$tell_path" ]] && tell_path="(not found)"
  server_dir="/usr/local/surgemail"
  echo "helper directory           : $(dirname "$(dirname "$script_path")")"
  echo "surgemail command          : $smcmd (surgemail helper command)"
  echo "tellmail path              : $tell_path"
  echo "SurgeMail Server directory : $server_dir"
}


cmd_diagnostics() {
  echo "=== SurgeMail Helper Diagnostics ==="
  echo "SurgeMail Helper version : v${HELPER_VERSION:-unknown}"
  echo "Script path    : $(readlink -f "$0" 2>/dev/null || echo "$0")"
  echo "Service name   : surgemail"
  local tbin="$(command -v tellmail 2>/dev/null || true)"
  echo "tellmail bin   : ${tbin:-tellmail} (found: $(command -v tellmail >/dev/null 2>&1 && echo yes || echo no))"
  local sm="direct"; command -v systemctl >/dev/null 2>&1 && sm="systemd" || (command -v service >/dev/null 2>&1 && sm="service" || true)
  echo "Service mgr    : $sm"
  local running="no"; if command -v tellmail >/dev/null 2>&1 && tellmail status >/dev/null 2>&1; then running="yes"; fi
  echo "Running        : $running"
  echo "GH_OWNER/REPO  : ${GH_OWNER:-mrlerch} / ${GH_REPO:-SurgeMail-Helper}"
}


compare_versions_semver() {
  local a="${1#v}" b="${2#v}" IFS=.
  local -a A=($a) B=($b)
  for ((i=0;i<3;i++)); do
    local ai=${A[i]:-0} bi=${B[i]:-0}
    if ((10#$ai > 10#$bi)); then return 1; fi
    if ((10#$ai < 10#$bi)); then return 2; fi
  done
  return 0
}

# Normalize semver-ish strings like "v1.14.12" -> "1.14.12" and fill missing parts.
norm_semver() {
  # strip leading "v" or "V"
  local v="${1#v}"; v="${v#V}"
  # keep only digits and dots; stop at any non [0-9.] (e.g., "-rc1" -> stop before -)
  v="${v%%[^0-9.]*}"
  # split to a.b.c (default missing parts to 0)
  local a b c
  IFS='.' read -r a b c <<<"$v"
  a=${a:-0}; b=${b:-0}; c=${c:-0}
  printf "%d.%d.%d" "$a" "$b" "$c"
}

cmd_self_check_update() {
  set +e
  local CHANNEL="release" AUTO=0 QUIET=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --channel) CHANNEL="${2:-release}"; shift 2 ;;
      --token)
        GH_TOKEN="${2:-}"; export GH_TOKEN
        shift 2
        ;;
      --auto) AUTO=1; shift ;;
      --quiet) QUIET=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      -h|--help) echo "Usage: surgemail self_check_update [--channel release|prerelease|dev] [--auto] [--quiet]"; set -e; return 0 ;;
      *) shift ;;
    esac
  done

  local remote="" is_branch=0
  case "$CHANNEL" in
    release)
      remote="$(gh_latest_release_tag)"
      ;;
    prerelease)
      remote="$(gh_first_prerelease_tag)"
      ;;
    dev)
      remote="$(gh_default_branch)"; is_branch=1
      ;;
    *)
      echo "Unknown channel: $CHANNEL"; set -e; return 0 ;;
  esac
  if [[ -z "$remote" ]]; then
    echo "Could not determine latest helper version from GitHub."
    set -e; return 0
  fi

  local local_v remote_v
  local_v="$(norm_semver "$HELPER_VERSION")"
  if (( is_branch==1 )); then
    # always consider dev newer unless the working copy is git and up to date
    if (( AUTO==1 )); then
      exec "$0" self_update --auto --channel dev ${VERBOSE:+--verbose}
    else
      read -rp "Update to development branch '$remote' now? [y/N]: " ans
      [[ "${ans,,}" == y || "${ans,,}" == yes ]] && exec "$0" self_update --channel dev
      echo "Ok, maybe next time. Exiting."
    fi
    set -e; return 0
  fi

  remote_v="$(norm_semver "$remote")"
  case "$(cmp_semver "$remote_v" "$local_v")" in
    0)
      (( QUIET==1 )) || echo "You are running the latest SurgeMail Helper script version v$local_v"
      set -e; return 0 ;;
    1)
      echo "Local version (v$local_v) is newer than remote (v$remote_v). No action."; set -e; return 0 ;;
    2)
      echo "A newer Helper version is available: v$remote_v (local v$local_v)."
      if (( AUTO==1 )); then
        exec "$0" self_update --auto --channel "$CHANNEL"
      else
        read -rp "Upgrade now? [y/N]: " ans
        if [[ "${ans,,}" == y || "${ans,,}" == yes ]]; then
          exec "$0" self_update --channel "$CHANNEL"
        else
          echo "Ok, maybe next time. Exiting."
        fi
      fi
      ;;
  esac
  set -e; return 0
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
  set +e
  local CHANNEL="release" AUTO=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --channel) CHANNEL="${2:-release}"; shift 2 ;;
      --token)
        GH_TOKEN="${2:-}"; export GH_TOKEN
        shift 2
        ;;
      --auto) AUTO=1; shift ;;
      --verbose) VERBOSE=1; shift ;;
      -h|--help) echo "Usage: surgemail self_update [--channel release|prerelease|dev] [--auto]"; set -e; return 0 ;;
      *) shift ;;
    esac
  done

  local owner="${GH_OWNER:-mrlerch}" repo="${GH_REPO:-SurgeMail-Helper}" ref="" is_branch=0

  case "$CHANNEL" in
    release)   ref="$(gh_latest_release_tag)";;
    prerelease) ref="$(gh_first_prerelease_tag)";;
    dev)       ref="$(gh_default_branch)"; is_branch=1;;
    *) echo "Unknown channel: $CHANNEL"; set -e; return 0;;
  esac
  if [[ -z "$ref" ]]; then
    if (( is_branch==1 )); then echo "Could not determine default branch from GitHub."; else echo "Could not determine latest release/tag from GitHub."; fi
    set -e; return 0
  fi

  local local_v remote_v
  local_v="$(norm_semver "$HELPER_VERSION")"
  if (( is_branch==0 )); then
    remote_v="$(norm_semver "$ref")"
    case "$(cmp_semver "$remote_v" "$local_v")" in
      0) echo "Already at latest version (v$local_v)."; set -e; return 0 ;;
      1)
        if (( AUTO==0 )); then
          read -rp "This would downgrade from v$local_v to v$remote_v. Continue? [y/N]: " ans
          if [[ "${ans,,}" != y && "${ans,,}" != yes ]]; then echo "Aborting downgrade."; set -e; return 0; fi
        fi
        ;;
      2) : ;; # upgrade
    esac
  fi

  local root; root="$(project_root)"
  if have_git_checkout; then
    echo "Detected git checkout. Updating via git..."
    (cd "$root" && git fetch --tags --all >/dev/null 2>&1)
    if (( is_branch==1 )); then
      (cd "$root" && git checkout -f "$ref" && git pull --ff-only origin "$ref") || { echo "Git update failed."; set -e; return 0; }
    else
      (cd "$root" && git -c advice.detachedHead=false checkout -f "tags/$ref") || { echo "Git checkout tag failed."; set -e; return 0; }
    fi
    echo "Helper updated via git to ${ref}."
    set -e; return 0
  else
    echo "No git checkout detected. Updating via ZIP..."
    local zip_url=""
    if (( is_branch==1 )); then
      zip_url="https://codeload.github.com/${owner}/${repo}/zip/refs/heads/${ref}"
    else
      zip_url="https://codeload.github.com/${owner}/${repo}/zip/refs/tags/${ref}"
    fi
    overlay_zip_to_root "$zip_url" || { echo "ZIP update failed."; set -e; return 0; }
    echo "Helper updated from ${CHANNEL} (${ref})."
    set -e; return 0
  fi
}


# ----------------------- SHORT_FLAG_ROUTER -----------------------
if [[ $# -eq 1 ]]; then
  case "$1" in
    -s) set -- status ;;
    -r) set -- reload ;;
    -u) set -- update ;;
    -d) set -- diagnostics ;;
    -v) set -- version ;;
    -w) set -- where ;;
    -h) set -- --help ;;
  esac
fi

# --------------------------- Router ----------------------------
case "${1:-}" in
  update|-u)        shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_update "$@";;
  check-update)     shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_check_update "$@";;
  stop)             shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_stop "$@";;
  start)            shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_start "$@";;
  restart)          shift || true; for a in "$@"; do if [[ "$a" == "--verbose" ]]; then VERBOSE=1; fi; done; cmd_restart "$@";;
  reload|-r)        shift || true; cmd_reload "$@";;
  status|-s)        shift || true; cmd_status "$@";;
  version|-v)       shift || true; cmd_version "$@";;
  where|-w)         shift || true; cmd_where "$@";;
  diagnostics|-d)   shift || true; cmd_diagnostics "$@";;
  self_check_update) shift || true; cmd_self_check_update "$@";;
  self_update)       shift || true; cmd_self_update "$@";;
  -h|--help|-help|help|man|"") show_main_help ;;
  *) echo "Unknown command: $1" >&2; exit 1 ;;
esac

# --- v1.14.12 helpers ---

cmp_semver() {
  # returns 0 if equal, 1 if a>b, 2 if a<b
  local a="$1" b="$2"
  if [[ "$a" == "$b" ]]; then echo 0; return 0; fi
  local bigger="$(printf '%s
%s
' "$a" "$b" | sort -V | tail -n1)"
  if [[ "$bigger" == "$a" ]]; then echo 1; else echo 2; fi
}

have_git_checkout() {
  # We are in scripts/ ... project root is one level up
  local root; root="$(cd "$(dirname "$0")/.." && pwd)"
  [[ -d "$root/.git" ]]
}

project_root() {
  cd "$(dirname "$0")/.." && pwd
}

overlay_zip_to_root() {
  # $1 = URL to zip
  local url="$1"
  local root; root="$(project_root)"
  local tmp; tmp="$(mktemp -d -t smh_upd_XXXXXXXX)"
  local zipf="$tmp/pkg.zip"
  echo "Downloading package..."
  if have curl; then curl -fsSL -o "$zipf" "$url"; else wget -qO "$zipf" "$url"; fi
  echo "Extracting..."
  mkdir -p "$tmp/unz"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zipf" -d "$tmp/unz"
  else
    # busybox unzip fallback
    python3 - <<'PY' "$zipf" "$tmp/unz" 2>/dev/null || true
PY
    tar -xf "$zipf" -C "$tmp/unz" 2>/dev/null || true
  fi
  # find inner top folder
  local inner; inner="$(find "$tmp/unz" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  if [[ -z "$inner" ]]; then echo "Extraction failed."; rm -rf "$tmp"; return 1; fi
  echo "Overlaying files..."
  (cd "$inner" && tar cf - .) | (cd "$root" && tar xvf - >/dev/null 2>&1)
  rm -rf "$tmp"
  echo "Helper updated."
}

# Help: self_check_update/self_update options
#   self_check_update  --channel <release|prerelease|dev> (default: release) --auto --quiet --token <gh_token>
#   self_update        --channel <release|prerelease|dev> (default: release) --auto --token <gh_token>
# GitHub API unauthenticated by default (rate limit ~60/hr). Optional token via --token or $GITHUB_TOKEN/$GH_TOKEN.

