#!/usr/bin/env python3
"""Talkie icon — NIGHT treatment variants (dark warm source).

A dark icon cannot borrow its boundary from the background: on the black watch
home screen there is no contrast, and relying on it is exactly what got the icon
rejected. So every Night variant carries its OWN edge — a lit warm rim/bevel
that follows max(circle, square) and therefore reads under BOTH the macOS
squircle and the watchOS circle, from one source. Field lighting + rim
color/intensity + glyph color are the variables. Glyph stays JetBrains Mono Bold.

Render: python3 scripts/icon-explorations/render-night.py
Output: scripts/icon-explorations/out/night/
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
FONT = REPO / "apps/macos/TalkieKit/Sources/TalkieKit/Resources/Fonts/JetBrainsMono-Bold.ttf"
OUT = Path(__file__).resolve().parent / "out" / "night"
OUT.mkdir(parents=True, exist_ok=True)

SIZE, SCALE = 1024, 4
CANVAS = SIZE * SCALE


def hx(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# field: ("flat", c) | ("vgrad", top, bottom)
# rim:   (color, width_frac, strength)  -> lit bevel: brightest at edge, fades in
# glyph: (color, height_frac)
VARIANTS = [
    {
        "key": "n1-cream-rim", "title": "Cream Rim",
        "field": ("flat", "#2A2418"), "rim": ("#EDE4D0", 0.08, 0.70),
        "glyph": ("#F2EAD8", 0.62),
        "why": "Flat warm-charcoal + crisp neutral cream bevel. The literal edge stroke from one source; max boundary pop on black.",
    },
    {
        "key": "n2-ember-rim", "title": "Ember Rim",
        "field": ("flat", "#2A2418"), "rim": ("#D29A4A", 0.10, 0.60),
        "glyph": ("#F2EAD8", 0.62),
        "why": "Amber lit rim = on-brand mag-tape glow. Warm edge halo reads as light catching the bezel; ties to VU identity.",
    },
    {
        "key": "n3-top-lit", "title": "Top-Lit",
        "field": ("vgrad", "#3A3220", "#1C180F"), "rim": ("#E7DCC4", 0.07, 0.55),
        "glyph": ("#F2EAD8", 0.62),
        "why": "Directional light (bright top -> deep bottom) gives form; rim guarantees the dark lower edge still bounds on black.",
    },
    {
        "key": "n4-bevel", "title": "Bevel",
        "field": ("flat", "#2A2418"), "rim": ("#F4ECDA", 0.045, 0.88),
        "glyph": ("#F2EAD8", 0.62),
        "why": "Tight bright hairline -> reads as a clean stroked edge rather than a glow. Sharpest, most product-like boundary.",
    },
    {
        "key": "n5-amber-glyph", "title": "Amber Glyph",
        "field": ("flat", "#2A2418"), "rim": ("#C9A86A", 0.08, 0.50),
        "glyph": ("#E3A53F", 0.62),
        "why": "Color lives in the MARK: amber 't' on dark, soft tan rim. Identity in the glyph, boundary in the rim.",
    },
    {
        "key": "n6-lifted", "title": "Lifted Field",
        "field": ("flat", "#34301F"), "rim": ("#E7DCC4", 0.06, 0.40),
        "glyph": ("#F2EAD8", 0.62),
        "why": "Field nudged lighter so it carries some separation from pure black itself; rim can then stay subtle. Most 'flat-modern'.",
    },
    {
        "key": "n7-hybrid", "title": "Hybrid",
        "field": ("flat", "#2A2418"), "rim": ("#EDE4D0", 0.08, 0.70),
        "glyph": ("#E3A53F", 0.62),
        "why": "Amber glyph for identity with the boundary-safe cream rim. Best combination of color and watch-on-black separation.",
    },
]


def edge_factors():
    yy, xx = np.mgrid[0:CANVAS, 0:CANVAS]
    c = (CANVAS - 1) / 2
    dx, dy = (xx - c) / c, (yy - c) / c
    return np.sqrt(dx * dx + dy * dy), np.maximum(np.abs(dx), np.abs(dy))


def render_field(spec):
    if spec[0] == "flat":
        return np.zeros((CANVAS, CANVAS, 3), np.float32) + np.array(hx(spec[1]), np.float32)
    top, bot = np.array(hx(spec[1]), np.float32), np.array(hx(spec[2]), np.float32)
    t = np.linspace(0, 1, CANVAS, dtype=np.float32)[:, None, None]
    return np.broadcast_to(top[None, None, :] * (1 - t) + bot[None, None, :] * t,
                           (CANVAS, CANVAS, 3)).copy()


def apply_rim(rgb, rim, radial, square):
    color, width, strength = hx(rim[0]), rim[1], rim[2]
    near = np.maximum(radial, square)
    band = np.clip((near - (1.0 - width)) / width, 0, 1)
    band = band * band * (3 - 2 * band)
    m = (band * strength)[..., None]
    return rgb * (1 - m) + np.array(color, np.float32) * m


def font_for_height(target):
    lo, hi = 1, CANVAS
    while lo < hi:
        mid = (lo + hi + 1) // 2
        f = ImageFont.truetype(str(FONT), mid)
        b = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), "t", font=f)
        lo, hi = (mid, hi) if (b[3] - b[1]) <= target else (lo, mid - 1)
    return ImageFont.truetype(str(FONT), lo)


def draw_glyph(img, glyph):
    color, frac = hx(glyph[0]), glyph[1]
    d = ImageDraw.Draw(img)
    f = font_for_height(round(frac * CANVAS))
    b = d.textbbox((0, 0), "t", font=f)
    w, h = b[2] - b[0], b[3] - b[1]
    d.text(((CANVAS - w) / 2 - b[0], (CANVAS - h) / 2 - b[1]), "t", font=f, fill=color + (255,))


def render_master(v):
    radial, square = edge_factors()
    rgb = apply_rim(render_field(v["field"]), v["rim"], radial, square)
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).convert("RGBA")
    draw_glyph(img, v["glyph"])
    return img.resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGB")


def squircle_mask(px):
    m = Image.new("L", (px, px), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, px - 1, px - 1], radius=round(px * 0.225), fill=255)
    return m


def circle_mask(px):
    m = Image.new("L", (px, px), 0)
    ImageDraw.Draw(m).ellipse([0, 0, px - 1, px - 1], fill=255)
    return m


def masked(master, fn, px):
    tile = master.resize((px, px), Image.Resampling.LANCZOS).convert("RGBA")
    tile.putalpha(fn(px))
    return tile


def contact_sheet(masters):
    pad, cell, small = 34, 200, 84
    label_w = 150
    cols = [("squircle / blk", "sq", cell, (0, 0, 0)),
            ("squircle / wht", "sq", cell, (255, 255, 255)),
            ("circle / blk", "ci", cell, (0, 0, 0)),
            ("circle / wht", "ci", cell, (255, 255, 255)),
            ("48 / blk", "ci", small, (0, 0, 0)),
            ("48 / wht", "ci", small, (255, 255, 255))]
    row_h = cell + pad
    W = label_w + sum(c[2] + pad for c in cols) + pad
    H = pad * 2 + 60 + len(masters) * row_h
    sheet = Image.new("RGB", (W, H), (40, 40, 44))
    d = ImageDraw.Draw(sheet)
    hf, sf = ImageFont.truetype(str(FONT), 22), ImageFont.truetype(str(FONT), 15)
    x = label_w + pad
    for title, _, w, _ in cols:
        d.text((x, pad + 6), title, font=sf, fill=(200, 200, 205)); x += w + pad
    y0 = pad + 50
    for ri, (v, master) in enumerate(masters):
        y = y0 + ri * row_h
        d.text((pad, y + cell // 2 - 24), v["title"], font=hf, fill=(235, 235, 240))
        d.text((pad, y + cell // 2 + 4), v["key"], font=sf, fill=(150, 150, 156))
        x = label_w + pad
        for _, kind, w, bg in cols:
            d.rectangle([x, y, x + w, y + cell], fill=bg)
            fn = circle_mask if kind == "ci" else squircle_mask
            tile = masked(master, fn, w)
            sheet.paste(tile, (x, y + (cell - w) // 2 if w != cell else y), tile)
            x += w + pad
    return sheet


def zoom_sheet(masters):
    sizes = [300, 88, 55, 48]
    pad = 30
    label_w = 170
    gap = 42
    row_h = 300 + pad
    W = label_w + sum(sizes) + gap * (len(sizes) - 1) + pad
    H = pad * 2 + 42 + row_h * len(masters)
    sheet = Image.new("RGB", (W, H), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    small_font = ImageFont.truetype(str(FONT), 15)
    x = label_w + pad
    for size in sizes:
        draw.text((x, pad), f"{size}px", font=small_font, fill=(190, 190, 196))
        x += size + gap

    y0 = pad + 42
    for row, (variant, master) in enumerate(masters):
        y = y0 + row * row_h
        draw.text((pad, y + 120), variant["key"], font=small_font, fill=(235, 235, 240))
        x = label_w + pad
        for size in sizes:
            tile = masked(master, circle_mask, size)
            sheet.paste(tile, (x, y + (300 - size) // 2), tile)
            x += size + gap
    return sheet


def write_composer_icons(masters):
    import json

    icons_dir = OUT / "composer-icons"
    icons_dir.mkdir(parents=True, exist_ok=True)
    for variant, master in masters:
        bundle = icons_dir / f"{variant['key']}.icon"
        assets = bundle / "Assets"
        assets.mkdir(parents=True, exist_ok=True)
        image_name = f"{variant['key']}.png"
        master.save(assets / image_name)
        icon = {
            "fill": {"solid": "extended-srgb:0.16471,0.14118,0.09412,1.00000"},
            "groups": [
                {
                    "layers": [
                        {
                            "image-name": image_name,
                            "name": variant["key"],
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
    for v in VARIANTS:
        m = render_master(v)
        m.save(OUT / f"master-{v['key']}.png")
        masters.append((v, m))
        print(f"  master-{v['key']}.png")
    sheet = contact_sheet(masters)
    sheet.save(OUT / "contact-sheet.png")
    zoom_sheet(masters).save(OUT / "zoom-circle-on-black.png")
    write_composer_icons(masters)
    print(f"  contact-sheet.png ({sheet.size[0]}x{sheet.size[1]})\nOutput: {OUT}")


if __name__ == "__main__":
    main()
