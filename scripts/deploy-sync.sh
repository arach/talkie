#!/bin/bash
# Deploy the latest TalkieSync debug build to ~/stable/
# Usage: ./scripts/deploy-sync.sh

set -euo pipefail

STABLE_DIR="$HOME/stable"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
APP_NAME="TalkieSync.app"

# Find the most recently modified TalkieSync build
BUILD_PATH=$(find "$DERIVED_DATA" -path "*/TalkieSync-*/Build/Products/Debug/$APP_NAME" -maxdepth 5 2>/dev/null \
    | while read -r p; do echo "$(stat -f '%m' "$p") $p"; done \
    | sort -rn \
    | head -1 \
    | cut -d' ' -f2-)

if [ -z "$BUILD_PATH" ]; then
    echo "❌ No TalkieSync build found in DerivedData"
    exit 1
fi

BUILD_TIME=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$BUILD_PATH")
echo "📦 Found: $BUILD_PATH"
echo "   Built: $BUILD_TIME"

# Kill running TalkieSync if any
SYNC_PID=$(pgrep -f "TalkieSync.app/Contents/MacOS/TalkieSync" 2>/dev/null || true)
if [ -n "$SYNC_PID" ]; then
    echo "⏹  Killing TalkieSync (PID $SYNC_PID)..."
    kill "$SYNC_PID" 2>/dev/null || true
    sleep 1
fi

# Copy to stable
mkdir -p "$STABLE_DIR"
rm -rf "$STABLE_DIR/$APP_NAME"
cp -R "$BUILD_PATH" "$STABLE_DIR/$APP_NAME"

echo "✅ Deployed to $STABLE_DIR/$APP_NAME"
echo "   Talkie will relaunch it on next sync"
