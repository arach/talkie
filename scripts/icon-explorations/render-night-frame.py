#!/usr/bin/env python3
"""Night frame variants for Talkie icons.

This pass keeps the square preview square-native: broad edge lighting, soft
corner lift, and only optional low-strength circular support for watchOS. The
goal is a single simple bitmap that stays bounded in both rounded-square and
circle masks without reading like a round button inside the square.
"""

from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
FONT = REPO / "apps/macos/TalkieKit/Sources/TalkieKit/Resources/Fonts/JetBrainsMono-Bold.ttf"
OUT = Path(__file__).resolve().parent / "out" / "night-frame"
OUT.mkdir(parents=True, exist_ok=True)

SIZE = 1024
SCALE = 4
CANVAS = SIZE * SCALE


def hx(value):
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


VARIANTS = [
    {
        "key": "f1-warm-amber",
        "title": "Warm Amber",
        "center": "#211B13",
        "edge": "#4D4230",
        "corner": "#6D604C",
        "glyph": "#E3A53F",
        "edge_strength": 0.68,
        "corner_strength": 0.16,
        "square_line": ("#9A896D", 0.034, 0.18),
        "circle_line": ("#D9C9A9", 0.030, 0.10),
    },
    {
        "key": "f2-warm-cream",
        "title": "Warm Cream",
        "center": "#211B13",
        "edge": "#4D4230",
        "corner": "#6D604C",
        "glyph": "#F2EAD8",
        "edge_strength": 0.68,
        "corner_strength": 0.16,
        "square_line": ("#9A896D", 0.034, 0.18),
        "circle_line": ("#D9C9A9", 0.030, 0.10),
    },
    {
        "key": "f3-brass-amber",
        "title": "Brass Amber",
        "center": "#201A12",
        "edge": "#5E4728",
        "corner": "#8C7042",
        "glyph": "#E3A53F",
        "edge_strength": 0.66,
        "corner_strength": 0.14,
        "square_line": ("#B99050", 0.032, 0.16),
        "circle_line": ("#D8A552", 0.032, 0.13),
    },
    {
        "key": "f4-slate-amber",
        "title": "Slate Amber",
        "center": "#1D221F",
        "edge": "#3E4A43",
        "corner": "#667165",
        "glyph": "#E3A53F",
        "edge_strength": 0.72,
        "corner_strength": 0.18,
        "square_line": ("#859184", 0.034, 0.16),
        "circle_line": ("#CFC6B1", 0.030, 0.10),
    },
    {
        "key": "f5-copper-amber",
        "title": "Copper Amber",
        "center": "#241912",
        "edge": "#5B3320",
        "corner": "#835138",
        "glyph": "#E8A64A",
        "edge_strength": 0.64,
        "corner_strength": 0.16,
        "square_line": ("#A46A45", 0.034, 0.16),
        "circle_line": ("#D08A54", 0.030, 0.11),
    },
    {
        "key": "f6-crisp-frame",
        "title": "Crisp Frame",
        "center": "#211B13",
        "edge": "#393125",
        "corner": "#5B5141",
        "glyph": "#E3A53F",
        "edge_strength": 0.56,
        "corner_strength": 0.14,
        "square_line": ("#EDE4D0", 0.020, 0.24),
        "circle_line": ("#EDE4D0", 0.024, 0.16),
    },
]


yy, xx = np.mgrid[0:CANVAS, 0:CANVAS]
center = (CANVAS - 1) / 2
dx = (xx - center) / center
dy = (yy - center) / center
radial = np.sqrt(dx * dx + dy * dy)
square = np.maximum(np.abs(dx), np.abs(dy))
superellipse = (np.abs(dx) ** 4 + np.abs(dy) ** 4) ** 0.25


def smoothstep(value):
    value = np.clip(value, 0, 1)
    return value * value * (3 - 2 * value)


def mix(rgb, color, amount):
    return rgb * (1 - amount[..., None]) + np.array(hx(color), np.float32) * amount[..., None]


def line_mask(distance, width):
    band = np.clip((distance - (1 - width)) / width, 0, 1)
    return band * band * (3 - 2 * band)


def render_background(spec):
    rgb = np.zeros((CANVAS, CANVAS, 3), np.float32) + np.array(hx(spec["center"]), np.float32)

    broad = smoothstep((0.52 * superellipse + 0.48 * square - 0.34) / 0.66)
    rgb = mix(rgb, spec["edge"], broad * spec["edge_strength"])

    corners = smoothstep((square - 0.83) / 0.17)
    rgb = mix(rgb, spec["corner"], corners * spec["corner_strength"])

    square_color, square_width, square_strength = spec["square_line"]
    rgb = mix(rgb, square_color, line_mask(square, square_width) * square_strength)

    circle_color, circle_width, circle_strength = spec["circle_line"]
    rgb = mix(rgb, circle_color, line_mask(radial, circle_width) * circle_strength)
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
    label_w = 160
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
    heading_font = ImageFont.truetype(str(FONT), 22)
    small_font = ImageFont.truetype(str(FONT), 15)

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
                [x, y, x + column_width, y + (cell if column_width == cell else column_width)],
                fill=background,
            )
            tile = masked(master, mask_fn, column_width)
            offset_y = y + (cell - column_width) // 2 if column_width != cell else y
            sheet.paste(tile, (x, offset_y), tile)
            x += column_width + pad
    return sheet


def zoom_sheet(masters):
    sizes = [300, 88, 55, 48]
    pad, label_w, gap = 30, 170, 42
    row_h = 300 + pad
    width = label_w + sum(sizes) + gap * (len(sizes) - 1) + pad
    height = pad * 2 + 42 + row_h * len(masters)
    sheet = Image.new("RGB", (width, height), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    small_font = ImageFont.truetype(str(FONT), 15)
    x = label_w + pad
    for size in sizes:
        draw.text((x, pad), f"{size}px", font=small_font, fill=(190, 190, 196))
        x += size + gap

    y0 = pad + 42
    for row, (spec, master) in enumerate(masters):
        y = y0 + row * row_h
        draw.text((pad, y + 120), spec["key"], font=small_font, fill=(235, 235, 240))
        x = label_w + pad
        for size in sizes:
            tile = masked(master, circle_mask, size)
            sheet.paste(tile, (x, y + (300 - size) // 2), tile)
            x += size + gap
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
            "fill": {"solid": "extended-srgb:0.12941,0.10588,0.07451,1.00000"},
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
    zoom_sheet(masters).save(OUT / "zoom-circle-on-black.png")
    write_composer_icons(masters)
    print(OUT / "contact-sheet.png")


if __name__ == "__main__":
    main()
