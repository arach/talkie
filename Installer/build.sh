#!/bin/bash
set -e

# Talkie for Mac - Installer Build Script
# Builds all components with proper signing and notarization

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
STAGING_DIR="$SCRIPT_DIR/staging"
PACKAGES_DIR="$SCRIPT_DIR/packages"
RESOURCES_DIR="$SCRIPT_DIR/resources"

# Version
VERSION="${VERSION:-1.2.0}"

# Signing identities
DEVELOPER_ID_APP="Developer ID Application: Arach Tchoupani (2U83JFPW66)"
DEVELOPER_ID_INSTALLER="Developer ID Installer: Arach Tchoupani (2U83JFPW66)"

# Notarization profile (created via: xcrun notarytool store-credentials "notarytool")
NOTARY_PROFILE="notarytool"

# Skip notarization if set (for testing)
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

echo "╔══════════════════════════════════════════════════════╗"
echo "║        Talkie for Mac - Installer Builder            ║"
echo "║                  Version: $VERSION                      ║"
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

# Clean previous builds
echo ""
echo "🧹 Cleaning previous builds..."
rm -rf "$STAGING_DIR"/*
rm -rf "$PACKAGES_DIR"/*.pkg
rm -f "$SCRIPT_DIR/Talkie-for-Mac.pkg"
rm -f "$SCRIPT_DIR/Talkie-for-Mac-Signed.pkg"

# Create directories
mkdir -p "$STAGING_DIR"/{engine,live,core}
mkdir -p "$PACKAGES_DIR"

# ═══════════════════════════════════════════════════════════
# FUNCTION: Sign an app bundle with Developer ID
# ═══════════════════════════════════════════════════════════
sign_app() {
    local APP_PATH="$1"
    local APP_NAME=$(basename "$APP_PATH")

    echo "  🔏 Signing $APP_NAME..."

    # Sign all frameworks and dylibs first
    find "$APP_PATH" -name "*.framework" -o -name "*.dylib" 2>/dev/null | while read item; do
        codesign --force --options runtime --timestamp \
            --sign "$DEVELOPER_ID_APP" "$item" 2>/dev/null || true
    done

    # Sign the main app bundle
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APP" \
        --entitlements "$ROOT_DIR/macOS/$(echo $APP_NAME | sed 's/.app//')/$(echo $APP_NAME | sed 's/.app//').entitlements" \
        "$APP_PATH" 2>/dev/null || \
    codesign --force --options runtime --timestamp \
        --sign "$DEVELOPER_ID_APP" "$APP_PATH"

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
    clean build 2>&1 | grep -E "(error:|warning:|BUILD)" || true

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
    clean build 2>&1 | grep -E "(error:|warning:|BUILD)" || true

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
# BUILD TALKIE CORE
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔧 Building Talkie (Core)..."
cd "$ROOT_DIR/macOS/Talkie"

# Generate Xcode project if using xcodegen
if [ -f "project.yml" ]; then
    xcodegen generate 2>/dev/null || true
fi

xcodebuild -project Talkie.xcodeproj \
    -scheme Talkie \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/TalkieCore" \
    -arch arm64 \
    clean build 2>&1 | grep -E "(error:|warning:|BUILD)" || true

CORE_APP="$BUILD_DIR/TalkieCore/Build/Products/Release/Talkie.app"
if [ ! -d "$CORE_APP" ]; then
    echo "❌ Talkie Core build failed"
    exit 1
fi
echo "✅ Talkie Core built"

# Stage Core - goes to /Applications
mkdir -p "$STAGING_DIR/core/Applications"
cp -R "$CORE_APP" "$STAGING_DIR/core/Applications/"

# Sign the staged app
sign_app "$STAGING_DIR/core/Applications/Talkie.app"

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

# ═══════════════════════════════════════════════════════════
# CREATE DISTRIBUTION PACKAGE
# ═══════════════════════════════════════════════════════════
echo ""
echo "📦 Creating distribution package..."

# Create unsigned distribution package first
productbuild --distribution "$SCRIPT_DIR/distribution.xml" \
    --resources "$RESOURCES_DIR" \
    --package-path "$PACKAGES_DIR" \
    "$SCRIPT_DIR/Talkie-for-Mac-unsigned.pkg"

# Sign the distribution package
echo ""
echo "🔏 Signing distribution package..."
productsign --sign "$DEVELOPER_ID_INSTALLER" \
    "$SCRIPT_DIR/Talkie-for-Mac-unsigned.pkg" \
    "$SCRIPT_DIR/Talkie-for-Mac.pkg"

rm "$SCRIPT_DIR/Talkie-for-Mac-unsigned.pkg"
echo "✅ Distribution package signed"

# Verify package signature
echo ""
echo "🔍 Verifying package signature..."
pkgutil --check-signature "$SCRIPT_DIR/Talkie-for-Mac.pkg"

# ═══════════════════════════════════════════════════════════
# NOTARIZATION
# ═══════════════════════════════════════════════════════════
if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo ""
    echo "⏭️  Skipping notarization (SKIP_NOTARIZE=1)"
else
    echo ""
    echo "📤 Submitting for notarization..."
    echo "   This may take several minutes..."

    # Submit for notarization and wait
    xcrun notarytool submit "$SCRIPT_DIR/Talkie-for-Mac.pkg" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    NOTARY_STATUS=$?

    if [ $NOTARY_STATUS -eq 0 ]; then
        echo "✅ Notarization successful"

        # Staple the notarization ticket
        echo ""
        echo "📎 Stapling notarization ticket..."
        xcrun stapler staple "$SCRIPT_DIR/Talkie-for-Mac.pkg"
        echo "✅ Notarization ticket stapled"
    else
        echo "❌ Notarization failed"
        echo "   Check the log with: xcrun notarytool log <submission-id> --keychain-profile $NOTARY_PROFILE"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════════════
# FINAL OUTPUT
# ═══════════════════════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║                    BUILD COMPLETE                     ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "📁 Output: $SCRIPT_DIR/Talkie-for-Mac.pkg"
echo ""

# Show package sizes
echo "Package sizes:"
ls -lh "$PACKAGES_DIR"/*.pkg | awk '{print "  " $9 ": " $5}'
echo ""
ls -lh "$SCRIPT_DIR/Talkie-for-Mac.pkg" | awk '{print "Distribution: " $9 ": " $5}'
echo ""

# Verify final package
echo "Final verification:"
spctl --assess --type install "$SCRIPT_DIR/Talkie-for-Mac.pkg" 2>&1 && echo "✅ Package passes Gatekeeper" || echo "⚠️  Gatekeeper check (may need notarization)"

echo ""
echo "🎉 Done! Package is ready for distribution."
echo ""
echo "To test installation:"
echo "  sudo installer -pkg '$SCRIPT_DIR/Talkie-for-Mac.pkg' -target /"
