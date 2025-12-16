#!/bin/bash
# Build and run TalkieLive macOS app

cd "$(dirname "$0")"

BUILD_DIR="/Users/arach/dev/talkie/build/TalkieLive"
APP_PATH="$BUILD_DIR/Build/Products/Debug/TalkieLive.app"

# Gracefully quit if running
osascript -e 'tell application "TalkieLive" to quit' 2>/dev/null
sleep 0.3

# Build to stable location
echo "Building TalkieLive..."
xcodebuild -project TalkieLive.xcodeproj \
    -scheme TalkieLive \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|BUILD|SUCCEEDED|FAILED)"

# Launch if build succeeded
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "Launching..."
    open "$APP_PATH"
else
    echo "Build failed"
    exit 1
fi
