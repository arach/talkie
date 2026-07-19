#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$ROOT/output"
DESTINATION="${TALKIE_SCREENSHOTS_PATH:-$ROOT/.upload}"
IPAD_SOURCE="$ROOT/../screenshots/iPad Pro 13-inch (M5)/01_Home.png"
WATCH_SOURCE="$ROOT/../screenshots/Apple Watch Series 11 (46mm)/00_WatchHome.png"

required=(
  '01-catch-every-thought.png'
  '02-talk-naturally.png'
  '03-finished-writing.png'
  '04-review-every-edit.png'
  '05-private-and-flexible.png'
  '06-voice-anywhere.png'
)

for filename in "${required[@]}"; do
  [[ -f "$SOURCE/$filename" ]] || {
    echo "Missing App Store screenshot: $SOURCE/$filename" >&2
    exit 1
  }
done

[[ -f "$IPAD_SOURCE" ]] || {
  echo "Missing 13-inch iPad screenshot: $IPAD_SOURCE" >&2
  exit 1
}

[[ -f "$WATCH_SOURCE" ]] || {
  echo "Missing Apple Watch screenshot: $WATCH_SOURCE" >&2
  exit 1
}

rm -rf "$DESTINATION"

for locale in en-US en-CA; do
  mkdir -p "$DESTINATION/$locale"
  for filename in "${required[@]}"; do
    /bin/cp -f "$SOURCE/$filename" "$DESTINATION/$locale/$filename"
  done
  /bin/cp -f "$IPAD_SOURCE" "$DESTINATION/$locale/07-talkie-home-ipad-13.png"
  /bin/cp -f "$WATCH_SOURCE" "$DESTINATION/$locale/08-talkie-capture-watch-46.png"
done

echo "Prepared App Store screenshot upload bundle: $DESTINATION"
echo "Localizations: en-US, en-CA"
echo "Screenshots per localization: $((${#required[@]} + 2))"
echo "Device sets: 6.9-inch iPhone, 13-inch iPad, Apple Watch Series 10/11"
