#!/bin/bash
# Find the most recent Talkie build for the current branch
#
# Usage:
#   ./scripts/find-build.sh              # Show build info
#   ./scripts/find-build.sh --path       # Just print binary path
#   ./scripts/find-build.sh --run        # Run the binary
#   ./scripts/find-build.sh --run --debug=<cmd>  # Run with debug command

set -e

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

# Find all TalkieSuite builds
BUILDS=$(find "$DERIVED_DATA" -maxdepth 1 -name "TalkieSuite-*" -type d 2>/dev/null || true)

if [ -z "$BUILDS" ]; then
    echo "❌ No TalkieSuite builds found in DerivedData"
    exit 1
fi

# Find the most recent build by checking the binary modification time
LATEST_BUILD=""
LATEST_TIME=0
LATEST_BINARY=""

while IFS= read -r build_dir; do
    BINARY="$build_dir/Build/Products/Debug/Talkie.app/Contents/MacOS/Talkie"

    if [ -f "$BINARY" ]; then
        # Get modification time (seconds since epoch)
        MOD_TIME=$(stat -f %m "$BINARY" 2>/dev/null || echo "0")

        if [ "$MOD_TIME" -gt "$LATEST_TIME" ]; then
            LATEST_TIME=$MOD_TIME
            LATEST_BUILD=$build_dir
            LATEST_BINARY=$BINARY
        fi
    fi
done <<< "$BUILDS"

if [ -z "$LATEST_BINARY" ]; then
    echo "❌ No built Talkie.app found in any DerivedData folder"
    exit 1
fi

# Format the timestamp for display
TIMESTAMP=$(date -r $LATEST_TIME "+%Y-%m-%d %H:%M:%S")

# Handle different output modes
case "${1:-}" in
    --path)
        echo "$LATEST_BINARY"
        ;;
    --run)
        shift
        exec "$LATEST_BINARY" "$@"
        ;;
    *)
        echo "🔍 Latest Talkie Build"
        echo "   Branch: $CURRENT_BRANCH"
        echo "   Built:  $TIMESTAMP"
        echo "   Path:   $LATEST_BINARY"
        echo ""
        echo "To run:"
        echo "   ./scripts/find-build.sh --run"
        echo "   ./scripts/find-build.sh --run --debug=help"
        ;;
esac
