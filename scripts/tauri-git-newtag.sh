#!/bin/bash
set -euo pipefail

# Resolve repo root so the script works from any subdir.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$repo_root" ]; then
  echo "Error: not inside a git repository." >&2
  exit 1
fi

# Project name derived from the origin remote URL (e.g. "tonywxx/mycli").
origin_url=$(git -C "$repo_root" remote get-url origin 2>/dev/null || true)
if [ -z "$origin_url" ]; then
  echo "Error: no 'origin' remote configured." >&2
  exit 1
fi
project=$(echo "$origin_url" | sed -E 's#\.git$##; s#^git@[^:]+:##; s#^https?://[^/]+/##')
# Full GitHub URL for display (e.g. "https://github.com/tonywxx/mycli").
project_url="https://github.com/${project}"

# Fetch the highest semver tag published on GitHub (origin).
# `|| true` guards against grep/pipefail aborting when no tags exist yet.
current=$( (git ls-remote --tags origin 2>/dev/null || true) \
  | awk '{print $2}' \
  | sed -E 's#refs/tags/##; s#\^{}$##' \
  | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
  | sed -E 's/^v//' \
  | awk -F. '{ v=$1*1000000+$2*1000+$3; if (v>max){max=v; ver=$0} } END {print ver}' ) || true

if [ -z "$current" ]; then
  current="0.0.0"
  echo "No existing tag found on GitHub; starting from v0.0.0."
fi

# Auto-increment. From the default 0.0.0 (no remote tag yet) start at 0.1.0;
# otherwise bump the patch component. Components are single-digit: bumping
# past 9 carries to the next component (v1.0.9 -> v1.1.0, v1.9.0 -> v2.0.0).
IFS='.' read -r major minor patch <<< "$current"
if [ "$current" = "0.0.0" ]; then
  minor=$((minor + 1))
  patch=0
else
  patch=$((patch + 1))
fi
if [ "$patch" -gt 9 ]; then
  patch=0
  minor=$((minor + 1))
fi
if [ "$minor" -gt 9 ]; then
  minor=0
  major=$((major + 1))
fi
new_tag="v${major}.${minor}.${patch}"

# Files whose versions are compared (local vs GitHub default branch).
version_files=(
  "package.json"
  "src-tauri/Cargo.toml"
  "src-tauri/tauri.conf.json"
)

# Extract the [package] version from Cargo.toml (reads stdin).
cargo_version() {
  awk '/^\[package\]/{pkg=1; next} /^\[/{pkg=0} pkg && /^version[[:space:]]*=[[:space:]]*"/{line=$0; sub(/^version[[:space:]]*=[[:space:]]*"/, "", line); sub(/".*/, "", line); print line; exit}'
}

# Extract the top-level "version" from a JSON file (reads stdin).
json_version() {
  grep -E '^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"' | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true
}

# GitHub default branch for fetching raw files.
default_branch=$(git -C "$repo_root" ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/{print $2; exit}' | sed -E 's#^refs/heads/##')
[ -z "$default_branch" ] && default_branch="main"

echo "Project : $project_url"
echo
for f in "${version_files[@]}"; do
  # Local version.
  local_v="n/a"
  if [ -f "$repo_root/$f" ]; then
    if [[ "$f" == *.toml ]]; then
      local_v=$(cargo_version < "$repo_root/$f")
    else
      local_v=$(json_version < "$repo_root/$f")
    fi
    [ -z "$local_v" ] && local_v="n/a"
  fi

  # GitHub version (default branch on origin).
  github_v="n/a"
  github_raw=$(curl -fsSL "https://raw.githubusercontent.com/${project}/${default_branch}/$f" 2>/dev/null || true)
  if [ -n "$github_raw" ]; then
    if [[ "$f" == *.toml ]]; then
      github_v=$(echo "$github_raw" | cargo_version)
    else
      github_v=$(echo "$github_raw" | json_version)
    fi
    [ -z "$github_v" ] && github_v="n/a"
  fi

  printf '%-6s %-32s : %s\n' "Local" "$f" "$local_v"
  printf '%-6s %-32s : %s\n' "Github" "$f" "$github_v"
done
echo
echo "Github Current Tag Version : v${current}"
echo "New Tag Version            : ${new_tag}"

read -r -p "Add new tag ${new_tag} and push to GitHub to release? [y/N/c] " answer
case "$answer" in
  [yY][eE][sS] | [yY])
    git -C "$repo_root" tag "$new_tag" && git -C "$repo_root" push origin "$new_tag"
    echo "Released ${new_tag}."
    ;;
  [cC])
    read -r -p "Enter custom version (e.g. v1.0.1, without 'v'): " custom
    custom_tag="v${custom}"
    git -C "$repo_root" tag "$custom_tag" && git -C "$repo_root" push origin "$custom_tag"
    echo "Released ${custom_tag}."
    ;;
  *)
    echo "Aborted. No tag created."
    exit 0
    ;;
esac
