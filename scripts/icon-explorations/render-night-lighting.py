#!/usr/bin/env python3
"""Night icon variants with broad lighting instead of an internal circle.

This pass avoids hard circular rims. It lights the whole field toward the
perimeter using a blended circle/squircle distance so the same source can feel
bounded under both watchOS circles and macOS rounded rectangles.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
FONT = REPO / "apps/macos/TalkieKit/Sources/TalkieKit/Resources/Fonts/JetBrainsMono-Bold.ttf"
OUT = Path(__file__).resolve().parent / "out-night-lighting"
OUT.mkdir(parents=True, exist_ok=True)

SIZE = 1024
SCALE = 4
CANVAS = SIZE * SCALE


def hx(value):
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


VARIANTS = [
    {
        "key": "l1-tape-night",
        "title": "Tape Night",
        "center": "#211B13",
        "edge": "#5B4F3C",
        "corner": "#7A6E5C",
        "glyph": "#F4EFE6",
        "edge_strength": 0.72,
        "corner_strength": 0.20,
        "directional": None,
        "why": "Dark canvas lifted toward tape-tan edges; calmest shared Night.",
    },
    {
        "key": "l2-brass-night",
        "title": "Brass Night",
        "center": "#201A12",
        "edge": "#6D552F",
        "corner": "#A18049",
        "glyph": "#F5ECDD",
        "edge_strength": 0.76,
        "corner_strength": 0.24,
        "directional": {"color": "#4B3820", "x": -0.40, "y": -0.46, "radius": 1.05, "strength": 0.24},
        "why": "Warm low-key brass, visible on black without turning orange.",
    },
    {
        "key": "l3-slate-night",
        "title": "Slate Night",
        "center": "#1D221F",
        "edge": "#4B554E",
        "corner": "#6D766C",
        "glyph": "#F2EAD8",
        "edge_strength": 0.78,
        "corner_strength": 0.24,
        "directional": {"color": "#344039", "x": -0.32, "y": -0.48, "radius": 1.12, "strength": 0.28},
        "why": "Cooler perimeter; stronger watch boundary with less sepia.",
    },
    {
        "key": "l4-smoked-kraft",
        "title": "Smoked Kraft",
        "center": "#2B2419",
        "edge": "#6B5940",
        "corner": "#A6926F",
        "glyph": "#F3EBDD",
        "edge_strength": 0.66,
        "corner_strength": 0.28,
        "directional": {"color": "#4C3A24", "x": 0.20, "y": -0.52, "radius": 1.18, "strength": 0.18},
        "why": "More paper/tape, still Night; easiest edge on both masks.",
    },
    {
        "key": "l5-copper-night",
        "title": "Copper Night",
        "center": "#231912",
        "edge": "#6C4026",
        "corner": "#9A6037",
        "glyph": "#F5EADC",
        "edge_strength": 0.70,
        "corner_strength": 0.22,
        "directional": {"color": "#51301E", "x": -0.36, "y": -0.42, "radius": 1.05, "strength": 0.20},
        "why": "Hot-mic warmth constrained to the perimeter, not the whole field.",
    },
    {
        "key": "l6-graphite-gold",
        "title": "Graphite Gold",
        "center": "#191816",
        "edge": "#4E4638",
        "corner": "#B79B61",
        "glyph": "#F3EBDD",
        "edge_strength": 0.62,
        "corner_strength": 0.30,
        "directional": None,
        "why": "Deepest field with a gold corner lift; watch edge is the stress test.",
    },
]


yy, xx = np.mgrid[0:CANVAS, 0:CANVAS]
center = (CANVAS - 1) / 2
dx = (xx - center) / center
dy = (yy - center) / center
radial = np.sqrt(dx * dx + dy * dy)
superellipse = (np.abs(dx) ** 4 + np.abs(dy) ** 4) ** 0.25
square = np.maximum(np.abs(dx), np.abs(dy))


def smoothstep(value):
    value = np.clip(value, 0, 1)
    return value * value * (3 - 2 * value)


def mix(rgb, color, amount):
    return rgb * (1 - amount[..., None]) + np.array(hx(color), np.float32) * amount[..., None]


def render_background(spec):
    rgb = np.zeros((CANVAS, CANVAS, 3), np.float32) + np.array(hx(spec["center"]), np.float32)

    distance = np.clip(0.58 * superellipse + 0.42 * radial, 0, 1.25)
    edge_amount = smoothstep((distance - 0.38) / 0.62) * spec["edge_strength"]
    rgb = mix(rgb, spec["edge"], edge_amount)

    corner_amount = smoothstep((square - 0.82) / 0.18) * spec["corner_strength"]
    rgb = mix(rgb, spec["corner"], corner_amount)

    directional = spec.get("directional")
    if directional:
        light_distance = np.sqrt((dx - directional["x"]) ** 2 + (dy - directional["y"]) ** 2)
        light = smoothstep(1 - light_distance / directional["radius"]) * directional["strength"]
        rgb = mix(rgb, directional["color"], light)

    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).convert("RGBA")


def font_for_height(target):
    low, high = 1, CANVAS
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    while low < high:
        mid = (low + high + 1) // 2
        font = ImageFont.truetype(str(FONT), mid)
        bbox = probe.textbbox((0, 0), "t", font=font)
        if bbox[3] - bbox[1] <= target:
            low = mid
        else:
            high = mid - 1
    return ImageFont.truetype(str(FONT), low)


def draw_glyph(image, spec):
    draw = ImageDraw.Draw(image)
    font = font_for_height(round(0.62 * CANVAS))
    bbox = draw.textbbox((0, 0), "t", font=font)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    x = (CANVAS - width) / 2 - bbox[0]
    y = (CANVAS - height) / 2 - bbox[1]
    draw.text((x, y), "t", font=font, fill=hx(spec["glyph"]) + (255,))


def render_master(spec):
    image = render_background(spec)
    draw_glyph(image, spec)
    return image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGB")


def squircle_mask(size):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1],
        radius=round(size * 0.225),
        fill=255,
    )
    return mask


def circle_mask(size):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
    return mask


def masked(master, mask_fn, size):
    tile = master.resize((size, size), Image.Resampling.LANCZOS).convert("RGBA")
    tile.putalpha(mask_fn(size))
    return tile


def contact_sheet(masters):
    pad, cell, small = 34, 200, 84
    label_w = 154
    columns = [
        ("squircle / black", squircle_mask, cell, (0, 0, 0)),
        ("squircle / white", squircle_mask, cell, (255, 255, 255)),
        ("circle / black", circle_mask, cell, (0, 0, 0)),
        ("circle / white", circle_mask, cell, (255, 255, 255)),
        ("48 / blk", circle_mask, small, (0, 0, 0)),
        ("48 / wht", circle_mask, small, (255, 255, 255)),
    ]
    row_height = cell + pad
    width = label_w + sum(column[2] + pad for column in columns) + pad
    height = pad * 2 + 60 + len(masters) * row_height
    sheet = Image.new("RGB", (width, height), (40, 40, 44))
    draw = ImageDraw.Draw(sheet)
    try:
        heading_font = ImageFont.truetype(str(FONT), 22)
        small_font = ImageFont.truetype(str(FONT), 15)
    except Exception:
        heading_font = small_font = ImageFont.load_default()

    x = label_w + pad
    for title, _, column_width, _ in columns:
        draw.text((x, pad + 6), title, font=small_font, fill=(200, 200, 205))
        x += column_width + pad

    y0 = pad + 50
    for row, (spec, master) in enumerate(masters):
        y = y0 + row * row_height
        draw.text((pad, y + cell // 2 - 26), spec["title"], font=heading_font, fill=(235, 235, 240))
        draw.text((pad, y + cell // 2 + 2), spec["key"], font=small_font, fill=(150, 150, 156))
        x = label_w + pad
        for _, mask_fn, column_width, background in columns:
            draw.rectangle(
                [x, y, x + column_width, y + cell if column_width == cell else y + column_width],
                fill=background,
            )
            tile = masked(master, mask_fn, column_width)
            offset_y = y + (cell - column_width) // 2 if column_width != cell else y
            sheet.paste(tile, (x, offset_y), tile)
            x += column_width + pad
    return sheet


def write_composer_icons(masters):
    import json

    icons_dir = OUT / "composer-icons"
    icons_dir.mkdir(parents=True, exist_ok=True)
    for spec, master in masters:
        bundle = icons_dir / f"{spec['key']}.icon"
        assets = bundle / "Assets"
        assets.mkdir(parents=True, exist_ok=True)
        image_name = f"{spec['key']}.png"
        master.save(assets / image_name)
        icon = {
            "fill": {"solid": "extended-srgb:0.95686,0.93725,0.90196,1.00000"},
            "groups": [
                {
                    "layers": [
                        {
                            "image-name": image_name,
                            "name": spec["key"],
                            "position": {"scale": 1, "translation-in-points": [0, 0]},
                        }
                    ]
                }
            ],
            "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
        }
        (bundle / "icon.json").write_text(json.dumps(icon, indent=2) + "\n")


def main():
    masters = []
    for spec in VARIANTS:
        master = render_master(spec)
        master.save(OUT / f"master-{spec['key']}.png")
        masters.append((spec, master))
        print(f"master-{spec['key']}.png")
    contact_sheet(masters).save(OUT / "contact-sheet.png")
    write_composer_icons(masters)
    print(OUT / "contact-sheet.png")


if __name__ == "__main__":
    main()
