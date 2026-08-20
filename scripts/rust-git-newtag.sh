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

# Local Cargo.toml version (from the directory the script is run in).
local_cargo="$PWD/Cargo.toml"
local_version="n/a"
if [ -f "$local_cargo" ]; then
  local_version=$(grep -E '^version[[:space:]]*=' "$local_cargo" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  [ -z "$local_version" ] && local_version="n/a"
fi

# GitHub Cargo.toml version (default branch on origin).
github_version="n/a"
default_branch=$(git -C "$repo_root" ls-remote --symref origin HEAD 2>/dev/null | awk '/^ref:/{print $2; exit}' | sed -E 's#^refs/heads/##')
[ -z "$default_branch" ] && default_branch="main"
github_cargo=$(curl -fsSL "https://raw.githubusercontent.com/${project}/${default_branch}/Cargo.toml" 2>/dev/null || true)
if [ -n "$github_cargo" ]; then
  github_version=$(echo "$github_cargo" | grep -E '^version[[:space:]]*=' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
  [ -z "$github_version" ] && github_version="n/a"
fi

echo "Project : $project_url"
echo "Local  Cargo.toml Version : $local_version"
echo "Github Cargo.toml Version : $github_version"
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
