#!/bin/bash
# Build, install, and launch Talkie in iOS Simulator

SCHEME="Talkie OS"
DEVICE="iPhone 16 Pro"
BUNDLE_ID="jdi.talkie-os"
DERIVED_DATA="/Users/arach/Library/Developer/Xcode/DerivedData/Talkie_OS-allortoczsqmvcchyrfuwhzihcos"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Talkie OS.app"

echo "🔨 Building..."
xcodebuild -scheme "$SCHEME" -destination "platform=iOS Simulator,name=$DEVICE" build 2>&1 | tail -3

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
