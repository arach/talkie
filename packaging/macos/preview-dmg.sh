#!/bin/bash
# DMG Preview Script - Quick iteration on DMG layout design
# Usage:
#   ./preview-dmg.sh          # Create and open test DMG
#   ./preview-dmg.sh --final  # Create compressed read-only DMG

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESOURCES_DIR="$SCRIPT_DIR/resources"
DMG_NAME="Talkie-for-Mac"
MOUNT_DIR="/Volumes/$DMG_NAME"
TEST_DMG="$SCRIPT_DIR/${DMG_NAME}-test.dmg"
FINAL_DMG="$SCRIPT_DIR/${DMG_NAME}-final.dmg"

# Parse args
MAKE_FINAL=false
[[ "$1" == "--final" ]] && MAKE_FINAL=true

echo "🎨 DMG Preview Builder"
echo "======================"

# Cleanup any existing mount
hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
rm -f "$TEST_DMG" "$FINAL_DMG" 2>/dev/null || true

# Step 1: Render background from HTML
echo ""
echo "📸 Rendering background from HTML..."
cd "$RESOURCES_DIR"
if command -v node &> /dev/null && [ -f "render-dmg-bg.js" ]; then
    node render-dmg-bg.js
else
    echo "   ⚠️  Node.js not found or render script missing, using existing PNG"
fi
cd "$SCRIPT_DIR"

# Step 2: Create temp DMG
echo ""
echo "💿 Creating disk image..."
hdiutil create -size 50m -fs HFS+ -volname "$DMG_NAME" "$TEST_DMG" -ov -quiet
hdiutil attach "$TEST_DMG" -mountpoint "$MOUNT_DIR" -quiet

# Step 3: Create placeholder Talkie.app with real icon
echo "📱 Creating Talkie.app placeholder..."
mkdir -p "$MOUNT_DIR/Talkie.app/Contents/MacOS"
mkdir -p "$MOUNT_DIR/Talkie.app/Contents/Resources"
echo '#!/bin/bash' > "$MOUNT_DIR/Talkie.app/Contents/MacOS/Talkie"
chmod +x "$MOUNT_DIR/Talkie.app/Contents/MacOS/Talkie"

# Try to copy real icon
ICON_SOURCE=""
for path in \
    "$SCRIPT_DIR/staging/Applications/Talkie.app/Contents/Resources/AppIcon.icns" \
    "/Applications/Talkie.app/Contents/Resources/AppIcon.icns"; do
    if [ -f "$path" ]; then
        ICON_SOURCE="$path"
        break
    fi
done

if [ -n "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$MOUNT_DIR/Talkie.app/Contents/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    ICON_KEY=""
    echo "   ⚠️  No Talkie icon found, using generic"
fi

cat > "$MOUNT_DIR/Talkie.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Talkie</string>
    <key>CFBundleIdentifier</key><string>to.talkie.app.test</string>
    <key>CFBundleName</key><string>Talkie</string>
    $ICON_KEY
</dict>
</plist>
PLIST

# Step 4: Create Applications alias with folder icon
echo "📁 Creating Applications alias..."
osascript -e 'tell application "Finder" to make alias file to folder "Applications" of startup disk at POSIX file "'"$MOUNT_DIR"'"' > /dev/null

# Set the Applications folder icon on the alias
osascript << 'ICONSCRIPT'
use framework "AppKit"
use scripting additions
set aliasPath to "/Volumes/Talkie-for-Mac/Applications"
set appsFolderIcon to (current application's NSWorkspace's sharedWorkspace()'s iconForFile:"/Applications")
(current application's NSWorkspace's sharedWorkspace()'s setIcon:appsFolderIcon forFile:aliasPath options:0)
ICONSCRIPT

# Step 5: Add background
echo "🖼️  Adding background..."
mkdir -p "$MOUNT_DIR/.background"
cp "$RESOURCES_DIR/dmg-background.png" "$MOUNT_DIR/.background/background.png"

sleep 1

# Step 6: Configure Finder layout
echo "⚙️  Configuring layout..."
osascript << 'APPLESCRIPT'
tell application "Finder"
    tell disk "Talkie-for-Mac"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false

        -- Window: 520x360
        set bounds of container window to {400, 100, 900, 460}

        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 100
        set background picture of theViewOptions to file ".background:background.png"
        set text size of theViewOptions to 10
        set label position of theViewOptions to right
        set shows item info of theViewOptions to false

        delay 1

        -- Icon positions (520px width, center at 260)
        set position of item "Talkie.app" of container window to {145, 225}
        set position of item "Applications" of container window to {395, 225}

        update without registering applications
        delay 2
        close
        open
        delay 1
    end tell
end tell
APPLESCRIPT

if [ "$MAKE_FINAL" = true ]; then
    echo ""
    echo "📦 Creating final compressed DMG..."
    osascript -e 'tell application "Finder" to close window "Talkie-for-Mac"' 2>/dev/null || true
    hdiutil detach "$MOUNT_DIR" -quiet
    hdiutil convert "$TEST_DMG" -format UDZO -o "$FINAL_DMG" -quiet
    rm -f "$TEST_DMG"
    echo ""
    echo "✅ Final DMG: $FINAL_DMG"
    open "$FINAL_DMG"
else
    echo ""
    echo "✅ Preview ready!"
    echo "   DMG is mounted at: $MOUNT_DIR"
    echo ""
    echo "   To iterate:"
    echo "   1. Edit resources/dmg-background.html"
    echo "   2. Run ./preview-dmg.sh again"
    echo ""
    echo "   To create final DMG:"
    echo "   ./preview-dmg.sh --final"
    echo ""
    echo "   To cleanup:"
    echo "   hdiutil detach '$MOUNT_DIR'"
fi
