#!/bin/bash
set -e

# Talkie for Mac - Installer Build Script
# Builds all components with proper signing and notarization
#
# Usage:
#   ./build.sh              # Build full installer (all 3 apps separate)
#   ./build.sh unified      # Build unified bundle (single Talkie.app with embedded helpers)
#   ./build.sh core         # Build Talkie-Core installer (Engine + Core)
#   ./build.sh live         # Build Talkie-Live installer (Engine + Live)
#   ./build.sh all          # Build all installers
#
# Environment variables:
#   VERSION=1.3.0           # Set version (default: 1.5.0)
#   SKIP_NOTARIZE=1         # Skip notarization (for testing)
#   SKIP_CLEAN=1            # Skip clean build (incremental, much faster)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
STAGING_DIR="$SCRIPT_DIR/staging"
PACKAGES_DIR="$SCRIPT_DIR/packages"
RESOURCES_DIR="$SCRIPT_DIR/resources"

# Version
VERSION="${VERSION:-1.5.4}"

# Target: full (default), core, live, or all
TARGET="${1:-full}"

# Signing identities
DEVELOPER_ID_APP="Developer ID Application: Arach Tchoupani (2U83JFPW66)"
DEVELOPER_ID_INSTALLER="Developer ID Installer: Arach Tchoupani (2U83JFPW66)"

# Notarization profile (created via: xcrun notarytool store-credentials "notarytool")
NOTARY_PROFILE="notarytool"

# Skip notarization if set (for testing)
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

# Skip clean build if set (for faster iteration)
SKIP_CLEAN="${SKIP_CLEAN:-0}"
BUILD_ACTION="clean build"
if [ "$SKIP_CLEAN" = "1" ]; then
    BUILD_ACTION="build"
fi

# Validate target
if [[ ! "$TARGET" =~ ^(full|unified|core|live|all)$ ]]; then
    echo "❌ Invalid target: $TARGET"
    echo "   Valid targets: full, unified, core, live, all"
    exit 1
fi

echo "╔══════════════════════════════════════════════════════╗"
echo "║        Talkie for Mac - Installer Builder            ║"
echo "║           Version: $VERSION  Target: $TARGET             ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Verify signing identities exist
echo "🔐 Verifying signing identities..."
if ! security find-identity -v | grep -q "$DEVELOPER_ID_APP"; then
    echo "❌ Developer ID Application certificate not found"
    echo "   Expected: $DEVELOPER_ID_APP"
    echo "   Run: security find-identity -v"
    exit 1
fi
if ! security find-identity -v | grep -q "$DEVELOPER_ID_INSTALLER"; then
    echo "❌ Developer ID Installer certificate not found"
    echo "   Expected: $DEVELOPER_ID_INSTALLER"
    exit 1
fi
echo "✅ Signing identities verified"

# Clean previous builds (only for target being built)
echo ""
echo "🧹 Cleaning previous builds..."
rm -rf "$STAGING_DIR"/*
rm -rf "$PACKAGES_DIR"/*.pkg

# Only delete the distribution pkg we're about to build
if [ "$TARGET" = "full" ] || [ "$TARGET" = "all" ]; then
    rm -f "$SCRIPT_DIR/Talkie-for-Mac.pkg"
    rm -f "$SCRIPT_DIR/Talkie-for-Mac-unsigned.pkg"
fi
if [ "$TARGET" = "core" ] || [ "$TARGET" = "all" ]; then
    rm -f "$SCRIPT_DIR/Talkie-Core.pkg"
    rm -f "$SCRIPT_DIR/Talkie-Core-unsigned.pkg"
fi
if [ "$TARGET" = "live" ] || [ "$TARGET" = "all" ]; then
    rm -f "$SCRIPT_DIR/Talkie-Live.pkg"
    rm -f "$SCRIPT_DIR/Talkie-Live-unsigned.pkg"
fi

# Create directories
mkdir -p "$STAGING_DIR"/{engine,live,core}
mkdir -p "$PACKAGES_DIR"

# ═══════════════════════════════════════════════════════════
# FUNCTION: Sign an app bundle with Developer ID
# ═══════════════════════════════════════════════════════════
sign_app() {
    local APP_PATH="$1"
    local APP_NAME=$(basename "$APP_PATH")
    local APP_BASE="${APP_NAME%.app}"

    echo "  🔏 Signing $APP_NAME..."

    # Sign all frameworks and dylibs first
    find "$APP_PATH" -name "*.framework" -o -name "*.dylib" 2>/dev/null | while read item; do
        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID_APP" "$item" 2>/dev/null || true
    done

    # Find entitlements file (handles different project structures)
    local ENTITLEMENTS=""
    for path in \
        "$ROOT_DIR/macOS/$APP_BASE/$APP_BASE/$APP_BASE.entitlements" \
        "$ROOT_DIR/macOS/$APP_BASE/$APP_BASE.entitlements" \
        "$ROOT_DIR/macOS/$APP_BASE/Talkie.entitlements"; do
        if [ -f "$path" ]; then
            ENTITLEMENTS="$path"
            break
        fi
    done

    # Sign the main app bundle
    if [ -n "$ENTITLEMENTS" ]; then
        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID_APP" \
            --entitlements "$ENTITLEMENTS" \
            "$APP_PATH"
    else
        echo "  ⚠️  No entitlements file found for $APP_NAME"
        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID_APP" "$APP_PATH"
    fi

    # Verify signature
    if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
        echo "  ✅ $APP_NAME signed and verified"
    else
        echo "  ⚠️  $APP_NAME signed (verification may require notarization)"
    fi
}

# ═══════════════════════════════════════════════════════════
# BUILD TALKIE ENGINE
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔧 Building TalkieEngine..."
cd "$ROOT_DIR/macOS/TalkieEngine"
xcodebuild -project TalkieEngine.xcodeproj \
    -scheme TalkieEngine \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/TalkieEngine" \
    -arch arm64 \
    $BUILD_ACTION 2>&1 | grep -E "(error:|warning:|BUILD)" || true

ENGINE_APP="$BUILD_DIR/TalkieEngine/Build/Products/Release/TalkieEngine.app"
if [ ! -d "$ENGINE_APP" ]; then
    echo "❌ TalkieEngine build failed"
    exit 1
fi
echo "✅ TalkieEngine built"

# Stage Engine - goes to /Applications + LaunchAgent to /Library/LaunchAgents
mkdir -p "$STAGING_DIR/engine/Applications"
mkdir -p "$STAGING_DIR/engine/Library/LaunchAgents"
cp -R "$ENGINE_APP" "$STAGING_DIR/engine/Applications/"

# Sign the staged app
sign_app "$STAGING_DIR/engine/Applications/TalkieEngine.app"

# Create LaunchAgent plist for installation
cat > "$STAGING_DIR/engine/Library/LaunchAgents/jdi.talkie.engine.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>jdi.talkie.engine</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/TalkieEngine.app/Contents/MacOS/TalkieEngine</string>
    </array>
    <key>MachServices</key>
    <dict>
        <key>jdi.talkie.engine.xpc</key>
        <true/>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/jdi.talkie.engine.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/jdi.talkie.engine.stderr.log</string>
</dict>
</plist>
PLIST

# ═══════════════════════════════════════════════════════════
# BUILD TALKIE LIVE
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔧 Building TalkieLive..."
cd "$ROOT_DIR/macOS/TalkieLive"
xcodebuild -project TalkieLive.xcodeproj \
    -scheme TalkieLive \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/TalkieLive" \
    -arch arm64 \
    $BUILD_ACTION 2>&1 | grep -E "(error:|warning:|BUILD)" || true

LIVE_APP="$BUILD_DIR/TalkieLive/Build/Products/Release/TalkieLive.app"
if [ ! -d "$LIVE_APP" ]; then
    echo "❌ TalkieLive build failed"
    exit 1
fi
echo "✅ TalkieLive built"

# Stage Live - goes to /Applications
mkdir -p "$STAGING_DIR/live/Applications"
cp -R "$LIVE_APP" "$STAGING_DIR/live/Applications/"

# Sign the staged app
sign_app "$STAGING_DIR/live/Applications/TalkieLive.app"

# ═══════════════════════════════════════════════════════════
# BUILD TALKIE CORE (uses archive/export for iCloud entitlements)
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔧 Building Talkie (Core)..."
cd "$ROOT_DIR/macOS/Talkie"

# Generate Xcode project if using xcodegen
if [ -f "project.yml" ]; then
    xcodegen generate 2>/dev/null || true
fi

# Talkie Core has iCloud entitlements which require proper provisioning
# Use archive → export workflow so Xcode handles signing correctly
# Archives are versioned so you can compare builds (clean up old versions manually)
CORE_ARCHIVE="$BUILD_DIR/TalkieCore/Talkie-$VERSION.xcarchive"
CORE_EXPORT="$BUILD_DIR/TalkieCore/Export-$VERSION"
CORE_APP="$CORE_EXPORT/Talkie.app"

# SKIP_CLEAN: reuse existing export if available (archive builds are always full)
if [ "$SKIP_CLEAN" = "1" ] && [ -d "$CORE_APP" ]; then
    echo "  ⏭️  Reusing existing Talkie.app export (SKIP_CLEAN=1)"
else
    echo "  📦 Creating archive..."
    xcodebuild -project Talkie.xcodeproj \
        -scheme Talkie \
        -configuration Release \
        -archivePath "$CORE_ARCHIVE" \
        -arch arm64 \
        archive 2>&1 | grep -E "(error:|warning:|ARCHIVE)" || true

    if [ ! -d "$CORE_ARCHIVE" ]; then
        echo "❌ Talkie Core archive failed"
        exit 1
    fi

    echo "  📤 Exporting with Developer ID..."
    xcodebuild -exportArchive \
        -archivePath "$CORE_ARCHIVE" \
        -exportPath "$CORE_EXPORT" \
        -exportOptionsPlist "$SCRIPT_DIR/exportOptions-core.plist" \
        2>&1 | grep -E "(error:|warning:|EXPORT)" || true

    if [ ! -d "$CORE_APP" ]; then
        echo "❌ Talkie Core export failed"
        exit 1
    fi
    echo "✅ Talkie Core built and signed via Xcode export"
fi

# Stage Core - goes to /Applications (already properly signed by Xcode)
rm -rf "$STAGING_DIR/core"
mkdir -p "$STAGING_DIR/core/Applications"
cp -R "$CORE_APP" "$STAGING_DIR/core/Applications/"

# Verify signature (no re-signing needed - Xcode handled it)
echo "  🔍 Verifying signature..."
if codesign --verify --deep --strict "$STAGING_DIR/core/Applications/Talkie.app" 2>/dev/null; then
    echo "  ✅ Talkie.app signature verified"
else
    echo "  ⚠️  Signature verification issue"
fi

# ═══════════════════════════════════════════════════════════
# CREATE UNIFIED BUNDLE (if target is unified)
# Uses workspace archive → export for proper iCloud signing
# ═══════════════════════════════════════════════════════════
if [ "$TARGET" = "unified" ] || [ "$TARGET" = "all" ]; then
    echo ""
    echo "📦 Building unified Talkie.app bundle..."
    echo "   (Using workspace archive for proper CloudKit signing)"

    UNIFIED_ARCHIVE="$BUILD_DIR/TalkieUnified/Talkie-Unified-$VERSION.xcarchive"
    UNIFIED_EXPORT="$BUILD_DIR/TalkieUnified/Export-$VERSION"
    UNIFIED_APP="$UNIFIED_EXPORT/Talkie.app"

    # SKIP_CLEAN: reuse existing export if available
    if [ "$SKIP_CLEAN" = "1" ] && [ -d "$UNIFIED_APP" ]; then
        echo "  ⏭️  Reusing existing unified Talkie.app export (SKIP_CLEAN=1)"
    else
        # Archive using the workspace scheme "Talkie for Mac"
        # This scheme:
        #   - Builds TalkieEngine and TalkieLive (Archive unchecked)
        #   - Builds Talkie with embed phase that copies helpers to LoginItems
        #   - Archives only Talkie.app (Archive checked)
        echo "  📦 Creating archive via workspace..."
        cd "$ROOT_DIR"
        xcodebuild -workspace TalkieSuite.xcworkspace \
            -scheme "Talkie for Mac" \
            -configuration Release \
            -archivePath "$UNIFIED_ARCHIVE" \
            -destination "generic/platform=macOS" \
            archive 2>&1 | grep -E "(error:|warning:|ARCHIVE|Signing)" || true

        if [ ! -d "$UNIFIED_ARCHIVE" ]; then
            echo "❌ Unified archive failed"
            exit 1
        fi
        echo "  ✅ Archive created"

        echo "  📤 Exporting with Developer ID..."
        xcodebuild -exportArchive \
            -archivePath "$UNIFIED_ARCHIVE" \
            -exportPath "$UNIFIED_EXPORT" \
            -exportOptionsPlist "$SCRIPT_DIR/exportOptions-unified.plist" \
            2>&1 | grep -E "(error:|warning:|EXPORT)" || true

        if [ ! -d "$UNIFIED_APP" ]; then
            echo "❌ Unified export failed"
            exit 1
        fi
        echo "  ✅ Exported with proper signing (iCloud entitlements preserved)"
    fi

    # Create unified staging directory
    rm -rf "$STAGING_DIR/unified"
    mkdir -p "$STAGING_DIR/unified/Applications"
    cp -R "$UNIFIED_APP" "$STAGING_DIR/unified/Applications/"

    # Verify unified bundle signature and structure
    echo "  🔍 Verifying unified bundle..."
    if codesign --verify --deep --strict "$STAGING_DIR/unified/Applications/Talkie.app" 2>/dev/null; then
        echo "  ✅ Signature verified"
    else
        echo "  ⚠️  Signature verification issue"
    fi

    # Verify helpers are embedded, if not - embed them manually
    UNIFIED_LOGIN_ITEMS="$STAGING_DIR/unified/Applications/Talkie.app/Contents/Library/LoginItems"
    if [ -d "$UNIFIED_LOGIN_ITEMS/TalkieEngine.app" ] && \
       [ -d "$UNIFIED_LOGIN_ITEMS/TalkieLive.app" ]; then
        echo "  ✅ Helper apps embedded in LoginItems (via build phase)"
    else
        echo "  📁 Embedding helper apps manually..."
        mkdir -p "$UNIFIED_LOGIN_ITEMS"

        # Copy from staging (already built and signed)
        cp -R "$STAGING_DIR/engine/Applications/TalkieEngine.app" "$UNIFIED_LOGIN_ITEMS/"
        cp -R "$STAGING_DIR/live/Applications/TalkieLive.app" "$UNIFIED_LOGIN_ITEMS/"

        # Re-seal the main bundle (preserve provisioning profile)
        echo "  🔏 Re-sealing unified bundle..."
        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID_APP" \
            --preserve-metadata=identifier,entitlements,requirements \
            "$STAGING_DIR/unified/Applications/Talkie.app"

        echo "  ✅ Helper apps embedded manually"
    fi

    # Show bundle structure
    echo "  📂 Unified bundle structure:"
    echo "     Talkie.app/"
    echo "       └── Contents/"
    echo "           └── Library/"
    echo "               └── LoginItems/"
    ls "$STAGING_DIR/unified/Applications/Talkie.app/Contents/Library/LoginItems/" 2>/dev/null | sed 's/^/                   ├── /' || echo "                   (empty)"

    echo "✅ Unified bundle created"
fi

# ═══════════════════════════════════════════════════════════
# CREATE COMPONENT PACKAGES
# ═══════════════════════════════════════════════════════════
echo ""
echo "📦 Creating component packages..."

# Create component plists to prevent relocation
cat > "$STAGING_DIR/engine-components.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>BundleIsRelocatable</key>
        <false/>
        <key>RootRelativeBundlePath</key>
        <string>Applications/TalkieEngine.app</string>
    </dict>
</array>
</plist>
PLIST

cat > "$STAGING_DIR/live-components.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>BundleIsRelocatable</key>
        <false/>
        <key>RootRelativeBundlePath</key>
        <string>Applications/TalkieLive.app</string>
    </dict>
</array>
</plist>
PLIST

cat > "$STAGING_DIR/core-components.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>BundleIsRelocatable</key>
        <false/>
        <key>RootRelativeBundlePath</key>
        <string>Applications/Talkie.app</string>
    </dict>
</array>
</plist>
PLIST

# TalkieEngine package (with scripts for LaunchAgent)
pkgbuild --root "$STAGING_DIR/engine" \
    --scripts "$SCRIPT_DIR/scripts/engine" \
    --component-plist "$STAGING_DIR/engine-components.plist" \
    --identifier "jdi.talkie.engine" \
    --version "$VERSION" \
    --install-location "/" \
    "$PACKAGES_DIR/TalkieEngine.pkg"
echo "  ✅ TalkieEngine.pkg"

# TalkieLive package
pkgbuild --root "$STAGING_DIR/live" \
    --component-plist "$STAGING_DIR/live-components.plist" \
    --identifier "jdi.talkie.live" \
    --version "$VERSION" \
    --install-location "/" \
    "$PACKAGES_DIR/TalkieLive.pkg"
echo "  ✅ TalkieLive.pkg"

# TalkieCore package
pkgbuild --root "$STAGING_DIR/core" \
    --component-plist "$STAGING_DIR/core-components.plist" \
    --identifier "jdi.talkie.core" \
    --version "$VERSION" \
    --install-location "/" \
    "$PACKAGES_DIR/TalkieCore.pkg"
echo "  ✅ TalkieCore.pkg"

# TalkieUnified package (only if building unified)
if [ "$TARGET" = "unified" ] || [ "$TARGET" = "all" ]; then
    # Create component plist for unified bundle
    cat > "$STAGING_DIR/unified-components.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <dict>
        <key>BundleIsRelocatable</key>
        <false/>
        <key>RootRelativeBundlePath</key>
        <string>Applications/Talkie.app</string>
    </dict>
</array>
</plist>
PLIST

    pkgbuild --root "$STAGING_DIR/unified" \
        --component-plist "$STAGING_DIR/unified-components.plist" \
        --identifier "jdi.talkie.unified" \
        --version "$VERSION" \
        --install-location "/" \
        "$PACKAGES_DIR/TalkieUnified.pkg"
    echo "  ✅ TalkieUnified.pkg"
fi

# ═══════════════════════════════════════════════════════════
# FUNCTION: Build, sign, notarize a distribution package
# ═══════════════════════════════════════════════════════════
build_distribution() {
    local DIST_XML="$1"
    local PKG_NAME="$2"
    local OUTPUT_PKG="$SCRIPT_DIR/$PKG_NAME.pkg"

    echo ""
    echo "📦 Creating $PKG_NAME distribution package..."

    # Create unsigned distribution package
    productbuild --distribution "$SCRIPT_DIR/$DIST_XML" \
        --resources "$RESOURCES_DIR" \
        --package-path "$PACKAGES_DIR" \
        "$SCRIPT_DIR/${PKG_NAME}-unsigned.pkg"

    # Sign the distribution package
    echo "🔏 Signing $PKG_NAME..."
    productsign --sign "$DEVELOPER_ID_INSTALLER" \
        "$SCRIPT_DIR/${PKG_NAME}-unsigned.pkg" \
        "$OUTPUT_PKG"

    rm -f "$SCRIPT_DIR/${PKG_NAME}-unsigned.pkg"
    echo "✅ $PKG_NAME signed"

    # Verify package signature
    echo "🔍 Verifying signature..."
    pkgutil --check-signature "$OUTPUT_PKG"

    # Notarization
    if [ "$SKIP_NOTARIZE" = "1" ]; then
        echo "⏭️  Skipping notarization (SKIP_NOTARIZE=1)"
    else
        echo "📤 Submitting $PKG_NAME for notarization..."

        xcrun notarytool submit "$OUTPUT_PKG" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait

        if [ $? -eq 0 ]; then
            echo "✅ Notarization successful"
            echo "📎 Stapling notarization ticket..."
            xcrun stapler staple "$OUTPUT_PKG"
            echo "✅ Ticket stapled"

            # Archive immediately after successful notarization
            local ARCHIVE_DIR="$SCRIPT_DIR/releases/$VERSION"
            mkdir -p "$ARCHIVE_DIR"
            cp "$OUTPUT_PKG" "$ARCHIVE_DIR/"
            echo "📂 Archived to releases/$VERSION/$PKG_NAME.pkg"
        else
            echo "❌ Notarization failed for $PKG_NAME"
            echo "   Check: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"
            return 1
        fi
    fi

    echo "✅ $PKG_NAME complete: $OUTPUT_PKG"
}

# ═══════════════════════════════════════════════════════════
# CREATE DISTRIBUTION PACKAGES BASED ON TARGET
# ═══════════════════════════════════════════════════════════
BUILT_PACKAGES=()

if [ "$TARGET" = "full" ] || [ "$TARGET" = "all" ]; then
    build_distribution "distribution.xml" "Talkie-for-Mac"
    BUILT_PACKAGES+=("Talkie-for-Mac.pkg")
fi

if [ "$TARGET" = "core" ] || [ "$TARGET" = "all" ]; then
    build_distribution "distribution-core.xml" "Talkie-Core"
    BUILT_PACKAGES+=("Talkie-Core.pkg")
fi

if [ "$TARGET" = "live" ] || [ "$TARGET" = "all" ]; then
    build_distribution "distribution-live.xml" "Talkie-Live"
    BUILT_PACKAGES+=("Talkie-Live.pkg")
fi

if [ "$TARGET" = "unified" ] || [ "$TARGET" = "all" ]; then
    build_distribution "distribution-unified.xml" "Talkie-Unified"
    BUILT_PACKAGES+=("Talkie-Unified.pkg")
fi

# ═══════════════════════════════════════════════════════════
# FINAL OUTPUT
# ═══════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                    BUILD COMPLETE                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Show built packages
echo "📁 Built packages:"
for pkg in "${BUILT_PACKAGES[@]}"; do
    ls -lh "$SCRIPT_DIR/$pkg" | awk '{print "  " $9 ": " $5}'
done
echo ""

# Show component packages
echo "Component packages:"
ls -lh "$PACKAGES_DIR"/*.pkg 2>/dev/null | awk '{print "  " $9 ": " $5}' || true
echo ""

# Verify final packages
echo "Gatekeeper verification:"
for pkg in "${BUILT_PACKAGES[@]}"; do
    spctl --assess --type install "$SCRIPT_DIR/$pkg" 2>&1 && echo "  ✅ $pkg passes Gatekeeper" || echo "  ⚠️  $pkg (may need notarization)"
done

echo ""
echo "🎉 Done! Packages are ready for distribution."
echo ""
echo "To test installation:"
for pkg in "${BUILT_PACKAGES[@]}"; do
    echo "  sudo installer -pkg '$SCRIPT_DIR/$pkg' -target /"
done
