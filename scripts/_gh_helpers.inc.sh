# _gh_helpers.inc.sh
# Minimal, reusable GitHub helper functions

# Tiny utility
have() { command -v "$1" >/dev/null 2>&1; }

gh_http_get() {
  # $1 = URL
  local url="$1"
  local ua="surgemail-helper/1.14.12"
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  if have curl; then
    if [ -n "$token" ]; then
      curl -fsSL -H "User-Agent: $ua" -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" "$url" 2>/dev/null || true
    else
      curl -fsSL -H "User-Agent: $ua" "$url" 2>/dev/null || true
    fi
  else
    if [ -n "$token" ]; then
      wget -qO- --header="User-Agent: $ua" --header="Authorization: Bearer $token" --header="Accept: application/vnd.github+json" "$url" 2>/dev/null || true
    else
      wget -qO- --header="User-Agent: $ua" "$url" 2>/dev/null || true
    fi
  fi
}

gh_latest_release_tag() {
  local owner="${GH_OWNER:-mrlerch}"; local repo="${GH_REPO:-SurgeMail-Helper}"
  local json; json="$(gh_http_get "https://api.github.com/repos/${owner}/${repo}/releases/latest")"
  local tag; tag="$(echo "$json" | tr -d '\n' | sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p' | head -n1)"
  if [ -z "$tag" ]; then
    # Fallback to latest tag when there are no Releases
    local tags_json; tags_json="$(gh_http_get "https://api.github.com/repos/${owner}/${repo}/tags?per_page=1")"
    tag="$(echo "$tags_json" | tr -d '\n' | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -n1)"
  fi
  echo "$tag"
}

gh_first_prerelease_tag() {
  local owner="${GH_OWNER:-mrlerch}"; local repo="${GH_REPO:-SurgeMail-Helper}"
  local json; json="$(gh_http_get "https://api.github.com/repos/${owner}/${repo}/releases?per_page=10")"
  echo "$json" | tr -d '\n' | sed -n 's/.*"prerelease":true[^}]*"tag_name":"\([^"]*\)".*/\1/p' | head -n1
}

gh_default_branch() {
  local owner="${GH_OWNER:-mrlerch}"; local repo="${GH_REPO:-SurgeMail-Helper}"
  # Prefer local git metadata without contacting remote to avoid SSH prompts
  if have git && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local ref
    ref="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"  # e.g., origin/main
    if [ -n "$ref" ]; then echo "${ref#origin/}"; return 0; fi
    if [ -f ".git/refs/remotes/origin/HEAD" ]; then
      ref="$(sed -n 's#^ref: refs/remotes/origin/\(.*\)$#\1#p' .git/refs/remotes/origin/HEAD)"
      if [ -n "$ref" ]; then echo "$ref"; return 0; fi
    fi
  fi
  # Fallback to GitHub API
  local json; json="$(gh_http_get "https://api.github.com/repos/${owner}/${repo}")"
  echo "$json" | tr -d '\n' | sed -n 's/.*"default_branch":"\([^"]*\)".*/\1/p' | head -n1
}

