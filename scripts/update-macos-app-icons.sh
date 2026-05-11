#!/bin/bash
# Regenerate macOS app icon PNGs with fully opaque edges for Cmd+Tab.
set -euo pipefail

SOURCE="${1:-icon-fix/source-1024.png}"
OUT_DIR="${2:-icon-fix/AppIcon.appiconset}"

if [ ! -f "$SOURCE" ]; then
  echo "Source icon not found: $SOURCE" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick 'magick' not found in PATH." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

# Generate all sizes as RGB (no alpha) to avoid Sequoia halo sampling.
for size in 16 32 128 256 512; do
  magick "$SOURCE" -resize ${size}x${size} -alpha off -define png:color-type=2 "$OUT_DIR/icon_${size}x${size}.png"
done

magick "$SOURCE" -resize 32x32 -alpha off -define png:color-type=2 "$OUT_DIR/icon_16x16@2x.png"
magick "$SOURCE" -resize 64x64 -alpha off -define png:color-type=2 "$OUT_DIR/icon_32x32@2x.png"
magick "$SOURCE" -resize 256x256 -alpha off -define png:color-type=2 "$OUT_DIR/icon_128x128@2x.png"
magick "$SOURCE" -resize 512x512 -alpha off -define png:color-type=2 "$OUT_DIR/icon_256x256@2x.png"
magick "$SOURCE" -resize 1024x1024 -alpha off -define png:color-type=2 "$OUT_DIR/icon_512x512@2x.png"

# Update app asset catalogs.
for dest in \
  "apps/macos/Talkie/Assets.xcassets/AppIcon.appiconset" \
  "apps/macos/TalkieAgent/TalkieAgent/Assets.xcassets/AppIcon.appiconset" \
  "AppIcon.appiconset"
do
  rm -f "$dest"/*.png
  cp "$OUT_DIR"/*.png "$dest/"
done

echo "Updated macOS app icon PNGs (opaque, full-bleed)."
