#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."

# Xcode launched from Finder may not have mise on its PATH.
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin"

if ! command -v mise >/dev/null 2>&1; then
  printf '%s\n' 'error: Install mise with brew install mise, then run ./Scripts/setup.sh.' >&2
  exit 1
fi

swift_files=()
for ((index = 0; index < SCRIPT_INPUT_FILE_COUNT; index++)); do
  input="SCRIPT_INPUT_FILE_$index"
  case "${!input}" in
    *.swift) swift_files+=("${!input}") ;;
  esac
done

mise --no-env exec -- swiftformat "${swift_files[@]}" --config .swiftformat --lint --cache ignore
exec mise --no-env exec -- swiftlint lint --config .swiftlint.yml --no-cache "${swift_files[@]}"
