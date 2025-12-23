#!/bin/bash
# profile-engine.sh
# Quick-start Instruments profiling for TalkieEngine
#
# Prerequisites:
# 1. TalkieEngine must be running (daemon or Xcode)
# 2. Xcode debugger should be DETACHED (Product > Detach from TalkieEngine)
#
# What gets captured:
# - jdi.talkie.engine: Transcription steps (file_check, model_check, audio_load, inference, etc.)
# - jdi.talkie.live: XPC round-trip from TalkieLive client
# - com.apple.e5rt: Neural Engine operations (CoreML inference)

set -e

# Find TalkieEngine PID
PID=$(pgrep -x TalkieEngine || true)

if [ -z "$PID" ]; then
    echo "ERROR: TalkieEngine is not running"
    echo ""
    echo "Start it via:"
    echo "  1. Xcode: Run TalkieEngine scheme"
    echo "  2. Daemon: launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/jdi.talkie.engine.dev.plist"
    exit 1
fi

echo "Found TalkieEngine (PID: $PID)"
echo ""
echo "Starting Instruments with Logging template..."
echo "After Instruments opens:"
echo "  1. Click the Record button (red circle)"
echo "  2. Trigger a transcription in TalkieLive"
echo "  3. Click Stop"
echo "  4. Look for 'jdi.talkie.engine' in Points of Interest"
echo ""

# Open Instruments with Logging template attached to TalkieEngine
open -a Instruments --args -t "Logging" -p "$PID"

echo "Instruments launched!"
