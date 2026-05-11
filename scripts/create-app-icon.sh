#!/bin/bash
# App Icon Creator for Talkie
# Creates macOS app icon with architect grid background and white squircle border

set -e

# Input: background-removed PNG of the device
INPUT="${1:-input.png}"
OUTPUT_DIR="${2:-output}"
APP_NAME="${3:-icon}"

if [ ! -f "$INPUT" ]; then
    echo "Usage: $0 <input.png> [output_dir] [app_name]"
    echo "  input.png: Background-removed image of the device"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Creating app icon from: $INPUT"

# Step 1: Center the device on 1024x1024 canvas
echo "Step 1: Centering device..."
magick "$INPUT" \
  -trim +repage \
  -gravity center \
  -background none \
  -extent 1024x1024 \
  /tmp/centered.png

# Step 2: Create clip mask (adjust these values per device)
# Current values tuned for the dual-lens camera device
# roundrectangle: left,top right,bottom cornerX,cornerY
CLIP_LEFT=209
CLIP_TOP=372
CLIP_RIGHT=823
CLIP_BOTTOM=642
CLIP_RADIUS=85

echo "Step 2: Creating clip mask..."
magick -size 1024x1024 xc:black \
  -fill white \
  -draw "roundrectangle $CLIP_LEFT,$CLIP_TOP $CLIP_RIGHT,$CLIP_BOTTOM $CLIP_RADIUS,$CLIP_RADIUS" \
  /tmp/clip_mask.png

# Step 3: Clip device to clean shape
echo "Step 3: Clipping device..."
magick /tmp/centered.png /tmp/clip_mask.png \
  -compose CopyOpacity -composite \
  /tmp/device_clipped.png

# Step 4: Add chrome border around device
CHROME_OUTER_LEFT=$((CLIP_LEFT - 15))
CHROME_OUTER_TOP=$((CLIP_TOP - 15))
CHROME_OUTER_RIGHT=$((CLIP_RIGHT + 15))
CHROME_OUTER_BOTTOM=$((CLIP_BOTTOM + 15))
CHROME_RADIUS=95

echo "Step 4: Adding chrome border..."
magick -size 1024x1024 xc:none \
  -fill white -draw "roundrectangle $CHROME_OUTER_LEFT,$CHROME_OUTER_TOP $CHROME_OUTER_RIGHT,$CHROME_OUTER_BOTTOM $CHROME_RADIUS,$CHROME_RADIUS" \
  \( -size 1024x1024 xc:white -fill black -draw "roundrectangle $CLIP_LEFT,$CLIP_TOP $CLIP_RIGHT,$CLIP_BOTTOM $CLIP_RADIUS,$CLIP_RADIUS" \) \
  -compose multiply -composite \
  -shade 130x60 -normalize \
  -brightness-contrast 55x45 \
  -fill "rgb(235,238,245)" -colorize 25% \
  \( -size 1024x1024 xc:none \
     -fill white -draw "roundrectangle $CHROME_OUTER_LEFT,$CHROME_OUTER_TOP $CHROME_OUTER_RIGHT,$CHROME_OUTER_BOTTOM $CHROME_RADIUS,$CHROME_RADIUS" \
     -fill black -draw "roundrectangle $CLIP_LEFT,$CLIP_TOP $CLIP_RIGHT,$CLIP_BOTTOM $CLIP_RADIUS,$CLIP_RADIUS" \) \
  -compose CopyOpacity -composite \
  /tmp/chrome_ring.png

# Step 5: Composite chrome + clipped device
echo "Step 5: Compositing device with chrome..."
magick /tmp/chrome_ring.png /tmp/device_clipped.png \
  -compose over -composite \
  /tmp/device_final.png

# Step 6: Create architect grid background
GRID_SIZE=64
BG_COLOR="rgb(8,8,10)"
GRID_COLOR="rgb(40,40,45)"

echo "Step 6: Creating architect grid background..."
magick -size ${GRID_SIZE}x${GRID_SIZE} xc:"$BG_COLOR" \
  -stroke "$GRID_COLOR" -strokewidth 1 \
  -draw "line $((GRID_SIZE-1)),0 $((GRID_SIZE-1)),$((GRID_SIZE-1))" \
  -draw "line 0,$((GRID_SIZE-1)) $((GRID_SIZE-1)),$((GRID_SIZE-1))" \
  /tmp/grid_tile.png

magick -size 1024x1024 tile:/tmp/grid_tile.png /tmp/grid_full.png

# Step 7: Create squircle mask for background
SQUIRCLE_MARGIN=80
SQUIRCLE_RADIUS=180

echo "Step 7: Creating squircle mask..."
magick -size 1024x1024 xc:black \
  -fill white \
  -draw "roundrectangle $SQUIRCLE_MARGIN,$SQUIRCLE_MARGIN $((1024-SQUIRCLE_MARGIN)),$((1024-SQUIRCLE_MARGIN)) $SQUIRCLE_RADIUS,$SQUIRCLE_RADIUS" \
  /tmp/squircle_mask.png

# Step 8: Apply squircle mask to grid (transparent outside)
echo "Step 8: Masking grid to squircle..."
magick /tmp/grid_full.png /tmp/squircle_mask.png \
  -alpha off -compose CopyOpacity -composite \
  /tmp/grid_transparent.png

# Step 9: Add white border to squircle
BORDER_COLOR="rgb(255,255,255)"
BORDER_WIDTH=3

echo "Step 9: Adding white squircle border..."
magick /tmp/grid_transparent.png \
  -stroke "$BORDER_COLOR" -strokewidth $BORDER_WIDTH -fill none \
  -draw "roundrectangle $SQUIRCLE_MARGIN,$SQUIRCLE_MARGIN $((1024-SQUIRCLE_MARGIN)),$((1024-SQUIRCLE_MARGIN)) $SQUIRCLE_RADIUS,$SQUIRCLE_RADIUS" \
  /tmp/icon_background.png

# Step 10: Final composite - device on grid background
echo "Step 10: Final composite..."
magick /tmp/icon_background.png /tmp/device_final.png \
  -gravity center \
  -compose over -composite \
  "$OUTPUT_DIR/${APP_NAME}_1024.png"

# Step 11: Generate all macOS icon sizes
echo "Step 11: Generating icon sizes..."
SOURCE="$OUTPUT_DIR/${APP_NAME}_1024.png"

magick "$SOURCE" -resize 16x16 "$OUTPUT_DIR/icon_16x16.png"
magick "$SOURCE" -resize 32x32 "$OUTPUT_DIR/icon_16x16@2x.png"
magick "$SOURCE" -resize 32x32 "$OUTPUT_DIR/icon_32x32.png"
magick "$SOURCE" -resize 64x64 "$OUTPUT_DIR/icon_32x32@2x.png"
magick "$SOURCE" -resize 128x128 "$OUTPUT_DIR/icon_128x128.png"
magick "$SOURCE" -resize 256x256 "$OUTPUT_DIR/icon_128x128@2x.png"
magick "$SOURCE" -resize 256x256 "$OUTPUT_DIR/icon_256x256.png"
magick "$SOURCE" -resize 512x512 "$OUTPUT_DIR/icon_256x256@2x.png"
magick "$SOURCE" -resize 512x512 "$OUTPUT_DIR/icon_512x512.png"
magick "$SOURCE" -resize 1024x1024 "$OUTPUT_DIR/icon_512x512@2x.png"

# Step 12: Create Contents.json
echo "Step 12: Creating Contents.json..."
cat > "$OUTPUT_DIR/Contents.json" << 'CONTENTS'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
CONTENTS

echo ""
echo "Done! Icon set created in: $OUTPUT_DIR"
echo ""
echo "To use in Xcode:"
echo "  1. Rename $OUTPUT_DIR to AppIcon.appiconset"
echo "  2. Copy to YourApp/Assets.xcassets/"
echo ""
echo "NOTE: Adjust CLIP_* values in script for different device shapes"
