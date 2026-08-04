#!/usr/bin/env python3
"""Generate Talkie's theme-responsive app-icon family.

Porcelain remains the primary icon across iOS, watchOS, and macOS. iOS also
gets alternate icons whose signal glyph follows the selected in-app theme.
The logo geometry and porcelain field stay fixed, so the family remains
recognizably Talkie while the glyph becomes a truthful theme signal.
"""

from pathlib import Path
import shutil

from PIL import Image, ImageDraw, ImageFont


REPOSITORY = Path(__file__).resolve().parents[1]
FONT = REPOSITORY / "apps/macos/TalkieKit/Sources/TalkieKit/Resources/Fonts/JetBrainsMono-Bold.ttf"
PRIMARY_CATALOGS = (
    REPOSITORY / "apps/ios/Talkie iOS/Resources/Assets.xcassets/AppIcon.appiconset",
    REPOSITORY / "apps/ios/TalkieWatch Watch App/Assets.xcassets/AppIcon.appiconset",
    REPOSITORY / "apps/macos/Talkie/Assets.xcassets/AppIcon.appiconset",
)
IOS_PRIMARY_CATALOG = PRIMARY_CATALOGS[0]

SIZE = 1024
RENDER_SCALE = 4
CANVAS = SIZE * RENDER_SCALE
FIELD_TOP = (29, 48, 75)
FIELD_BOTTOM = (11, 19, 32)
THEME_GLYPHS = {
    "Porcelain": (120, 166, 255, 255),
    "Scope": (232, 154, 60, 255),
    "Mineral": (223, 137, 85, 255),
    "Midnight": (94, 106, 210, 255),
    "Tactical": (255, 136, 0, 255),
    "Ghost": (99, 102, 241, 255),
    "Lift": (99, 102, 241, 255),
    "Graphite": (250, 250, 250, 255),
    "Carbon": (61, 224, 138, 255),
    "Ember": (217, 140, 43, 255),
}


def font_for_target_height(target_height: int) -> ImageFont.FreeTypeFont:
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    low, high = 1, CANVAS
    while low < high:
        midpoint = (low + high + 1) // 2
        candidate = ImageFont.truetype(str(FONT), midpoint)
        bounds = probe.textbbox((0, 0), "t", font=candidate)
        if bounds[3] - bounds[1] <= target_height:
            low = midpoint
        else:
            high = midpoint - 1
    return ImageFont.truetype(str(FONT), low)


def render_master(glyph: tuple[int, int, int, int]) -> Image.Image:
    gradient = Image.linear_gradient("L").resize((CANVAS, CANVAS), Image.Resampling.BICUBIC)
    top = Image.new("RGB", (CANVAS, CANVAS), FIELD_TOP)
    bottom = Image.new("RGB", (CANVAS, CANVAS), FIELD_BOTTOM)
    image = Image.composite(bottom, top, gradient).convert("RGBA")

    draw = ImageDraw.Draw(image)
    font = font_for_target_height(round(CANVAS * 0.62))
    bounds = draw.textbbox((0, 0), "t", font=font)
    width = bounds[2] - bounds[0]
    height = bounds[3] - bounds[1]
    origin = (
        (CANVAS - width) / 2 - bounds[0],
        (CANVAS - height) / 2 - bounds[1],
    )
    draw.text(origin, "t", font=font, fill=glyph)
    return image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).convert("RGB")


def update_catalog(catalog: Path, master: Image.Image) -> None:
    for destination in sorted(catalog.glob("*.png")):
        with Image.open(destination) as existing:
            output_size = existing.size
        master.resize(output_size, Image.Resampling.LANCZOS).save(destination)
        print(f"{destination.relative_to(REPOSITORY)} ({output_size[0]}px)")


def main() -> None:
    if not FONT.is_file():
        raise SystemExit(f"Icon font not found: {FONT}")

    porcelain = render_master(THEME_GLYPHS["Porcelain"])
    for catalog in PRIMARY_CATALOGS:
        update_catalog(catalog, porcelain)

    for theme_name, glyph in THEME_GLYPHS.items():
        if theme_name == "Porcelain":
            continue
        catalog = IOS_PRIMARY_CATALOG.with_name(f"AppIcon{theme_name}.appiconset")
        shutil.copytree(IOS_PRIMARY_CATALOG, catalog, dirs_exist_ok=True)
        update_catalog(catalog, render_master(glyph))


if __name__ == "__main__":
    main()
