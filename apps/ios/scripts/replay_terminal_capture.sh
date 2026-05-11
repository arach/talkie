#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <lab|live> <chunks.json|transcript.bin> [output.png]" >&2
  exit 64
fi

mode="$1"
capture="$2"
output="${3:-/tmp/talkie-terminal-replay.png}"

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
resources_dir="$repo_root/apps/ios/Talkie iOS/Resources/SSHTerminal"
script_path="$repo_root/apps/ios/scripts/wk_terminal_replay.swift"

case "$mode" in
  lab)
    html="$resources_dir/glyph-lab.html"
    ;;
  live)
    html="$resources_dir/index.html"
    ;;
  *)
    echo "mode must be 'lab' or 'live'" >&2
    exit 64
    ;;
esac

swift "$script_path" "$html" "$output" "$capture"
