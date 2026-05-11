#!/bin/bash
#
# sync-version.sh - Sync Talkie marketing and build versions across projects.
#
# Usage:
#   ./scripts/sync-version.sh                 # Sync VERSION + BUILD_NUMBER
#   ./scripts/sync-version.sh 2.5.12          # Set and sync a new marketing version
#   ./scripts/sync-version.sh --build 4       # Set and sync a build number
#   ./scripts/sync-version.sh --bump-build    # Increment BUILD_NUMBER, then sync
#   ./scripts/sync-version.sh --check         # Check consistency without changes
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_FILE="$ROOT_DIR/BUILD_NUMBER"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

IOS_PBXPROJ="$ROOT_DIR/apps/ios/Talkie-iOS.xcodeproj/project.pbxproj"
TALKIE_PBXPROJ="$ROOT_DIR/apps/macos/Talkie/Talkie.xcodeproj/project.pbxproj"
TALKIE_PROJECTYML="$ROOT_DIR/apps/macos/Talkie/project.yml"
TALKIE_INFO_PLIST="$ROOT_DIR/apps/macos/Talkie/Talkie-Info.plist"
TALKIEAGENT_PBXPROJ="$ROOT_DIR/apps/macos/TalkieAgent/TalkieAgent.xcodeproj/project.pbxproj"
TALKIEAGENT_INFO_PLIST="$ROOT_DIR/apps/macos/TalkieAgent/TalkieAgent/Info.plist"
TALKIESYNC_PBXPROJ="$ROOT_DIR/apps/macos/TalkieSync/TalkieSync.xcodeproj/project.pbxproj"
TALKIESYNC_PLIST="$ROOT_DIR/apps/macos/TalkieSync/TalkieSync/Info.plist"

usage() {
    cat <<EOF
Usage: $0 [version] [--build N] [--bump-build] [--check]

  (no args)      Sync VERSION and BUILD_NUMBER files into all projects
  <version>      Set and sync marketing version, e.g. 2.5.12
  --build N      Set and sync the global build number
  --bump-build   Increment BUILD_NUMBER before syncing
  --check        Check consistency without changes
EOF
}

read_file_value() {
    local file="$1"
    if [[ -f "$file" ]]; then
        tr -d '[:space:]' < "$file"
    fi
}

get_version() {
    read_file_value "$VERSION_FILE"
}

get_build_number() {
    local build
    build="$(read_file_value "$BUILD_FILE")"
    echo "${build:-1}"
}

validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid version '$version'. Use X.Y.Z, e.g. 2.5.12.${NC}" >&2
        exit 1
    fi
}

validate_build() {
    local build="$1"
    if [[ ! "$build" =~ ^[0-9]+$ ]] || [[ "$build" -lt 1 ]]; then
        echo -e "${RED}Error: Invalid build '$build'. Use a positive integer.${NC}" >&2
        exit 1
    fi
}

get_pbxproj_setting() {
    local file="$1"
    local key="$2"
    if [[ -f "$file" ]]; then
        grep -o "$key = [^;]*" "$file" | head -1 | sed "s/$key = //"
    else
        echo "N/A"
    fi
}

get_projectyml_setting() {
    local file="$1"
    local key="$2"
    if [[ -f "$file" ]]; then
        grep -E "^[[:space:]]+$key:" "$file" | head -1 | sed -E 's/.*: "([^"]*)"/\1/'
    else
        echo "N/A"
    fi
}

get_plist_key() {
    local file="$1"
    local key="$2"
    if [[ -f "$file" ]]; then
        /usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

update_pbxproj_setting() {
    local file="$1"
    local key="$2"
    local value="$3"
    local name="$4"

    if [[ -f "$file" ]]; then
        sed -i '' "s/$key = [^;]*/$key = $value/g" "$file"
        echo -e "  ${GREEN}✓${NC} $name $key"
    else
        echo -e "  ${RED}✗${NC} $name $key (file not found)"
    fi
}

update_projectyml() {
    local file="$1"
    local version="$2"
    local build="$3"

    if [[ -f "$file" ]]; then
        sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$version\"/g" "$file"
        sed -i '' "s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$build\"/g" "$file"
        echo -e "  ${GREEN}✓${NC} project.yml"
    else
        echo -e "  ${YELLOW}⚠${NC} project.yml (file not found)"
    fi
}

set_plist_key() {
    local file="$1"
    local key="$2"
    local value="$3"

    if ! /usr/libexec/PlistBuddy -c "Set :$key $value" "$file" 2>/dev/null; then
        /usr/libexec/PlistBuddy -c "Add :$key string $value" "$file"
    fi
}

update_plist_to_build_settings() {
    local file="$1"
    local name="$2"

    if [[ -f "$file" ]]; then
        set_plist_key "$file" "CFBundleShortVersionString" '$(MARKETING_VERSION)'
        set_plist_key "$file" "CFBundleVersion" '$(CURRENT_PROJECT_VERSION)'
        echo -e "  ${GREEN}✓${NC} $name Info.plist build settings"
    else
        echo -e "  ${YELLOW}⚠${NC} $name Info.plist (file not found)"
    fi
}

check_setting() {
    local label="$1"
    local actual="$2"
    local expected="$3"

    printf "  %-34s %s\n" "$label:" "$actual"
    [[ "$actual" == "$expected" ]]
}

check_versions() {
    local expected_version expected_build ok=0
    expected_version="$(get_version)"
    expected_build="$(get_build_number)"

    echo "📋 Version Check"
    echo "================"
    echo ""
    echo "VERSION:      ${expected_version:-'(not found)'}"
    echo "BUILD_NUMBER: $expected_build"
    echo ""
    echo "Marketing versions:"

    check_setting "iOS project" "$(get_pbxproj_setting "$IOS_PBXPROJ" MARKETING_VERSION)" "$expected_version" || ok=1
    check_setting "macOS Talkie project" "$(get_pbxproj_setting "$TALKIE_PBXPROJ" MARKETING_VERSION)" "$expected_version" || ok=1
    check_setting "macOS project.yml" "$(get_projectyml_setting "$TALKIE_PROJECTYML" MARKETING_VERSION)" "$expected_version" || ok=1
    check_setting "TalkieAgent project" "$(get_pbxproj_setting "$TALKIEAGENT_PBXPROJ" MARKETING_VERSION)" "$expected_version" || ok=1
    check_setting "TalkieSync project" "$(get_pbxproj_setting "$TALKIESYNC_PBXPROJ" MARKETING_VERSION)" "$expected_version" || ok=1

    echo ""
    echo "Build numbers:"
    check_setting "iOS project" "$(get_pbxproj_setting "$IOS_PBXPROJ" CURRENT_PROJECT_VERSION)" "$expected_build" || ok=1
    check_setting "macOS Talkie project" "$(get_pbxproj_setting "$TALKIE_PBXPROJ" CURRENT_PROJECT_VERSION)" "$expected_build" || ok=1
    check_setting "macOS project.yml" "$(get_projectyml_setting "$TALKIE_PROJECTYML" CURRENT_PROJECT_VERSION)" "$expected_build" || ok=1
    check_setting "TalkieAgent project" "$(get_pbxproj_setting "$TALKIEAGENT_PBXPROJ" CURRENT_PROJECT_VERSION)" "$expected_build" || ok=1
    check_setting "TalkieSync project" "$(get_pbxproj_setting "$TALKIESYNC_PBXPROJ" CURRENT_PROJECT_VERSION)" "$expected_build" || ok=1

    echo ""
    echo "Info.plist bindings:"
    check_setting "Talkie ShortVersion" "$(get_plist_key "$TALKIE_INFO_PLIST" CFBundleShortVersionString)" '$(MARKETING_VERSION)' || ok=1
    check_setting "Talkie Build" "$(get_plist_key "$TALKIE_INFO_PLIST" CFBundleVersion)" '$(CURRENT_PROJECT_VERSION)' || ok=1
    check_setting "TalkieAgent ShortVersion" "$(get_plist_key "$TALKIEAGENT_INFO_PLIST" CFBundleShortVersionString)" '$(MARKETING_VERSION)' || ok=1
    check_setting "TalkieAgent Build" "$(get_plist_key "$TALKIEAGENT_INFO_PLIST" CFBundleVersion)" '$(CURRENT_PROJECT_VERSION)' || ok=1
    check_setting "TalkieSync ShortVersion" "$(get_plist_key "$TALKIESYNC_PLIST" CFBundleShortVersionString)" '$(MARKETING_VERSION)' || ok=1
    check_setting "TalkieSync Build" "$(get_plist_key "$TALKIESYNC_PLIST" CFBundleVersion)" '$(CURRENT_PROJECT_VERSION)' || ok=1

    echo ""
    if [[ "$ok" -eq 0 ]]; then
        echo -e "${GREEN}✓ All versions and build numbers match${NC}"
    else
        echo -e "${YELLOW}⚠ Versions or build numbers are out of sync${NC}"
        echo "  Run: ./scripts/sync-version.sh"
        return 1
    fi
}

sync_versions() {
    local version="$1"
    local build="$2"

    echo "🔄 Syncing Talkie $version ($build)"
    echo ""

    echo "$version" > "$VERSION_FILE"
    echo "$build" > "$BUILD_FILE"
    echo -e "  ${GREEN}✓${NC} VERSION"
    echo -e "  ${GREEN}✓${NC} BUILD_NUMBER"

    update_pbxproj_setting "$IOS_PBXPROJ" MARKETING_VERSION "$version" "iOS"
    update_pbxproj_setting "$IOS_PBXPROJ" CURRENT_PROJECT_VERSION "$build" "iOS"

    update_pbxproj_setting "$TALKIE_PBXPROJ" MARKETING_VERSION "$version" "macOS Talkie"
    update_pbxproj_setting "$TALKIE_PBXPROJ" CURRENT_PROJECT_VERSION "$build" "macOS Talkie"
    update_projectyml "$TALKIE_PROJECTYML" "$version" "$build"

    update_pbxproj_setting "$TALKIEAGENT_PBXPROJ" MARKETING_VERSION "$version" "TalkieAgent"
    update_pbxproj_setting "$TALKIEAGENT_PBXPROJ" CURRENT_PROJECT_VERSION "$build" "TalkieAgent"

    update_pbxproj_setting "$TALKIESYNC_PBXPROJ" MARKETING_VERSION "$version" "TalkieSync"
    update_pbxproj_setting "$TALKIESYNC_PBXPROJ" CURRENT_PROJECT_VERSION "$build" "TalkieSync"

    update_plist_to_build_settings "$TALKIE_INFO_PLIST" "Talkie"
    update_plist_to_build_settings "$TALKIEAGENT_INFO_PLIST" "TalkieAgent"
    update_plist_to_build_settings "$TALKIESYNC_PLIST" "TalkieSync"

    echo ""
    echo -e "${GREEN}Done!${NC} Talkie $version ($build) is synced across projects."
}

check_only=0
version_arg=""
build_arg=""
bump_build=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check|-c)
            check_only=1
            shift
            ;;
        --build)
            if [[ $# -lt 2 ]]; then
                echo -e "${RED}Error: --build requires a value.${NC}" >&2
                exit 1
            fi
            build_arg="$2"
            shift 2
            ;;
        --bump-build)
            bump_build=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            if [[ -n "$version_arg" ]]; then
                echo -e "${RED}Error: Multiple version arguments supplied.${NC}" >&2
                exit 1
            fi
            version_arg="$1"
            shift
            ;;
    esac
done

if [[ "$check_only" -eq 1 ]]; then
    check_versions
    exit $?
fi

version="${version_arg:-$(get_version)}"
build="${build_arg:-$(get_build_number)}"

if [[ -z "$version" ]]; then
    echo -e "${RED}Error: No version found in VERSION file.${NC}" >&2
    exit 1
fi

validate_version "$version"
validate_build "$build"

if [[ "$bump_build" -eq 1 ]]; then
    build=$((build + 1))
fi

sync_versions "$version" "$build"
