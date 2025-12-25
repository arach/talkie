#!/usr/bin/env python3
"""
Automatically fix hardcoded colors for light mode compatibility.
Replaces hardcoded Color.white/black.opacity() with Theme.current semantic tokens.
"""

import re
import sys
from pathlib import Path
from typing import Dict, List, Tuple

# Mapping of opacity values to semantic tokens
OPACITY_MAP = {
    # Very subtle backgrounds
    "0.02": "TalkieTheme.surface",
    "0.03": "TalkieTheme.surface",
    "0.04": "TalkieTheme.hover",
    "0.05": "TalkieTheme.hover",

    # Subtle borders/dividers
    "0.06": "TalkieTheme.borderSubtle",
    "0.08": "TalkieTheme.divider",
    "0.1": "TalkieTheme.divider",
    "0.12": "TalkieTheme.divider",

    # Medium elements
    "0.15": "TalkieTheme.surfaceCard",
    "0.2": "TalkieTheme.border",
    "0.25": "TalkieTheme.textMuted",

    # Text colors
    "0.3": "TalkieTheme.textMuted",
    "0.4": "TalkieTheme.textTertiary",
    "0.5": "TalkieTheme.textTertiary",
    "0.6": "TalkieTheme.textSecondary",
    "0.7": "TalkieTheme.textSecondary",
    "0.8": "TalkieTheme.textSecondary",
    "0.9": "TalkieTheme.textPrimary",
}

# Special case replacements
SPECIAL_CASES = {
    ".foregroundColor(.primary)": "Theme.current.foreground",
    ".foregroundColor(.secondary)": "Theme.current.foregroundSecondary",
}

def find_opacity_match(opacity_str: str) -> str:
    """Find the best semantic token match for a given opacity value."""
    try:
        opacity = float(opacity_str)

        # Find closest match
        closest = min(OPACITY_MAP.keys(), key=lambda x: abs(float(x) - opacity))
        if abs(float(closest) - opacity) <= 0.02:  # Within 2% tolerance
            return OPACITY_MAP[closest]
    except ValueError:
        pass

    # Default fallback
    return f"TalkieTheme.hover  // TODO: Review opacity {opacity_str}"

def fix_color_opacity(content: str) -> Tuple[str, int]:
    """Fix Color.white/black.opacity() patterns."""
    changes = 0

    # Pattern: Color.white.opacity(X) or Color.black.opacity(X)
    pattern = r'Color\.(white|black)\.opacity\(([\d.]+)\)'

    def replace_opacity(match):
        nonlocal changes
        color = match.group(1)  # white or black
        opacity = match.group(2)  # numeric value

        replacement = find_opacity_match(opacity)
        changes += 1
        return replacement

    content = re.sub(pattern, replace_opacity, content)
    return content, changes

def fix_foreground_colors(content: str) -> Tuple[str, int]:
    """Fix .foregroundColor(.primary/.secondary) patterns."""
    changes = 0

    for old, new in SPECIAL_CASES.items():
        count = content.count(old)
        if count > 0:
            content = content.replace(old, f".foregroundColor({new})")
            changes += count

    return content, changes

def fix_color_literals(content: str) -> Tuple[str, int]:
    """Fix Color(white:) and Color(red:green:blue:) literals."""
    changes = 0

    # Pattern: Color(white: 0.XX, alpha: 1.0) or Color(white: 0.XX)
    pattern = r'Color\(white:\s*([\d.]+)(?:,\s*alpha:\s*[\d.]+)?\)'

    def replace_literal(match):
        nonlocal changes
        white_val = match.group(1)
        replacement = find_opacity_match(white_val)
        changes += 1
        return replacement

    content = re.sub(pattern, replace_literal, content)
    return content, changes

def process_file(filepath: Path, dry_run: bool = False) -> Tuple[int, bool]:
    """Process a single Swift file."""
    try:
        content = filepath.read_text()
        original_content = content

        total_changes = 0

        # Apply all fixes
        content, changes = fix_color_opacity(content)
        total_changes += changes

        content, changes = fix_foreground_colors(content)
        total_changes += changes

        content, changes = fix_color_literals(content)
        total_changes += changes

        if total_changes > 0:
            if not dry_run:
                filepath.write_text(content)
            return total_changes, True

        return 0, False
    except Exception as e:
        print(f"❌ Error processing {filepath}: {e}", file=sys.stderr)
        return 0, False

def main():
    import argparse

    parser = argparse.ArgumentParser(description="Fix hardcoded colors for light mode")
    parser.add_argument("--dry-run", action="store_true", help="Show what would change without modifying files")
    parser.add_argument("--views-only", action="store_true", help="Only process Views/ directory")
    parser.add_argument("paths", nargs="*", help="Specific paths to process (default: macOS/Talkie/Views)")
    args = parser.parse_args()

    # Determine paths to process
    base_dir = Path("/Users/arach/dev/talkie-dashboard")

    if args.paths:
        paths = [Path(p) for p in args.paths]
    elif args.views_only:
        paths = [base_dir / "macOS/Talkie/Views"]
    else:
        paths = [base_dir / "macOS/Talkie/Views"]

    # Collect all Swift files
    swift_files = []
    for path in paths:
        if path.is_file() and path.suffix == ".swift":
            swift_files.append(path)
        elif path.is_dir():
            swift_files.extend(path.rglob("*.swift"))

    print(f"🔍 Processing {len(swift_files)} Swift files...")
    if args.dry_run:
        print("⚠️  DRY RUN - no files will be modified")
    print()

    total_files_changed = 0
    total_changes = 0

    for filepath in sorted(swift_files):
        changes, modified = process_file(filepath, dry_run=args.dry_run)
        if modified:
            total_files_changed += 1
            total_changes += changes
            rel_path = filepath.relative_to(base_dir)
            status = "📝" if args.dry_run else "✅"
            print(f"{status} {rel_path}: {changes} changes")

    print()
    print(f"{'📊 Summary (dry run):' if args.dry_run else '✅ Complete:'}")
    print(f"   Files modified: {total_files_changed}")
    print(f"   Total changes: {total_changes}")

    if args.dry_run and total_changes > 0:
        print()
        print("Run without --dry-run to apply changes")

if __name__ == "__main__":
    main()
