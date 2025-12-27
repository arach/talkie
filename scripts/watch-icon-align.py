#!/usr/bin/env -S uv run
"""
Watch Icon Alignment Tool
Usage: uv run watch-icon-align.py [center_x] [center_y] [dot_radius]

Defaults: center_x=513, center_y=330, dot_radius=35
"""

import subprocess
import sys

SOURCE = "/Users/arach/Downloads/arach_httpss.mj.runOhVwdzwHKE8_just_a_square_app_icon_on_a_fl_4917f25c-67b1-4dcf-8b99-39963e6dafa9_0.png"
OUTPUT = "/tmp/watch_crosshairs.png"
SIZE = 390
HALF = SIZE // 2

def generate(center_x=513, center_y=330, dot_radius=35):
    crop_x = center_x - HALF
    crop_y = center_y - HALF

    # Build ImageMagick command
    cmd = [
        "magick", SOURCE,
        "-crop", f"{SIZE}x{SIZE}+{crop_x}+{crop_y}", "+repage",
        "-stroke", "yellow", "-strokewidth", "1",
        # Center crosshairs
        "-draw", f"line {HALF},0 {HALF},{SIZE}",
        "-draw", f"line 0,{HALF} {SIZE},{HALF}",
        # Boundary box
        "-draw", f"line {HALF - dot_radius},0 {HALF - dot_radius},{SIZE}",
        "-draw", f"line {HALF + dot_radius},0 {HALF + dot_radius},{SIZE}",
        "-draw", f"line 0,{HALF - dot_radius} {SIZE},{HALF - dot_radius}",
        "-draw", f"line 0,{HALF + dot_radius} {SIZE},{HALF + dot_radius}",
        OUTPUT
    ]

    subprocess.run(cmd, check=True)
    print(f"Generated: {OUTPUT}")
    print(f"Settings: X={center_x}, Y={center_y}, radius={dot_radius}")

    # Open in Preview
    subprocess.run(["open", OUTPUT])

if __name__ == "__main__":
    x = int(sys.argv[1]) if len(sys.argv) > 1 else 513
    y = int(sys.argv[2]) if len(sys.argv) > 2 else 330
    r = int(sys.argv[3]) if len(sys.argv) > 3 else 35

    generate(x, y, r)
