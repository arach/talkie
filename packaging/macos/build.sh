#!/bin/bash
set -e

# Talkie for Mac - Unified DMG Build Script
# Builds all components, embeds them in a single Talkie.app, creates signed/notarized DMG
#
# Usage:
#   ./build.sh
#   ./build.sh --version 2.5.11 --build 4
#   ./build.sh --bump-build
#   VERSION=2.0.1 ./build.sh
#
# Environment variables:
#   VERSION=2.0.1           # Set marketing version (defaults to ../VERSION)
#   BUILD_NUMBER=4          # Set build number (defaults to ../BUILD_NUMBER)
#   SKIP_NOTARIZE=1         # Skip notarization (for testing)
#   SKIP_CLEAN=1            # Skip clean build (faster iteration)
#   TALKIE_SIGNING_ENV_FILE # Optional shell env file with local signing identifiers

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
STAGING_DIR="$SCRIPT_DIR/staging"
RESOURCES_DIR="$SCRIPT_DIR/resources"
SIGNING_ENV_FILE="${TALKIE_SIGNING_ENV_FILE:-$ROOT_DIR/Config/signing.env}"

if [ -f "$SIGNING_ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$SIGNING_ENV_FILE"
    set +a
fi

# Parse arguments
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
BUMP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --build)
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --bump-build)
            BUMP_BUILD=1
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Default to repo-level release metadata.
if [ -z "$VERSION" ] && [ -f "$ROOT_DIR/VERSION" ]; then
    VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
fi
if [ -z "$BUILD_NUMBER" ] && [ -f "$ROOT_DIR/BUILD_NUMBER" ]; then
    BUILD_NUMBER="$(tr -d '[:space:]' < "$ROOT_DIR/BUILD_NUMBER")"
fi

if [ -z "$VERSION" ]; then
    echo "❌ VERSION not specified"
    echo "   Usage: ./build.sh --version 2.0.1 --build 4"
    echo "   Or:    VERSION=2.0.1 ./build.sh"
    exit 1
fi
if [ -z "$BUILD_NUMBER" ]; then
    echo "❌ BUILD_NUMBER not specified"
    echo "   Usage: ./build.sh --version 2.0.1 --build 4"
    echo "   Or:    BUILD_NUMBER=4 ./build.sh"
    exit 1
fi

# ═══════════════════════════════════════════════════════════
# SYNC VERSION IN SOURCE FILES
# ═══════════════════════════════════════════════════════════
SYNC_ARGS=("$VERSION" "--build" "$BUILD_NUMBER")
if [ "$BUMP_BUILD" = "1" ]; then
    SYNC_ARGS+=("--bump-build")
fi

"$ROOT_DIR/scripts/sync-version.sh" "${SYNC_ARGS[@]}"
VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="$(tr -d '[:space:]' < "$ROOT_DIR/BUILD_NUMBER")"

# Signing identity and account-scoped identifiers
DEVELOPER_ID_APP="${TALKIE_DEVELOPER_ID_APP:-}"
TEAM_ID="${TALKIE_TEAM_ID:-}"
NOTARY_PROFILE="${TALKIE_NOTARY_PROFILE:-notarytool}"
APP_IDENTIFIER="${TALKIE_APP_IDENTIFIER:-}"
CORE_BUNDLE_ID="${TALKIE_MAC_CORE_BUNDLE_ID:-}"
AGENT_BUNDLE_ID="${TALKIE_MAC_AGENT_BUNDLE_ID:-}"
SYNC_BUNDLE_ID="${TALKIE_MAC_SYNC_BUNDLE_ID:-}"
MAC_APP_GROUP="${TALKIE_MAC_APP_GROUP:-}"
MAC_SHARED_SETTINGS_SUITE="${TALKIE_MAC_SHARED_SETTINGS_SUITE:-}"
CLOUDKIT_CONTAINER="${TALKIE_CLOUDKIT_CONTAINER:-}"
CORE_PROFILE_NAME="${TALKIE_MAC_CORE_PROFILE_NAME:-}"
SYNC_PROFILE_NAME="${TALKIE_MAC_SYNC_PROFILE_NAME:-}"
EXPORT_OPTIONS_CORE_TEMPLATE="${TALKIE_EXPORT_OPTIONS_CORE_TEMPLATE:-$SCRIPT_DIR/exportOptions-core.plist.in}"
EXPORT_OPTIONS_PROVISIONED_TEMPLATE="${TALKIE_EXPORT_OPTIONS_PROVISIONED_TEMPLATE:-$SCRIPT_DIR/exportOptions-developer-id-provisioned.plist.in}"
EXPORT_OPTIONS_CORE_PLIST="$BUILD_DIR/exportOptions-core.plist"
EXPORT_OPTIONS_PROVISIONED_PLIST="$BUILD_DIR/exportOptions-developer-id-provisioned.plist"

MISSING_SIGNING_CONFIG=()
[ -z "$DEVELOPER_ID_APP" ] && MISSING_SIGNING_CONFIG+=("TALKIE_DEVELOPER_ID_APP")
[ -z "$TEAM_ID" ] && MISSING_SIGNING_CONFIG+=("TALKIE_TEAM_ID")
[ -z "$APP_IDENTIFIER" ] && MISSING_SIGNING_CONFIG+=("TALKIE_APP_IDENTIFIER")
[ -z "$CORE_BUNDLE_ID" ] && MISSING_SIGNING_CONFIG+=("TALKIE_MAC_CORE_BUNDLE_ID")
[ -z "$AGENT_BUNDLE_ID" ] && MISSING_SIGNING_CONFIG+=("TALKIE_MAC_AGENT_BUNDLE_ID")
[ -z "$SYNC_BUNDLE_ID" ] && MISSING_SIGNING_CONFIG+=("TALKIE_MAC_SYNC_BUNDLE_ID")
[ -z "$MAC_APP_GROUP" ] && MISSING_SIGNING_CONFIG+=("TALKIE_MAC_APP_GROUP")
[ -z "$MAC_SHARED_SETTINGS_SUITE" ] && MISSING_SIGNING_CONFIG+=("TALKIE_MAC_SHARED_SETTINGS_SUITE")
[ -z "$CLOUDKIT_CONTAINER" ] && MISSING_SIGNING_CONFIG+=("TALKIE_CLOUDKIT_CONTAINER")
[ -z "$CORE_PROFILE_NAME" ] && MISSING_SIGNING_CONFIG+=("TALKIE_MAC_CORE_PROFILE_NAME")
[ -z "$SYNC_PROFILE_NAME" ] && MISSING_SIGNING_CONFIG+=("TALKIE_MAC_SYNC_PROFILE_NAME")

if [ "${#MISSING_SIGNING_CONFIG[@]}" -gt 0 ]; then
    echo "❌ Missing release signing configuration:"
    printf '   - %s\n' "${MISSING_SIGNING_CONFIG[@]}"
    echo ""
    echo "Copy Config/signing.env.example to a private file, fill it in, then run:"
    echo "  TALKIE_SIGNING_ENV_FILE=/path/to/private/talkie-signing.env ./build.sh"
    exit 1
fi

for template in "$EXPORT_OPTIONS_CORE_TEMPLATE" "$EXPORT_OPTIONS_PROVISIONED_TEMPLATE"; do
    if [ ! -f "$template" ]; then
        echo "❌ Export options template not found: $template"
        exit 1
    fi
done

render_export_options() {
    local template="$1"
    local output="$2"

    mkdir -p "$(dirname "$output")"
    sed -e "s|__TALKIE_TEAM_ID__|${TEAM_ID}|g" \
        -e "s|__TALKIE_MAC_CORE_BUNDLE_ID__|${CORE_BUNDLE_ID}|g" \
        -e "s|__TALKIE_MAC_SYNC_BUNDLE_ID__|${SYNC_BUNDLE_ID}|g" \
        -e "s|__TALKIE_MAC_CORE_PROFILE_NAME__|${CORE_PROFILE_NAME}|g" \
        -e "s|__TALKIE_MAC_SYNC_PROFILE_NAME__|${SYNC_PROFILE_NAME}|g" \
        "$template" > "$output"
}

render_export_options "$EXPORT_OPTIONS_CORE_TEMPLATE" "$EXPORT_OPTIONS_CORE_PLIST"
render_export_options "$EXPORT_OPTIONS_PROVISIONED_TEMPLATE" "$EXPORT_OPTIONS_PROVISIONED_PLIST"

# Optional App Store Connect API credentials for hosted CI runners.
# When present, xcodebuild can fetch/update Developer ID provisioning assets
# without relying on an interactive Apple ID account in Xcode.
XCODE_AUTH_ARGS=()
if [ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" ] && \
   [ -n "${APP_STORE_CONNECT_KEY_ID:-}" ] && \
   [ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
    XCODE_AUTH_ARGS=(
        -authenticationKeyPath "$APP_STORE_CONNECT_API_KEY_PATH"
        -authenticationKeyID "$APP_STORE_CONNECT_KEY_ID"
        -authenticationKeyIssuerID "$APP_STORE_CONNECT_ISSUER_ID"
    )
fi

XCODE_RELEASE_SETTINGS=(
    DEVELOPMENT_TEAM="$TEAM_ID"
    TALKIE_DEVELOPMENT_TEAM="$TEAM_ID"
    TALKIE_APP_IDENTIFIER="$APP_IDENTIFIER"
    TALKIE_MAC_CORE_BUNDLE_ID="$CORE_BUNDLE_ID"
    TALKIE_MAC_AGENT_BUNDLE_ID="$AGENT_BUNDLE_ID"
    TALKIE_MAC_SYNC_BUNDLE_ID="$SYNC_BUNDLE_ID"
    TALKIE_MAC_APP_GROUP="$MAC_APP_GROUP"
    TALKIE_MAC_SHARED_SETTINGS_SUITE="$MAC_SHARED_SETTINGS_SUITE"
    TALKIE_CLOUDKIT_CONTAINER="$CLOUDKIT_CONTAINER"
)

# Processed entitlements directory
PROCESSED_ENTITLEMENTS_DIR="$BUILD_DIR/ProcessedEntitlements"
mkdir -p "$PROCESSED_ENTITLEMENTS_DIR"

# Options
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
SKIP_CLEAN="${SKIP_CLEAN:-0}"

# Archive directories
ARCHIVES_DIR="$BUILD_DIR/Archives"
EXPORTS_DIR="$BUILD_DIR/Exports"

echo "╔══════════════════════════════════════════════════════╗"
echo "║        Talkie for Mac - DMG Builder                  ║"
echo "║              Version: $VERSION ($BUILD_NUMBER)                    ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Verify signing identity
echo "🔐 Verifying signing identity..."
if ! security find-identity -v | grep -Fq "$DEVELOPER_ID_APP"; then
    echo "❌ Developer ID Application certificate not found"
    exit 1
fi
echo "✅ Signing identity verified"

# Clean previous builds
echo ""
echo "🧹 Cleaning previous builds..."
rm -rf "$STAGING_DIR"
rm -f "$SCRIPT_DIR/Talkie-for-Mac.dmg"
rm -f "$SCRIPT_DIR/Talkie-for-Mac-temp.dmg"
mkdir -p "$STAGING_DIR"

# ═══════════════════════════════════════════════════════════
# FUNCTION: Process entitlements file (resolve Xcode variables)
# ═══════════════════════════════════════════════════════════
process_entitlements() {
    local SOURCE_FILE="$1"
    local BUNDLE_ID="$2"
    local OUTPUT_FILE="$3"

    # Resolve Xcode signing variables before re-signing exported bundles.
    sed -e "s/\$(AppIdentifierPrefix)/${TEAM_ID}./g" \
        -e "s/\$(TeamIdentifierPrefix)/${TEAM_ID}./g" \
        -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
        -e "s/\$(TALKIE_APP_IDENTIFIER)/${APP_IDENTIFIER}/g" \
        -e "s/\$(TALKIE_MAC_APP_GROUP)/${MAC_APP_GROUP}/g" \
        -e "s/\$(TALKIE_MAC_SHARED_SETTINGS_SUITE)/${MAC_SHARED_SETTINGS_SUITE}/g" \
        -e "s/\$(TALKIE_CLOUDKIT_CONTAINER)/${CLOUDKIT_CONTAINER}/g" \
        "$SOURCE_FILE" > "$OUTPUT_FILE"
}

# ═══════════════════════════════════════════════════════════
# FUNCTION: Sign an app bundle with processed entitlements
# ═══════════════════════════════════════════════════════════
sign_app() {
    local APP_PATH="$1"
    local BUNDLE_ID="$2"
    local APP_NAME=$(basename "$APP_PATH")
    local APP_BASE="${APP_NAME%.app}"

    echo "  🔏 Signing $APP_NAME..."

    # Sign all frameworks and dylibs first
    find "$APP_PATH" -name "*.framework" -o -name "*.dylib" 2>/dev/null | while read item; do
        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID_APP" "$item" 2>/dev/null || true
    done

    # Find entitlements file
    local ENTITLEMENTS=""
    for path in \
        "$ROOT_DIR/apps/macos/$APP_BASE/$APP_BASE/$APP_BASE.entitlements" \
        "$ROOT_DIR/apps/macos/$APP_BASE/$APP_BASE.entitlements" \
        "$ROOT_DIR/apps/macos/$APP_BASE/Talkie.entitlements"; do
        if [ -f "$path" ]; then
            ENTITLEMENTS="$path"
            break
        fi
    done

    # Sign the main app bundle
    if [ -n "$ENTITLEMENTS" ] && [ -n "$BUNDLE_ID" ]; then
        # Process entitlements to resolve Xcode variables
        local PROCESSED_ENTITLEMENTS="$PROCESSED_ENTITLEMENTS_DIR/${APP_BASE}.entitlements"
        process_entitlements "$ENTITLEMENTS" "$BUNDLE_ID" "$PROCESSED_ENTITLEMENTS"

        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID_APP" \
            --entitlements "$PROCESSED_ENTITLEMENTS" \
            "$APP_PATH"
    elif [ -n "$ENTITLEMENTS" ]; then
        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID_APP" \
            --entitlements "$ENTITLEMENTS" \
            "$APP_PATH"
    else
        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID_APP" "$APP_PATH"
    fi

    echo "  ✅ $APP_NAME signed"
}

# ═══════════════════════════════════════════════════════════
# ARCHIVE & EXPORT TALKIEAGENT
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔧 Archiving TalkieAgent..."
cd "$ROOT_DIR/apps/macos/TalkieAgent"

LIVE_ARCHIVE="$ARCHIVES_DIR/TalkieAgent.xcarchive"
LIVE_EXPORT="$EXPORTS_DIR/TalkieAgent"

if [ "$SKIP_CLEAN" = "1" ] && [ -d "$LIVE_EXPORT/TalkieAgent.app" ]; then
    echo "  ⏭️  Reusing existing export (SKIP_CLEAN=1)"
else
    rm -rf "$LIVE_ARCHIVE" "$LIVE_EXPORT"

    xcodebuild -project TalkieAgent.xcodeproj \
        -scheme TalkieAgent \
        -configuration Release \
        -archivePath "$LIVE_ARCHIVE" \
        -arch arm64 \
        -allowProvisioningUpdates \
        "${XCODE_AUTH_ARGS[@]}" \
        "${XCODE_RELEASE_SETTINGS[@]}" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        'OTHER_SWIFT_FLAGS=$(inherited) -swift-version 5' \
        archive 2>&1 | grep -E "(error:|warning:|ARCHIVE)" || true

    if [ ! -d "$LIVE_ARCHIVE" ]; then
        echo "❌ TalkieAgent archive failed"
        exit 1
    fi

    echo "  📤 Exporting with Developer ID..."
    xcodebuild -exportArchive \
        -archivePath "$LIVE_ARCHIVE" \
        -exportPath "$LIVE_EXPORT" \
        -exportOptionsPlist "$EXPORT_OPTIONS_CORE_PLIST" \
        -allowProvisioningUpdates \
        "${XCODE_AUTH_ARGS[@]}" \
        2>&1 | grep -E "(error:|warning:|EXPORT)" || true
fi

LIVE_APP="$LIVE_EXPORT/TalkieAgent.app"
if [ ! -d "$LIVE_APP" ]; then
    echo "❌ TalkieAgent export failed"
    exit 1
fi
echo "✅ TalkieAgent archived & exported"

# ═══════════════════════════════════════════════════════════
# ARCHIVE & EXPORT TALKIESYNC
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔧 Archiving TalkieSync..."
cd "$ROOT_DIR/apps/macos/TalkieSync"

SYNC_ARCHIVE="$ARCHIVES_DIR/TalkieSync.xcarchive"
SYNC_EXPORT="$EXPORTS_DIR/TalkieSync"

if [ "$SKIP_CLEAN" = "1" ] && [ -d "$SYNC_EXPORT/TalkieSync.app" ]; then
    echo "  ⏭️  Reusing existing export (SKIP_CLEAN=1)"
else
    rm -rf "$SYNC_ARCHIVE" "$SYNC_EXPORT"

    xcodebuild -project TalkieSync.xcodeproj \
        -scheme TalkieSync \
        -configuration Release \
        -archivePath "$SYNC_ARCHIVE" \
        -arch arm64 \
        -allowProvisioningUpdates \
        "${XCODE_AUTH_ARGS[@]}" \
        "${XCODE_RELEASE_SETTINGS[@]}" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        archive 2>&1 | grep -E "(error:|warning:|ARCHIVE)" || true

    if [ ! -d "$SYNC_ARCHIVE" ]; then
        echo "❌ TalkieSync archive failed"
        exit 1
    fi

    echo "  📤 Exporting with Developer ID..."
    xcodebuild -exportArchive \
        -archivePath "$SYNC_ARCHIVE" \
        -exportPath "$SYNC_EXPORT" \
        -exportOptionsPlist "$EXPORT_OPTIONS_PROVISIONED_PLIST" \
        -allowProvisioningUpdates \
        "${XCODE_AUTH_ARGS[@]}" \
        2>&1 | grep -E "(error:|warning:|EXPORT)" || true
fi

SYNC_APP="$SYNC_EXPORT/TalkieSync.app"
if [ ! -d "$SYNC_APP" ]; then
    echo "❌ TalkieSync export failed"
    exit 1
fi
echo "✅ TalkieSync archived & exported"

# ═══════════════════════════════════════════════════════════
# ARCHIVE & EXPORT TALKIE (CORE)
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔧 Archiving Talkie..."
cd "$ROOT_DIR/apps/macos/Talkie"

CORE_ARCHIVE="$ARCHIVES_DIR/Talkie.xcarchive"
CORE_EXPORT="$EXPORTS_DIR/Talkie"

if [ "$SKIP_CLEAN" = "1" ] && [ -d "$CORE_EXPORT/Talkie.app" ]; then
    echo "  ⏭️  Reusing existing export (SKIP_CLEAN=1)"
else
    rm -rf "$CORE_ARCHIVE" "$CORE_EXPORT"

    xcodebuild -project Talkie.xcodeproj \
        -scheme Talkie \
        -configuration Release \
        -archivePath "$CORE_ARCHIVE" \
        -arch arm64 \
        -allowProvisioningUpdates \
        "${XCODE_AUTH_ARGS[@]}" \
        "${XCODE_RELEASE_SETTINGS[@]}" \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        'OTHER_SWIFT_FLAGS=$(inherited) -swift-version 5' \
        archive 2>&1 | grep -E "(error:|warning:|ARCHIVE)" || true

    if [ ! -d "$CORE_ARCHIVE" ]; then
        echo "❌ Talkie archive failed"
        exit 1
    fi

    echo "  📤 Exporting with Developer ID..."
    xcodebuild -exportArchive \
        -archivePath "$CORE_ARCHIVE" \
        -exportPath "$CORE_EXPORT" \
        -exportOptionsPlist "$EXPORT_OPTIONS_PROVISIONED_PLIST" \
        -allowProvisioningUpdates \
        "${XCODE_AUTH_ARGS[@]}" \
        2>&1 | grep -E "(error:|warning:|EXPORT)" || true
fi

CORE_APP="$CORE_EXPORT/Talkie.app"
if [ ! -d "$CORE_APP" ]; then
    echo "❌ Talkie export failed"
    exit 1
fi
echo "✅ Talkie archived & exported"

# ═══════════════════════════════════════════════════════════
# CREATE UNIFIED BUNDLE
# ═══════════════════════════════════════════════════════════
echo ""
echo "📦 Creating unified Talkie.app bundle..."

# Copy core app as base (already properly signed via exportArchive)
mkdir -p "$STAGING_DIR/Applications"
cp -R "$CORE_APP" "$STAGING_DIR/Applications/"

# Remove resources that will be downloaded during onboarding/updates
# Core build should be just logic - fonts, presets, workflows downloaded separately
echo "  🗑️  Removing downloadable resources..."
rm -rf "$STAGING_DIR/Applications/Talkie.app/Contents/Resources/Resources/Fonts"
rm -rf "$STAGING_DIR/Applications/Talkie.app/Contents/Resources/Resources/Presets"
rm -rf "$STAGING_DIR/Applications/Talkie.app/Contents/Resources/Resources/WorkflowTemplates"
rm -rf "$STAGING_DIR/Applications/Talkie.app/Contents/Resources/Resources/SystemWorkflows"

# Create LoginItems directory and embed helpers
LOGIN_ITEMS="$STAGING_DIR/Applications/Talkie.app/Contents/Library/LoginItems"
mkdir -p "$LOGIN_ITEMS"

echo "  📁 Embedding TalkieAgent..."
cp -R "$LIVE_APP" "$LOGIN_ITEMS/"
sign_app "$LOGIN_ITEMS/TalkieAgent.app" "$AGENT_BUNDLE_ID"

echo "  📁 Embedding TalkieSync..."
cp -R "$SYNC_APP" "$LOGIN_ITEMS/"
sign_app "$LOGIN_ITEMS/TalkieSync.app" "$SYNC_BUNDLE_ID"

# Copy launch agent plists for classic launchd (installed to ~/Library/LaunchAgents on first run)
LAUNCH_AGENTS="$STAGING_DIR/Applications/Talkie.app/Contents/Resources/LaunchAgents"
mkdir -p "$LAUNCH_AGENTS"
echo "  📋 Embedding launch agent plist templates..."
cp "$RESOURCES_DIR/user-agents/jdi.talkie.agent.plist" "$LAUNCH_AGENTS/"
cp "$RESOURCES_DIR/user-agents/jdi.talkie.sync.plist" "$LAUNCH_AGENTS/"

# Sign the main bundle (after embedding)
echo "  🔏 Signing unified Talkie.app..."
TALKIE_ENTITLEMENTS="$ROOT_DIR/apps/macos/Talkie/Talkie.entitlements"
TALKIE_PROCESSED_ENTITLEMENTS="$PROCESSED_ENTITLEMENTS_DIR/Talkie.entitlements"
process_entitlements "$TALKIE_ENTITLEMENTS" "$CORE_BUNDLE_ID" "$TALKIE_PROCESSED_ENTITLEMENTS"
codesign --force --options runtime --timestamp \
    --sign "$DEVELOPER_ID_APP" \
    --entitlements "$TALKIE_PROCESSED_ENTITLEMENTS" \
    "$STAGING_DIR/Applications/Talkie.app"

# Verify
if codesign --verify --deep --strict "$STAGING_DIR/Applications/Talkie.app" 2>/dev/null; then
    echo "  ✅ Unified bundle signed and verified"
else
    echo "  ⚠️  Signature verification issue (may resolve after notarization)"
fi

echo ""
echo "  📂 Bundle structure:"
echo "     Talkie.app/Contents/Library/LoginItems/"
ls "$LOGIN_ITEMS/" | sed 's/^/       ├── /'

# ═══════════════════════════════════════════════════════════
# CREATE DMG
# ═══════════════════════════════════════════════════════════
echo ""
echo "💿 Creating DMG..."

DMG_NAME="Talkie-for-Mac"
OUTPUT_DMG="$SCRIPT_DIR/$DMG_NAME.dmg"
TEMP_DMG="$SCRIPT_DIR/${DMG_NAME}-temp.dmg"
MOUNT_DIR="/Volumes/$DMG_NAME"

# Clean up any existing mount
hdiutil detach "$MOUNT_DIR" 2>/dev/null || true

# Create temporary DMG
echo "  📁 Creating disk image..."
hdiutil create -size 200m -fs HFS+ -volname "$DMG_NAME" "$TEMP_DMG" -ov

# Mount it
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR"

# Copy the app
echo "  📋 Copying Talkie.app..."
cp -R "$STAGING_DIR/Applications/Talkie.app" "$MOUNT_DIR/"

# Create Applications alias (renders icon faster than symlink)
osascript -e 'tell application "Finder" to make alias file to folder "Applications" of startup disk at POSIX file "'"$MOUNT_DIR"'"'

# Add background image
echo "  🎨 Adding background..."
mkdir -p "$MOUNT_DIR/.background"
cp "$RESOURCES_DIR/dmg-background.png" "$MOUNT_DIR/.background/background.png"

sleep 2

# Set DMG layout
echo "  🎨 Setting layout..."
osascript << 'APPLESCRIPT'
tell application "Finder"
    tell disk "Talkie-for-Mac"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 900, 460}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set background picture of theViewOptions to file ".background:background.png"
        set text size of theViewOptions to 10
        set label position of theViewOptions to right
        delay 1
        -- Icon positions (520px width, center at 260)
        set position of item "Talkie.app" of container window to {145, 225}
        set position of item "Applications" of container window to {395, 225}
        update without registering applications
        delay 1
        close
        open
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
sleep 1

# Unmount
hdiutil detach "$MOUNT_DIR"

# Convert to compressed DMG
echo "  📦 Compressing..."
hdiutil convert "$TEMP_DMG" -format UDZO -o "$OUTPUT_DMG" -ov
rm -f "$TEMP_DMG"

# Sign the DMG
echo "  🔏 Signing DMG..."
codesign --force --sign "$DEVELOPER_ID_APP" "$OUTPUT_DMG"

# ═══════════════════════════════════════════════════════════
# NOTARIZE
# ═══════════════════════════════════════════════════════════
if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo ""
    echo "⏭️  Skipping notarization (SKIP_NOTARIZE=1)"
else
    echo ""
    echo "📤 Submitting for notarization..."

    xcrun notarytool submit "$OUTPUT_DMG" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    if [ $? -eq 0 ]; then
        echo "✅ Notarization successful"
        echo "📎 Stapling ticket..."
        xcrun stapler staple "$OUTPUT_DMG"
        echo "✅ Ticket stapled"

        # Archive
        ARCHIVE_DIR="$SCRIPT_DIR/releases/$VERSION"
        mkdir -p "$ARCHIVE_DIR"
        cp "$OUTPUT_DMG" "$ARCHIVE_DIR/"
        echo "📂 Archived to releases/$VERSION/"
    else
        echo "❌ Notarization failed"
        echo "   Check: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════
# DONE
# ═══════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                  BUILD COMPLETE                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
ls -lh "$OUTPUT_DMG"
echo ""
echo "To install:"
echo "  open '$OUTPUT_DMG'"
echo ""
