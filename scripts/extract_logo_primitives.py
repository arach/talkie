#!/usr/bin/env python3
import argparse
import json
import math
import os
from collections import deque, defaultdict

from PIL import Image, ImageFilter


def load_image(path):
    img = Image.open(path)
    if img.mode == "RGBA":
        bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
        img = Image.alpha_composite(bg, img).convert("RGB")
    else:
        img = img.convert("RGB")
    return img


def otsu_threshold(gray):
    hist = gray.histogram()
    total = sum(hist)
    sum_total = sum(i * hist[i] for i in range(256))

    sum_b = 0
    w_b = 0
    max_var = -1
    threshold = 128

    for i in range(256):
        w_b += hist[i]
        if w_b == 0:
            continue
        w_f = total - w_b
        if w_f == 0:
            break
        sum_b += i * hist[i]
        m_b = sum_b / w_b
        m_f = (sum_total - sum_b) / w_f
        var_between = w_b * w_f * (m_b - m_f) ** 2
        if var_between > max_var:
            max_var = var_between
            threshold = i

    return threshold


def dominant_background_color(rgb, alpha=None, step=8, downsample=256, alpha_cutoff=10):
    small = rgb.resize((downsample, downsample), Image.BILINEAR)
    alpha_small = alpha.resize((downsample, downsample), Image.BILINEAR) if alpha else None

    hist = {}
    small_data = list(small.getdata())
    alpha_data = list(alpha_small.getdata()) if alpha_small else None

    for i, (r, g, b) in enumerate(small_data):
        if alpha_data and alpha_data[i] < alpha_cutoff:
            continue
        key = (r // step, g // step, b // step)
        hist[key] = hist.get(key, 0) + 1

    if not hist:
        return (255, 255, 255)

    bg_bin = max(hist.items(), key=lambda kv: kv[1])[0]
    return tuple(int((c + 0.5) * step) for c in bg_bin)


def kmeans_1d_threshold(values, max_iter=25):
    if not values:
        return 0.0

    c1 = min(values)
    c2 = max(values)

    for _ in range(max_iter):
        g1 = []
        g2 = []
        for v in values:
            if abs(v - c1) < abs(v - c2):
                g1.append(v)
            else:
                g2.append(v)

        c1_new = sum(g1) / len(g1) if g1 else c1
        c2_new = sum(g2) / len(g2) if g2 else c2

        if abs(c1_new - c1) < 0.01 and abs(c2_new - c2) < 0.01:
            break

        c1, c2 = c1_new, c2_new

    c_low, c_high = sorted([c1, c2])
    return (c_low + c_high) / 2


def make_mask(
    img,
    threshold_offset=0,
    closing_size=5,
    mode="otsu",
    bg_step=8,
    bg_downsample=256,
    alpha_cutoff=10,
    bg_threshold=None,
):
    if img.mode == "RGBA":
        alpha = img.split()[-1]
        rgb = img.convert("RGB")
    else:
        alpha = None
        rgb = img.convert("RGB")

    info = {"mode": mode}

    if mode == "bg":
        bg_color = dominant_background_color(
            rgb,
            alpha=alpha,
            step=bg_step,
            downsample=bg_downsample,
            alpha_cutoff=alpha_cutoff,
        )
        info["bg_color"] = bg_color

        # sample distances on downsample for threshold
        small = rgb.resize((bg_downsample, bg_downsample), Image.BILINEAR)
        alpha_small = alpha.resize((bg_downsample, bg_downsample), Image.BILINEAR) if alpha else None
        small_data = list(small.getdata())
        alpha_data = list(alpha_small.getdata()) if alpha_small else None

        distances = []
        for i, (r, g, b) in enumerate(small_data):
            if alpha_data and alpha_data[i] < alpha_cutoff:
                continue
            d = math.sqrt(
                (r - bg_color[0]) ** 2
                + (g - bg_color[1]) ** 2
                + (b - bg_color[2]) ** 2
            )
            distances.append(d)

        threshold = bg_threshold if bg_threshold is not None else kmeans_1d_threshold(distances)
        threshold = max(0.0, threshold + threshold_offset)
        info["threshold"] = threshold

        w, h = rgb.size
        rgb_data = list(rgb.getdata())
        alpha_data_full = list(alpha.getdata()) if alpha else None
        mask = Image.new("L", (w, h), 0)
        mask_data = mask.load()

        for i, (r, g, b) in enumerate(rgb_data):
            if alpha_data_full and alpha_data_full[i] < alpha_cutoff:
                continue
            d = math.sqrt(
                (r - bg_color[0]) ** 2
                + (g - bg_color[1]) ** 2
                + (b - bg_color[2]) ** 2
            )
            if d > threshold:
                mask_data[i % w, i // w] = 255

    else:
        gray = rgb.convert("L")
        threshold = otsu_threshold(gray)
        threshold = max(0, min(255, threshold + threshold_offset))
        info["threshold"] = threshold
        mask = gray.point(lambda p: 255 if p < threshold else 0)

    if closing_size and closing_size >= 3:
        mask = mask.filter(ImageFilter.MaxFilter(closing_size))
        mask = mask.filter(ImageFilter.MinFilter(closing_size))

    return mask, info


def largest_component(mask, exclude_border=False):
    w, h = mask.size
    data = list(mask.getdata())
    visited = [False] * (w * h)
    largest = []

    neighbors = [
        (-1, -1), (0, -1), (1, -1),
        (-1, 0),           (1, 0),
        (-1, 1),  (0, 1),  (1, 1),
    ]

    for y in range(h):
        row_offset = y * w
        for x in range(w):
            idx = row_offset + x
            if data[idx] == 0 or visited[idx]:
                continue
            queue = deque([idx])
            visited[idx] = True
            component = [idx]
            touches_border = False

            while queue:
                i = queue.popleft()
                cy = i // w
                cx = i - (cy * w)
                if cx == 0 or cy == 0 or cx == w - 1 or cy == h - 1:
                    touches_border = True
                for dx, dy in neighbors:
                    nx = cx + dx
                    ny = cy + dy
                    if nx < 0 or ny < 0 or nx >= w or ny >= h:
                        continue
                    ni = ny * w + nx
                    if visited[ni] or data[ni] == 0:
                        continue
                    visited[ni] = True
                    queue.append(ni)
                    component.append(ni)

            if exclude_border and touches_border:
                continue
            if len(component) > len(largest):
                largest = component

    if not largest and exclude_border and any(data):
        return largest_component(mask, exclude_border=False)

    out = Image.new("L", (w, h), 0)
    out_data = out.load()
    for idx in largest:
        out_data[idx % w, idx // w] = 255

    return out


def silhouette_from_mask(mask):
    w, h = mask.size
    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fill = Image.new("RGBA", (w, h), (0, 0, 0, 255))
    return Image.composite(fill, base, mask)


def marching_squares(mask):
    w, h = mask.size
    data = list(mask.getdata())

    def is_on(x, y):
        return data[y * w + x] > 0

    def key(pt):
        return (round(pt[0], 3), round(pt[1], 3))

    segments = []
    for y in range(h - 1):
        for x in range(w - 1):
            tl = 1 if is_on(x, y) else 0
            tr = 1 if is_on(x + 1, y) else 0
            br = 1 if is_on(x + 1, y + 1) else 0
            bl = 1 if is_on(x, y + 1) else 0
            case = (tl << 3) | (tr << 2) | (br << 1) | bl
            if case == 0 or case == 15:
                continue

            top = (x + 0.5, y)
            right = (x + 1, y + 0.5)
            bottom = (x + 0.5, y + 1)
            left = (x, y + 0.5)

            crossings = []
            if tl != tr:
                crossings.append(("top", top))
            if tr != br:
                crossings.append(("right", right))
            if br != bl:
                crossings.append(("bottom", bottom))
            if bl != tl:
                crossings.append(("left", left))

            if len(crossings) == 2:
                p1 = key(crossings[0][1])
                p2 = key(crossings[1][1])
                segments.append((p1, p2))
            elif len(crossings) == 4:
                if case == 5:
                    segments.append((key(top), key(right)))
                    segments.append((key(bottom), key(left)))
                elif case == 10:
                    segments.append((key(top), key(left)))
                    segments.append((key(bottom), key(right)))

    adj = defaultdict(list)
    for p1, p2 in segments:
        adj[p1].append(p2)
        adj[p2].append(p1)

    paths = []
    visited_edges = set()

    def edge_id(a, b):
        return (a, b) if a < b else (b, a)

    for p1, p2 in segments:
        eid = edge_id(p1, p2)
        if eid in visited_edges:
            continue

        path = [p1, p2]
        visited_edges.add(eid)
        prev = p1
        curr = p2

        while True:
            neighbors = adj[curr]
            if not neighbors:
                break
            next_pt = None
            if len(neighbors) == 1:
                next_pt = neighbors[0]
            else:
                next_pt = neighbors[0] if neighbors[0] != prev else neighbors[1]

            if next_pt == path[0]:
                path.append(next_pt)
                break

            eid_next = edge_id(curr, next_pt)
            if eid_next in visited_edges:
                break

            visited_edges.add(eid_next)
            path.append(next_pt)
            prev, curr = curr, next_pt

        paths.append(path)

    if not paths:
        return []

    paths.sort(key=lambda p: len(p), reverse=True)
    return paths[0]


def rdp(points, epsilon):
    if len(points) < 3:
        return points

    def dist_point_line(pt, start, end):
        sx, sy = start
        ex, ey = end
        px, py = pt
        dx = ex - sx
        dy = ey - sy
        if dx == 0 and dy == 0:
            return math.hypot(px - sx, py - sy)
        t = ((px - sx) * dx + (py - sy) * dy) / (dx * dx + dy * dy)
        t = max(0.0, min(1.0, t))
        cx = sx + t * dx
        cy = sy + t * dy
        return math.hypot(px - cx, py - cy)

    max_dist = 0.0
    index = 0
    for i in range(1, len(points) - 1):
        d = dist_point_line(points[i], points[0], points[-1])
        if d > max_dist:
            index = i
            max_dist = d

    if max_dist > epsilon:
        left = rdp(points[: index + 1], epsilon)
        right = rdp(points[index:], epsilon)
        return left[:-1] + right

    return [points[0], points[-1]]


def save_svg(path_points, out_path, width, height):
    if not path_points:
        return
    d = [f"M {path_points[0][0]:.2f} {path_points[0][1]:.2f}"]
    for x, y in path_points[1:]:
        d.append(f"L {x:.2f} {y:.2f}")
    d.append("Z")
    path_data = " ".join(d)

    svg = f"""<svg width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\" xmlns=\"http://www.w3.org/2000/svg\">
  <path d=\"{path_data}\" fill=\"#000\" />
</svg>"""

    with open(out_path, "w") as f:
        f.write(svg)


def save_strokes_svg(strokes, out_path, width, height):
    palette = ["#ff4d4d", "#ffa94d", "#ffd43b", "#69db7c", "#4dabf7", "#9775fa"]
    paths = []
    for i, stroke in enumerate(strokes):
        pts = stroke["points"]
        if not pts:
            continue
        d = [f"M {pts[0][0]:.2f} {pts[0][1]:.2f}"]
        for x, y in pts[1:]:
            d.append(f"L {x:.2f} {y:.2f}")
        color = palette[i % len(palette)]
        paths.append(f'<path d="{" ".join(d)}" fill="none" stroke="{color}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>')
    svg = f"""<svg width="{width}" height="{height}" viewBox="0 0 {width} {height}" xmlns="http://www.w3.org/2000/svg">
  {"".join(paths)}
</svg>"""
    with open(out_path, "w") as f:
        f.write(svg)


def distance_transform(mask):
    w, h = mask.size
    data = list(mask.getdata())
    inf = 1e9
    dist = [0.0 if v > 0 else inf for v in data]

    diag = 1.41421356237

    for y in range(h):
        row = y * w
        for x in range(w):
            i = row + x
            d = dist[i]
            if x > 0:
                d = min(d, dist[i - 1] + 1)
            if y > 0:
                d = min(d, dist[i - w] + 1)
            if x > 0 and y > 0:
                d = min(d, dist[i - w - 1] + diag)
            if x + 1 < w and y > 0:
                d = min(d, dist[i - w + 1] + diag)
            dist[i] = d

    for y in range(h - 1, -1, -1):
        row = y * w
        for x in range(w - 1, -1, -1):
            i = row + x
            d = dist[i]
            if x + 1 < w:
                d = min(d, dist[i + 1] + 1)
            if y + 1 < h:
                d = min(d, dist[i + w] + 1)
            if x + 1 < w and y + 1 < h:
                d = min(d, dist[i + w + 1] + diag)
            if x > 0 and y + 1 < h:
                d = min(d, dist[i + w - 1] + diag)
            dist[i] = d

    return dist


def compute_sdf(mask):
    w, h = mask.size
    fg = mask
    bg = Image.new("L", (w, h), 255)
    bg.paste(0, mask=fg)

    dist_fg = distance_transform(fg)
    dist_bg = distance_transform(bg)

    sdf = [dist_fg[i] - dist_bg[i] for i in range(w * h)]
    max_abs = max(abs(v) for v in sdf) or 1.0

    sdf_16 = Image.new("I;16", (w, h))
    scaled = [int((v / max_abs * 0.5 + 0.5) * 65535) for v in sdf]
    sdf_16.putdata(scaled)

    sdf_8 = Image.new("L", (w, h))
    scaled_8 = [int((v / max_abs * 0.5 + 0.5) * 255) for v in sdf]
    sdf_8.putdata(scaled_8)

    return sdf_16, sdf_8, max_abs


def fourier_series(points, center, terms=12, samples=720):
    cx, cy = center
    bins = [0.0 for _ in range(samples)]
    counts = [0 for _ in range(samples)]

    for x, y in points:
        dx = x - cx
        dy = y - cy
        theta = math.atan2(dy, dx)
        if theta < 0:
            theta += 2 * math.pi
        r = math.hypot(dx, dy)
        idx = int((theta / (2 * math.pi)) * samples) % samples
        if r > bins[idx]:
            bins[idx] = r
        counts[idx] += 1

    for i in range(samples):
        if bins[i] == 0.0:
            # interpolate from nearest non-zero
            left = (i - 1) % samples
            right = (i + 1) % samples
            while bins[left] == 0.0 and left != i:
                left = (left - 1) % samples
            while bins[right] == 0.0 and right != i:
                right = (right + 1) % samples
            bins[i] = max(bins[left], bins[right])

    max_r = max(bins) or 1.0
    bins = [r / max_r for r in bins]

    coeffs = []
    a0 = sum(bins) / samples
    coeffs.append({"k": 0, "a": a0, "b": 0.0})

    for k in range(1, terms + 1):
        a = 0.0
        b = 0.0
        for i, r in enumerate(bins):
            theta = (i / samples) * 2 * math.pi
            a += r * math.cos(k * theta)
            b += r * math.sin(k * theta)
        a = (2 / samples) * a
        b = (2 / samples) * b
        coeffs.append({"k": k, "a": a, "b": b})

    return coeffs, max_r


def sample_fourier(coeffs, samples=360):
    pts = []
    for i in range(samples):
        theta = (i / samples) * 2 * math.pi
        r = 0.0
        for c in coeffs:
            k = c["k"]
            a = c["a"]
            b = c["b"]
            if k == 0:
                r += a
            else:
                r += a * math.cos(k * theta) + b * math.sin(k * theta)
        x = r * math.cos(theta)
        y = r * math.sin(theta)
        pts.append((x, y))
    return pts


def curvature_peaks(points, count=4):
    n = len(points)
    if n < 10:
        return list(range(n))

    curvatures = []
    for i in range(n):
        x0, y0 = points[(i - 1) % n]
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        v1x, v1y = x0 - x1, y0 - y1
        v2x, v2y = x2 - x1, y2 - y1
        l1 = math.hypot(v1x, v1y)
        l2 = math.hypot(v2x, v2y)
        if l1 == 0 or l2 == 0:
            curvatures.append(0.0)
            continue
        dot = (v1x * v2x + v1y * v2y) / (l1 * l2)
        dot = max(-1.0, min(1.0, dot))
        angle = math.acos(dot)
        curvatures.append(angle / (l1 + l2))

    # smooth
    window = 7
    smooth = []
    for i in range(n):
        total = 0.0
        for k in range(-window // 2, window // 2 + 1):
            total += curvatures[(i + k) % n]
        smooth.append(total / (window + 1))

    # pick peaks with separation
    order = sorted(range(n), key=lambda i: smooth[i], reverse=True)
    min_sep = max(5, n // (count * 2))
    peaks = []
    for idx in order:
        if all(min((idx - p) % n, (p - idx) % n) >= min_sep for p in peaks):
            peaks.append(idx)
        if len(peaks) >= count:
            break

    peaks.sort()
    return peaks


def split_strokes(points, count=4, epsilon=2.0):
    n = len(points)
    if n == 0:
        return []

    peaks = curvature_peaks(points, count=count)
    if len(peaks) < 2:
        return [{"points": points}]

    strokes = []
    for i in range(len(peaks)):
        start = peaks[i]
        end = peaks[(i + 1) % len(peaks)]
        if start < end:
            segment = points[start : end + 1]
        else:
            segment = points[start:] + points[: end + 1]
        if epsilon > 0:
            segment = rdp(segment, epsilon=epsilon)
        strokes.append({"points": segment, "start_idx": start, "end_idx": end})

    return strokes


def main():
    parser = argparse.ArgumentParser(description="Extract silhouette, SDF, and math model from logo icon.")
    parser.add_argument("--input", default="apps/macos/Talkie/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png")
    parser.add_argument("--outdir", default="assets/logo-primitives")
    parser.add_argument("--threshold-offset", type=float, default=0)
    parser.add_argument("--closing-size", type=int, default=5)
    parser.add_argument("--mask-mode", choices=["otsu", "bg"], default="otsu")
    parser.add_argument("--bg-step", type=int, default=8)
    parser.add_argument("--bg-downsample", type=int, default=256)
    parser.add_argument("--bg-threshold", type=float, default=None)
    parser.add_argument("--alpha-cutoff", type=int, default=10)
    parser.add_argument("--contour-size", type=int, default=512)
    parser.add_argument("--sdf-size", type=int, default=512)
    parser.add_argument("--fourier-terms", type=int, default=14)
    parser.add_argument("--fourier-samples", type=int, default=720)
    parser.add_argument("--rdp-epsilon", type=float, default=1.0)
    parser.add_argument("--skip-sdf", action="store_true")
    parser.add_argument("--skip-math", action="store_true")
    parser.add_argument("--stroke-count", type=int, default=4)
    parser.add_argument("--stroke-epsilon", type=float, default=2.0)
    parser.add_argument("--skip-strokes", action="store_true")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    img = load_image(args.input)
    mask, mask_info = make_mask(
        img,
        threshold_offset=args.threshold_offset,
        closing_size=args.closing_size,
        mode=args.mask_mode,
        bg_step=args.bg_step,
        bg_downsample=args.bg_downsample,
        alpha_cutoff=args.alpha_cutoff,
        bg_threshold=args.bg_threshold,
    )
    mask = largest_component(mask, exclude_border=True)

    mask_path = os.path.join(args.outdir, "bowtie_mask.png")
    mask.save(mask_path)

    silhouette = silhouette_from_mask(mask)
    silhouette_path = os.path.join(args.outdir, "bowtie_silhouette.png")
    silhouette.save(silhouette_path)

    # contour + svg
    contour_mask = mask.resize((args.contour_size, args.contour_size), Image.NEAREST)
    contour = marching_squares(contour_mask)
    scale = img.size[0] / args.contour_size
    contour_scaled_raw = [(x * scale, y * scale) for x, y in contour] if contour else []

    raw_svg_path = os.path.join(args.outdir, "bowtie_silhouette_raw.svg")
    save_svg(contour_scaled_raw, raw_svg_path, img.size[0], img.size[1])

    if contour:
        contour_simplified = rdp(contour, epsilon=args.rdp_epsilon) if args.rdp_epsilon > 0 else contour
        contour_scaled = [(x * scale, y * scale) for x, y in contour_simplified]
    else:
        contour_scaled = []

    svg_path = os.path.join(args.outdir, "bowtie_silhouette.svg")
    save_svg(contour_scaled, svg_path, img.size[0], img.size[1])

    if contour_scaled_raw and not args.skip_strokes:
        strokes = split_strokes(contour_scaled_raw, count=args.stroke_count, epsilon=args.stroke_epsilon)
        strokes_path = os.path.join(args.outdir, "bowtie_strokes.json")
        with open(strokes_path, "w") as f:
            json.dump({"strokes": strokes}, f, indent=2)

        strokes_svg_path = os.path.join(args.outdir, "bowtie_strokes.svg")
        save_strokes_svg(strokes, strokes_svg_path, img.size[0], img.size[1])

    sdf_max = None
    sdf_16_path = None
    sdf_8_path = None
    if not args.skip_sdf:
        # SDF
        sdf_mask = mask.resize((args.sdf_size, args.sdf_size), Image.NEAREST)
        sdf_16, sdf_8, sdf_max = compute_sdf(sdf_mask)
        sdf_16_path = os.path.join(args.outdir, "bowtie_sdf_16.png")
        sdf_8_path = os.path.join(args.outdir, "bowtie_sdf_8.png")
        sdf_16.save(sdf_16_path)
        sdf_8.save(sdf_8_path)

    # math model
    if contour_scaled_raw and not args.skip_math:
        xs = [p[0] for p in contour_scaled_raw]
        ys = [p[1] for p in contour_scaled_raw]
        cx = (min(xs) + max(xs)) / 2
        cy = (min(ys) + max(ys)) / 2
        coeffs, max_r = fourier_series(contour_scaled_raw, (cx, cy), args.fourier_terms, args.fourier_samples)

        model = {
            "center": [cx, cy],
            "scale": max_r,
            "terms": coeffs,
            "samples": args.fourier_samples,
            "source": os.path.basename(args.input),
            "threshold": mask_info.get("threshold"),
            "mask_mode": mask_info.get("mode"),
            "bg_color": mask_info.get("bg_color"),
            "threshold_offset": args.threshold_offset,
            "contour_size": args.contour_size,
        }
        model_path = os.path.join(args.outdir, "bowtie_math.json")
        with open(model_path, "w") as f:
            json.dump(model, f, indent=2)

        # preview SVG from Fourier
        preview_pts = sample_fourier(coeffs, samples=360)
        preview_scaled = [(cx + p[0] * max_r, cy + p[1] * max_r) for p in preview_pts]
        preview_svg_path = os.path.join(args.outdir, "bowtie_math.svg")
        save_svg(preview_scaled, preview_svg_path, img.size[0], img.size[1])

    meta_path = os.path.join(args.outdir, "bowtie_meta.json")
    with open(meta_path, "w") as f:
        json.dump(
            {
                "input": args.input,
                "threshold": mask_info.get("threshold"),
                "mask_mode": mask_info.get("mode"),
                "bg_color": mask_info.get("bg_color"),
                "threshold_offset": args.threshold_offset,
                "closing_size": args.closing_size,
                "sdf_size": args.sdf_size if not args.skip_sdf else None,
                "sdf_max_abs": sdf_max,
            },
            f,
            indent=2,
        )

    print("Generated:")
    print("-", silhouette_path)
    print("-", svg_path)
    print("-", raw_svg_path)
    print("-", mask_path)
    if not args.skip_strokes:
        print("-", os.path.join(args.outdir, "bowtie_strokes.svg"))
        print("-", os.path.join(args.outdir, "bowtie_strokes.json"))
    if sdf_16_path:
        print("-", sdf_16_path)
    if sdf_8_path:
        print("-", sdf_8_path)
    print("-", meta_path)


if __name__ == "__main__":
    main()
