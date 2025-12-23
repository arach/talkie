#!/bin/bash
# Smart launcher - finds the DerivedData matching this worktree

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODEPROJ="$PROJECT_ROOT/macOS/Talkie/Talkie.xcodeproj"
CACHE_FILE="$PROJECT_ROOT/.deriveddata"

# Try cached path first
if [ -f "$CACHE_FILE" ]; then
  CACHED_DIR=$(cat "$CACHE_FILE")
  APP="$CACHED_DIR/Build/Products/Debug/Talkie.app"
  if [ -d "$APP" ]; then
    # Kill only THIS worktree's Talkie (not others)
    pkill -f "$APP/Contents/MacOS/Talkie" 2>/dev/null && sleep 0.3
    echo "Launching: $APP"
    open "$APP"
    exit 0
  else
    # Cached path invalid, will re-scan
    rm "$CACHE_FILE"
  fi
fi

# Scan DerivedData for matching project
for dir in ~/Library/Developer/Xcode/DerivedData/Talkie-*/; do
  info="$dir/info.plist"
  if [ -f "$info" ]; then
    workspace=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$info" 2>/dev/null)
    if [ "$workspace" = "$XCODEPROJ" ]; then
      # Cache it for next time
      echo "$dir" > "$CACHE_FILE"

      APP="$dir/Build/Products/Debug/Talkie.app"
      if [ -d "$APP" ]; then
        pkill -f "$APP/Contents/MacOS/Talkie" 2>/dev/null && sleep 0.3
        echo "Launching: $APP"
        open "$APP"
        exit 0
      else
        echo "Build not found. Run: xcodebuild -scheme Talkie -configuration Debug build"
        exit 1
      fi
    fi
  fi
done

echo "No DerivedData found for $XCODEPROJ"
echo "Build first: cd macOS/Talkie && xcodebuild -scheme Talkie build"
exit 1
