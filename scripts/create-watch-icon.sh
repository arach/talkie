#!/bin/bash
# Apple Watch Icon Generator for Talkie
# Renders a Night 1024px watch master, then resizes every watch icon slot.
# Square app icons use the same flat field and mark without a ring; watchOS
# gets a lighter circular boundary with subtle directional lighting so it stays
# readable on the black home screen without becoming a heavy band.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DEFAULT_FONT="$REPO_ROOT/apps/macos/TalkieKit/Sources/TalkieKit/Resources/Fonts/JetBrainsMono-Bold.ttf"

FONT="${TALKIE_ICON_FONT:-$DEFAULT_FONT}"
DEST="${1:-$REPO_ROOT/apps/ios/TalkieWatch Watch App/Assets.xcassets/AppIcon.appiconset}"
MASTER_OUT="${2:-$REPO_ROOT/assets/icon-assets/composed/watch-flat-night-1024.png}"

if [ ! -f "$FONT" ]; then
  echo "Usage: TALKIE_ICON_FONT=/path/to/font.ttf $0 [output_dir] [master_output.png]"
  echo "  Font defaults to: $DEFAULT_FONT"
  exit 1
fi

mkdir -p "$DEST" "$(dirname "$MASTER_OUT")"

echo "Creating Apple Watch icons with font: $FONT"
echo "Output directory: $DEST"
echo "Master output: $MASTER_OUT"
echo ""

python3 - "$FONT" "$DEST" "$MASTER_OUT" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

font_path = Path(sys.argv[1])
dest = Path(sys.argv[2])
master_out = Path(sys.argv[3])

SIZE = 1024
SCALE = 4
CANVAS = SIZE * SCALE
BRAND = {
    "field": (43, 37, 24),
    "glyph": (227, 165, 63),
    "watch_highlight": (232, 211, 174),
    "watch_shadow": (111, 90, 55),
}

WATCH_SIZES = [
    (48, "icon-48.png"),
    (55, "icon-55.png"),
    (58, "icon-58.png"),
    (66, "icon-66.png"),
    (80, "icon-80.png"),
    (87, "icon-87.png"),
    (88, "icon-88.png"),
    (92, "icon-92.png"),
    (100, "icon-100.png"),
    (102, "icon-102.png"),
    (108, "icon-108.png"),
    (172, "icon-172.png"),
    (196, "icon-196.png"),
    (216, "icon-216.png"),
    (234, "icon-234.png"),
    (258, "icon-258.png"),
    (1024, "icon-1024.png"),
]


def font_for_target_height(target_height):
    low = 1
    high = CANVAS
    while low < high:
        mid = (low + high + 1) // 2
        font = ImageFont.truetype(str(font_path), mid)
        bbox = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), "t", font=font)
        height = bbox[3] - bbox[1]
        if height <= target_height:
            low = mid
        else:
            high = mid - 1
    return ImageFont.truetype(str(font_path), low)


def draw_mark(base):
    draw = ImageDraw.Draw(base)
    font = font_for_target_height(round(650 * SCALE))
    bbox = draw.textbbox((0, 0), "t", font=font)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    x = (CANVAS - width) / 2 - bbox[0]
    y = (CANVAS - height) / 2 - bbox[1] - 8 * SCALE
    draw.text((x, y), "t", font=font, fill=BRAND["glyph"] + (255,))


def draw_watch_ring(base):
    width = round(18 * SCALE)
    inset = width // 2
    bbox = [inset, inset, CANVAS - inset - 1, CANVAS - inset - 1]

    glow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        [inset + 2 * SCALE, inset + 3 * SCALE, CANVAS - inset - 1 + 2 * SCALE, CANVAS - inset - 1 + 3 * SCALE],
        outline=(0, 0, 0, 86),
        width=width,
    )
    base.alpha_composite(glow.filter(ImageFilter.GaussianBlur(radius=2 * SCALE)))

    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).ellipse(bbox, outline=235, width=width)
    gradient = Image.linear_gradient("L").resize((CANVAS, CANVAS), Image.Resampling.BICUBIC)
    highlight = Image.new("RGBA", (CANVAS, CANVAS), BRAND["watch_highlight"] + (0,))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), BRAND["watch_shadow"] + (0,))
    ring = Image.composite(shadow, highlight, gradient)
    ring.putalpha(mask)
    base.alpha_composite(ring)


def render_master():
    base = Image.new("RGBA", (CANVAS, CANVAS), BRAND["field"] + (255,))
    draw_watch_ring(base)
    draw_mark(base)
    return base.resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGB")


master = render_master()
master.save(master_out)

for size, filename in WATCH_SIZES:
    resized = master.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(dest / filename)
    print(f"  Created {filename} ({size}px)")
PY

echo ""
echo "Done! Apple Watch icon set generated."
echo "Icons are in: $DEST"
