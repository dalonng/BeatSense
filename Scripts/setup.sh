#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

if ! command -v mise >/dev/null 2>&1; then
  printf '%s\n' 'mise is required. Install it with brew install mise.' >&2
  exit 1
fi

mise install
exec mise exec -- just generate
