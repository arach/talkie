#!/usr/bin/env python3
"""Night-focused Talkie icon variants.

Scratch-only renderer for exploring dark-field treatments that remain bounded
under both macOS-style rounded-square masks and watchOS circular masks.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
FONT = REPO / "apps/macos/TalkieKit/Sources/TalkieKit/Resources/Fonts/JetBrainsMono-Bold.ttf"
OUT = Path(__file__).resolve().parent / "out-night"
OUT.mkdir(parents=True, exist_ok=True)

SIZE = 1024
SCALE = 4
CANVAS = SIZE * SCALE


def hx(value):
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


VARIANTS = [
    {
        "key": "n1-warm-keyline",
        "title": "Warm Keyline",
        "field": "#262017",
        "glyph": "#F3EBDD",
        "edge": "#B99B63",
        "edge_width": 0.070,
        "edge_strength": 0.72,
        "inner": "#16120D",
        "inner_width": 0.055,
        "inner_strength": 0.32,
        "light": None,
        "why": "Warm charcoal plus a tape-metal keyline at the actual mask edge.",
    },
    {
        "key": "n2-copper-edge",
        "title": "Copper Edge",
        "field": "#211C14",
        "glyph": "#F4EFE6",
        "edge": "#C07A3E",
        "edge_width": 0.090,
        "edge_strength": 0.58,
        "inner": "#14100B",
        "inner_width": 0.050,
        "inner_strength": 0.26,
        "light": None,
        "why": "A restrained hot-mic/copper perimeter without filling the whole icon orange.",
    },
    {
        "key": "n3-brass-lit",
        "title": "Brass Lit",
        "field": "#2B251A",
        "glyph": "#F6EFE0",
        "edge": "#D3B06C",
        "edge_width": 0.105,
        "edge_strength": 0.48,
        "inner": "#17130D",
        "inner_width": 0.055,
        "inner_strength": 0.20,
        "light": {"color": "#6C5734", "x": -0.42, "y": -0.52, "radius": 0.92, "strength": 0.32},
        "why": "Directional brass light, so the dark field has shape before masking.",
    },
    {
        "key": "n4-slate-lit",
        "title": "Slate Lit",
        "field": "#20241F",
        "glyph": "#F2EAD8",
        "edge": "#9EA89D",
        "edge_width": 0.080,
        "edge_strength": 0.54,
        "inner": "#10130F",
        "inner_width": 0.050,
        "inner_strength": 0.26,
        "light": {"color": "#465046", "x": -0.36, "y": -0.48, "radius": 0.98, "strength": 0.34},
        "why": "Cool green-gray edge separates from black without becoming beige.",
    },
    {
        "key": "n5-paper-rim",
        "title": "Paper Rim",
        "field": "#211B13",
        "glyph": "#F4EFE6",
        "edge": "#E7D9BC",
        "edge_width": 0.050,
        "edge_strength": 0.82,
        "inner": "#18130D",
        "inner_width": 0.080,
        "inner_strength": 0.36,
        "light": None,
        "why": "The most explicit boundary: a narrow paper-colored perimeter.",
    },
    {
        "key": "n6-smoked-tape",
        "title": "Smoked Tape",
        "field": "#31291D",
        "glyph": "#F1E8D7",
        "edge": "#7A6E5C",
        "edge_width": 0.115,
        "edge_strength": 0.70,
        "inner": "#17130D",
        "inner_width": 0.050,
        "inner_strength": 0.24,
        "light": {"color": "#5B4B31", "x": 0.18, "y": -0.56, "radius": 1.08, "strength": 0.22},
        "why": "Brand tape-tan rim, dark enough to feel like Night but no black edge.",
    },
]


def edge_factors():
    yy, xx = np.mgrid[0:CANVAS, 0:CANVAS]
    center = (CANVAS - 1) / 2
    dx = (xx - center) / center
    dy = (yy - center) / center
    radial = np.sqrt(dx * dx + dy * dy)
    square = np.maximum(np.abs(dx), np.abs(dy))
    return dx, dy, radial, square


DX, DY, RADIAL, SQUARE = edge_factors()
MASK_EDGE = np.maximum(RADIAL, SQUARE)


def smoothstep(value):
    value = np.clip(value, 0, 1)
    return value * value * (3 - 2 * value)


def apply_color_mix(rgb, color, amount):
    return rgb * (1 - amount[..., None]) + np.array(hx(color), np.float32) * amount[..., None]


def render_background(spec):
    rgb = np.zeros((CANVAS, CANVAS, 3), np.float32) + np.array(hx(spec["field"]), np.float32)

    light = spec.get("light")
    if light:
        distance = np.sqrt((DX - light["x"]) ** 2 + (DY - light["y"]) ** 2)
        amount = smoothstep(1 - distance / light["radius"]) * light["strength"]
        rgb = apply_color_mix(rgb, light["color"], amount)

    edge = smoothstep((MASK_EDGE - (1 - spec["edge_width"])) / spec["edge_width"]) * spec["edge_strength"]
    rgb = apply_color_mix(rgb, spec["edge"], edge)

    inner_start = 1 - spec["edge_width"] - spec["inner_width"]
    inner = smoothstep((MASK_EDGE - inner_start) / spec["inner_width"])
    inner = (1 - np.abs(inner * 2 - 1)) * spec["inner_strength"]
    rgb = apply_color_mix(rgb, spec["inner"], inner)
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
                            "position": {
                                "scale": 1,
                                "translation-in-points": [0, 0],
                            },
                        }
                    ]
                }
            ],
            "supported-platforms": {
                "circles": ["watchOS"],
                "squares": "shared",
            },
        }
        (bundle / "icon.json").write_text(__import__("json").dumps(icon, indent=2) + "\n")


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
