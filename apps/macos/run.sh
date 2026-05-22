#!/bin/bash
# Unified build and run script for Talkie macOS apps
#
# Usage:
#   ./run.sh TalkieAgent    # Build and run TalkieAgent
#   ./run.sh Talkie         # Build and run Talkie (main app)
#   ./run.sh TalkieAgent Talkie
#   ./run.sh all            # Build all apps
#   ./run.sh --list         # List available apps
#
# Options:
#   --no-launch    Build only, don't launch
#   --clean        Clean before building
#   --verbose      Show full build output

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE="$ROOT_DIR/TalkieSuite.xcworkspace"
BUILD_BASE="$ROOT_DIR/build/macos"
DEV_APPS_DIR="${TALKIE_DEV_APPS_DIR:-$HOME/Applications/Talkie.dev}"
ALLOW_DERIVEDDATA_FALLBACK="${TALKIE_ALLOW_DERIVEDDATA_FALLBACK:-0}"
RUN_ENV="${TALKIE_RUN_ENV:-dev}"
SIGNING_ENV_FILE="${TALKIE_SIGNING_ENV_FILE:-$ROOT_DIR/Config/signing.env}"

if [ -f "$SIGNING_ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$SIGNING_ENV_FILE"
    set +a
fi

LOCAL_XCCONFIG="$ROOT_DIR/Config/Signing.local.xcconfig"

xcconfig_value() {
    local key=$1
    local file=$2
    local line
    local value

    [ -f "$file" ] || return 1

    # Local signing config is intentionally simple: KEY = value.
    line=$(grep -E "^[[:space:]]*$key[[:space:]]*=" "$file" | tail -n 1)
    [ -n "$line" ] || return 1

    value="${line#*=}"
    value="${value%%//*}"
    printf '%s\n' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

apply_local_xcconfig_default() {
    local key=$1
    local value

    [ -z "${!key:-}" ] || return 0
    value=$(xcconfig_value "$key" "$LOCAL_XCCONFIG" || true)
    [ -n "$value" ] || return 0
    export "$key=$value"
}

apply_local_xcconfig_default TALKIE_DEVELOPMENT_TEAM
apply_local_xcconfig_default TALKIE_CODE_SIGNING_ALLOWED
apply_local_xcconfig_default TALKIE_CODE_SIGNING_REQUIRED
apply_local_xcconfig_default TALKIE_CODE_SIGN_IDENTITY
apply_local_xcconfig_default TALKIE_APP_IDENTIFIER

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

AVAILABLE_APPS="TalkieAgent Talkie"

# Get scheme for app
get_scheme() {
    case $1 in
        TalkieAgent|live) echo "TalkieAgent" ;;
        Talkie|core|code) echo "Talkie (Talkie project)" ;;
    esac
}

get_product() {
    case $1 in
        TalkieAgent|live) echo "TalkieAgent" ;;
        Talkie|core|code) echo "Talkie" ;;
    esac
}

normalize_app() {
    case $1 in
        TalkieAgent|live) echo "TalkieAgent" ;;
        Talkie|core|code) echo "Talkie" ;;
        *) return 1 ;;
    esac
}

get_bundle_id() {
    local app_path=$1
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_path/Contents/Info.plist" 2>/dev/null || true
}

get_entitlements() {
    case $1 in
        TalkieAgent|live) echo "$SCRIPT_DIR/TalkieAgent/TalkieAgent/TalkieAgent.entitlements" ;;
        Talkie|core|code) echo "$SCRIPT_DIR/Talkie/Talkie.entitlements" ;;
    esac
}

get_xpc_service_name() {
    local bundle_id=$1

    case "$bundle_id" in
        *.dev)
            echo "${bundle_id%.dev}.xpc.dev"
            ;;
        *.staging)
            echo "${bundle_id%.staging}.xpc.staging"
            ;;
        *)
            echo "${bundle_id}.xpc"
            ;;
    esac
}

latest_derived_app() {
    local product=$1
    local derived_data="$HOME/Library/Developer/Xcode/DerivedData"
    local latest_app=""
    local latest_time=0

    [ -d "$derived_data" ] || return 1

    for project_dir in "$derived_data"/*; do
        [ -d "$project_dir" ] || continue

        local app_path="$project_dir/Build/Products/Debug/$product.app"
        local executable_path="$app_path/Contents/MacOS/$product"
        [ -f "$executable_path" ] || continue

        local mod_time
        mod_time=$(stat -f %m "$executable_path" 2>/dev/null || echo "0")

        if [ "$mod_time" -gt "$latest_time" ]; then
            latest_time=$mod_time
            latest_app=$app_path
        fi
    done

    [ -n "$latest_app" ] || return 1
    echo "$latest_app"
}

stable_dev_app() {
    local product=$1
    echo "$DEV_APPS_DIR/$product.app"
}

is_nonprod_bundle_id() {
    local bundle_id=$1
    [[ "$bundle_id" == *.dev || "$bundle_id" == *.staging ]]
}

resolve_app_path() {
    local app=$1
    local product=$(get_product "$app")
    local local_app="$BUILD_BASE/$product/Build/Products/Debug/$product.app"
    local dev_app
    dev_app=$(stable_dev_app "$product")

    if $EXEC_ONLY; then
        [ -d "$dev_app" ] && echo "$dev_app" && return 0
        [ -d "$local_app" ] && echo "$local_app" && return 0
        if [ "$ALLOW_DERIVEDDATA_FALLBACK" = "1" ]; then
            latest_derived_app "$product" && return 0
        fi
        return 1
    fi

    echo "$local_app"
}

install_dev_app_if_needed() {
    local app_path=$1
    local product=$2
    local bundle_id=$3
    local dest

    RUNNABLE_APP_PATH="$app_path"

    is_nonprod_bundle_id "$bundle_id" || return 0

    dest=$(stable_dev_app "$product")
    if [ "$app_path" = "$dest" ]; then
        RUNNABLE_APP_PATH="$dest"
        return 0
    fi

    echo -n "  Installing dev app... "
    mkdir -p "$DEV_APPS_DIR"
    rm -rf "$dest"
    /usr/bin/ditto "$app_path" "$dest"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
        -f "$dest" >/dev/null 2>&1 || true
    RUNNABLE_APP_PATH="$dest"
    echo -e "${GREEN}done${NC}"
    echo "  Path: $dest"
}

quit_bundle_id() {
    local bundle_id=$1
    osascript -e "tell application id \"$bundle_id\" to quit" 2>/dev/null || true
}

bootout_label() {
    local label=$1
    /bin/launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
}

stop_bundle_ids() {
    for bundle_id in "$@"; do
        quit_bundle_id "$bundle_id"
    done

    sleep 0.5

    for bundle_id in "$@"; do
        bootout_label "$bundle_id"
    done
}

talkie_bundle_id() {
    local app_id=$1
    local env=$2
    local project_prefix="${TALKIE_APP_IDENTIFIER:-to.talkie.app}"

    if [ "$env" = "prod" ]; then
        echo "$project_prefix.$app_id"
    else
        echo "$project_prefix.$app_id.$env"
    fi
}

stop_talkie_app_family() {
    local product=$1
    local app_id=$2
    local bundle_id
    local dev_executable
    local build_executable
    bundle_id=$(talkie_bundle_id "$app_id" "$RUN_ENV")
    dev_executable="$DEV_APPS_DIR/$product.app/Contents/MacOS/$product"
    build_executable="$BUILD_BASE/$product/Build/Products/Debug/$product.app/Contents/MacOS/$product"

    echo -n "  Stopping $product ($RUN_ENV)... "
    stop_bundle_ids "$bundle_id"
    pkill -f "$dev_executable" 2>/dev/null || true
    pkill -f "$build_executable" 2>/dev/null || true
    echo -e "${GREEN}done${NC}"
}

dequarantine_app() {
    local app_path=$1

    [ -d "$app_path" ] || return 0

    echo -n "  Clearing quarantine... "
    /usr/bin/xattr -dr com.apple.quarantine "$app_path" 2>/dev/null || true
    echo -e "${GREEN}done${NC}"
}

sign_app_bundle() {
    local app=$1
    local app_path=$2
    local identity=$3
    local entitlements

    [ -n "$identity" ] || return 0
    [ -d "$app_path" ] || return 0

    entitlements=$(get_entitlements "$app")

    echo -n "  Code signing bundle... "
    if [ -f "$entitlements" ] && ! grep -q '\$(' "$entitlements"; then
        codesign --force --deep --sign "$identity" --entitlements "$entitlements" "$app_path" >/dev/null
    else
        codesign --force --deep --sign "$identity" "$app_path" >/dev/null
    fi
    codesign --verify --deep --strict "$app_path" >/dev/null
    echo -e "${GREEN}done${NC}"
}

stop_conflicting_instances() {
    local app=$1

    case "$app" in
        TalkieAgent|live)
            stop_talkie_app_family "TalkieAgent" "agent"
            ;;
        Talkie|core|code)
            stop_talkie_app_family "Talkie" "mac"
            ;;
    esac
}

launch_dev_agent_via_launchctl() {
    local app_path=$1
    local executable_name=$2
    local bundle_id=$3
    local xpc_service
    xpc_service=$(get_xpc_service_name "$bundle_id")
    local executable_path="$app_path/Contents/MacOS/$executable_name"
    local plist_path="$HOME/Library/LaunchAgents/$bundle_id.plist"

    mkdir -p "$HOME/Library/LaunchAgents"
    bootout_label "$bundle_id"
    rm -f "$plist_path"

    cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$bundle_id</string>
    <key>ProgramArguments</key>
    <array>
        <string>$executable_path</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>$xpc_service</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>/tmp/$bundle_id.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/$bundle_id.stderr.log</string>
</dict>
</plist>
EOF

    /bin/launchctl bootstrap "gui/$(id -u)" "$plist_path" >/dev/null 2>&1 || true
    /bin/launchctl kickstart "gui/$(id -u)/$bundle_id" >/dev/null 2>&1 || true
    /bin/launchctl print "gui/$(id -u)/$bundle_id" >/dev/null 2>&1
}

launch_app() {
    local app=$1
    local app_path=$2
    local product=$(get_product "$app")
    local bundle_id
    bundle_id=$(get_bundle_id "$app_path")

    if [ "$product" = "TalkieAgent" ] && [[ "$bundle_id" == *.dev || "$bundle_id" == *.staging ]]; then
        echo -n "  Launching via launchctl... "
        if launch_dev_agent_via_launchctl "$app_path" "$product" "$bundle_id"; then
            echo -e "${GREEN}done${NC}"
        else
            echo -e "${RED}failed${NC}"
            return 1
        fi
        return 0
    fi

    echo -n "  Launching... "
    open "$app_path"
    echo -e "${GREEN}done${NC}"
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
            echo "  TalkieAgent  - menu bar transcription agent"
            echo "  Talkie       - main app with workflows"
            echo ""
            echo "Usage: ./run.sh [apps...] [options]"
            echo "  ./run.sh TalkieAgent       Build and run TalkieAgent"
            echo "  ./run.sh TalkieAgent Talkie"
            echo "                            Build multiple apps"
            echo "  ./run.sh all               Build all apps"
            echo ""
            echo "Options:"
            echo "  -e            Just run (no build)"
            echo "  --no-launch   Build only"
            echo "  --clean       Clean build"
            echo "  --verbose     Full output"
            echo "  --debug, -d   Print PID and attach Xcode debugger"
            echo ""
            echo "Dev apps install to: ${DEV_APPS_DIR/#$HOME/~}"
            echo "Run environment: $RUN_ENV"
            exit 0
            ;;
        --help|-h)
            echo "Talkie Build Script"
            echo ""
            echo "Usage: ./run.sh [apps...] [options]"
            echo ""
            echo "Apps: TalkieAgent, Talkie, all"
            echo ""
            echo "Options:"
            echo "  -e            Just run latest build (no rebuild)"
            echo "  --no-launch   Build only, don't launch"
            echo "  --clean       Clean before building"
            echo "  --verbose     Show full build output"
            echo "  --debug, -d   Print PID and attach Xcode debugger"
            echo "  --list, -l    List available apps"
            echo "  --help, -h    Show this help"
            echo ""
            echo "Dev apps install to: ${DEV_APPS_DIR/#$HOME/~}"
            echo "Run environment: $RUN_ENV"
            echo "Set TALKIE_ALLOW_DERIVEDDATA_FALLBACK=1 for one-off Xcode-only runs."
            exit 0
            ;;
        all)
            APPS_TO_BUILD="$AVAILABLE_APPS"
            ;;
        *)
            if normalized_app=$(normalize_app "$arg"); then
                APPS_TO_BUILD="$APPS_TO_BUILD $normalized_app"
            else
                echo -e "${RED}Unknown app or option: $arg${NC}"
                echo "Run './run.sh --list' to see available apps"
                exit 1
            fi
            ;;
    esac
done

# Default to TalkieAgent if no app specified
if [ -z "$APPS_TO_BUILD" ]; then
    echo -e "${YELLOW}No app specified, defaulting to 'TalkieAgent'${NC}"
    echo "Run './run.sh --list' for options"
    echo ""
    APPS_TO_BUILD="TalkieAgent"
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

# Build an app using the workspace
build_app() {
    local app=$1
    local scheme=$(get_scheme "$app")
    local product=$(get_product "$app")
    local build_dir="$BUILD_BASE/$product"
    local app_path

    echo -e "${CYAN}━━━ $product ━━━${NC}"

    # Stop conflicting production/dev instances before relaunching
    stop_conflicting_instances "$app"

    # Check if exec-only mode
    if $EXEC_ONLY; then
        app_path=$(resolve_app_path "$app") || true
        if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
            echo -e "  ${RED}No runnable build found for $product${NC}"
            echo "  Run without -e to build first."
            return 1
        fi
        echo -e "  ${GREEN}Using freshest build${NC}"
        echo "  Path: $app_path"
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
        local development_team="${TALKIE_DEVELOPMENT_TEAM:-${TALKIE_TEAM_ID:-}}"
        local code_sign_identity="${TALKIE_CODE_SIGN_IDENTITY:-Apple Development}"
        local xcodebuild_args=(
            -workspace "$WORKSPACE"
            -scheme "$scheme"
            -configuration Debug
            -destination "platform=macOS"
            -derivedDataPath "$build_dir"
        )

        if [ -n "$development_team" ]; then
            echo "  Signing: post-build $code_sign_identity ($development_team)"
        else
            echo "  Signing: disabled"
        fi

        xcodebuild_args+=(
            "CODE_SIGNING_ALLOWED=NO"
            "CODE_SIGNING_REQUIRED=NO"
            "CODE_SIGN_IDENTITY="
        )

        if $VERBOSE; then
            xcodebuild "${xcodebuild_args[@]}" build 2>&1 || build_result=$?
        else
            xcodebuild "${xcodebuild_args[@]}" build 2>&1 | build_filter
            build_result=${PIPESTATUS[0]}
        fi

        if [ $build_result -ne 0 ]; then
            echo -e "  ${RED}Build FAILED${NC}"
            return 1
        fi

        echo -e "  ${GREEN}Build SUCCEEDED${NC}"
        app_path="$build_dir/Build/Products/Debug/$product.app"
    fi

    if [ -n "${TALKIE_DEVELOPMENT_TEAM:-${TALKIE_TEAM_ID:-}}" ]; then
        sign_app_bundle "$app" "$app_path" "${TALKIE_CODE_SIGN_IDENTITY:-Apple Development}" || return 1
    fi

    local bundle_id
    bundle_id=$(get_bundle_id "$app_path")
    install_dev_app_if_needed "$app_path" "$product" "$bundle_id" || return 1
    app_path="$RUNNABLE_APP_PATH"

    if [ -n "${TALKIE_DEVELOPMENT_TEAM:-${TALKIE_TEAM_ID:-}}" ]; then
        codesign --verify --deep --strict "$app_path" >/dev/null || return 1
    fi

    dequarantine_app "$app_path"

    # Launch
    if ! $NO_LAUNCH; then
        launch_app "$app" "$app_path" || return 1

        # Debug mode: show PID and attach debugger
        if $DEBUG_MODE; then
            attach_xcode_debugger "$product" "$app_path"
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
