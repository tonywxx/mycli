#!/usr/bin/env bash

set -euo pipefail

# No args: use current directory and run interactively (confirm with [Y/n]).
# Otherwise the first argument is the project dir; an optional second is a version.
interactive=0
if [[ $# -eq 0 ]]; then
  root_dir=$(pwd)
  interactive=1
else
  root_dir=$(cd -- "$1" && pwd)
  shift
fi

if [[ $# -eq 0 ]]; then
  current=$(node -p "require('$root_dir/package.json').version")
  if [[ ! $current =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: invalid version in package.json ($current)" >&2
    exit 1
  fi
  IFS=. read -r major minor patch <<< "$current"
  # Roll the minor over instead of carrying patch past 9 (0.1.9 -> 0.2.0).
  if [[ $patch -ge 9 ]]; then
    version="$major.$((minor + 1)).0"
  else
    version="$major.$minor.$((patch + 1))"
  fi
elif [[ $# -eq 1 && $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  version="$1"
else
  echo "Usage: $0 [dir] [X.Y.Z]" >&2
  echo "  No args : use current dir, show versions, confirm with [Y/n]" >&2
  echo "  dir     Tauri project root (containing package.json and src-tauri/)" >&2
  echo "  X.Y.Z   Optional explicit version (default: patch+1, patch 9 rolls minor)" >&2
  exit 1
fi

# Interactive mode: show the three files' current versions and confirm before writing.
if [[ $interactive -eq 1 ]]; then
  ver_file=$(mktemp)
  node --input-type=module - "$root_dir" <<'READVER' > "$ver_file"
import fs from 'node:fs'
import path from 'node:path'

const root = process.argv[2]
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8')
const pkg = JSON.parse(read('package.json')).version
const tauri = JSON.parse(read('src-tauri/tauri.conf.json')).version
const cargoMatch = read('src-tauri/Cargo.toml').match(/^\[package\][^]*?\nversion = "([^"]+)"/m)
const cargo = cargoMatch ? cargoMatch[1] : '(not found)'

console.log(`  package.json              : ${pkg}`)
console.log(`  src-tauri/Cargo.toml      : ${cargo}`)
console.log(`  src-tauri/tauri.conf.json : ${tauri}`)
READVER
  current_versions=$(cat "$ver_file")
  rm -f "$ver_file"

  echo "Current versions in $root_dir:"
  echo "$current_versions"
  echo "New version (auto): $version"
  read -r -p "Proceed? [Y/n] " reply || true
  case "$reply" in
    ''|Y|y) ;;
    *) echo "Aborted." >&2; exit 0 ;;
  esac
fi

node --input-type=module - "$version" "$root_dir" <<'NODE'
import fs from 'node:fs'
import path from 'node:path'

const [version, root] = process.argv.slice(2)
const files = {
  package: path.join(root, 'package.json'),
  cargo: path.join(root, 'src-tauri/Cargo.toml'),
  tauri: path.join(root, 'src-tauri/tauri.conf.json'),
}

const packageJson = JSON.parse(fs.readFileSync(files.package, 'utf8'))
const tauriConfig = JSON.parse(fs.readFileSync(files.tauri, 'utf8'))
const cargo = fs.readFileSync(files.cargo, 'utf8')

if (!/^\[package\]\n(?:[^\n]*\n)*?version = "[^"]+"/m.test(cargo)) {
  throw new Error(`Could not find the package version in ${files.cargo}`)
}

packageJson.version = version
tauriConfig.version = version
const updatedCargo = cargo.replace(
  /^(\[package\]\n(?:[^\n]*\n)*?version = ")[^"]+(")/m,
  `$1${version}$2`,
)

fs.writeFileSync(files.package, `${JSON.stringify(packageJson, null, '\t')}\n`)
fs.writeFileSync(files.tauri, `${JSON.stringify(tauriConfig, null, '\t')}\n`)
fs.writeFileSync(files.cargo, updatedCargo)

const versions = [
  JSON.parse(fs.readFileSync(files.package, 'utf8')).version,
  /^version = "([^"]+)"/m.exec(fs.readFileSync(files.cargo, 'utf8'))?.[1],
  JSON.parse(fs.readFileSync(files.tauri, 'utf8')).version,
]
if (!versions.every((actual) => actual === version)) {
  throw new Error(`Version sync failed: ${versions.join(', ')}`)
}

console.log(`Set package.json, Cargo.toml, and tauri.conf.json to ${version}`)
NODE
