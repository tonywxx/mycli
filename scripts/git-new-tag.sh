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
# otherwise bump the patch component.
IFS='.' read -r major minor patch <<< "$current"
if [ "$current" = "0.0.0" ]; then
  minor=$((minor + 1))
  patch=0
  new_tag="v${major}.${minor}.${patch}"
else
  patch=$((patch + 1))
  new_tag="v${major}.${minor}.${patch}"
fi

echo "Project : $project_url"
echo "Current : v${current} (remote)"
echo "New     : ${new_tag}"

read -r -p "Add new tag ${new_tag} and push to GitHub to release? [y/N] " answer
case "$answer" in
  [yY][eE][sS] | [yY])
    git -C "$repo_root" tag "$new_tag" && git -C "$repo_root" push origin "$new_tag"
    echo "Released ${new_tag}."
    ;;
  *)
    echo "Aborted. No tag created."
    exit 0
    ;;
esac
