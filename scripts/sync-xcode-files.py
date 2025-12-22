#!/usr/bin/env python3
"""
sync-xcode-files.py - Keep Swift files in sync with Xcode project

Scans for .swift files not in project.pbxproj and adds them to the correct
PBXGroup, preserving folder structure. Creates backup before any changes.

Usage:
    ./sync-xcode-files.py              # Add missing files to project
    ./sync-xcode-files.py --check      # List missing files (no changes)
    ./sync-xcode-files.py --dry-run    # Simulate add (no changes)
    ./sync-xcode-files.py --diff       # Show unified diff (no changes)

What it does:
    1. Finds .swift files on disk not in project.pbxproj
    2. Parses PBXGroup hierarchy to find correct parent group
    3. Adds PBXFileReference, PBXBuildFile, and Sources entries
    4. Adds file to parent group's children array

Skips: build/, .build/, DerivedData/, Packages/, .swiftpm/, xcshareddata/
"""

import os
import re
import sys
import uuid
import shutil
from pathlib import Path
from typing import Dict, List, Optional, Tuple

PROJECT_DIR = Path("/Users/arach/dev/talkie/macOS/Talkie")
PBXPROJ = PROJECT_DIR / "Talkie.xcodeproj" / "project.pbxproj"

# Directories to skip
SKIP_DIRS = {'build', '.build', 'DerivedData', 'Packages', '.swiftpm', 'xcshareddata'}


def generate_uuid():
    """Generate a 24-char hex UUID like Xcode does."""
    return uuid.uuid4().hex[:24].upper()


def find_swift_files():
    """Find all .swift files in project, excluding build dirs."""
    swift_files = []
    for root, dirs, files in os.walk(PROJECT_DIR):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.endswith('.xcodeproj')]
        for f in files:
            if f.endswith('.swift'):
                swift_files.append(Path(root) / f)
    return sorted(swift_files)


def get_files_in_project(content):
    """Get set of filenames already in project."""
    pattern = r'/\* ([^*]+\.swift) \*/ = \{isa = PBXFileReference'
    return set(re.findall(pattern, content))


def parse_groups(content: str) -> Dict[str, dict]:
    """Parse all PBXGroup entries and return a dict of id -> group info."""
    groups = {}

    # Find each group - with or without /* Name */ comment
    # Pattern 1: ID /* Name */ = { isa = PBXGroup;
    # Pattern 2: ID = { isa = PBXGroup; (main group has no name)
    group_header = r'(\w{24})(?:\s*/\*\s*([^*]*)\s*\*/)?\s*=\s*\{\s*isa = PBXGroup;'

    for match in re.finditer(group_header, content):
        group_id = match.group(1)
        name = match.group(2).strip() if match.group(2) else ""

        # Find the full block by matching braces
        block_start = match.start()
        brace_count = 0
        block_end = block_start
        for i, char in enumerate(content[block_start:], block_start):
            if char == '{':
                brace_count += 1
            elif char == '}':
                brace_count -= 1
                if brace_count == 0:
                    block_end = i + 1
                    break

        block = content[block_start:block_end]

        # Extract children
        children_match = re.search(r'children = \(([^)]*)\)', block)
        children = []
        if children_match:
            children = re.findall(r'(\w{24})', children_match.group(1))

        # Extract path (may not exist - use name as default)
        path_match = re.search(r'path = ([^;]+);', block)
        path = path_match.group(1).strip().strip('"') if path_match else name

        groups[group_id] = {
            'name': name,
            'path': path,
            'children': children,
        }

    return groups


def find_group_by_path(content: str, groups: Dict, path_parts: List[str]) -> Optional[str]:
    """Find a group ID by traversing the path. Returns None if not found."""
    if not path_parts:
        return None

    # Find root groups (direct children of main project group)
    # Look for the main project group that contains Views, Models, etc.
    main_group_pattern = r'mainGroup = (\w{24})'
    main_match = re.search(main_group_pattern, content)
    if not main_match:
        return None

    current_group_id = main_match.group(1)

    for part in path_parts:
        found = False
        if current_group_id in groups:
            for child_id in groups[current_group_id]['children']:
                if child_id in groups and groups[child_id]['path'] == part:
                    current_group_id = child_id
                    found = True
                    break
        if not found:
            return None

    return current_group_id


def add_child_to_group(content: str, group_id: str, child_id: str, child_name: str) -> str:
    """Add a child reference to a group's children array."""
    # Find the group and its children section
    group_pattern = rf'({group_id} /\* [^*]* \*/ = \{{\s*isa = PBXGroup;\s*children = \()([^)]*)\)'

    def replacer(match):
        prefix = match.group(1)
        children = match.group(2)
        new_child = f'\n\t\t\t\t{child_id} /* {child_name} */,'
        return f'{prefix}{new_child}{children})'

    return re.sub(group_pattern, replacer, content, count=1)


def create_group(content: str, parent_group_id: str, group_name: str) -> Tuple[str, str]:
    """Create a new PBXGroup and add it to parent. Returns (new_content, new_group_id)."""
    new_group_id = generate_uuid()

    # Create group entry
    group_entry = f'''\t\t{new_group_id} /* {group_name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t);
\t\t\tpath = {group_name};
\t\t\tsourceTree = "<group>";
\t\t}};
'''

    # Insert in PBXGroup section
    group_marker = '/* Begin PBXGroup section */'
    idx = content.find(group_marker)
    if idx != -1:
        insert_pos = idx + len(group_marker) + 1
        content = content[:insert_pos] + group_entry + content[insert_pos:]

    # Add to parent group's children
    content = add_child_to_group(content, parent_group_id, new_group_id, group_name)

    return content, new_group_id


def ensure_group_path(content: str, path_parts: List[str]) -> Tuple[str, str]:
    """Ensure all groups in path exist, creating as needed. Returns (content, leaf_group_id)."""
    groups = parse_groups(content)

    # Find main group
    main_group_pattern = r'mainGroup = (\w{24})'
    main_match = re.search(main_group_pattern, content)
    if not main_match:
        raise ValueError("Could not find mainGroup")

    current_group_id = main_match.group(1)

    for i, part in enumerate(path_parts):
        # Look for this part in current group's children
        found_id = None
        groups = parse_groups(content)  # Re-parse after modifications

        if current_group_id in groups:
            for child_id in groups[current_group_id]['children']:
                if child_id in groups and groups[child_id]['path'] == part:
                    found_id = child_id
                    break

        if found_id:
            current_group_id = found_id
        else:
            # Create the group
            content, new_id = create_group(content, current_group_id, part)
            current_group_id = new_id

    return content, current_group_id


def add_file_to_project(content: str, filepath: Path) -> str:
    """Add a Swift file to the project.pbxproj with proper group handling."""
    filename = filepath.name
    rel_path = filepath.relative_to(PROJECT_DIR)
    path_parts = list(rel_path.parts[:-1])  # Directory parts without filename

    file_ref_id = generate_uuid()
    build_file_id = generate_uuid()

    # 1. Ensure parent group exists and get its ID
    if path_parts:
        content, parent_group_id = ensure_group_path(content, path_parts)
    else:
        # File at root - find main group
        main_match = re.search(r'mainGroup = (\w{24})', content)
        parent_group_id = main_match.group(1) if main_match else None

    # 2. Add PBXFileReference
    file_ref_entry = f'\t\t{file_ref_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n'

    file_ref_marker = '/* Begin PBXFileReference section */'
    idx = content.find(file_ref_marker)
    if idx != -1:
        insert_pos = idx + len(file_ref_marker) + 1
        content = content[:insert_pos] + file_ref_entry + content[insert_pos:]

    # 3. Add file to parent group's children
    if parent_group_id:
        content = add_child_to_group(content, parent_group_id, file_ref_id, filename)

    # 4. Add PBXBuildFile
    build_file_entry = f'\t\t{build_file_id} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {filename} */; }};\n'

    build_file_marker = '/* Begin PBXBuildFile section */'
    idx = content.find(build_file_marker)
    if idx != -1:
        insert_pos = idx + len(build_file_marker) + 1
        content = content[:insert_pos] + build_file_entry + content[insert_pos:]

    # 5. Add to PBXSourcesBuildPhase
    sources_pattern = r'(/\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;[^}]*files = \()([^)]*)\)'

    def sources_replacer(match):
        prefix = match.group(1)
        files = match.group(2)
        new_entry = f'\n\t\t\t\t{build_file_id} /* {filename} in Sources */,'
        return f'{prefix}{new_entry}{files})'

    content = re.sub(sources_pattern, sources_replacer, content, count=1)

    return content


def main():
    import difflib

    check_only = '--check' in sys.argv
    dry_run = '--dry-run' in sys.argv
    show_diff = '--diff' in sys.argv

    if not PBXPROJ.exists():
        print(f"Error: {PBXPROJ} not found")
        sys.exit(1)

    print(f"Scanning {PROJECT_DIR}...")
    print()

    with open(PBXPROJ, 'r', encoding='utf-8') as f:
        original_content = f.read()

    content = original_content
    existing_files = get_files_in_project(content)
    all_swift_files = find_swift_files()

    missing = []
    for filepath in all_swift_files:
        if filepath.name not in existing_files:
            missing.append(filepath)

    if not missing:
        print("✓ All files in sync")
        return

    print(f"Missing from project ({len(missing)}):")
    print()

    for f in missing:
        rel = f.relative_to(PROJECT_DIR)
        print(f"  {rel}")
    print()

    if check_only:
        print("Run without --check to add them")
        return

    # Process all files
    for filepath in missing:
        content = add_file_to_project(content, filepath)

    if show_diff:
        # Show unified diff
        orig_lines = original_content.splitlines(keepends=True)
        new_lines = content.splitlines(keepends=True)
        diff = difflib.unified_diff(orig_lines, new_lines,
                                     fromfile='project.pbxproj (before)',
                                     tofile='project.pbxproj (after)')
        diff_text = ''.join(diff)
        if diff_text:
            print("Changes:")
            print(diff_text[:3000])  # Truncate for readability
            if len(diff_text) > 3000:
                print(f"  ... ({len(diff_text) - 3000} more characters)")
        return

    if dry_run:
        print("Dry run - no changes made")
        print(f"Would add {len(missing)} file(s) to project")
        return

    # Actually write changes
    backup_path = str(PBXPROJ) + '.backup'
    shutil.copy(PBXPROJ, backup_path)

    with open(PBXPROJ, 'w', encoding='utf-8') as f:
        f.write(content)

    print(f"✓ Added {len(missing)} file(s)")
    print(f"  Backup: {backup_path}")


if __name__ == '__main__':
    main()
