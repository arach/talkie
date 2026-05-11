#!/bin/bash
# Build, install, and launch Talkie in iOS Simulator

SCHEME="Talkie"
DEVICE="iPhone 16 Pro"
BUNDLE_ID="jdi.talkie-os"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$SCRIPT_DIR/build/DerivedData}"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Talkie.app"

echo "🔨 Building..."
xcodebuild -project "$SCRIPT_DIR/Talkie-iOS.xcodeproj" -scheme "$SCHEME" -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath "$DERIVED_DATA" build 2>&1 | tail -3

if [ $? -eq 0 ]; then
    echo "📱 Installing..."
    xcrun simctl boot "$DEVICE" 2>/dev/null || true
    open -a Simulator
    xcrun simctl install "$DEVICE" "$APP_PATH"

    echo "🚀 Launching..."
    xcrun simctl launch "$DEVICE" "$BUNDLE_ID"
    echo "✅ Done"
else
    echo "❌ Build failed"
    exit 1
fi
