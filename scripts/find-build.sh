#!/bin/bash
# Find the most recent Talkie or TalkieAgent build in DerivedData
#
# Usage:
#   ./scripts/find-build.sh              # Show build info
#   ./scripts/find-build.sh --app TalkieAgent
#   ./scripts/find-build.sh --path       # Just print app path
#   ./scripts/find-build.sh --binary-path
#   ./scripts/find-build.sh --run        # Run the binary

set -e

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
APP_NAME="Talkie"
OUTPUT_MODE="summary"

while [ $# -gt 0 ]; do
    case "$1" in
        --app)
            APP_NAME="$2"
            shift 2
            ;;
        --path)
            OUTPUT_MODE="app"
            shift
            ;;
        --binary-path)
            OUTPUT_MODE="binary"
            shift
            ;;
        --run)
            OUTPUT_MODE="run"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Find all DerivedData builds
BUILDS=$(find "$DERIVED_DATA" -maxdepth 1 -type d 2>/dev/null || true)

if [ -z "$BUILDS" ]; then
    echo "❌ No DerivedData builds found"
    exit 1
fi

# Find the most recent build by checking the binary modification time
LATEST_BUILD=""
LATEST_TIME=0
LATEST_APP=""
LATEST_BINARY=""

while IFS= read -r build_dir; do
    APP="$build_dir/Build/Products/Debug/$APP_NAME.app"
    BINARY="$APP/Contents/MacOS/$APP_NAME"

    if [ -f "$BINARY" ]; then
        # Get modification time (seconds since epoch)
        MOD_TIME=$(stat -f %m "$BINARY" 2>/dev/null || echo "0")

        if [ "$MOD_TIME" -gt "$LATEST_TIME" ]; then
            LATEST_TIME=$MOD_TIME
            LATEST_BUILD=$build_dir
            LATEST_APP=$APP
            LATEST_BINARY=$BINARY
        fi
    fi
done <<< "$BUILDS"

if [ -z "$LATEST_BINARY" ]; then
    echo "❌ No built $APP_NAME.app found in any DerivedData folder"
    exit 1
fi

# Format the timestamp for display
TIMESTAMP=$(date -r $LATEST_TIME "+%Y-%m-%d %H:%M:%S")

# Handle different output modes
case "$OUTPUT_MODE" in
    app)
        echo "$LATEST_APP"
        ;;
    binary)
        echo "$LATEST_BINARY"
        ;;
    run)
        exec "$LATEST_BINARY"
        ;;
    *)
        echo "🔍 Latest $APP_NAME Build"
        echo "   Branch: $CURRENT_BRANCH"
        echo "   Built:  $TIMESTAMP"
        echo "   App:    $LATEST_APP"
        echo "   Binary: $LATEST_BINARY"
        echo ""
        echo "To run:"
        echo "   ./scripts/find-build.sh --app $APP_NAME --run"
        ;;
esac
