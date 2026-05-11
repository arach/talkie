#!/bin/bash
# Cleanup stale URL scheme registrations for Talkie dev builds
#
# Problem: Multiple debug builds in DerivedData all claim talkie-dev:// scheme.
# LaunchServices caches these registrations, and the wrong (stale) build may
# handle URLs when clicked.
#
# Solution: Unregister all apps claiming talkie-dev://, then re-register
# only the current worktree's build.
#
# Usage:
#   ./scripts/cleanup-url-schemes.sh           # Cleanup and re-register
#   ./scripts/cleanup-url-schemes.sh --check   # Show current registrations only
#   ./scripts/cleanup-url-schemes.sh --all     # Also cleanup talkie-staging://

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
XCODEPROJ="$PROJECT_ROOT/apps/macos/Talkie/Talkie.xcodeproj"
CACHE_FILE="$PROJECT_ROOT/.deriveddata"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
CHECK_ONLY=false
INCLUDE_STAGING=false
for arg in "$@"; do
  case $arg in
    --check) CHECK_ONLY=true ;;
    --all) INCLUDE_STAGING=true ;;
  esac
done

# Schemes to cleanup
SCHEMES=("talkie-dev")
if [ "$INCLUDE_STAGING" = true ]; then
  SCHEMES+=("talkie-staging")
fi

echo -e "${BLUE}=== Talkie URL Scheme Cleanup ===${NC}"
echo ""

# Function to find apps registered for a URL scheme
find_apps_for_scheme() {
  local scheme="$1"
  # Use lsregister to dump all registrations, then grep for the scheme
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump 2>/dev/null | \
    grep -B 20 "bindings:.*$scheme:" | \
    grep "path:" | \
    sed 's/.*path: *//' | \
    sort -u
}

# Function to get current worktree's app path
get_current_app_path() {
  # Try cached path first
  if [ -f "$CACHE_FILE" ]; then
    CACHED_DIR=$(cat "$CACHE_FILE" | sed 's:/*$::')
    APP="$CACHED_DIR/Build/Products/Debug/Talkie.app"
    if [ -d "$APP" ]; then
      echo "$APP"
      return 0
    fi
  fi

  # Scan DerivedData for matching project
  for dir in ~/Library/Developer/Xcode/DerivedData/Talkie-*/; do
    dir="${dir%/}"
    info="$dir/info.plist"
    if [ -f "$info" ]; then
      workspace=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$info" 2>/dev/null)
      if [ "$workspace" = "$XCODEPROJ" ]; then
        APP="$dir/Build/Products/Debug/Talkie.app"
        if [ -d "$APP" ]; then
          echo "$APP"
          return 0
        fi
      fi
    fi
  done

  return 1
}

# Show current registrations
echo -e "${YELLOW}Current URL scheme registrations:${NC}"
for scheme in "${SCHEMES[@]}"; do
  echo ""
  echo -e "  ${BLUE}$scheme://${NC}"
  apps=$(find_apps_for_scheme "$scheme")
  if [ -n "$apps" ]; then
    echo "$apps" | while read app; do
      if [ -d "$app" ]; then
        echo -e "    ${GREEN}✓${NC} $app"
      else
        echo -e "    ${RED}✗${NC} $app ${RED}(stale - app no longer exists)${NC}"
      fi
    done
  else
    echo -e "    ${YELLOW}(no registrations found)${NC}"
  fi
done

if [ "$CHECK_ONLY" = true ]; then
  echo ""
  exit 0
fi

echo ""
echo -e "${YELLOW}Cleaning up stale registrations...${NC}"

# Find current worktree's app
CURRENT_APP=$(get_current_app_path)
if [ -z "$CURRENT_APP" ]; then
  echo -e "${RED}Error: No build found for current worktree${NC}"
  echo "Build first: xcodebuild -project $XCODEPROJ -scheme Talkie -configuration Debug build"
  exit 1
fi

echo -e "Current worktree app: ${GREEN}$CURRENT_APP${NC}"
echo ""

# Unregister all apps for each scheme
for scheme in "${SCHEMES[@]}"; do
  echo -e "Cleaning ${BLUE}$scheme://${NC} registrations..."
  apps=$(find_apps_for_scheme "$scheme")
  if [ -n "$apps" ]; then
    echo "$apps" | while read app; do
      if [ "$app" != "$CURRENT_APP" ]; then
        echo -e "  Unregistering: ${RED}$app${NC}"
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$app" 2>/dev/null || true
      else
        echo -e "  Keeping: ${GREEN}$app${NC} (current worktree)"
      fi
    done
  fi
done

echo ""
echo -e "${YELLOW}Re-registering current build...${NC}"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$CURRENT_APP"
echo -e "  Registered: ${GREEN}$CURRENT_APP${NC}"

# Also register TalkieAgent and TalkieEngine if they exist
DERIVED_DATA_DIR=$(dirname "$(dirname "$(dirname "$CURRENT_APP")")")
for app_name in TalkieAgent TalkieEngine; do
  APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/$app_name.app"
  if [ -d "$APP_PATH" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
    echo -e "  Registered: ${GREEN}$APP_PATH${NC}"
  fi
done

echo ""
echo -e "${GREEN}=== Cleanup complete ===${NC}"
echo ""
echo "Verification:"
./scripts/cleanup-url-schemes.sh --check
