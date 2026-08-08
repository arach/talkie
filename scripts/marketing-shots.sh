#!/bin/bash
set -euo pipefail

# Captures the website screenshot inventory: every core page in every curated
# theme, plus a manifest.json describing what's there.
#
# The work happens inside the app (--debug=marketing-shots), which renders each
# screen into its own window rather than driving the live UI. That's what makes
# a run repeatable — no coordinates, no dependence on which screen was open, and
# the theme switch is a settings call instead of three clicks through a picker.
#
# Usage:
#   ./scripts/marketing-shots.sh                          # ~/Desktop/talkie-shots-<stamp>/
#   ./scripts/marketing-shots.sh out/shots                # explicit directory
#   ./scripts/marketing-shots.sh out/shots 1600 1000      # explicit size

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

OUT="${1:-}"
WIDTH="${2:-}"
HEIGHT="${3:-}"

APP=""
for candidate in \
  "$ROOT_DIR/build/Debug/Talkie.app" \
  "$HOME/Library/Developer/Xcode/DerivedData/TalkieSuite-"*/Build/Products/Debug/Talkie.app \
  "/Applications/Talkie.app"
do
  if [ -x "$candidate/Contents/MacOS/Talkie" ]; then APP="$candidate"; break; fi
done

if [ -z "$APP" ]; then
  echo "❌ No Talkie.app found. Build first: talkie-dev build talkie" >&2
  exit 1
fi

echo "📦 $APP"

# The capture process drives the real settings singleton to switch themes, so a
# second instance reading and writing the same UserDefaults at the same time can
# race it. Quit the running app first; it restores your theme when it finishes.
if pgrep -qf "Talkie.app/Contents/MacOS/Talkie"; then
  echo "⏹  Quitting the running Talkie so it doesn't race the theme switch"
  osascript -e 'tell application id "to.talkie.app.mac.dev" to quit' 2>/dev/null || true
  sleep 2
fi

ARGS=()
[ -n "$OUT" ] && ARGS+=("$OUT")
if [ -n "$WIDTH" ] && [ -n "$HEIGHT" ]; then ARGS+=("$WIDTH" "$HEIGHT"); fi

set +e
"$APP/Contents/MacOS/Talkie" --debug=marketing-shots "${ARGS[@]}" 2>&1 \
  | grep -E "📸|✅|❌|📁"
status=${PIPESTATUS[0]}
set -e

exit "$status"
