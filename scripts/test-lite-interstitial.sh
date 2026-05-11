#!/bin/bash
#
# Test script for Talkie Lite Mode Interstitial
#
# This script creates a payload file and launches Talkie in lite mode,
# simulating what TalkieAgent does when routing to interstitial.
#
# Usage:
#   ./test-lite-interstitial.sh                    # Default test text
#   ./test-lite-interstitial.sh "Custom text"     # Custom text
#   ./test-lite-interstitial.sh --debug           # With log streaming
#

set -e

# Configuration
TALKIE_BUNDLE_ID_RELEASE="jdi.talkie.core"
TALKIE_BUNDLE_ID_DEV="jdi.talkie.core.dev"

# Parse arguments
DEBUG_MODE=false
TEST_TEXT="This is a test transcription for the lite mode interstitial. It should appear in the editor panel where you can polish it with LLM or edit manually."

while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        *)
            TEST_TEXT="$1"
            shift
            ;;
    esac
done

# Find Talkie executable
find_talkie() {
    # 1. Try Launch Services (most reliable)
    for bundle_id in "$TALKIE_BUNDLE_ID_DEV" "$TALKIE_BUNDLE_ID_RELEASE"; do
        app_path=$(mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" 2>/dev/null | head -1)
        if [[ -n "$app_path" && -x "$app_path/Contents/MacOS/Talkie" ]]; then
            echo "$app_path/Contents/MacOS/Talkie"
            return 0
        fi
    done

    # 2. Check DerivedData (newest first)
    derived_data="$HOME/Library/Developer/Xcode/DerivedData"
    if [[ -d "$derived_data" ]]; then
        for dir in $(ls -t "$derived_data" | grep "^Talkie-"); do
            executable="$derived_data/$dir/Build/Products/Debug/Talkie.app/Contents/MacOS/Talkie"
            if [[ -x "$executable" ]]; then
                echo "$executable"
                return 0
            fi
        done
    fi

    # 3. Standard locations
    for path in "/Applications/Talkie.app" "$HOME/Applications/Talkie.app"; do
        if [[ -x "$path/Contents/MacOS/Talkie" ]]; then
            echo "$path/Contents/MacOS/Talkie"
            return 0
        fi
    done

    return 1
}

# Create payload file
create_payload() {
    local text="$1"
    local payload_file="/tmp/talkie-test-payload-$$.json"

    # Generate test data
    local timestamp=$(date +%s)
    local test_id=$((RANDOM % 90000 + 10000))
    local audio_filename="test-audio-${test_id}.m4a"

    cat > "$payload_file" << EOF
{
    "id": ${test_id},
    "text": $(echo "$text" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
    "audioFilename": "${audio_filename}",
    "timestamp": ${timestamp}
}
EOF

    chmod 600 "$payload_file"
    echo "$payload_file"
}

# Main
echo "=== Talkie Lite Mode Interstitial Test ==="
echo ""

# Find Talkie
TALKIE_PATH=$(find_talkie)
if [[ -z "$TALKIE_PATH" ]]; then
    echo "ERROR: Could not find Talkie.app"
    echo "Make sure Talkie is built or installed."
    exit 1
fi
echo "Found Talkie: $TALKIE_PATH"

# Create payload
PAYLOAD_FILE=$(create_payload "$TEST_TEXT")
echo "Created payload: $PAYLOAD_FILE"
echo ""
echo "Payload contents:"
cat "$PAYLOAD_FILE"
echo ""

# Start log streaming in background if debug mode
if $DEBUG_MODE; then
    echo "Starting log stream (Ctrl+C to stop after test)..."
    log stream --predicate 'process == "Talkie" AND (eventMessage CONTAINS "[LITE]" OR eventMessage CONTAINS "[main.swift]")' --info &
    LOG_PID=$!
    sleep 1
fi

# Launch Talkie in lite mode
echo ""
echo "Launching: $TALKIE_PATH --interstitial --payload=$PAYLOAD_FILE"
echo ""

"$TALKIE_PATH" --interstitial --payload="$PAYLOAD_FILE" &
TALKIE_PID=$!

echo "Talkie launched with PID: $TALKIE_PID"
echo ""

# Wait a moment and check if still running
sleep 2
if ps -p $TALKIE_PID > /dev/null 2>&1; then
    echo "SUCCESS: Talkie lite mode is running"
    echo ""
    echo "The interstitial panel should now be visible."
    echo "Press Enter to kill Talkie and exit, or Ctrl+C to leave it running."
    read -r
    kill $TALKIE_PID 2>/dev/null || true
else
    echo "WARNING: Talkie process exited within 2 seconds"
    echo "Check Console.app for errors or run with --debug flag"
fi

# Clean up log stream
if $DEBUG_MODE && [[ -n "$LOG_PID" ]]; then
    kill $LOG_PID 2>/dev/null || true
fi

echo "Done."
