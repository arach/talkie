#!/bin/bash
#
# sync-version.sh - Sync version number across all Talkie projects
#
# Usage:
#   ./scripts/sync-version.sh           # Sync version from VERSION file
#   ./scripts/sync-version.sh 1.8.0     # Set and sync a new version
#   ./scripts/sync-version.sh --check   # Check version consistency (no changes)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$ROOT_DIR/VERSION"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Files to update
TALKIE_PBXPROJ="$ROOT_DIR/macOS/Talkie/Talkie.xcodeproj/project.pbxproj"
TALKIE_PROJECTYML="$ROOT_DIR/macOS/Talkie/project.yml"
TALKIELIVE_PBXPROJ="$ROOT_DIR/macOS/TalkieLive/TalkieLive.xcodeproj/project.pbxproj"
TALKIEENGINE_PLIST="$ROOT_DIR/macOS/TalkieEngine/TalkieEngine/Info.plist"

# Get current version from VERSION file
get_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE" | tr -d '[:space:]'
    else
        echo ""
    fi
}

# Extract version from a pbxproj file
get_pbxproj_version() {
    local file="$1"
    if [[ -f "$file" ]]; then
        grep -o 'MARKETING_VERSION = [^;]*' "$file" | head -1 | sed 's/MARKETING_VERSION = //'
    else
        echo "N/A"
    fi
}

# Extract version from Info.plist
get_plist_version() {
    local file="$1"
    if [[ -f "$file" ]]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$file" 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

# Check mode - just show current versions
check_versions() {
    echo "📋 Version Check"
    echo "================"
    echo ""

    local version=$(get_version)
    echo "VERSION file: ${version:-'(not found)'}"
    echo ""
    echo "Project versions:"
    echo "  Talkie:       $(get_pbxproj_version "$TALKIE_PBXPROJ")"
    echo "  TalkieLive:   $(get_pbxproj_version "$TALKIELIVE_PBXPROJ")"
    echo "  TalkieEngine: $(get_plist_version "$TALKIEENGINE_PLIST")"

    # Check consistency
    local t=$(get_pbxproj_version "$TALKIE_PBXPROJ")
    local l=$(get_pbxproj_version "$TALKIELIVE_PBXPROJ")
    local e=$(get_plist_version "$TALKIEENGINE_PLIST")

    echo ""
    if [[ "$t" == "$l" && "$l" == "$e" && "$t" == "$version" ]]; then
        echo -e "${GREEN}✓ All versions match${NC}"
    else
        echo -e "${YELLOW}⚠ Versions are out of sync${NC}"
        echo "  Run: ./scripts/sync-version.sh"
    fi
}

# Update version in a pbxproj file
update_pbxproj() {
    local file="$1"
    local version="$2"
    local name="$3"

    if [[ -f "$file" ]]; then
        # macOS sed requires empty string after -i
        sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $version/" "$file"
        echo -e "  ${GREEN}✓${NC} $name"
    else
        echo -e "  ${RED}✗${NC} $name (file not found)"
    fi
}

# Update version in project.yml
update_projectyml() {
    local file="$1"
    local version="$2"

    if [[ -f "$file" ]]; then
        sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$version\"/" "$file"
        echo -e "  ${GREEN}✓${NC} project.yml"
    fi
}

# Update version in Info.plist
update_plist() {
    local file="$1"
    local version="$2"
    local name="$3"

    if [[ -f "$file" ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$file"
        echo -e "  ${GREEN}✓${NC} $name"
    else
        echo -e "  ${RED}✗${NC} $name (file not found)"
    fi
}

# Main sync function
sync_version() {
    local version="$1"

    echo "🔄 Syncing version to $version"
    echo ""

    # Update VERSION file if new version provided
    echo "$version" > "$VERSION_FILE"
    echo -e "  ${GREEN}✓${NC} VERSION file"

    # Update all project files
    update_pbxproj "$TALKIE_PBXPROJ" "$version" "Talkie"
    update_pbxproj "$TALKIELIVE_PBXPROJ" "$version" "TalkieLive"
    update_plist "$TALKIEENGINE_PLIST" "$version" "TalkieEngine"
    update_projectyml "$TALKIE_PROJECTYML" "$version"

    echo ""
    echo -e "${GREEN}Done!${NC} Version $version synced across all projects."
    echo ""
    echo "Next steps:"
    echo "  1. Rebuild projects in Xcode"
    echo "  2. git add -A && git commit -m '🔖 Bump version to $version'"
}

# Parse arguments
case "${1:-}" in
    --check|-c)
        check_versions
        ;;
    --help|-h)
        echo "Usage: $0 [version|--check]"
        echo ""
        echo "  (no args)   Sync version from VERSION file"
        echo "  <version>   Set and sync a new version (e.g., 1.8.0)"
        echo "  --check     Check version consistency (no changes)"
        ;;
    "")
        version=$(get_version)
        if [[ -z "$version" ]]; then
            echo -e "${RED}Error: No version found in VERSION file${NC}"
            exit 1
        fi
        sync_version "$version"
        ;;
    *)
        # Validate version format (basic check)
        if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}Error: Invalid version format. Use X.Y.Z (e.g., 1.8.0)${NC}"
            exit 1
        fi
        sync_version "$1"
        ;;
esac
