#!/bin/bash
# iOS App Icon Creator for Talkie
# Creates iOS app icon set from a 1024x1024 master icon

set -e

# Input: 1024x1024 PNG icon (preferably with iOS rounded square shape)
INPUT="${1:-input.png}"
OUTPUT_DIR="${2:-ios-icon-output}"

if [ ! -f "$INPUT" ]; then
    echo "Usage: $0 <input.png> [output_dir]"
    echo "  input.png: 1024x1024 icon (background removed, iOS rounded square)"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "Creating iOS icon set from: $INPUT"
echo ""

# Prepare master icon: trim transparency, scale to fill ~95% of space, center on canvas
echo "Preparing master icon (trimming and scaling to fill space)..."
magick "$INPUT" \
    -trim +repage \
    -resize 973x973 \
    -gravity center \
    -background none \
    -extent 1024x1024 \
    /tmp/ios_icon_1024.png

MASTER="/tmp/ios_icon_1024.png"

# iOS Icon Sizes (no mask needed - iOS applies it automatically)
# Format: filename, size
declare -a SIZES=(
    "icon_1024.png,1024"
    "icon_20x20@2x.png,40"
    "icon_20x20@3x.png,60"
    "icon_29x29@2x.png,58"
    "icon_29x29@3x.png,87"
    "icon_40x40@2x.png,80"
    "icon_40x40@3x.png,120"
    "icon_60x60@2x.png,120"
    "icon_60x60@3x.png,180"
    "icon_76x76.png,76"
    "icon_76x76@2x.png,152"
    "icon_83.5x83.5@2x.png,167"
)

echo "Generating icon sizes..."
for entry in "${SIZES[@]}"; do
    IFS=',' read -r filename size <<< "$entry"
    echo "  $filename (${size}x${size})"
    magick "$MASTER" -resize "${size}x${size}" "$OUTPUT_DIR/$filename"
done

echo ""
echo "Creating Contents.json..."
cat > "$OUTPUT_DIR/Contents.json" << 'CONTENTS'
{
  "images" : [
    {
      "filename" : "icon_20x20@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "icon_20x20@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "20x20"
    },
    {
      "filename" : "icon_29x29@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "icon_29x29@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "29x29"
    },
    {
      "filename" : "icon_40x40@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "icon_40x40@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "40x40"
    },
    {
      "filename" : "icon_60x60@2x.png",
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60"
    },
    {
      "filename" : "icon_60x60@3x.png",
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "60x60"
    },
    {
      "filename" : "icon_20x20.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "20x20"
    },
    {
      "filename" : "icon_20x20@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "20x20"
    },
    {
      "filename" : "icon_29x29.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "29x29"
    },
    {
      "filename" : "icon_29x29@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "29x29"
    },
    {
      "filename" : "icon_40x40.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "40x40"
    },
    {
      "filename" : "icon_40x40@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "40x40"
    },
    {
      "filename" : "icon_76x76.png",
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "76x76"
    },
    {
      "filename" : "icon_76x76@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "76x76"
    },
    {
      "filename" : "icon_83.5x83.5@2x.png",
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "83.5x83.5"
    },
    {
      "filename" : "icon_1024.png",
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
CONTENTS

# Generate missing iPad 1x sizes
echo "  icon_20x20.png (20x20)"
magick "$MASTER" -resize "20x20" "$OUTPUT_DIR/icon_20x20.png"
echo "  icon_29x29.png (29x29)"
magick "$MASTER" -resize "29x29" "$OUTPUT_DIR/icon_29x29.png"
echo "  icon_40x40.png (40x40)"
magick "$MASTER" -resize "40x40" "$OUTPUT_DIR/icon_40x40.png"

echo ""
echo "✓ Done! iOS icon set created in: $OUTPUT_DIR"
echo ""
echo "To use in Xcode:"
echo "  1. Open: iOS/Talkie iOS/Resources/Assets.xcassets/"
echo "  2. Replace AppIcon.appiconset contents with files from $OUTPUT_DIR"
echo "  3. Or run: cp $OUTPUT_DIR/* 'iOS/Talkie iOS/Resources/Assets.xcassets/AppIcon.appiconset/'"
echo ""
