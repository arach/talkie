#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$ROOT/output"
DESTINATION="${TALKIE_SCREENSHOTS_PATH:-$ROOT/.upload}"

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

rm -rf "$DESTINATION"

for locale in en-US en-CA; do
  mkdir -p "$DESTINATION/$locale"
  for filename in "${required[@]}"; do
    /bin/cp -f "$SOURCE/$filename" "$DESTINATION/$locale/$filename"
  done
done

echo "Prepared App Store screenshot upload bundle: $DESTINATION"
echo "Localizations: en-US, en-CA"
echo "Screenshots per localization: ${#required[@]}"
