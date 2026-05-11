#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

derived_data="${TMPDIR:-/tmp}/talkie-runner-derived-data"
xcodebuild \
  -project TalkieRunner.xcodeproj \
  -scheme TalkieRunner \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  build >/dev/null

open "$derived_data/Build/Products/Debug/TalkieRunner.app"
