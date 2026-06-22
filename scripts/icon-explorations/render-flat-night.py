#!/usr/bin/env python3
"""Flat Night icon variants for Talkie.

Each option keeps the square art full-bleed and simple. watchOS can get a
separate circular boundary; the final amber treatment uses a thinner ring with
subtle directional lighting so it remains visible on black without becoming a
heavy monotone band.
"""

from pathlib import Path
import json

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO = Path(__file__).resolve().parents[2]
FONT = REPO / "apps/macos/TalkieKit/Sources/TalkieKit/Resources/Fonts/JetBrainsMono-Bold.ttf"
OUT = Path(__file__).resolve().parent / "out" / "flat-night"
OUT.mkdir(parents=True, exist_ok=True)

SIZE = 1024
SCALE = 4
CANVAS = SIZE * SCALE


def hx(value):
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


VARIANTS = [
    {
        "key": "flat-amber",
        "title": "Flat Amber",
        "field": "#2B2518",
        "glyph": "#E3A53F",
        "watch_ring": None,
        "square_border": None,
    },
    {
        "key": "flat-cream",
        "title": "Flat Cream",
        "field": "#2B2518",
        "glyph": "#F2EAD8",
        "watch_ring": None,
        "square_border": None,
    },
    {
        "key": "lift-amber",
        "title": "Lift Amber",
        "field": "#2B2518",
        "glyph": "#E3A53F",
        "watch_ring": None,
        "square_border": None,
    },
    {
        "key": "watch-lit-ring",
        "title": "Watch Lit",
        "field": "#2B2518",
        "glyph": "#E3A53F",
        "watch_ring": {
            "style": "lit",
            "highlight": "#E8D3AE",
            "shadow": "#6F5A37",
            "width": 18,
        },
        "square_border": None,
    },
    {
        "key": "watch-cream-ring",
        "title": "Watch Cream",
        "field": "#2B2518",
        "glyph": "#F2EAD8",
        "watch_ring": ("#D8CCB5", 14),
        "square_border": None,
    },
    {
        "key": "thin-frame",
        "title": "Thin Frame",
        "field": "#2B2518",
        "glyph": "#E3A53F",
        "watch_ring": ("#A99473", 14),
        "square_border": ("#645742", 10),
    },
]


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


def draw_glyph(image, color):
    draw = ImageDraw.Draw(image)
    font = font_for_height(round(0.62 * CANVAS))
    bbox = draw.textbbox((0, 0), "t", font=font)
    width = bbox[2] - bbox[0]
    height = bbox[3] - bbox[1]
    x = (CANVAS - width) / 2 - bbox[0]
    y = (CANVAS - height) / 2 - bbox[1]
    draw.text((x, y), "t", font=font, fill=hx(color) + (255,))


def draw_square_border(image, border):
    if not border:
        return
    color, width = border
    draw = ImageDraw.Draw(image)
    inset = width // 2
    draw.rounded_rectangle(
        [inset, inset, CANVAS - inset - 1, CANVAS - inset - 1],
        radius=round(CANVAS * 0.225),
        outline=hx(color) + (255,),
        width=width,
    )


def draw_watch_ring(image, ring):
    if not ring:
        return
    if isinstance(ring, dict) and ring.get("style") == "lit":
        width = round(ring["width"] * SCALE)
        inset = width // 2
        bbox = [inset, inset, CANVAS - inset - 1, CANVAS - inset - 1]

        glow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        glow_draw = ImageDraw.Draw(glow)
        glow_draw.ellipse(
            [inset + 2 * SCALE, inset + 3 * SCALE, CANVAS - inset - 1 + 2 * SCALE, CANVAS - inset - 1 + 3 * SCALE],
            outline=(0, 0, 0, 86),
            width=width,
        )
        image.alpha_composite(glow.filter(ImageFilter.GaussianBlur(radius=2 * SCALE)))

        mask = Image.new("L", (CANVAS, CANVAS), 0)
        ImageDraw.Draw(mask).ellipse(bbox, outline=235, width=width)
        gradient = Image.linear_gradient("L").resize((CANVAS, CANVAS), Image.Resampling.BICUBIC)
        highlight = Image.new("RGBA", (CANVAS, CANVAS), hx(ring["highlight"]) + (0,))
        shadow = Image.new("RGBA", (CANVAS, CANVAS), hx(ring["shadow"]) + (0,))
        layer = Image.composite(shadow, highlight, gradient)
        layer.putalpha(mask)
        image.alpha_composite(layer)
        return
    color, width = ring
    draw = ImageDraw.Draw(image)
    inset = width // 2
    draw.ellipse(
        [inset, inset, CANVAS - inset - 1, CANVAS - inset - 1],
        outline=hx(color) + (255,),
        width=width,
    )


def render_master(spec, watch=False):
    image = Image.new("RGBA", (CANVAS, CANVAS), hx(spec["field"]) + (255,))
    draw_square_border(image, spec["square_border"] if not watch else None)
    draw_watch_ring(image, spec["watch_ring"] if watch else None)
    draw_glyph(image, spec["glyph"])
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


def contact_sheet(rows):
    pad, cell, small = 34, 200, 84
    label_w = 170
    columns = [
        ("square / black", "square", cell, (0, 0, 0)),
        ("square / white", "square", cell, (255, 255, 255)),
        ("watch / black", "watch", cell, (0, 0, 0)),
        ("watch / white", "watch", cell, (255, 255, 255)),
        ("48 / black", "watch", small, (0, 0, 0)),
        ("48 / white", "watch", small, (255, 255, 255)),
    ]
    row_height = cell + pad
    width = label_w + sum(column[2] + pad for column in columns) + pad
    height = pad * 2 + 60 + len(rows) * row_height
    sheet = Image.new("RGB", (width, height), (40, 40, 44))
    draw = ImageDraw.Draw(sheet)
    heading_font = ImageFont.truetype(str(FONT), 22)
    small_font = ImageFont.truetype(str(FONT), 15)

    x = label_w + pad
    for title, _, column_width, _ in columns:
        draw.text((x, pad + 6), title, font=small_font, fill=(200, 200, 205))
        x += column_width + pad

    y0 = pad + 50
    for row_index, (spec, square, watch) in enumerate(rows):
        y = y0 + row_index * row_height
        draw.text((pad, y + cell // 2 - 26), spec["title"], font=heading_font, fill=(235, 235, 240))
        draw.text((pad, y + cell // 2 + 2), spec["key"], font=small_font, fill=(150, 150, 156))
        x = label_w + pad
        for _, kind, column_width, background in columns:
            draw.rectangle(
                [x, y, x + column_width, y + (cell if column_width == cell else column_width)],
                fill=background,
            )
            source = watch if kind == "watch" else square
            mask = circle_mask if kind == "watch" else squircle_mask
            tile = masked(source, mask, column_width)
            offset_y = y + (cell - column_width) // 2 if column_width != cell else y
            sheet.paste(tile, (x, offset_y), tile)
            x += column_width + pad
    return sheet


def write_composer_icons(rows):
    icons_dir = OUT / "composer-icons"
    icons_dir.mkdir(parents=True, exist_ok=True)
    for spec, square, _ in rows:
        bundle = icons_dir / f"{spec['key']}.icon"
        assets = bundle / "Assets"
        assets.mkdir(parents=True, exist_ok=True)
        image_name = f"{spec['key']}.png"
        square.save(assets / image_name)
        icon = {
            "fill": {"solid": "extended-srgb:0.16863,0.14510,0.09412,1.00000"},
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
    rows = []
    for spec in VARIANTS:
        square = render_master(spec, watch=False)
        watch = render_master(spec, watch=True)
        square.save(OUT / f"square-{spec['key']}.png")
        watch.save(OUT / f"watch-{spec['key']}.png")
        rows.append((spec, square, watch))
        print(spec["key"])
    contact_sheet(rows).save(OUT / "contact-sheet.png")
    write_composer_icons(rows)
    print(OUT / "contact-sheet.png")


if __name__ == "__main__":
    main()
