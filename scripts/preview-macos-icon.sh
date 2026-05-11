#!/bin/bash
# Quick visual preview of how macOS masks a Cmd+Tab icon.
# Usage: bash scripts/preview-macos-icon.sh [source.png] [output.png] [bg_color] [mask.png]
set -euo pipefail

SOURCE="${1:-apps/macos/Talkie/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png}"
OUTPUT="${2:-/tmp/talkie-icon-preview.png}"
BG_COLOR="${3:-#1c1c1e}"
MASK="${4:-icon-fix/mask-edge.png}"

if [ ! -f "$SOURCE" ]; then
  echo "Source icon not found: $SOURCE" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "ImageMagick 'magick' not found in PATH." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

src_png="$tmpdir/source.png"
mask_png="$tmpdir/mask.png"
masked_png="$tmpdir/masked.png"

magick "$SOURCE" -resize 1024x1024 -alpha on "$src_png"

if [ -f "$MASK" ]; then
  cp "$MASK" "$mask_png"
else
  magick -size 1024x1024 xc:black \
    -fill white \
    -draw "roundrectangle 0,0 1023,1023 180,180" \
    "$mask_png"
fi

magick "$src_png" "$mask_png" -compose CopyOpacity -composite "$masked_png"

magick -size 1024x1024 xc:"$BG_COLOR" \
  "$masked_png" -compose over -composite \
  -alpha off -define png:color-type=2 \
  "$OUTPUT"

if command -v python3 >/dev/null 2>&1; then
  python3 - "$SOURCE" <<'PY'
import sys
try:
    from PIL import Image
except Exception:
    print("Note: PIL not available; skipping edge-alpha check.")
    sys.exit(0)

path = sys.argv[1]
img = Image.open(path)
if img.mode != "RGBA":
    print("Edge alpha check: no alpha channel (good).")
    sys.exit(0)
alpha = img.getchannel("A")
w, h = img.size
edges = []
for x in range(w):
    edges.append(alpha.getpixel((x, 0)))
    edges.append(alpha.getpixel((x, h - 1)))
for y in range(h):
    edges.append(alpha.getpixel((0, y)))
    edges.append(alpha.getpixel((w - 1, y)))
print(f"Edge alpha check: min={min(edges)} max={max(edges)} (255/255 is fully opaque).")
PY
fi

echo "Preview written to: $OUTPUT"
