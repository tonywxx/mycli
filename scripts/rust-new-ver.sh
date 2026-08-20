#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <dir> [X.Y.Z]" >&2
  echo "  <dir>  Cargo project root (containing Cargo.toml)" >&2
  echo "  X.Y.Z  Optional explicit version (default: auto-increment patch)" >&2
  exit 1
fi

root_dir=$(cd -- "$1" && pwd)
shift

if [[ $# -eq 0 ]]; then
  current=$(node -p "(() => { const m = require('fs').readFileSync('$root_dir/Cargo.toml','utf8').match(/^\\[package\\](?:\\n(?!\\n)[^\\n]*)*?\\nversion = \"([^\"]+)\"/m); if(!m) throw new Error('could not find package version'); return m[1]; })()")
  if [[ ! $current =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: invalid version in Cargo.toml ($current)" >&2
    exit 1
  fi
  IFS=. read -r major minor patch <<< "$current"
  version="$major.$minor.$((patch + 1))"
elif [[ $# -eq 1 && $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  version="$1"
else
  echo "Usage: $0 <dir> [X.Y.Z]" >&2
  exit 1
fi

node --input-type=module - "$version" "$root_dir" <<'NODE'
import fs from 'node:fs'
import path from 'node:path'

const [version, root] = process.argv.slice(2)
const cargoFile = path.join(root, 'Cargo.toml')
const cargo = fs.readFileSync(cargoFile, 'utf8')

if (!/^\[package\]\n(?:[^\n]*\n)*?version = "[^"]+"/m.test(cargo)) {
  throw new Error(`Could not find the package version in ${cargoFile}`)
}

const updatedCargo = cargo.replace(
  /^(\[package\]\n(?:[^\n]*\n)*?version = ")[^"]+(")/m,
  `$1${version}$2`,
)

fs.writeFileSync(cargoFile, updatedCargo)

const actual = /^version = "([^"]+)"/m.exec(fs.readFileSync(cargoFile, 'utf8'))?.[1]
if (actual !== version) {
  throw new Error(`Version sync failed: ${actual}`)
}

console.log(`Set Cargo.toml to ${version}`)
NODE
