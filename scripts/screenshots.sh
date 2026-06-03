#!/bin/bash
set -e
set -o pipefail

# Talkie App Store Screenshot Script
# Fast alternative to fastlane snapshot — boots sim, overrides status bar,
# runs UI tests, collects PNGs at exact App Store dimensions.
#
# Usage:
#   ./scripts/screenshots.sh                # Both devices (iPhone + iPad)
#   ./scripts/screenshots.sh iphone         # iPhone only
#   ./scripts/screenshots.sh ipad           # iPad only
#   ./scripts/screenshots.sh --list         # Show available devices + resolutions
#   ./scripts/screenshots.sh --open         # Open output folder after

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
DIM='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Device Config ────────────────────────────────────────────────────

IPHONE_NAME="iPhone 17 Pro Max"
IPHONE_W=1320
IPHONE_H=2868
IPHONE_CLASS="6.9\" iPhone"

IPAD_NAME="iPad Pro 13-inch (M5)"
IPAD_W=2064
IPAD_H=2752
IPAD_CLASS="13\" iPad"

# Fastlane cache dir (SnapshotHelper reads language/locale from here)
CACHE_DIR="$HOME/Library/Caches/tools.fastlane"
CACHE_SCREENSHOTS="$CACHE_DIR/screenshots"

# Output
OUTPUT_DIR="$ROOT_DIR/apps/ios/fastlane/screenshots"
BUILD_CACHE_DIR="$HOME/Library/Caches/codex-builds"
DERIVED_DATA_DIR="${TALKIE_SCREENSHOTS_DERIVED_DATA_DIR:-$BUILD_CACHE_DIR/deriveddata-ios-screenshots}"

# ─── Helpers ──────────────────────────────────────────────────────────

info()    { echo -e "${CYAN}ℹ${NC}  $1"; }
success() { echo -e "${GREEN}✓${NC}  $1"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $1"; }
fail()    { echo -e "${RED}✗${NC}  $1"; exit 1; }
step()    { echo -e "\n${BOLD}$1${NC}"; }

device_attr() {
    local device="$1" attr="$2"
    case "$device" in
        "$IPHONE_NAME")
            case "$attr" in
                udid)  resolve_udid "$IPHONE_NAME" || true ;;
                w)     echo "$IPHONE_W" ;;
                h)     echo "$IPHONE_H" ;;
                class) echo "$IPHONE_CLASS" ;;
            esac
            ;;
        "$IPAD_NAME")
            case "$attr" in
                udid)  resolve_udid "$IPAD_NAME" || true ;;
                w)     echo "$IPAD_W" ;;
                h)     echo "$IPAD_H" ;;
                class) echo "$IPAD_CLASS" ;;
            esac
            ;;
        *)
            fail "Unknown device: $device"
            ;;
    esac
}

resolve_udid() {
    local name="$1"
    xcrun simctl list devices available -j | /usr/bin/ruby -rjson -e '
      name = ARGV[0]
      devices = JSON.parse(STDIN.read)["devices"].values.flatten
      match = devices.find { |device| device["name"] == name && device["isAvailable"] }
      exit 1 unless match
      puts match["udid"]
    ' "$name"
}

validate_device() {
    local name="$1"
    local udid
    udid=$(device_attr "$name" udid)

    if [ -z "$udid" ]; then
        fail "Simulator not found: $name\n   Create it in Xcode → Window → Devices and Simulators"
    fi
}

boot_simulator() {
    local name="$1"
    local udid
    udid=$(device_attr "$name" udid)

    if xcrun simctl list devices | grep "$udid" | grep -q "Booted"; then
        info "$name already booted"
    else
        info "Booting $name..."
        xcrun simctl boot "$udid"
        sleep 3
        success "$name booted"
    fi
}

override_status_bar() {
    local udid="$1"
    xcrun simctl status_bar "$udid" override \
        --time "9:41" \
        --dataNetwork wifi \
        --wifiBars 3 \
        --cellularBars 4 \
        --batteryState charged \
        --batteryLevel 100
}

clear_status_bar() {
    local udid="$1"
    xcrun simctl status_bar "$udid" clear 2>/dev/null || true
}

setup_fastlane_cache() {
    mkdir -p "$CACHE_DIR"
    mkdir -p "$CACHE_SCREENSHOTS"
    echo "en" > "$CACHE_DIR/language.txt"
    echo "en_US" > "$CACHE_DIR/locale.txt"
}

clear_cache_screenshots() {
    rm -f "$CACHE_SCREENSHOTS"/*.png
}

build_tests() {
    info "Building tests..."
    mkdir -p "$BUILD_CACHE_DIR"
    local log_file="$BUILD_CACHE_DIR/talkie-screenshots-build-$(date +%Y%m%d-%H%M%S).log"

    xcodebuild build-for-testing \
        -project "$ROOT_DIR/apps/ios/Talkie-iOS.xcodeproj" \
        -scheme TalkieUITests \
        -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$DERIVED_DATA_DIR" \
        2>&1 | tee "$log_file" | while IFS= read -r line; do
            # Show compilation progress and errors
            if echo "$line" | grep -qE "^(Compiling|Linking|Build Succeeded|BUILD SUCCEEDED|error:|warning:.*error)"; then
                echo -e "   ${DIM}$line${NC}"
            fi
        done

    local exit_code="${PIPESTATUS[0]}"
    if [ "$exit_code" -ne 0 ]; then
        warn "Build log: $log_file"
    fi
    return "$exit_code"
}

run_tests() {
    local udid="$1"
    mkdir -p "$BUILD_CACHE_DIR"
    local log_file="$BUILD_CACHE_DIR/talkie-screenshots-test-$(date +%Y%m%d-%H%M%S).log"

    xcodebuild test-without-building \
        -project "$ROOT_DIR/apps/ios/Talkie-iOS.xcodeproj" \
        -scheme TalkieUITests \
        -destination "platform=iOS Simulator,id=$udid" \
        -only-testing:TalkieUITests/TalkieUITestsScreenshots/test00_Splash \
        -only-testing:TalkieUITests/TalkieUITestsScreenshots/test01_Home \
        -only-testing:TalkieUITests/TalkieUITestsScreenshots/test02_Recording \
        -only-testing:TalkieUITests/TalkieUITestsScreenshots/test03_MemoDetail \
        -only-testing:TalkieUITests/TalkieUITestsScreenshots/test04_Settings \
        -only-testing:TalkieUITests/TalkieUITestsScreenshots/test05_Keyboard \
        -parallel-testing-enabled NO \
        -derivedDataPath "$DERIVED_DATA_DIR" \
        2>&1 | tee "$log_file" | while IFS= read -r line; do
            if echo "$line" | grep -qE "(snapshot:|Test Case|Test Suite|Tests? (passed|failed)|TEST SUCCEEDED|TEST FAILED|error:)"; then
                echo -e "   ${DIM}$line${NC}"
            fi
        done

    local exit_code="${PIPESTATUS[0]}"
    if [ "$exit_code" -ne 0 ]; then
        warn "Test log: $log_file"
    fi
    return "$exit_code"
}

collect_screenshots() {
    local device_name="$1"
    local dest="$OUTPUT_DIR/$device_name"

    mkdir -p "$dest"
    rm -f "$dest"/*.png

    local count=0
    for file in "$CACHE_SCREENSHOTS"/*.png; do
        [ -f "$file" ] || continue
        local basename
        basename=$(basename "$file")
        # SnapshotHelper format: "{SimulatorName}-{snapshotName}.png"
        # Strip the simulator name prefix
        local shot_name="${basename#"$device_name"-}"
        cp "$file" "$dest/$shot_name"
        count=$((count + 1))
    done

    if [ "$count" -eq 0 ]; then
        warn "No screenshots collected for $device_name"
        return 1
    fi

    success "Collected $count screenshots → $dest/"
}

verify_screenshots() {
    local device_name="$1"
    local expected_w expected_h
    expected_w=$(device_attr "$device_name" w)
    expected_h=$(device_attr "$device_name" h)
    local dir="$OUTPUT_DIR/$device_name"
    local all_ok=true

    for file in "$dir"/*.png; do
        [ -f "$file" ] || continue
        local fname
        fname=$(basename "$file")

        local w h
        w=$(sips -g pixelWidth "$file" | tail -1 | awk '{print $2}')
        h=$(sips -g pixelHeight "$file" | tail -1 | awk '{print $2}')

        if [ "$w" = "$expected_w" ] && [ "$h" = "$expected_h" ]; then
            success "$fname  ${DIM}${w} × ${h}${NC}"
        else
            warn "$fname  ${w} × ${h}  (expected ${expected_w} × ${expected_h})"
            all_ok=false
        fi
    done

    $all_ok
}

capture_device() {
    local device_name="$1"
    local udid
    udid=$(device_attr "$device_name" udid)
    local cls
    cls=$(device_attr "$device_name" class)
    local ew eh
    ew=$(device_attr "$device_name" w)
    eh=$(device_attr "$device_name" h)

    step "📱 $device_name  ${DIM}($cls, ${ew}×${eh})${NC}"

    validate_device "$device_name"
    boot_simulator "$device_name"

    info "Overriding status bar → 9:41, full bars, charged"
    override_status_bar "$udid"

    setup_fastlane_cache
    clear_cache_screenshots

    info "Running screenshot tests (no clones)..."
    set +e
    run_tests "$udid"
    local test_exit=$?
    set -e

    # Always restore status bar
    clear_status_bar "$udid"

    if [ $test_exit -ne 0 ]; then
        fail "Tests failed for $device_name (exit $test_exit)"
    fi

    collect_screenshots "$device_name"
    verify_screenshots "$device_name"
}

show_list() {
    echo -e "\n${BOLD}Available devices:${NC}\n"
    printf "  %-28s  %-40s  %-12s  %s\n" "DEVICE" "UDID" "PIXELS" "CLASS"
    printf "  %-28s  %-40s  %-12s  %s\n" "------" "----" "------" "-----"

    for name in "$IPHONE_NAME" "$IPAD_NAME"; do
        local udid cls
        udid=$(device_attr "$name" udid)
        cls=$(device_attr "$name" class)
        local ew eh
        ew=$(device_attr "$name" w)
        eh=$(device_attr "$name" h)

        local status="✓"
        if [ -z "$udid" ]; then
            status="✗ not found"
        fi

        printf "  %-28s  %-40s  %-12s  %s  %s\n" "$name" "$udid" "${ew}×${eh}" "$cls" "$status"
    done
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────

DEVICES=()
OPEN_AFTER=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        iphone|iPhone)
            DEVICES+=("$IPHONE_NAME")
            shift
            ;;
        ipad|iPad)
            DEVICES+=("$IPAD_NAME")
            shift
            ;;
        --list|-l)
            show_list
            exit 0
            ;;
        --open|-o)
            OPEN_AFTER=true
            shift
            ;;
        --help|-h)
            echo "Usage: screenshots.sh [iphone|ipad] [--list] [--open]"
            echo ""
            echo "  iphone     iPhone 17 Pro Max only"
            echo "  ipad       iPad Pro 13-inch (M5) only"
            echo "  --list     Show available devices and resolutions"
            echo "  --open     Open output folder when done"
            exit 0
            ;;
        *)
            fail "Unknown argument: $1  (try --help)"
            ;;
    esac
done

# Default: both devices
if [ ${#DEVICES[@]} -eq 0 ]; then
    DEVICES=("$IPHONE_NAME" "$IPAD_NAME")
fi

step "📸 Talkie App Store Screenshots"
info "Output: $OUTPUT_DIR"

# Build once, test on each device
build_tests

for device in "${DEVICES[@]}"; do
    capture_device "$device"
done

# Summary
step "Done!"
for device in "${DEVICES[@]}"; do
    echo -e "  ${GREEN}→${NC} $OUTPUT_DIR/$device/"
done

if $OPEN_AFTER; then
    open "$OUTPUT_DIR"
fi
