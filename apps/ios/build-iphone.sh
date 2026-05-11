#!/bin/bash
#
# build-iphone.sh - Build and deploy Talkie to connected iPhone
#
# Usage:
#   ./build-iphone.sh              # Build and install
#   ./build-iphone.sh -r|--run     # Build, install, and launch app
#   ./build-iphone.sh --build-only # Just build, don't install
#   ./build-iphone.sh --install    # Just install (skip build)
#   ./build-iphone.sh --launch     # Just launch (assumes installed)
#   ./build-iphone.sh --list       # List connected devices
#

set -e

# Config
PROJECT="Talkie-iOS.xcodeproj"
SCHEME="Talkie"
CONFIG="Debug"
BUNDLE_ID="${TALKIE_IOS_APP_BUNDLE_ID:-${TALKIE_IOS_BUNDLE_ID:-}}"
DEVICE_CACHE_FILE_LOCAL=".iphone-device-id.local"
DEVICE_CACHE_FILE_LEGACY=".iphone-device-id"
DERIVED_DATA_PATH="$(pwd)/build/DerivedData-iphone"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIG-iphoneos/Talkie.app"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

cd "$(dirname "$0")"

# Normalize to uppercase to keep IDs consistent across tools
normalize_device_id() {
    echo "${1:-}" | tr '[:lower:]' '[:upper:]'
}

save_cached_device_id() {
    local device_id
    device_id=$(normalize_device_id "$1")

    if [[ -z "$device_id" ]]; then
        return 1
    fi

    echo "$device_id" > "$DEVICE_CACHE_FILE_LOCAL"
    return 0
}

read_cached_device_id() {
    if [[ -f "$DEVICE_CACHE_FILE_LOCAL" ]]; then
        cat "$DEVICE_CACHE_FILE_LOCAL"
        return 0
    fi

    # Backward-compatible fallback for older sessions.
    if [[ -f "$DEVICE_CACHE_FILE_LEGACY" ]]; then
        cat "$DEVICE_CACHE_FILE_LEGACY"
        return 0
    fi

    return 1
}

is_device_connected() {
    local device_id
    device_id=$(normalize_device_id "$1")

    if [[ -z "$device_id" ]]; then
        return 1
    fi

    xcrun xctrace list devices 2>/dev/null | grep -q "$device_id"
}

resolve_bundle_id() {
    if [[ -n "$BUNDLE_ID" ]]; then
        echo "$BUNDLE_ID"
        return 0
    fi

    if [[ -f "$APP_PATH/Info.plist" ]]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_PATH/Info.plist"
        return $?
    fi

    echo -e "${RED}Error: TALKIE_IOS_APP_BUNDLE_ID is not set and no built app was found at $APP_PATH.${NC}" >&2
    return 1
}

# Find iPhone device ID
find_iphone() {
    # Highest priority: explicit env var override.
    if [[ -n "${TALKIE_DEVICE_ID:-}" ]]; then
        OVERRIDE_ID=$(normalize_device_id "$TALKIE_DEVICE_ID")
        if is_device_connected "$OVERRIDE_ID"; then
            save_cached_device_id "$OVERRIDE_ID"
            echo "$OVERRIDE_ID"
            return 0
        fi
        echo -e "${YELLOW}Configured TALKIE_DEVICE_ID ($OVERRIDE_ID) is not connected.${NC}" >&2
    fi

    # Check local cache first
    CACHED_ID=$(read_cached_device_id || true)
    if [[ -n "$CACHED_ID" ]]; then
        CACHED_ID=$(normalize_device_id "$CACHED_ID")
        if is_device_connected "$CACHED_ID"; then
            save_cached_device_id "$CACHED_ID"
            echo "$CACHED_ID"
            return 0
        fi
    fi

    # Find iPhone from connected devices
    DEVICE_LINE=$(xcrun xctrace list devices 2>/dev/null | grep "iPhone" | grep -v "Simulator" | head -1)
    if [[ -z "$DEVICE_LINE" ]]; then
        return 1
    fi

    # Extract device ID (in parentheses at end)
    DEVICE_ID=$(echo "$DEVICE_LINE" | grep -oE '\([A-Za-z0-9-]+\)$' | tr -d '()')
    DEVICE_ID=$(normalize_device_id "$DEVICE_ID")

    if [[ -n "$DEVICE_ID" ]]; then
        # Cache it
        save_cached_device_id "$DEVICE_ID"
        echo "$DEVICE_ID"
        return 0
    fi

    return 1
}

# List devices
list_devices() {
    echo -e "${CYAN}Connected Devices:${NC}"
    xcrun xctrace list devices 2>/dev/null | grep -E "iPhone|iPad" | grep -v "Simulator"

    CACHED_ID=$(read_cached_device_id || true)
    if [[ -n "$CACHED_ID" ]]; then
        echo -e "\n${CYAN}Cached device ID:${NC} $(normalize_device_id "$CACHED_ID")"
        echo -e "${CYAN}Cache file:${NC} $(pwd)/$DEVICE_CACHE_FILE_LOCAL"
    else
        echo -e "\n${YELLOW}No cached device ID found.${NC}"
        echo -e "Use ${CYAN}$0 --set-device <DEVICE_ID>${NC} to pin one."
    fi
}

show_cached_device() {
    CACHED_ID=$(read_cached_device_id || true)
    if [[ -z "$CACHED_ID" ]]; then
        echo -e "${YELLOW}No cached device ID found.${NC}"
        echo -e "Cache path: $(pwd)/$DEVICE_CACHE_FILE_LOCAL"
        return 1
    fi

    CACHED_ID=$(normalize_device_id "$CACHED_ID")
    echo -e "${CYAN}Cached device ID:${NC} $CACHED_ID"
    echo -e "${CYAN}Cache file:${NC} $(pwd)/$DEVICE_CACHE_FILE_LOCAL"

    if is_device_connected "$CACHED_ID"; then
        echo -e "${GREEN}Status:${NC} connected"
    else
        echo -e "${YELLOW}Status:${NC} not currently connected"
    fi
}

# Build
do_build() {
    DEVICE_ID="$1"
    echo -e "${CYAN}Building $SCHEME for device $DEVICE_ID...${NC}"

    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIG" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -destination "id=$DEVICE_ID" \
        build 2>&1 | grep -E "^(Build|Compile|Link|Sign|Copy|error:|warning:|\*\*)" || true

    # Check if build succeeded
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        echo -e "${GREEN}Build succeeded${NC}"
        return 0
    else
        echo -e "${RED}Build failed${NC}"
        return 1
    fi
}

# Install
do_install() {
    DEVICE_ID="$1"

    if [[ -z "$APP_PATH" ]]; then
        echo -e "${RED}Error: Talkie.app not found. Run build first.${NC}"
        return 1
    fi

    if [[ ! -d "$APP_PATH" ]]; then
        echo -e "${RED}Error: Expected app at $APP_PATH but it does not exist. Run build first.${NC}"
        return 1
    fi

    echo -e "${CYAN}Installing to device $DEVICE_ID...${NC}"
    echo -e "${YELLOW}App: $APP_PATH${NC}"

    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1 | grep -E "App installed|bundleID|error" || true

    echo -e "${GREEN}Installed!${NC}"
}

# Filter known-benign stderr from `devicectl process launch` (Xcode 16+): it may log
# CoreDeviceError 1002 "No provider was found" while loading provisioning metadata, then launch anyway.
filter_devicectl_launch_noise() {
    grep -v -E '^$|Failed to load provisioning|No provider was found|devicectl manage create' || true
}

# Launch app
do_launch() {
    DEVICE_ID="$1"
    DEEP_LINK="${2:-}"
    LAUNCH_BUNDLE_ID=$(resolve_bundle_id)

    if [[ -n "$DEEP_LINK" ]]; then
        echo -e "${CYAN}Launching $LAUNCH_BUNDLE_ID with deep link: $DEEP_LINK${NC}"
        # Pass the URL as an environment variable the app can read
        # Note: Environment variables require the DEVICECTL_CHILD_ prefix or -e flag
        xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing \
            -e "{\"TALKIE_OPEN_URL\": \"$DEEP_LINK\"}" \
            "$LAUNCH_BUNDLE_ID" 2>&1 | filter_devicectl_launch_noise
    else
        echo -e "${CYAN}Launching $LAUNCH_BUNDLE_ID...${NC}"
        xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$LAUNCH_BUNDLE_ID" 2>&1 | filter_devicectl_launch_noise
    fi

    echo -e "${GREEN}Launched!${NC}"
}

# Main
case "${1:-}" in
    --list|-l)
        list_devices
        ;;
    --show-device)
        show_cached_device
        ;;
    --set-device|-s)
        DEVICE_ID_OVERRIDE=$(normalize_device_id "${2:-}")
        if [[ -z "$DEVICE_ID_OVERRIDE" ]]; then
            echo -e "${RED}Usage: $0 --set-device <DEVICE_ID>${NC}"
            exit 1
        fi

        save_cached_device_id "$DEVICE_ID_OVERRIDE"
        echo -e "${GREEN}Saved preferred device:${NC} $DEVICE_ID_OVERRIDE"
        echo -e "${CYAN}Cache file:${NC} $(pwd)/$DEVICE_CACHE_FILE_LOCAL"
        if ! is_device_connected "$DEVICE_ID_OVERRIDE"; then
            echo -e "${YELLOW}Note:${NC} That device is not currently connected."
        fi
        ;;
    --clear-device)
        rm -f "$DEVICE_CACHE_FILE_LOCAL"
        rm -f "$DEVICE_CACHE_FILE_LEGACY"
        echo -e "${GREEN}Cleared cached device ID.${NC}"
        ;;
    --build-only|-b)
        DEVICE_ID=$(find_iphone)
        if [[ -z "$DEVICE_ID" ]]; then
            echo -e "${RED}No iPhone found${NC}"
            exit 1
        fi
        do_build "$DEVICE_ID"
        ;;
    --install|-i)
        DEVICE_ID=$(find_iphone)
        if [[ -z "$DEVICE_ID" ]]; then
            echo -e "${RED}No iPhone found${NC}"
            exit 1
        fi
        do_install "$DEVICE_ID"
        ;;
    --launch)
        DEVICE_ID=$(find_iphone)
        if [[ -z "$DEVICE_ID" ]]; then
            echo -e "${RED}No iPhone found${NC}"
            exit 1
        fi
        do_launch "$DEVICE_ID"
        ;;
    --run|-r)
        # Build, install, and launch
        DEVICE_ID=$(find_iphone)
        if [[ -z "$DEVICE_ID" ]]; then
            echo -e "${RED}No iPhone found${NC}"
            exit 1
        fi
        echo -e "${CYAN}Found iPhone: $DEVICE_ID${NC}"
        do_build "$DEVICE_ID" && do_install "$DEVICE_ID" && do_launch "$DEVICE_ID"
        ;;
    --keyboard|-k)
        # Build, install, and launch directly into keyboard playground
        DEVICE_ID=$(find_iphone)
        if [[ -z "$DEVICE_ID" ]]; then
            echo -e "${RED}No iPhone found${NC}"
            exit 1
        fi
        echo -e "${CYAN}Found iPhone: $DEVICE_ID${NC}"
        do_build "$DEVICE_ID" && do_install "$DEVICE_ID" && do_launch "$DEVICE_ID" "talkie://keyboard"
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (no args)       Build and install"
        echo "  -r, --run       Build, install, and launch app"
        echo "  -k, --keyboard  Build, install, and open keyboard playground"
        echo "  -b, --build-only  Just build"
        echo "  -i, --install   Just install (assumes already built)"
        echo "  --launch        Just launch (assumes installed)"
        echo "  -l, --list      List connected devices"
        echo "  -s, --set-device <id>  Save preferred physical device ID"
        echo "  --show-device   Show cached preferred device ID"
        echo "  --clear-device  Remove cached preferred device ID"
        echo ""
        echo "Env override:"
        echo "  TALKIE_DEVICE_ID=<id>  Use this device for the current run"
        echo "  TALKIE_IOS_APP_BUNDLE_ID=<id>  Override launch bundle identifier"
        ;;
    *)
        DEVICE_ID=$(find_iphone)
        if [[ -z "$DEVICE_ID" ]]; then
            echo -e "${RED}No iPhone found. Connect your device and try again.${NC}"
            echo -e "Use ${CYAN}$0 --list${NC} to see connected devices."
            exit 1
        fi

        echo -e "${CYAN}Found iPhone: $DEVICE_ID${NC}"
        do_build "$DEVICE_ID" && do_install "$DEVICE_ID"
        ;;
esac
