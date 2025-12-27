#!/bin/bash
# Apple Watch Icon Generator for Talkie
# Creates watch-optimized icons from a source image
# Watch icons are displayed in circles - need high contrast and simple design

set -e

SOURCE="${1:-input.png}"
DEST="${2:-/Users/arach/dev/talkie/iOS/TalkieWatch/Assets.xcassets/AppIcon.appiconset}"

if [ ! -f "$SOURCE" ]; then
  echo "Usage: $0 <source_image.png> [output_dir]"
  echo "  source_image.png: Source image (ideally square, transparent background)"
  exit 1
fi

echo "Creating Apple Watch icons from: $SOURCE"
echo "Output directory: $DEST"
echo ""

# Step 1: Prepare source - remove background, trim, and center
echo "Step 1: Preparing source image..."

# Trim whitespace and center on square canvas
magick "$SOURCE" \
  -fuzz 15% -trim +repage \
  -gravity center \
  -background none \
  -extent 1024x1024 \
  /tmp/watch_trimmed.png

# Step 2: Create a clean circular mask for watch display
# Watch icons look best with the subject filling most of the circle
echo "Step 2: Creating base icon with subtle background..."

# Dark gradient background that looks good on watch
magick -size 1024x1024 \
  radial-gradient:'#2a2a2e'-'#1a1a1c' \
  /tmp/watch_bg.png

# Scale and center the device to fit nicely (85% of canvas)
magick /tmp/watch_trimmed.png \
  -resize 870x870 \
  -gravity center \
  -background none \
  -extent 1024x1024 \
  /tmp/watch_device.png

# Composite device on background
magick /tmp/watch_bg.png /tmp/watch_device.png \
  -gravity center \
  -compose over -composite \
  /tmp/watch_icon_base.png

# Add subtle vignette for depth (circular darkening at edges)
echo "Step 3: Adding circular vignette..."
magick /tmp/watch_icon_base.png \
  \( -size 1024x1024 radial-gradient:none-'rgba(0,0,0,0.3)' \) \
  -compose multiply -composite \
  /tmp/watch_icon_final.png

# Generate all watch icon sizes
echo "Step 4: Generating watch icon sizes..."

generate_icon() {
  local size=$1
  local name=$2
  magick /tmp/watch_icon_final.png -resize ${size}x${size} "$DEST/$name"
  echo "  Created $name (${size}px)"
}

# All required watch sizes from Contents.json
generate_icon 48 "icon-48.png"      # 24@2x - 38mm notification
generate_icon 55 "icon-55.png"      # 27.5@2x - 42mm notification
generate_icon 58 "icon-58.png"      # 29@2x - companion settings
generate_icon 66 "icon-66.png"      # 33@2x - 45mm notification
generate_icon 80 "icon-80.png"      # 40@2x - 38mm home screen
generate_icon 87 "icon-87.png"      # 29@3x - companion settings
generate_icon 88 "icon-88.png"      # 44@2x - 40mm home screen
generate_icon 92 "icon-92.png"      # 46@2x - 41mm home screen
generate_icon 100 "icon-100.png"    # 50@2x - 44mm home screen
generate_icon 102 "icon-102.png"    # 51@2x - 45mm home screen
generate_icon 108 "icon-108.png"    # 54@2x - 49mm home screen
generate_icon 172 "icon-172.png"    # 86@2x - 38mm short look
generate_icon 196 "icon-196.png"    # 98@2x - 42mm short look
generate_icon 216 "icon-216.png"    # 108@2x - 44mm short look
generate_icon 234 "icon-234.png"    # 117@2x - 45mm short look
generate_icon 258 "icon-258.png"    # 129@2x - 49mm short look
generate_icon 1024 "icon-1024.png"  # App Store

# Cleanup
rm -f /tmp/watch_trimmed.png /tmp/watch_bg.png /tmp/watch_device.png /tmp/watch_icon_base.png /tmp/watch_icon_final.png

echo ""
echo "Done! Apple Watch icon set generated."
echo "Icons are in: $DEST"
