#!/bin/bash
# Xcode Build Phase Script: Cleanup stale URL scheme registrations
#
# Add this as a "Run Script" build phase in Xcode (Debug config only):
#   1. Select target -> Build Phases -> + -> New Run Script Phase
#   2. Set shell to: /bin/bash
#   3. Paste: "${SRCROOT}/../scripts/xcode-cleanup-url-schemes.sh"
#   4. Check "For install builds only" = NO, "Based on dependency analysis" = NO
#
# This ensures only the current build handles talkie-dev:// URLs.

# Only run for Debug builds
if [ "$CONFIGURATION" != "Debug" ]; then
  exit 0
fi

# Only run if we have a built app
APP_PATH="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app"
if [ ! -d "$APP_PATH" ]; then
  exit 0
fi

echo "🧹 Cleaning up stale URL scheme registrations..."

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Find all apps claiming talkie-dev://
STALE_APPS=$($LSREGISTER -dump 2>/dev/null | grep -B 20 "bindings:.*talkie-dev:" | grep "path:" | sed 's/.*path: *//' | sort -u)

# Unregister apps that aren't our current build
if [ -n "$STALE_APPS" ]; then
  echo "$STALE_APPS" | while read app; do
    # Normalize paths for comparison
    NORMALIZED_APP=$(cd "$(dirname "$app")" 2>/dev/null && pwd)/$(basename "$app") 2>/dev/null || echo "$app"
    NORMALIZED_CURRENT=$(cd "$(dirname "$APP_PATH")" 2>/dev/null && pwd)/$(basename "$APP_PATH") 2>/dev/null || echo "$APP_PATH"

    if [ "$NORMALIZED_APP" != "$NORMALIZED_CURRENT" ] && [ -d "$app" ]; then
      echo "  Unregistering stale: $app"
      $LSREGISTER -u "$app" 2>/dev/null || true
    fi
  done
fi

# Force re-register current build
echo "  Registering current: $APP_PATH"
$LSREGISTER -f "$APP_PATH"

echo "✓ URL scheme cleanup complete"
