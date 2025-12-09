#!/bin/bash
set -e

# Talkie for Mac - Installer Build Script
# Builds all components and creates a distributable package

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$ROOT_DIR/build"
STAGING_DIR="$SCRIPT_DIR/staging"
PACKAGES_DIR="$SCRIPT_DIR/packages"
RESOURCES_DIR="$SCRIPT_DIR/resources"

# Version
VERSION="${VERSION:-1.0.0}"

echo "╔══════════════════════════════════════════════════════╗"
echo "║        Talkie for Mac - Installer Builder            ║"
echo "║                  Version: $VERSION                      ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$STAGING_DIR"/*
rm -rf "$PACKAGES_DIR"/*.pkg
rm -f "$SCRIPT_DIR/Talkie-for-Mac.pkg"

# Create directories
mkdir -p "$STAGING_DIR"/{engine,live,core}
mkdir -p "$PACKAGES_DIR"

# ═══════════════════════════════════════════════════════════
# BUILD TALKIE ENGINE
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔧 Building TalkieEngine..."
cd "$ROOT_DIR/TalkieEngine"
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
cd "$ROOT_DIR/TalkieLive"
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

# ═══════════════════════════════════════════════════════════
# BUILD TALKIE CORE
# ═══════════════════════════════════════════════════════════
echo ""
echo "🔧 Building Talkie (Core)..."
cd "$ROOT_DIR/macOS"

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

# ═══════════════════════════════════════════════════════════
# CREATE COMPONENT PACKAGES
# ═══════════════════════════════════════════════════════════
echo ""
echo "📦 Creating component packages..."

# TalkieEngine package (with scripts for LaunchAgent)
pkgbuild --root "$STAGING_DIR/engine" \
    --scripts "$SCRIPT_DIR/scripts/engine" \
    --identifier "jdi.talkie.engine" \
    --version "$VERSION" \
    --install-location "/" \
    "$PACKAGES_DIR/TalkieEngine.pkg"
echo "  ✅ TalkieEngine.pkg"

# TalkieLive package
pkgbuild --root "$STAGING_DIR/live" \
    --identifier "jdi.talkie.live" \
    --version "$VERSION" \
    --install-location "/" \
    "$PACKAGES_DIR/TalkieLive.pkg"
echo "  ✅ TalkieLive.pkg"

# TalkieCore package
pkgbuild --root "$STAGING_DIR/core" \
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

productbuild --distribution "$SCRIPT_DIR/distribution.xml" \
    --resources "$RESOURCES_DIR" \
    --package-path "$PACKAGES_DIR" \
    "$SCRIPT_DIR/Talkie-for-Mac.pkg"

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

# Optionally create DMG
if [ "$CREATE_DMG" = "1" ]; then
    echo "💿 Creating DMG..."
    DMG_DIR="$BUILD_DIR/dmg"
    mkdir -p "$DMG_DIR"
    cp "$SCRIPT_DIR/Talkie-for-Mac.pkg" "$DMG_DIR/"

    hdiutil create -volname "Talkie for Mac" \
        -srcfolder "$DMG_DIR" \
        -ov -format UDZO \
        "$SCRIPT_DIR/Talkie-for-Mac.dmg"

    echo "💿 DMG created: $SCRIPT_DIR/Talkie-for-Mac.dmg"
fi

echo "🎉 Done!"
