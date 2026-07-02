#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Launch Talkie Dev
# @raycast.mode compact
# @raycast.packageName Talkie
# @raycast.description Open the stable locally-built Talkie dev app without rebuilding.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEV_APPS_DIR="${TALKIE_DEV_APPS_DIR:-$HOME/Applications/dev/Talkie}"
APP_PATH="$DEV_APPS_DIR/Talkie.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
BUILD_HINT="cd \"$REPO_ROOT/apps/macos\" && ./run.sh Talkie --no-launch"

fail() {
    echo "$1"
    exit 1
}

if [ ! -d "$APP_PATH" ]; then
    fail "Talkie Dev is not installed at $APP_PATH. Build once: $BUILD_HINT"
fi

if [ ! -f "$INFO_PLIST" ]; then
    fail "Talkie Dev at $APP_PATH is missing Info.plist. Rebuild once: $BUILD_HINT"
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || true)"
if [ -z "$BUNDLE_ID" ]; then
    fail "Could not read Talkie bundle id at $APP_PATH. Rebuild once: $BUILD_HINT"
fi

case "$BUNDLE_ID" in
    *.dev)
        ;;
    *)
        fail "Refusing to launch non-dev Talkie bundle ($BUNDLE_ID) at $APP_PATH. Rebuild dev once: $BUILD_HINT"
        ;;
esac

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$APP_PATH" >/dev/null 2>&1 || true

open "$APP_PATH"
echo "Opened Talkie Dev ($BUNDLE_ID)"
