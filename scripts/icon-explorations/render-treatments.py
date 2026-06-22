#!/usr/bin/env python3
"""Talkie icon treatment explorations (design-lead scratch).

Renders ~6 distinct icon treatments from one shared idea: JetBrains Mono Bold
lowercase 't'. The only thing that varies is FIELD / BOUNDARY / GLYPH color so
we can evaluate which reads as a crisply *bounded* shape under BOTH the macOS
squircle mask and the watchOS circle mask, on BOTH black and white system
backgrounds.

Does NOT touch production assets. Outputs to scripts/icon-explorations/out/.
Each treatment writes a 1024 master PNG; a contact sheet shows every treatment
masked both ways on both backgrounds, plus a 48px circle legibility row.
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

REPO = Path(__file__).resolve().parents[2]
FONT = REPO / "apps/macos/TalkieKit/Sources/TalkieKit/Resources/Fonts/JetBrainsMono-Bold.ttf"
OUT = Path(__file__).resolve().parent / "out"
OUT.mkdir(parents=True, exist_ok=True)

SIZE = 1024
SCALE = 4
CANVAS = SIZE * SCALE


def hx(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---- treatment table -------------------------------------------------------
# field:  ("flat", color) | ("vgrad", top, bottom)
# rim:    None | (color, width_frac, strength)   rim follows max(circle,square)
# glyph:  (color, height_frac)
TREATMENTS = [
    {
        "key": "1-paper",
        "title": "Paper",
        "field": ("flat", "#EFE7D6"),
        "rim": None,
        "glyph": ("#16140E", 0.62),
        "why": "Refined current: warmer/flatter cream, vignette killed. Clean & brand-true; lightest of the set on white.",
    },
    {
        "key": "2-tape-tan",
        "title": "Tape-Tan",
        "field": ("flat", "#D9C49B"),
        "rim": None,
        "glyph": ("#1A160E", 0.62),
        "why": "Saturated mid-tone. The single safest field: clearly bounded on BOTH black and white with zero edge tricks.",
    },
    {
        "key": "3-amber",
        "title": "Amber",
        "field": ("vgrad", "#E9B45A", "#D6902C"),
        "rim": None,
        "glyph": ("#1C160C", 0.60),
        "why": "Leans into Talkie's mag-tape/VU amber identity. Most ownable colour; high contrast on every background.",
    },
    {
        "key": "4-reel",
        "title": "Reel",
        "field": ("vgrad", "#F1E7D3", "#C9B488"),
        "rim": None,
        "glyph": ("#16140E", 0.62),
        "why": "Directional tape-reel light (top bright -> bottom warm). Depth without the sphere look; darker base anchors the lower edge.",
    },
    {
        "key": "5-night",
        "title": "Night",
        "field": ("flat", "#2A2418"),
        "rim": None,
        "glyph": ("#F2EAD8", 0.62),
        "why": "Warm-charcoal (not pure black) inverse. Bold on white; verify the edge survives the BLACK watch home screen.",
    },
    {
        "key": "6-rim-tan",
        "title": "Rim-Tan",
        "field": ("flat", "#DECBA4"),
        "rim": ("#8A7752", 0.07, 0.55),
        "glyph": ("#16140E", 0.62),
        "why": "Flat tan + a tonal rim that follows max(circle,square) so BOTH masks inherit a defined edge from one source. Rim, not an internal button.",
    },
]


def edge_factors():
    yy, xx = np.mgrid[0:CANVAS, 0:CANVAS]
    c = (CANVAS - 1) / 2
    dx = (xx - c) / c
    dy = (yy - c) / c
    radial = np.sqrt(dx * dx + dy * dy)          # 1.0 at inscribed-circle edge
    square = np.maximum(np.abs(dx), np.abs(dy))   # 1.0 at square edge
    return radial, square


def render_field(spec):
    kind = spec[0]
    if kind == "flat":
        rgb = np.zeros((CANVAS, CANVAS, 3), np.float32) + np.array(hx(spec[1]), np.float32)
    else:  # vgrad
        top = np.array(hx(spec[1]), np.float32)
        bot = np.array(hx(spec[2]), np.float32)
        t = np.linspace(0, 1, CANVAS, dtype=np.float32)[:, None, None]
        rgb = top[None, None, :] * (1 - t) + bot[None, None, :] * t
        rgb = np.broadcast_to(rgb, (CANVAS, CANVAS, 3)).copy()
    return rgb


def apply_rim(rgb, rim, radial, square):
    color, width, strength = hx(rim[0]), rim[1], rim[2]
    near = np.maximum(radial, square)             # near EITHER mask edge
    band = np.clip((near - (1.0 - width)) / width, 0, 1)
    band = band * band * (3 - 2 * band)           # smoothstep
    m = (band * strength)[..., None]
    return rgb * (1 - m) + np.array(color, np.float32) * m


def font_for_height(target):
    lo, hi = 1, CANVAS
    while lo < hi:
        mid = (lo + hi + 1) // 2
        f = ImageFont.truetype(str(FONT), mid)
        b = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), "t", font=f)
        if (b[3] - b[1]) <= target:
            lo = mid
        else:
            hi = mid - 1
    return ImageFont.truetype(str(FONT), lo)


def draw_glyph(img, glyph):
    color, frac = hx(glyph[0]), glyph[1]
    d = ImageDraw.Draw(img)
    f = font_for_height(round(frac * CANVAS))
    b = d.textbbox((0, 0), "t", font=f)
    w, h = b[2] - b[0], b[3] - b[1]
    x = (CANVAS - w) / 2 - b[0]
    y = (CANVAS - h) / 2 - b[1]
    d.text((x, y), "t", font=f, fill=color + (255,))


def render_master(t):
    radial, square = edge_factors()
    rgb = render_field(t["field"])
    if t["rim"]:
        rgb = apply_rim(rgb, t["rim"], radial, square)
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).convert("RGBA")
    draw_glyph(img, t["glyph"])
    return img.resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGB")


# ---- masks + contact sheet -------------------------------------------------
def squircle_mask(px):
    m = Image.new("L", (px, px), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, px - 1, px - 1], radius=round(px * 0.225), fill=255)
    return m


def circle_mask(px):
    m = Image.new("L", (px, px), 0)
    ImageDraw.Draw(m).ellipse([0, 0, px - 1, px - 1], fill=255)
    return m


def masked(master, mask_fn, px):
    tile = master.resize((px, px), Image.Resampling.LANCZOS).convert("RGBA")
    tile.putalpha(mask_fn(px))
    return tile


def contact_sheet(masters):
    pad, cell, small = 34, 200, 84
    label_w = 132
    cols = [("squircle / black", "sq", cell, (0, 0, 0)),
            ("squircle / white", "sq", cell, (255, 255, 255)),
            ("circle / black", "ci", cell, (0, 0, 0)),
            ("circle / white", "ci", cell, (255, 255, 255)),
            ("48 / blk", "ci", small, (0, 0, 0)),
            ("48 / wht", "ci", small, (255, 255, 255))]
    row_h = cell + pad
    W = label_w + sum(c[2] + pad for c in cols) + pad
    H = pad * 2 + 60 + len(masters) * row_h
    sheet = Image.new("RGB", (W, H), (40, 40, 44))
    d = ImageDraw.Draw(sheet)
    try:
        hf = ImageFont.truetype(str(FONT), 22)
        sf = ImageFont.truetype(str(FONT), 15)
    except Exception:
        hf = sf = ImageFont.load_default()
    # column headers
    x = label_w + pad
    for title, _, w, _ in cols:
        d.text((x, pad + 6), title, font=sf, fill=(200, 200, 205))
        x += w + pad
    y0 = pad + 50
    for ri, (t, master) in enumerate(masters):
        y = y0 + ri * row_h
        d.text((pad, y + cell // 2 - 24), t["title"], font=hf, fill=(235, 235, 240))
        d.text((pad, y + cell // 2 + 4), t["key"], font=sf, fill=(150, 150, 156))
        x = label_w + pad
        for _, kind, w, bg in cols:
            d.rectangle([x, y, x + w, y + cell if w == cell else y + w], fill=bg)
            mask_fn = circle_mask if kind == "ci" else squircle_mask
            tile = masked(master, mask_fn, w)
            oy = y + (cell - w) // 2 if w != cell else y
            sheet.paste(tile, (x, oy), tile)
            x += w + pad
    return sheet


def main():
    masters = []
    for t in TREATMENTS:
        m = render_master(t)
        m.save(OUT / f"master-{t['key']}.png")
        masters.append((t, m))
        print(f"  master-{t['key']}.png")
    sheet = contact_sheet(masters)
    sheet.save(OUT / "contact-sheet.png")
    print(f"  contact-sheet.png  ({sheet.size[0]}x{sheet.size[1]})")
    print(f"\nOutput: {OUT}")


if __name__ == "__main__":
    main()
