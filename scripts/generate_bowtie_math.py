#!/usr/bin/env python3
import argparse
import json
import math
import os
from PIL import Image


def load_bbox(path):
    img = Image.open(path)
    if img.mode == "RGBA":
        alpha = img.split()[-1]
        bbox = alpha.getbbox()
    else:
        bbox = img.getbbox()
    return bbox, img.size


def cassini_points(a, b, count=2000):
    points = []
    for i in range(count):
        theta = (i / count) * 2 * math.pi
        cos2 = math.cos(2 * theta)
        sin2 = math.sin(2 * theta)
        inside = b**4 - a**4 * (sin2 ** 2)
        if inside < 0:
            inside = 0.0
        r2 = a**2 * cos2 + math.sqrt(inside)
        if r2 < 0:
            r2 = 0.0
        r = math.sqrt(r2)
        x = r * math.cos(theta)
        y = r * math.sin(theta)
        points.append((x, y))
    return points


def transform_points(points, rotate_deg=0.0, scale_x=1.0, scale_y=1.0, translate=(0.0, 0.0)):
    rot = math.radians(rotate_deg)
    cos_r = math.cos(rot)
    sin_r = math.sin(rot)
    out = []
    tx, ty = translate
    for x, y in points:
        xr = x * cos_r - y * sin_r
        yr = x * sin_r + y * cos_r
        xr *= scale_x
        yr *= scale_y
        out.append((xr + tx, yr + ty))
    return out


def bounds(points):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return min(xs), min(ys), max(xs), max(ys)


def save_svg(points, out_path, width, height, stroke="#111", stroke_width=2, fill="none"):
    if not points:
        return
    d = [f"M {points[0][0]:.2f} {points[0][1]:.2f}"]
    for x, y in points[1:]:
        d.append(f"L {x:.2f} {y:.2f}")
    d.append("Z")
    svg = f"""<svg width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\" xmlns=\"http://www.w3.org/2000/svg\">
  <path d=\"{' '.join(d)}\" fill=\"{fill}\" stroke=\"{stroke}\" stroke-width=\"{stroke_width}\" stroke-linecap=\"round\" stroke-linejoin=\"round\" />
</svg>"""
    with open(out_path, "w") as f:
        f.write(svg)


def save_strokes_svg(strokes, out_path, width, height):
    palette = ["#111111", "#444444", "#777777", "#aaaaaa"]
    paths = []
    for i, stroke in enumerate(strokes):
        pts = stroke
        if not pts:
            continue
        d = [f"M {pts[0][0]:.2f} {pts[0][1]:.2f}"]
        for x, y in pts[1:]:
            d.append(f"L {x:.2f} {y:.2f}")
        color = palette[i % len(palette)]
        paths.append(
            f'<path d="{" ".join(d)}" fill="none" stroke="{color}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" />'
        )
    svg = f"""<svg width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\" xmlns=\"http://www.w3.org/2000/svg\">
  <rect width=\"100%\" height=\"100%\" fill=\"#f5f5f5\" />
  {''.join(paths)}
</svg>"""
    with open(out_path, "w") as f:
        f.write(svg)


def split_strokes(points, segments=4):
    n = len(points)
    if n == 0:
        return []
    stride = n // segments
    strokes = []
    for i in range(segments):
        start = i * stride
        end = (i + 1) * stride if i < segments - 1 else n
        strokes.append(points[start:end])
    return strokes


def main():
    parser = argparse.ArgumentParser(description="Generate analytic bowtie using Cassini oval.")
    parser.add_argument("--outdir", default="assets/logo-primitives-math")
    parser.add_argument("--guide", default="assets/logo-primitives-variants/t6_c7_e0/bowtie_silhouette.png")
    parser.add_argument("--a", type=float, default=1.0)
    parser.add_argument("--b", type=float, default=1.22)
    parser.add_argument("--rotate", type=float, default=0.0)
    parser.add_argument("--points", type=int, default=2400)
    parser.add_argument("--stroke-count", type=int, default=4)
    parser.add_argument("--name", default="bowtie_cassini")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    bbox, size = load_bbox(args.guide)
    if bbox is None:
        raise SystemExit("Guide image has empty bbox.")
    x0, y0, x1, y1 = bbox
    guide_w = x1 - x0
    guide_h = y1 - y0
    guide_cx = x0 + guide_w / 2
    guide_cy = y0 + guide_h / 2

    base = cassini_points(args.a, args.b, count=args.points)
    minx, miny, maxx, maxy = bounds(base)
    base_w = maxx - minx
    base_h = maxy - miny

    # scale to guide bbox
    scale_x = guide_w / base_w if base_w else 1.0
    scale_y = guide_h / base_h if base_h else 1.0

    # translate to center
    tx = guide_cx
    ty = guide_cy
    centered = [(x - (minx + base_w / 2), y - (miny + base_h / 2)) for x, y in base]

    points = transform_points(centered, rotate_deg=args.rotate, scale_x=scale_x, scale_y=scale_y, translate=(tx, ty))

    svg_path = os.path.join(args.outdir, f"{args.name}.svg")
    save_svg(points, svg_path, size[0], size[1], stroke="#111111", stroke_width=3)

    strokes = split_strokes(points, segments=args.stroke_count)
    strokes_svg = os.path.join(args.outdir, f"{args.name}_strokes.svg")
    save_strokes_svg(strokes, strokes_svg, size[0], size[1])

    strokes_json = os.path.join(args.outdir, f"{args.name}_strokes.json")
    with open(strokes_json, "w") as f:
        json.dump({"strokes": strokes}, f, indent=2)

    params_json = os.path.join(args.outdir, f"{args.name}_params.json")
    with open(params_json, "w") as f:
        json.dump(
            {
                "a": args.a,
                "b": args.b,
                "rotate": args.rotate,
                "points": args.points,
                "guide": args.guide,
                "scale_x": scale_x,
                "scale_y": scale_y,
                "translate": [tx, ty],
                "bbox": bbox,
            },
            f,
            indent=2,
        )

    print("Generated:")
    print("-", svg_path)
    print("-", strokes_svg)
    print("-", strokes_json)
    print("-", params_json)


if __name__ == "__main__":
    main()
