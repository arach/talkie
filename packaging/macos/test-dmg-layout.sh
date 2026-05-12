#!/bin/bash
# Quick DMG layout test - doesn't rebuild apps, just tests icon positioning
# Usage: ./test-dmg-layout.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$SCRIPT_DIR/resources"
DMG_NAME="Talkie-for-Mac"
TEST_DMG="$SCRIPT_DIR/${DMG_NAME}-test.dmg"
MOUNT_DIR="/Volumes/$DMG_NAME"

echo "🧪 Testing DMG layout..."

# Clean up any existing mount/file
hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
rm -f "$TEST_DMG"

# Create temporary DMG
echo "  📁 Creating test disk image..."
hdiutil create -size 50m -fs HFS+ -volname "$DMG_NAME" "$TEST_DMG" -ov -quiet

# Mount it
hdiutil attach "$TEST_DMG" -mountpoint "$MOUNT_DIR" -quiet

# Create a minimal placeholder app with the real icon
echo "  📋 Creating placeholder app with Talkie icon..."
mkdir -p "$MOUNT_DIR/Talkie.app/Contents/MacOS"
mkdir -p "$MOUNT_DIR/Talkie.app/Contents/Resources"
echo '#!/bin/bash' > "$MOUNT_DIR/Talkie.app/Contents/MacOS/Talkie"
chmod +x "$MOUNT_DIR/Talkie.app/Contents/MacOS/Talkie"

# Copy the real app icon if available
ICON_SOURCE=""
if [ -f "$SCRIPT_DIR/staging/Applications/Talkie.app/Contents/Resources/AppIcon.icns" ]; then
    ICON_SOURCE="$SCRIPT_DIR/staging/Applications/Talkie.app/Contents/Resources/AppIcon.icns"
elif [ -f "/Applications/Talkie.app/Contents/Resources/AppIcon.icns" ]; then
    ICON_SOURCE="/Applications/Talkie.app/Contents/Resources/AppIcon.icns"
fi

if [ -n "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$MOUNT_DIR/Talkie.app/Contents/Resources/AppIcon.icns"
    ICON_LINE="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    ICON_LINE=""
fi

cat > "$MOUNT_DIR/Talkie.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Talkie</string>
    <key>CFBundleIdentifier</key>
    <string>to.talkie.app.test</string>
    <key>CFBundleName</key>
    <string>Talkie</string>
    $ICON_LINE
</dict>
</plist>
PLIST

# Create Applications alias and set custom icon
osascript -e 'tell application "Finder" to make alias file to folder "Applications" of startup disk at POSIX file "'"$MOUNT_DIR"'"'

# Set Applications folder icon on the alias (helps it render faster)
osascript << 'ICONSCRIPT'
use framework "AppKit"
use scripting additions

set aliasPath to "/Volumes/Talkie-for-Mac/Applications"
set appsFolderIcon to (current application's NSWorkspace's sharedWorkspace()'s iconForFile:"/Applications")
(current application's NSWorkspace's sharedWorkspace()'s setIcon:appsFolderIcon forFile:aliasPath options:0)
ICONSCRIPT

# Add background image
echo "  🎨 Adding background..."
mkdir -p "$MOUNT_DIR/.background"
cp "$RESOURCES_DIR/dmg-background.png" "$MOUNT_DIR/.background/background.png"

sleep 1

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
        set bounds of container window to {400, 100, 900, 440}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set background picture of theViewOptions to file ".background:background.png"
        set text size of theViewOptions to 10
        set label position of theViewOptions to bottom
        set shows item info of theViewOptions to false
        delay 1
        -- Icons moved inward, y=225
        set position of item "Talkie.app" of container window to {135, 225}
        set position of item "Applications" of container window to {385, 225}
        update without registering applications
        delay 2
        -- Force refresh
        close
        open
        delay 1
    end tell
end tell
APPLESCRIPT

echo ""
echo "✅ Test DMG ready!"
echo "   The Finder window should be open showing the layout."
echo ""
echo "   When done reviewing, run:"
echo "   hdiutil detach '$MOUNT_DIR' && rm '$TEST_DMG'"
echo ""
