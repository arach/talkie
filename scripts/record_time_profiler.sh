#!/bin/bash
# record_time_profiler.sh - Record Time Profiler trace via xctrace
#
# Usage:
#   record_time_profiler.sh --attach <pid> [--time-limit 90s] [--output /tmp/trace.trace]
#   record_time_profiler.sh --launch /path/to/App.app [--time-limit 90s] [--output /tmp/trace.trace]

set -euo pipefail

TIME_LIMIT="90s"
OUTPUT=""
MODE=""
TARGET=""

usage() {
    echo "Usage:"
    echo "  $0 --attach <pid> [--time-limit 90s] [--output /tmp/trace.trace]"
    echo "  $0 --launch /path/to/App.app [--time-limit 90s] [--output /tmp/trace.trace]"
    echo ""
    echo "Options:"
    echo "  --attach <pid>       Attach to running process by PID"
    echo "  --launch <app>       Launch app and profile (path to .app bundle)"
    echo "  --time-limit <time>  Recording duration (default: 90s)"
    echo "  --output <path>      Output .trace file (default: /tmp/<appname>.trace)"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --attach)
            MODE="attach"
            TARGET="$2"
            shift 2
            ;;
        --launch)
            MODE="launch"
            TARGET="$2"
            shift 2
            ;;
        --time-limit)
            TIME_LIMIT="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -z "$MODE" || -z "$TARGET" ]]; then
    echo "Error: Must specify --attach <pid> or --launch <app>"
    usage
fi

# Generate default output path if not specified
if [[ -z "$OUTPUT" ]]; then
    if [[ "$MODE" == "launch" ]]; then
        APP_NAME=$(basename "$TARGET" .app)
    else
        APP_NAME="pid-$TARGET"
    fi
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    OUTPUT="/tmp/${APP_NAME}-${TIMESTAMP}.trace"
fi

echo "Recording Time Profiler trace..."
echo "  Mode: $MODE"
echo "  Target: $TARGET"
echo "  Time limit: $TIME_LIMIT"
echo "  Output: $OUTPUT"
echo ""

if [[ "$MODE" == "attach" ]]; then
    # Verify PID exists
    if ! ps -p "$TARGET" > /dev/null 2>&1; then
        echo "Error: No process found with PID $TARGET"
        exit 1
    fi

    echo "Attaching to PID $TARGET..."
    xcrun xctrace record \
        --template 'Time Profiler' \
        --time-limit "$TIME_LIMIT" \
        --output "$OUTPUT" \
        --attach "$TARGET"
else
    # Launch mode - find the binary inside the .app bundle
    if [[ ! -d "$TARGET" ]]; then
        echo "Error: App bundle not found: $TARGET"
        exit 1
    fi

    APP_NAME=$(basename "$TARGET" .app)
    BINARY="$TARGET/Contents/MacOS/$APP_NAME"

    if [[ ! -x "$BINARY" ]]; then
        # Try to find the binary
        BINARY=$(find "$TARGET/Contents/MacOS" -type f -perm +111 | head -1)
        if [[ -z "$BINARY" ]]; then
            echo "Error: Could not find executable in $TARGET/Contents/MacOS/"
            exit 1
        fi
    fi

    echo "Launching $BINARY..."
    xcrun xctrace record \
        --template 'Time Profiler' \
        --time-limit "$TIME_LIMIT" \
        --output "$OUTPUT" \
        --launch -- "$BINARY"
fi

echo ""
echo "Trace saved to: $OUTPUT"
echo ""
echo "Next steps:"
echo "  1. Extract samples: scripts/extract_time_samples.py --trace '$OUTPUT' --output /tmp/samples.xml"
echo "  2. Get load address: vmmap <pid> | rg -m1 '__TEXT'"
echo "  3. Analyze: scripts/top_hotspots.py --samples /tmp/samples.xml --binary <binary> --load-address <addr>"
