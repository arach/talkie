#!/bin/zsh
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
resources_dir="$repo_root/apps/ios/Talkie iOS/Resources/SSHTerminal"
script_path="$repo_root/apps/ios/scripts/wk_terminal_lab.swift"
ansi_fixture="$repo_root/apps/ios/scripts/renderer-ansi-fixture.b64"
unicode_fixture="$resources_dir/renderer-fixture.txt"

usage() {
  cat >&2 <<'EOF'
usage: open_terminal_glyph_lab.sh [unicode|ansi|<fixture.txt|fixture.b64|capture.bin|chunks.json>]

Examples:
  open_terminal_glyph_lab.sh
  open_terminal_glyph_lab.sh ansi
  open_terminal_glyph_lab.sh unicode
  open_terminal_glyph_lab.sh "$HOME/Downloads/chunks 2.json"
  open_terminal_glyph_lab.sh "$HOME/Downloads/transcript 3.bin"
EOF
}

if [[ $# -gt 1 ]]; then
  usage
  exit 64
fi

input="${1:-ansi}"

case "$input" in
  ansi)
    replay="$ansi_fixture"
    ;;
  unicode)
    replay="$unicode_fixture"
    ;;
  *)
    replay="$input"
    ;;
esac

swift "$script_path" "$resources_dir/glyph-lab.html" "$replay"
