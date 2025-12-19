#!/bin/bash
# Unified build and run script for Talkie macOS apps
#
# Usage:
#   ./run.sh live           # Build and run TalkieLive
#   ./run.sh engine         # Build and install TalkieEngine (service)
#   ./run.sh core           # Build and run Talkie (main app)
#   ./run.sh live engine    # Build and run multiple apps
#   ./run.sh all            # Build all apps
#   ./run.sh --list         # List available apps
#
# Options:
#   --no-launch    Build only, don't launch
#   --clean        Clean before building
#   --verbose      Show full build output

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE="$SCRIPT_DIR/../TalkieSuite.xcworkspace"
BUILD_BASE="$SCRIPT_DIR/../build"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Options
NO_LAUNCH=false
CLEAN=false
VERBOSE=false
DEBUG_MODE=false
EXEC_ONLY=false

AVAILABLE_APPS="live engine core"

# Get scheme for app
get_scheme() {
    case $1 in
        live)   echo "TalkieLive" ;;
        engine) echo "TalkieEngine" ;;
        core)   echo "Talkie" ;;
    esac
}

# Get app type (service or regular app)
get_type() {
    case $1 in
        engine) echo "service" ;;
        *)      echo "app" ;;
    esac
}

# Parse arguments
APPS_TO_BUILD=""
for arg in "$@"; do
    case $arg in
        --no-launch)
            NO_LAUNCH=true
            ;;
        --clean)
            CLEAN=true
            ;;
        --verbose)
            VERBOSE=true
            ;;
        --debug|-d)
            DEBUG_MODE=true
            ;;
        -e|--exec-only)
            EXEC_ONLY=true
            ;;
        --list|-l)
            echo "Available apps:"
            echo "  live    - TalkieLive (always-on transcription UI)"
            echo "  engine  - TalkieEngine (transcription service)"
            echo "  core    - Talkie (main app with workflows)"
            echo ""
            echo "Usage: ./run.sh [apps...] [options]"
            echo "  ./run.sh live              Build and run TalkieLive"
            echo "  ./run.sh live engine       Build multiple apps"
            echo "  ./run.sh all               Build all apps"
            echo ""
            echo "Options:"
            echo "  -e            Just run (no build)"
            echo "  --no-launch   Build only"
            echo "  --clean       Clean build"
            echo "  --verbose     Full output"
            echo "  --debug, -d   Print PID and attach Xcode debugger"
            exit 0
            ;;
        --help|-h)
            echo "Talkie Build Script"
            echo ""
            echo "Usage: ./run.sh [apps...] [options]"
            echo ""
            echo "Apps: live, engine, core, all"
            echo ""
            echo "Options:"
            echo "  -e            Just run latest build (no rebuild)"
            echo "  --no-launch   Build only, don't launch"
            echo "  --clean       Clean before building"
            echo "  --verbose     Show full build output"
            echo "  --debug, -d   Print PID and attach Xcode debugger"
            echo "  --list, -l    List available apps"
            echo "  --help, -h    Show this help"
            exit 0
            ;;
        all)
            APPS_TO_BUILD="$AVAILABLE_APPS"
            ;;
        *)
            if echo " $AVAILABLE_APPS " | grep -q " $arg "; then
                APPS_TO_BUILD="$APPS_TO_BUILD $arg"
            else
                echo -e "${RED}Unknown app or option: $arg${NC}"
                echo "Run './run.sh --list' to see available apps"
                exit 1
            fi
            ;;
    esac
done

# Default to TalkieLive if no app specified
if [ -z "$APPS_TO_BUILD" ]; then
    echo -e "${YELLOW}No app specified, defaulting to 'live'${NC}"
    echo "Run './run.sh --list' for options"
    echo ""
    APPS_TO_BUILD="live"
fi

# Trim leading space
APPS_TO_BUILD=$(echo $APPS_TO_BUILD | xargs)

# Build output filter
build_filter() {
    if $VERBOSE; then
        cat
    else
        grep -E "(error:|warning:|BUILD|Compiling|Linking)" || true
    fi
}

# Quit app gracefully
quit_app() {
    local app_name=$1
    echo -n "  Stopping $app_name... "
    osascript -e "tell application \"$app_name\" to quit" 2>/dev/null || true
    sleep 0.3
    echo -e "${GREEN}done${NC}"
}

# Stop engine service
stop_engine() {
    echo -n "  Stopping TalkieEngine service... "
    pkill -f "TalkieEngine.app" 2>/dev/null || true
    sleep 0.3
    echo -e "${GREEN}done${NC}"
}

# Install and start engine service
install_engine() {
    local app_path=$1
    local stable_path="$BUILD_BASE/Debug"

    echo -n "  Installing to stable path... "
    mkdir -p "$stable_path"
    rm -rf "$stable_path/TalkieEngine.app"
    cp -R "$app_path" "$stable_path/"
    echo -e "${GREEN}done${NC}"

    echo -n "  Starting service... "
    # Try to start via LaunchAgent if configured
    local agent_label="jdi.talkie.engine.debug"
    if launchctl list 2>/dev/null | grep -q "$agent_label"; then
        launchctl kickstart -p "gui/$(id -u)/$agent_label" 2>/dev/null || \
        open "$stable_path/TalkieEngine.app"
    else
        open "$stable_path/TalkieEngine.app"
    fi
    sleep 0.5

    if pgrep -f "TalkieEngine.app" > /dev/null; then
        local pid=$(pgrep -f "TalkieEngine.app" | head -1)
        echo -e "${GREEN}running${NC} (PID: $pid)"
    else
        echo -e "${YELLOW}started${NC}"
    fi
}

# Build an app using the workspace
build_app() {
    local app=$1
    local scheme=$(get_scheme "$app")
    local type=$(get_type "$app")
    local build_dir="$BUILD_BASE/$scheme"
    local app_path="$build_dir/Build/Products/Debug/$scheme.app"

    echo -e "${CYAN}━━━ $scheme ━━━${NC}"

    # Stop if running
    if [ "$type" = "service" ]; then
        stop_engine
    else
        quit_app "$scheme"
    fi

    # Check if exec-only mode
    if $EXEC_ONLY; then
        if [ ! -d "$app_path" ]; then
            echo -e "  ${RED}App not found at: $app_path${NC}"
            echo "  Run without -e to build first."
            return 1
        fi
        echo -e "  ${GREEN}Using existing build${NC}"
    else
        # Clean if requested
        if $CLEAN; then
            echo -n "  Cleaning... "
            rm -rf "$build_dir"
            echo -e "${GREEN}done${NC}"
        fi

        # Build using workspace
        echo "  Building..."
        local build_result=0

        if $VERBOSE; then
            xcodebuild -workspace "$WORKSPACE" \
                -scheme "$scheme" \
                -configuration Debug \
                -derivedDataPath "$build_dir" \
                CODE_SIGN_IDENTITY="Apple Development" \
                DEVELOPMENT_TEAM="2U83JFPW66" \
                build 2>&1 || build_result=$?
        else
            xcodebuild -workspace "$WORKSPACE" \
                -scheme "$scheme" \
                -configuration Debug \
                -derivedDataPath "$build_dir" \
                CODE_SIGN_IDENTITY="Apple Development" \
                DEVELOPMENT_TEAM="2U83JFPW66" \
                build 2>&1 | build_filter
            build_result=${PIPESTATUS[0]}
        fi

        if [ $build_result -ne 0 ]; then
            echo -e "  ${RED}Build FAILED${NC}"
            return 1
        fi

        echo -e "  ${GREEN}Build SUCCEEDED${NC}"
    fi

    # Launch/install
    if ! $NO_LAUNCH; then
        if [ "$type" = "service" ]; then
            install_engine "$app_path"
        else
            echo -n "  Launching... "
            open "$app_path"
            echo -e "${GREEN}done${NC}"
        fi

        # Debug mode: show PID and attach debugger
        if $DEBUG_MODE; then
            attach_xcode_debugger "$scheme" "$app_path"
        fi
    fi

    echo ""
    return 0
}

# Attach Xcode debugger to app
attach_xcode_debugger() {
    local app_name=$1
    local app_path=$2

    echo ""
    echo -e "${YELLOW}━━━ DEBUG MODE ━━━${NC}"

    # Wait for app to launch
    sleep 2

    # Get PID
    local pid=$(pgrep -x "$app_name" | head -1)
    if [ -z "$pid" ]; then
        pid=$(pgrep -f "$app_name.app/Contents/MacOS/$app_name" | head -1)
    fi
    if [ -z "$pid" ]; then
        pid=$(pgrep -f "$app_path" | head -1)
    fi

    if [ -z "$pid" ]; then
        echo -e "  ${RED}⚠️  Could not find $app_name process${NC}"
        echo -e "  ${YELLOW}Searching for: $app_name${NC}"
        return 1
    fi

    echo -e "  📱 App: ${CYAN}$app_name${NC}"
    echo -e "  🔢 PID: ${CYAN}$pid${NC}"
    echo ""
    echo -e "  To attach debugger in Xcode:"
    echo -e "  ${CYAN}Debug → Attach to Process by PID or Name → $pid${NC}"
    echo ""
}

# Main
echo -e "${BLUE}Talkie Build Script${NC}"
echo "Apps: $APPS_TO_BUILD"
echo ""

FAILED=""
for app in $APPS_TO_BUILD; do
    if ! build_app "$app"; then
        FAILED="$FAILED $app"
    fi
done

# Summary
if [ -n "$FAILED" ]; then
    echo -e "${RED}Failed:$FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}All builds succeeded!${NC}"
fi
