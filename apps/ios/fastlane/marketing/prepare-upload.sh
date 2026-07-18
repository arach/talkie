#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$ROOT/output"
IPAD_SOURCE="$ROOT/output-ipad"
DESTINATION="${TALKIE_SCREENSHOTS_PATH:-$ROOT/.upload}"
WATCH_SOURCE="$ROOT/../screenshots/Apple Watch Series 11 (46mm)/00_WatchHome.png"

required_iphone=(
  '01-catch-every-thought.png'
  '02-talk-naturally.png'
  '03-finished-writing.png'
  '04-review-every-edit.png'
  '05-private-and-flexible.png'
  '06-voice-anywhere.png'
)

required_ipad=(
  '01-voice-into-action-ipad.png'
  '02-talk-at-full-speed-ipad.png'
  '03-finished-writing-ipad.png'
  '04-ask-talkie-anything-ipad.png'
  '05-approve-every-edit-ipad.png'
  '06-dictate-anywhere-ipad.png'
)

for filename in "${required_iphone[@]}"; do
  [[ -f "$SOURCE/$filename" ]] || {
    echo "Missing App Store screenshot: $SOURCE/$filename" >&2
    exit 1
  }
done

for filename in "${required_ipad[@]}"; do
  [[ -f "$IPAD_SOURCE/$filename" ]] || {
    echo "Missing 13-inch iPad screenshot: $IPAD_SOURCE/$filename" >&2
    exit 1
  }
done

[[ -f "$WATCH_SOURCE" ]] || {
  echo "Missing Apple Watch screenshot: $WATCH_SOURCE" >&2
  exit 1
}

rm -rf "$DESTINATION"

for locale in en-US en-CA; do
  mkdir -p "$DESTINATION/$locale"
  for filename in "${required_iphone[@]}"; do
    /bin/cp -f "$SOURCE/$filename" "$DESTINATION/$locale/$filename"
  done
  for filename in "${required_ipad[@]}"; do
    /bin/cp -f "$IPAD_SOURCE/$filename" "$DESTINATION/$locale/$filename"
  done
  /bin/cp -f "$WATCH_SOURCE" "$DESTINATION/$locale/07-talkie-capture-watch-46.png"
done

echo "Prepared App Store screenshot upload bundle: $DESTINATION"
echo "Localizations: en-US, en-CA"
echo "Screenshots per localization: $((${#required_iphone[@]} + ${#required_ipad[@]} + 1))"
echo "Device sets: 6.9-inch iPhone (6), 13-inch iPad landscape (6), Apple Watch Series 10/11 (1)"
