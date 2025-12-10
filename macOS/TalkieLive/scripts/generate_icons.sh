#!/bin/bash
# Generate TalkieLive app icons with chrome bezel effect
# Usage: ./generate_icons.sh <source_image.png>

SOURCE="${1:-/tmp/icon_source_square.png}"
DEST="$(dirname "$0")/../TalkieLive/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE" ]; then
  echo "Error: Source image not found: $SOURCE"
  exit 1
fi

apply_chrome() {
  local size=$1
  local output=$2

  # Calculate proportional sizes (bezel ~86% of canvas, inner ~84%)
  local bezel_size=$((size * 86 / 100))
  local inner_size=$((size * 84 / 100))
  local bezel_radius=$((bezel_size * 15 / 100))
  local inner_radius=$((inner_size * 15 / 100))
  local bezel_max=$((bezel_size - 1))
  local inner_max=$((inner_size - 1))

  # Chrome bezel with gradient (light top, dark bottom)
  magick -size ${bezel_size}x${bezel_size} \
    gradient:'#d8d8d8'-'#888888' \
    -alpha set \
    \( +clone -alpha extract -fill black -colorize 100 \
       -fill white -draw "roundrectangle 0,0,$bezel_max,$bezel_max,$bezel_radius,$bezel_radius" \) \
    -alpha off -compose CopyOpacity -composite \
    /tmp/bezel.png

  # Inner content with rounded corners
  magick "$SOURCE" -resize ${inner_size}x${inner_size} -alpha on \
    \( +clone -alpha extract -fill black -colorize 100 \
       -fill white -draw "roundrectangle 0,0,$inner_max,$inner_max,$inner_radius,$inner_radius" \) \
    -alpha off -compose CopyOpacity -composite \
    /tmp/inner.png

  # Composite with drop shadow
  local shadow_blur=$((size / 60))
  local shadow_offset=$((size / 80))
  [ $shadow_blur -lt 1 ] && shadow_blur=1
  [ $shadow_offset -lt 1 ] && shadow_offset=1

  magick -size ${size}x${size} xc:none \
    \( /tmp/bezel.png -shadow 35x${shadow_blur}+0+${shadow_offset} \) -gravity center -composite \
    /tmp/bezel.png -gravity center -composite \
    /tmp/inner.png -gravity center -composite \
    "$DEST/$output"

  echo "Created $output (${size}px)"
}

echo "Generating TalkieLive icons from: $SOURCE"
echo "Output directory: $DEST"
echo ""

apply_chrome 16 icon_16x16.png
apply_chrome 32 icon_16x16@2x.png
apply_chrome 32 icon_32x32.png
apply_chrome 64 icon_32x32@2x.png
apply_chrome 128 icon_128x128.png
apply_chrome 256 icon_128x128@2x.png
apply_chrome 256 icon_256x256.png
apply_chrome 512 icon_256x256@2x.png
apply_chrome 512 icon_512x512.png
apply_chrome 1024 icon_512x512@2x.png

# Cleanup temp files
rm -f /tmp/bezel.png /tmp/inner.png

echo ""
echo "Done! Icon set generated with chrome bezel effect."
