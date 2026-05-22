#!/bin/bash
# Smart launcher - finds and launches the DerivedData build for this worktree
# Usage: ./run.sh [--build] [--cleanup] [--view <route>]
#
# Options:
#   --build         Build before launching
#   --cleanup       Cleanup stale URL scheme registrations before launching
#   --view <route>  After launch, navigate to a view via URL scheme.
#                   Routes: home, library, library/memo?id=<uuid>,
#                           library/dictation?id=<uuid>, agent, settings
#                   Debug builds use the talkie-dev:// scheme automatically.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODEPROJ="$PROJECT_ROOT/apps/macos/Talkie/Talkie.xcodeproj"
CACHE_FILE="$PROJECT_ROOT/.deriveddata"
URL_SCHEME="talkie-dev"  # Debug builds register this scheme (see project.yml)

# Parse arguments
DO_BUILD=false
DO_CLEANUP=false
VIEW=""
while [ $# -gt 0 ]; do
  case $1 in
    --build) DO_BUILD=true; shift ;;
    --cleanup) DO_CLEANUP=true; shift ;;
    --view) VIEW="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Helper: after launching the app, open a deep link to navigate.
# Small sleep lets the app settle before handling the URL.
navigate_to_view() {
  if [ -n "$VIEW" ]; then
    # Give the app time to register its URL handler after a cold launch.
    # 1.8s is enough on a clean build; lower and the open silently drops.
    sleep 1.8
    echo "   View: ${URL_SCHEME}://${VIEW}"
    open "${URL_SCHEME}://${VIEW}"
  fi
}

# Optional cleanup step (unregister stale URL schemes)
if [ "$DO_CLEANUP" = true ]; then
  echo "Cleaning up URL scheme registrations..."
  "$SCRIPT_DIR/cleanup-url-schemes.sh" 2>/dev/null || echo "  (cleanup script not found, skipping)"
  echo ""
fi

# Optional build step
if [ "$DO_BUILD" = true ]; then
  echo "Building Talkie..."
  xcodebuild -project "$XCODEPROJ" -scheme Talkie -configuration Debug build 2>&1 | tail -20
  if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "Build failed!"
    exit 1
  fi
  echo "✓ Build succeeded!"
  echo ""
fi

# Try cached path first
if [ -f "$CACHE_FILE" ]; then
  CACHED_DIR=$(cat "$CACHE_FILE" | sed 's:/*$::')  # Strip trailing slash
  APP="$CACHED_DIR/Build/Products/Debug/Talkie.app"
  if [ -d "$APP" ]; then
    # Kill only THIS worktree's Talkie (not others)
    pkill -f "$APP/Contents/MacOS/Talkie" 2>/dev/null && sleep 0.3
    echo "🚀 Launching Talkie"
    echo "   App: $APP"
    echo "   Binary: $APP/Contents/MacOS/Talkie"
    open "$APP"
    navigate_to_view
    exit 0
  else
    # Cached path invalid, will re-scan
    rm "$CACHE_FILE"
  fi
fi

# Scan DerivedData for matching project
for dir in ~/Library/Developer/Xcode/DerivedData/Talkie-*/; do
  dir="${dir%/}"  # Strip trailing slash
  info="$dir/info.plist"
  if [ -f "$info" ]; then
    workspace=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$info" 2>/dev/null)
    if [ "$workspace" = "$XCODEPROJ" ]; then
      # Cache it for next time (without trailing slash)
      echo "$dir" > "$CACHE_FILE"

      APP="$dir/Build/Products/Debug/Talkie.app"
      if [ -d "$APP" ]; then
        pkill -f "$APP/Contents/MacOS/Talkie" 2>/dev/null && sleep 0.3
        echo "🚀 Launching Talkie"
        echo "   App: $APP"
        echo "   Binary: $APP/Contents/MacOS/Talkie"
        open "$APP"
        navigate_to_view
        exit 0
      else
        echo "Build not found. Run: xcodebuild -scheme Talkie -configuration Debug build"
        exit 1
      fi
    fi
  fi
done

echo "No DerivedData found for $XCODEPROJ"
echo "Build first: cd apps/macos/Talkie && xcodebuild -scheme Talkie build"
exit 1
