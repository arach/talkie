#!/usr/bin/env python3
import argparse
import json
import math
import os


def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def mul(a, s):
    return (a[0] * s, a[1] * s)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def length(v):
    return math.hypot(v[0], v[1])


def normalize(v):
    l = length(v)
    if l == 0:
        return (0.0, 0.0)
    return (v[0] / l, v[1] / l)


def bezier_q(ctrl, t):
    # cubic bezier
    mt = 1.0 - t
    mt2 = mt * mt
    t2 = t * t
    a = mt2 * mt
    b = 3 * mt2 * t
    c = 3 * mt * t2
    d = t2 * t
    x = a * ctrl[0][0] + b * ctrl[1][0] + c * ctrl[2][0] + d * ctrl[3][0]
    y = a * ctrl[0][1] + b * ctrl[1][1] + c * ctrl[2][1] + d * ctrl[3][1]
    return (x, y)


def bezier_q_prime(ctrl, t):
    mt = 1.0 - t
    a = -3 * mt * mt
    b = 3 * mt * mt - 6 * mt * t
    c = 6 * mt * t - 3 * t * t
    d = 3 * t * t
    x = a * ctrl[0][0] + b * ctrl[1][0] + c * ctrl[2][0] + d * ctrl[3][0]
    y = a * ctrl[0][1] + b * ctrl[1][1] + c * ctrl[2][1] + d * ctrl[3][1]
    return (x, y)


def bezier_q_prime2(ctrl, t):
    mt = 1.0 - t
    a = 6 * mt
    b = -12 * mt + 6 * t
    c = 6 * mt - 12 * t
    d = 6 * t
    x = a * ctrl[0][0] + b * ctrl[1][0] + c * ctrl[2][0] + d * ctrl[3][0]
    y = a * ctrl[0][1] + b * ctrl[1][1] + c * ctrl[2][1] + d * ctrl[3][1]
    return (x, y)


def chord_length_parameterize(points):
    u = [0.0]
    for i in range(1, len(points)):
        u.append(u[-1] + length(sub(points[i], points[i - 1])))
    total = u[-1]
    if total == 0:
        return [0.0 for _ in u]
    return [x / total for x in u]


def generate_bezier(points, u, left_tan, right_tan):
    p0 = points[0]
    p3 = points[-1]

    c = [[0.0, 0.0], [0.0, 0.0]]
    x = [0.0, 0.0]

    for i, ui in enumerate(u):
        b0 = (1 - ui) ** 3
        b1 = 3 * ui * (1 - ui) ** 2
        b2 = 3 * ui * ui * (1 - ui)
        b3 = ui ** 3

        a1 = mul(left_tan, b1)
        a2 = mul(right_tan, b2)

        c[0][0] += dot(a1, a1)
        c[0][1] += dot(a1, a2)
        c[1][0] += dot(a1, a2)
        c[1][1] += dot(a2, a2)

        tmp = sub(points[i], add(add(mul(p0, b0), mul(p0, 0.0)), add(mul(p3, b3), mul(p3, 0.0))))
        tmp = sub(tmp, add(mul(p0, b0), mul(p3, b3)))
        x[0] += dot(a1, tmp)
        x[1] += dot(a2, tmp)

    det_c0_c1 = c[0][0] * c[1][1] - c[1][0] * c[0][1]
    alpha_l = 0.0
    alpha_r = 0.0
    if abs(det_c0_c1) > 1e-6:
        alpha_l = (x[0] * c[1][1] - x[1] * c[0][1]) / det_c0_c1
        alpha_r = (c[0][0] * x[1] - c[1][0] * x[0]) / det_c0_c1

    seg_length = length(sub(p3, p0))
    epsilon = 1e-6
    if alpha_l < epsilon or alpha_r < epsilon:
        alpha_l = alpha_r = seg_length / 3.0

    p1 = add(p0, mul(left_tan, alpha_l))
    p2 = add(p3, mul(right_tan, alpha_r))
    return [p0, p1, p2, p3]


def reparameterize(points, u, bezier):
    return [newton_raphson_root_find(bezier, p, u_i) for p, u_i in zip(points, u)]


def newton_raphson_root_find(bezier, point, u):
    q = bezier_q(bezier, u)
    q1 = bezier_q_prime(bezier, u)
    q2 = bezier_q_prime2(bezier, u)
    numerator = dot(sub(q, point), q1)
    denominator = dot(q1, q1) + dot(sub(q, point), q2)
    if denominator == 0.0:
        return u
    return u - numerator / denominator


def compute_max_error(points, bezier, u):
    max_dist = 0.0
    split = len(points) // 2
    for i, (p, ui) in enumerate(zip(points, u)):
        q = bezier_q(bezier, ui)
        d = length(sub(q, p))
        if d > max_dist:
            max_dist = d
            split = i
    return max_dist, split


def fit_cubic(points, left_tan, right_tan, error):
    u = chord_length_parameterize(points)
    bezier = generate_bezier(points, u, left_tan, right_tan)
    max_error, split = compute_max_error(points, bezier, u)

    if max_error < error:
        return [bezier]

    if max_error < error * error:
        for _ in range(5):
            u = reparameterize(points, u, bezier)
            bezier = generate_bezier(points, u, left_tan, right_tan)
            max_error, split = compute_max_error(points, bezier, u)
            if max_error < error:
                return [bezier]

    center_tan = normalize(sub(points[split - 1], points[split + 1]))
    left = fit_cubic(points[: split + 1], left_tan, center_tan, error)
    right = fit_cubic(points[split:], mul(center_tan, -1.0), right_tan, error)
    return left + right


def fit_curve(points, error=4.0):
    if len(points) < 2:
        return []
    left_tan = normalize(sub(points[1], points[0]))
    right_tan = normalize(sub(points[-2], points[-1]))
    return fit_cubic(points, left_tan, right_tan, error)


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


def save_svg(segments, out_path, width, height, stroke="#111", stroke_width=3, bg="#f5f5f5"):
    path_data = []
    for segs in segments:
        if not segs:
            continue
        p0 = segs[0][0]
        path_data.append(f"M {p0[0]:.2f} {p0[1]:.2f}")
        for seg in segs:
            _, c1, c2, p3 = seg
            path_data.append(
                f"C {c1[0]:.2f} {c1[1]:.2f} {c2[0]:.2f} {c2[1]:.2f} {p3[0]:.2f} {p3[1]:.2f}"
            )

    svg = f"""<svg width=\"{width}\" height=\"{height}\" viewBox=\"0 0 {width} {height}\" xmlns=\"http://www.w3.org/2000/svg\">
  <rect width=\"100%\" height=\"100%\" fill=\"{bg}\" />
  <path d=\"{' '.join(path_data)}\" fill=\"none\" stroke=\"{stroke}\" stroke-width=\"{stroke_width}\" stroke-linecap=\"round\" stroke-linejoin=\"round\" />
</svg>"""
    with open(out_path, "w") as f:
        f.write(svg)


def main():
    parser = argparse.ArgumentParser(description="Fit cubic Beziers to bowtie strokes.")
    parser.add_argument("--input", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=1024)
    parser.add_argument("--error", type=float, default=4.0)
    parser.add_argument("--stroke-errors", default=None)
    parser.add_argument("--pre-rdp", default=None)
    parser.add_argument("--warp-right", type=float, default=1.0)
    parser.add_argument("--warp-right-x", type=float, default=680.0)
    parser.add_argument("--warp-right-y", type=float, default=512.0)
    parser.add_argument("--separate-right", type=float, default=0.0)
    parser.add_argument("--separate-right-x", type=float, default=680.0)
    parser.add_argument("--separate-top-index", type=int, default=1)
    parser.add_argument("--separate-bottom-index", type=int, default=0)
    parser.add_argument("--raise-top-right", type=float, default=0.0)
    parser.add_argument("--raise-top-right-x", type=float, default=700.0)
    parser.add_argument("--raise-top-span", type=float, default=120.0)
    parser.add_argument("--raise-top-index", type=int, default=1)
    parser.add_argument("--pin-right-tip", action="store_true")
    parser.add_argument("--pin-right-tip-dx", type=float, default=0.0)
    parser.add_argument("--pin-right-tip-dy", type=float, default=0.0)
    parser.add_argument("--name", default="bowtie_bezier")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    data = json.load(open(args.input))
    strokes = data.get("strokes", [])

    stroke_errors = {}
    if args.stroke_errors:
        for part in args.stroke_errors.split(","):
            if not part.strip():
                continue
            idx, val = part.split(":")
            stroke_errors[int(idx)] = float(val)

    rdp_errors = {}
    if args.pre_rdp:
        for part in args.pre_rdp.split(","):
            if not part.strip():
                continue
            idx, val = part.split(":")
            rdp_errors[int(idx)] = float(val)

    processed = []
    for idx, stroke in enumerate(strokes):
        points = stroke.get("points", stroke)
        if args.warp_right != 1.0:
            warped = []
            for x, y in points:
                if x >= args.warp_right_x:
                    y = args.warp_right_y + (y - args.warp_right_y) * args.warp_right
                warped.append((x, y))
            points = warped
        if idx in rdp_errors:
            points = rdp(points, epsilon=rdp_errors[idx])
        processed.append(points)

    if args.separate_right > 0.0:
        top_idx = args.separate_top_index
        bottom_idx = args.separate_bottom_index
        if 0 <= top_idx < len(processed) and 0 <= bottom_idx < len(processed):
            top_pts = processed[top_idx]
            bot_pts = processed[bottom_idx]
            if top_pts and bot_pts:
                bot_sorted = sorted(bot_pts, key=lambda p: p[0])

                def closest_y(points_sorted, target_x):
                    best = points_sorted[0]
                    best_d = abs(best[0] - target_x)
                    for p in points_sorted[1:]:
                        d = abs(p[0] - target_x)
                        if d < best_d:
                            best = p
                            best_d = d
                    return best[1]

                new_top = []
                for x, y in top_pts:
                    if x >= args.separate_right_x:
                        yb = closest_y(bot_sorted, x)
                        y = min(y, yb - args.separate_right)
                    new_top.append((x, y))

                top_sorted = sorted(new_top, key=lambda p: p[0])

                new_bot = []
                for x, y in bot_pts:
                    if x >= args.separate_right_x:
                        yt = closest_y(top_sorted, x)
                        y = max(y, yt + args.separate_right)
                    new_bot.append((x, y))

                processed[top_idx] = new_top
                processed[bottom_idx] = new_bot

    if args.raise_top_right > 0.0:
        idx = args.raise_top_index
        if 0 <= idx < len(processed):
            pts = processed[idx]
            if pts:
                raised = []
                span = max(1.0, args.raise_top_span)
                for x, y in pts:
                    if x >= args.raise_top_right_x:
                        t = min(1.0, max(0.0, (x - args.raise_top_right_x) / span))
                        # smoothstep
                        t = t * t * (3 - 2 * t)
                        y = y - args.raise_top_right * t
                    raised.append((x, y))
                processed[idx] = raised

    if args.pin_right_tip:
        top_idx = args.raise_top_index
        bottom_idx = args.separate_bottom_index
        if 0 <= top_idx < len(processed) and 0 <= bottom_idx < len(processed):
            top_pts = processed[top_idx]
            bot_pts = processed[bottom_idx]
            if top_pts and bot_pts:
                bottom_tip = bot_pts[-1]
                pin_target = (bottom_tip[0] + args.pin_right_tip_dx, bottom_tip[1] + args.pin_right_tip_dy)
                # pin whichever end of the top stroke is closest to the bottom tip
                d0 = math.hypot(top_pts[0][0] - bottom_tip[0], top_pts[0][1] - bottom_tip[1])
                d1 = math.hypot(top_pts[-1][0] - bottom_tip[0], top_pts[-1][1] - bottom_tip[1])
                if d0 <= d1:
                    top_pts[0] = pin_target
                else:
                    top_pts[-1] = pin_target
                processed[top_idx] = top_pts

    bezier_strokes = []
    for idx, points in enumerate(processed):
        err = stroke_errors.get(idx, args.error)
        segs = fit_curve(points, error=err)
        bezier_strokes.append(segs)

    svg_path = os.path.join(args.outdir, f"{args.name}.svg")
    save_svg(bezier_strokes, svg_path, args.width, args.height)

    out_json = os.path.join(args.outdir, f"{args.name}.json")
    serial = []
    for segs in bezier_strokes:
        s = []
        for seg in segs:
            p0, c1, c2, p3 = seg
            s.append({"p0": p0, "c1": c1, "c2": c2, "p3": p3})
        serial.append(s)
    with open(out_json, "w") as f:
        json.dump({"strokes": serial, "error": args.error}, f, indent=2)

    print("Generated:")
    print("-", svg_path)
    print("-", out_json)


if __name__ == "__main__":
    main()
