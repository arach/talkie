#!/bin/bash
# TalkieLive restart script

# Kill existing instances
pkill -9 -f "TalkieLive" 2>/dev/null
sleep 1

# Restart TalkieEngine via LaunchAgent if needed
if ! pgrep -f "TalkieEngine" > /dev/null; then
    echo "Starting TalkieEngine..."
    launchctl kickstart gui/501/live.talkie.engine 2>/dev/null || \
    /Users/arach/Applications/TalkieEngine.app/Contents/MacOS/TalkieEngine &
    sleep 2
fi

# Find and start TalkieLive
LIVE_APP=$(find ~/Library/Developer/Xcode/DerivedData/TalkieLive-*/Build/Products/Debug -name "TalkieLive.app" -type d 2>/dev/null | head -1)
if [ -z "$LIVE_APP" ]; then
    echo "ERROR: TalkieLive.app not found in DerivedData"
    exit 1
fi

echo "Starting: $LIVE_APP"
open "$LIVE_APP"
sleep 2

echo ""
echo "=== Running processes ==="
pgrep -fl "TalkieEngine\|TalkieLive"
