#!/bin/bash
# Launch the preview app, trigger Cmd+Tab, and capture a screenshot.
# Usage: bash scripts/capture-cmdtab-preview.sh [AppIcon.appiconset] [output.png] [app_path] [capture_delay] [hold_seconds]
set -euo pipefail

ICONSET="${1:-apps/macos/Talkie/Assets.xcassets/AppIcon.appiconset}"
OUTPUT="${2:-/tmp/talkie-cmdtab.png}"
APP_DIR="${3:-/tmp/TalkieIconPreview.app}"
CAPTURE_DELAY="${4:-1}"
HOLD_SECONDS="${5:-1.5}"

if ! command -v screencapture >/dev/null 2>&1; then
  echo "screencapture not found. This script requires macOS." >&2
  exit 1
fi

if ! command -v osascript >/dev/null 2>&1; then
  echo "osascript not found. This script requires macOS." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/preview-macos-switcher.sh" "$ICONSET" "$APP_DIR"
sleep 0.2

screencapture -x -T "$CAPTURE_DELAY" "$OUTPUT" &
capture_pid=$!

sleep 0.1
osascript <<APPLESCRIPT
tell application "System Events"
  key down command
  keystroke tab
  delay $HOLD_SECONDS
  key up command
end tell
APPLESCRIPT

wait "$capture_pid"
echo "Cmd+Tab screenshot saved to: $OUTPUT"
