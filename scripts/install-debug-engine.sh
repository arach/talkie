#!/bin/bash
# install-debug-engine.sh
# Copies the latest debug build of TalkieEngine to the stable path
# and restarts the debug LaunchAgent.
#
# Usage: ./scripts/install-debug-engine.sh
#        or add as Xcode post-build script

set -e

# Configuration
DERIVED_DATA_BASE="$HOME/Library/Developer/Xcode/DerivedData"
STABLE_DEBUG_PATH="$HOME/dev/talkie/build/Debug"
LAUNCH_AGENT_LABEL="jdi.talkie.engine.debug"
SERVICE_NAME="jdi.talkie.engine.xpc.dev.debug"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🔧 TalkieEngine Debug Installer"
echo "================================"

# Find the most recent TalkieEngine debug build in DerivedData
find_latest_build() {
    local latest_app=""
    local latest_time=0

    for dir in "$DERIVED_DATA_BASE"/TalkieSuite-*/Build/Products/Debug/TalkieEngine.app; do
        if [ -d "$dir" ]; then
            local mtime=$(stat -f "%m" "$dir" 2>/dev/null || echo 0)
            if [ "$mtime" -gt "$latest_time" ]; then
                latest_time=$mtime
                latest_app="$dir"
            fi
        fi
    done

    # Also check TalkieEngine-* projects
    for dir in "$DERIVED_DATA_BASE"/TalkieEngine-*/Build/Products/Debug/TalkieEngine.app; do
        if [ -d "$dir" ]; then
            local mtime=$(stat -f "%m" "$dir" 2>/dev/null || echo 0)
            if [ "$mtime" -gt "$latest_time" ]; then
                latest_time=$mtime
                latest_app="$dir"
            fi
        fi
    done

    echo "$latest_app"
}

# Stop any running debug engine
stop_debug_engine() {
    echo -n "⏹️  Stopping debug engine... "

    # Try to unload the LaunchAgent
    launchctl bootout gui/$(id -u)/$LAUNCH_AGENT_LABEL 2>/dev/null || true

    # Kill any remaining processes using the debug service
    pkill -f "TalkieEngine.app.*Debug" 2>/dev/null || true

    # Small delay to ensure process is fully stopped
    sleep 0.5
    echo -e "${GREEN}done${NC}"
}

# Copy build to stable location
install_build() {
    local source="$1"

    echo -n "📦 Installing to stable path... "

    # Create directory if needed
    mkdir -p "$STABLE_DEBUG_PATH"

    # Remove old build
    rm -rf "$STABLE_DEBUG_PATH/TalkieEngine.app"

    # Copy new build
    cp -R "$source" "$STABLE_DEBUG_PATH/"

    echo -e "${GREEN}done${NC}"
    echo "   → $STABLE_DEBUG_PATH/TalkieEngine.app"
}

# Start the debug engine
start_debug_engine() {
    echo -n "▶️  Starting debug engine... "

    # Bootstrap the LaunchAgent
    launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/$LAUNCH_AGENT_LABEL.plist 2>/dev/null || \
    launchctl kickstart gui/$(id -u)/$LAUNCH_AGENT_LABEL 2>/dev/null || true

    # Small delay for startup
    sleep 1

    # Verify it's running
    if pgrep -f "$STABLE_DEBUG_PATH/TalkieEngine.app" > /dev/null; then
        echo -e "${GREEN}done${NC}"
        local pid=$(pgrep -f "$STABLE_DEBUG_PATH/TalkieEngine.app")
        echo "   → PID: $pid"
    else
        echo -e "${YELLOW}waiting...${NC}"
        sleep 2
        if pgrep -f "$STABLE_DEBUG_PATH/TalkieEngine.app" > /dev/null; then
            local pid=$(pgrep -f "$STABLE_DEBUG_PATH/TalkieEngine.app")
            echo -e "   → ${GREEN}Started${NC} (PID: $pid)"
        else
            echo -e "   → ${RED}Failed to start${NC}"
            echo "   Try: launchctl kickstart -p gui/$(id -u)/$LAUNCH_AGENT_LABEL"
        fi
    fi
}

# Main
main() {
    # Find latest build
    echo "🔍 Finding latest debug build..."
    local latest=$(find_latest_build)

    if [ -z "$latest" ]; then
        echo -e "${RED}Error:${NC} No TalkieEngine debug build found in DerivedData"
        echo "       Build TalkieEngine in Xcode first (Cmd+B)"
        exit 1
    fi

    echo "   → Found: $latest"

    # Get build timestamp
    local build_time=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$latest")
    echo "   → Built: $build_time"

    # Stop, install, start
    stop_debug_engine
    install_build "$latest"
    start_debug_engine

    echo ""
    echo -e "${GREEN}✅ Debug engine installed successfully!${NC}"
    echo ""
    echo "Talkie will now connect to the debug engine."
    echo "To view logs: log stream --predicate 'subsystem == \"jdi.talkie.engine\"' --level debug"
}

main "$@"
