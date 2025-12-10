#!/bin/bash
# Build and run Talkie macOS app

# Gracefully quit if running
osascript -e 'tell application "Talkie" to quit' 2>/dev/null
sleep 0.5

# Build
echo "Building..."
xcodebuild -scheme Talkie -destination 'platform=macOS' build 2>&1 | grep -E "(error:|warning:|BUILD)"

# Launch if build succeeded
if [ ${PIPESTATUS[0]} -eq 0 ]; then
    echo "Launching..."
    open /Users/arach/Library/Developer/Xcode/DerivedData/Talkie-hdznsqjanoubvscjmqluykrfnayn/Build/Products/Debug/Talkie.app
else
    echo "Build failed"
    exit 1
fi
