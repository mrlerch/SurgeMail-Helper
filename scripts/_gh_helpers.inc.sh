# _gh_helpers.inc.sh
# Minimal, reusable GitHub helper functions (robust + debuggable)

# Tiny utility
have() { command -v "$1" >/dev/null 2>&1; }

# Resolve owner/repo once (override with GH_OWNER / GH_REPO if needed)
: "${GH_OWNER:=mrlerch}"
: "${GH_REPO:=SurgeMail-Helper}"
: "${GH_API:=https://api.github.com}"

# Optional token (export GH_TOKEN or GITHUB_TOKEN to raise rate limits / access private)
__gh_token() { printf "%s" "${GH_TOKEN:-${GITHUB_TOKEN:-}}"; }

# Core HTTP GET with headers and optional auth
gh_http_get() {
  # $1 = URL
  local url="$1"
  local ua="surgemail-helper/1.15.2"
  local token; token="$(__gh_token)"
  if have curl; then
    if [ -n "$token" ]; then
      curl -fsSL -H "User-Agent: $ua" \
                  -H "Authorization: Bearer $token" \
                  -H "Accept: application/vnd.github+json" \
                  "$url" 2>/dev/null || true
    else
      curl -fsSL -H "User-Agent: $ua" \
                  -H "Accept: application/vnd.github+json" \
                  "$url" 2>/dev/null || true
    fi
  else
    if [ -n "$token" ]; then
      wget -qO- --header="User-Agent: $ua" \
                --header="Authorization: Bearer $token" \
                --header="Accept: application/vnd.github+json" \
                "$url" 2>/dev/null || true
    else
      wget -qO- --header="User-Agent: $ua" \
                --header="Accept: application/vnd.github+json" \
                "$url" 2>/dev/null || true
    fi
  fi
}

# Quick rate-limit/debug helper (prints remaining/used; used by debug only)
gh_rate_debug() {
  local rl; rl="$(gh_http_get "$GH_API/rate_limit")"
  printf "%s\n" "$rl" | tr -d '\n' | sed -n 's/.*"core":{"limit":[0-9]\+,"remaining":\([0-9]\+\).*/remaining:\1/p'
}

# Latest release tag (falls back to latest tag if no Releases)
gh_latest_release_tag() {
  local json tag tags_json
  json="$(gh_http_get "$GH_API/repos/$GH_OWNER/$GH_REPO/releases/latest")"
  tag="$(printf "%s" "$json" | tr -d '\n' | sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p' | head -n1)"
  if [ -z "$tag" ]; then
    # No releases; fall back to most recent tag
    tags_json="$(gh_http_get "$GH_API/repos/$GH_OWNER/$GH_REPO/tags?per_page=1")"
    tag="$(printf "%s" "$tags_json" | tr -d '\n' | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -n1)"
  fi
  printf "%s" "$tag"
}

# Prerelease channel target: the NEWEST non-draft release, pre-release or not.
# (A pre-release channel must never offer an older pre-release over a newer
# stable release.) GitHub sends "tag_name" BEFORE "prerelease"/"draft" inside
# each release object, and objects nest braces (author, assets), so split the
# compact JSON into one record per "tag_name" and read each record in order.
# Portable: POSIX sed with a literal newline (GNU and BSD/macOS).
gh_first_prerelease_tag() {
  local json
  json="$(gh_http_get "$GH_API/repos/$GH_OWNER/$GH_REPO/releases?per_page=50")"
  printf "%s" "$json" | tr -d '\n' | sed 's/"tag_name":/\
"tag_name":/g' | while IFS= read -r rec; do
    case "$rec" in '"tag_name":'*) ;; *) continue ;; esac
    case "$rec" in *'"draft":true'*) continue ;; esac
    printf "%s" "$rec" | sed -n 's/^"tag_name":"\([^"]*\)".*/\1/p'
    break
  done
}

# Default branch (no network/SSH unless necessary)
gh_default_branch() {
  # Prefer local git metadata
  if have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local ref
    ref="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"  # e.g., origin/main
    if [ -n "$ref" ]; then printf "%s" "${ref#origin/}"; return 0; fi
    if [ -f ".git/refs/remotes/origin/HEAD" ]; then
      ref="$(sed -n 's#^ref: refs/remotes/origin/\(.*\)$#\1#p' .git/refs/remotes/origin/HEAD)"
      if [ -n "$ref" ]; then printf "%s" "$ref"; return 0; fi
    fi
  fi
  # Fallback to API
  local json
  json="$(gh_http_get "$GH_API/repos/$GH_OWNER/$GH_REPO")"
  printf "%s" "$json" | tr -d '\n' | sed -n 's/.*"default_branch":"\([^"]*\)".*/\1/p' | head -n1
}

