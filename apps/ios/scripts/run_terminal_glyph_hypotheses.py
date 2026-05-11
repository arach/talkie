#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import re
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
REPLAY_SCRIPT = REPO_ROOT / "iOS" / "scripts" / "replay_terminal_capture.sh"
ANSI_FIXTURE = REPO_ROOT / "iOS" / "scripts" / "renderer-ansi-fixture.b64"
FOOTER_NEEDLE = b"\x1b[K\x1b[38;5;239m\x1b[48;5;237m"


def load_fixture() -> bytes:
    return base64.b64decode(ANSI_FIXTURE.read_text().strip())


def split_lines(raw: bytes) -> list[bytes]:
    return raw.split(b"\r\n")


def join_lines(lines: list[bytes]) -> bytes:
    return b"\r\n".join(lines)


def replace_robot_middle(line: bytes, cursor_col: int, clear_width: int, payload: str) -> bytes:
    pattern = re.compile(
        rb"^(.*\x1b\[" + str(cursor_col).encode() + rb"C)(.*?)(\x1b\[" + str(clear_width).encode() + rb"X.*)$",
        re.DOTALL,
    )
    match = pattern.match(line)
    if not match:
        raise ValueError(f"could not match robot line for cursor {cursor_col}")
    return match.group(1) + payload.encode("utf-8") + match.group(3)


def strip_background(line: bytes) -> bytes:
    return line.replace(b"\x1b[48;5;16m", b"").replace(b"\x1b[49m", b"")


def build_variants(raw: bytes) -> dict[str, bytes]:
    parts = split_lines(raw)
    footer_index = raw.find(FOOTER_NEEDLE)
    footer_only = raw[footer_index:] if footer_index >= 0 else raw

    card_only = join_lines(parts[:13])
    frame_no_robot = join_lines([parts[i] for i in range(13) if i not in {4, 5, 6}])
    robot_only = join_lines([parts[0], parts[4], parts[5], parts[6]])

    no_bg_parts = parts[:13]
    no_bg_parts[4] = strip_background(no_bg_parts[4])
    no_bg_parts[5] = strip_background(no_bg_parts[5])
    card_no_bg = join_lines(no_bg_parts)

    unicode_parts = parts[:13]
    unicode_parts[4] = replace_robot_middle(unicode_parts[4], 16, 16, "▐▛███▜▌")
    unicode_parts[5] = replace_robot_middle(unicode_parts[5], 15, 15, "▝▜█████▛▘")
    unicode_parts[6] = replace_robot_middle(unicode_parts[6], 17, 17, "▘▘ ▝▝")
    card_unicode_robot = join_lines(unicode_parts)

    footer_ascii_prompts = (
        footer_only
        .replace(b"_ \x1b[38;5;231m", b"> \x1b[38;5;231m")
        .replace(b"_\x1b[39m\x1b[1X\x1b[C", b"* \x1b[39m\x1b[1X\x1b[C")
        .replace(b"__\x1b[7m \x1b(B\x1b[m\x1b[K", b"> |\x1b[K")
    )

    full_ascii_prompts = (
        raw
        .replace(b"_ \x1b[38;5;231m", b"> \x1b[38;5;231m")
        .replace(b"_\x1b[39m\x1b[1X\x1b[C", b"* \x1b[39m\x1b[1X\x1b[C")
        .replace(b"__\x1b[7m \x1b(B\x1b[m\x1b[K", b"> |\x1b[K")
    )

    return {
        "01_full": raw,
        "02_card_only": card_only,
        "03_frame_no_robot": frame_no_robot,
        "04_robot_only": robot_only,
        "05_card_no_bg": card_no_bg,
        "06_card_unicode_robot": card_unicode_robot,
        "07_footer_only": footer_only,
        "08_footer_ascii_prompts": footer_ascii_prompts,
        "09_full_ascii_prompts": full_ascii_prompts,
    }


def render_variant(name: str, data: bytes, output_dir: Path) -> Path:
    bin_path = output_dir / f"{name}.bin"
    png_path = output_dir / f"{name}.png"
    bin_path.write_bytes(data)
    subprocess.run(
        [str(REPLAY_SCRIPT), "lab", str(bin_path), str(png_path)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return png_path


def build_contact_sheet(image_paths: list[Path], output_path: Path) -> None:
    try:
        from PIL import Image, ImageDraw
    except Exception:
        return

    images: list[Image.Image] = []
    labels: list[str] = []
    for path in image_paths:
        images.append(Image.open(path).convert("RGB"))
        labels.append(path.stem)

    width = max(image.width for image in images)
    label_height = 36
    total_height = sum(image.height + label_height for image in images)
    sheet = Image.new("RGB", (width, total_height), (15, 17, 21))
    draw = ImageDraw.Draw(sheet)

    y = 0
    for label, image in zip(labels, images):
        draw.rectangle((0, y, width, y + label_height), fill=(20, 24, 34))
        draw.text((16, y + 10), label, fill=(216, 221, 231))
        y += label_height
        sheet.paste(image, (0, y))
        y += image.height

    sheet.save(output_path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate local xterm glyph hypothesis snapshots.")
    parser.add_argument(
        "--output-dir",
        default="/tmp/talkie-glyph-hypotheses",
        help="Directory for generated .bin and .png files.",
    )
    args = parser.parse_args()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    raw = load_fixture()
    variants = build_variants(raw)
    image_paths = [render_variant(name, data, output_dir) for name, data in variants.items()]

    contact_sheet = output_dir / "contact-sheet.png"
    build_contact_sheet(image_paths, contact_sheet)

    print(output_dir)
    if contact_sheet.exists():
        print(contact_sheet)


if __name__ == "__main__":
    main()
