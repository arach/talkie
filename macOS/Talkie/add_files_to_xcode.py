#!/usr/bin/env python3
"""
Add GRDB data layer files to Xcode project programmatically
"""

import re
import uuid
import os

# Files to add (organized by group)
FILES_TO_ADD = {
    'Data/Models': [
        'Data/Models/VoiceMemo.swift',
        'Data/Models/TranscriptVersion.swift',
        'Data/Models/WorkflowRun.swift',
        'Data/Models/MemoSource.swift',
    ],
    'Data/Database': [
        'Data/Database/DatabaseManager.swift',
        'Data/Database/MemoRepository.swift',
        'Data/Database/GRDBRepository.swift',
        'Data/Database/CoreDataMigration.swift',
    ],
    'Data/ViewModels': [
        'Data/ViewModels/MemosViewModel.swift',
    ],
    'Data/Sync': [
        'Data/Sync/CloudKitSyncEngine.swift',
    ],
    'Views/Memos': [
        'Views/Memos/AllMemosView2.swift',
    ],
    'Views/Migration': [
        'Views/Migration/MigrationView.swift',
    ],
    'App': [
        'App/DataLayerIntegration.swift',
    ],
}

PROJECT_FILE = 'Talkie.xcodeproj/project.pbxproj'

def generate_uuid():
    """Generate Xcode-style UUID (24 hex chars)"""
    return uuid.uuid4().hex[:24].upper()

def add_files_to_project():
    """Add files to Xcode project"""

    # Read project file
    with open(PROJECT_FILE, 'r') as f:
        content = f.read()

    # Generate UUIDs for all files
    file_refs = {}
    build_files = {}

    for group, files in FILES_TO_ADD.items():
        for file_path in files:
            file_name = os.path.basename(file_path)
            file_refs[file_path] = generate_uuid()
            build_files[file_path] = generate_uuid()

    # Generate UUIDs for groups
    group_uuids = {}
    for group in FILES_TO_ADD.keys():
        if group not in ['Views/Memos', 'Views/Migration', 'App']:  # These groups likely exist
            group_uuids[group] = generate_uuid()

    # 1. Add PBXFileReference entries
    print("📝 Adding file references...")
    file_ref_section = "\n/* Begin PBXFileReference section */"
    file_ref_entries = []

    for file_path, ref_uuid in file_refs.items():
        file_name = os.path.basename(file_path)
        entry = f'\t\t{ref_uuid} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = "<group>"; }};'
        file_ref_entries.append(entry)

    # Find the PBXFileReference section and add entries
    pattern = r'(/\* Begin PBXFileReference section \*/)'
    replacement = file_ref_section + '\n' + '\n'.join(file_ref_entries)
    content = re.sub(pattern, replacement, content, count=1)

    # 2. Add PBXBuildFile entries
    print("🔨 Adding build file entries...")
    build_file_section = "\n/* Begin PBXBuildFile section */"
    build_file_entries = []

    for file_path, build_uuid in build_files.items():
        file_name = os.path.basename(file_path)
        ref_uuid = file_refs[file_path]
        entry = f'\t\t{build_uuid} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref_uuid} /* {file_name} */; }};'
        build_file_entries.append(entry)

    pattern = r'(/\* Begin PBXBuildFile section \*/)'
    replacement = build_file_section + '\n' + '\n'.join(build_file_entries)
    content = re.sub(pattern, replacement, content, count=1)

    # 3. Add to PBXSourcesBuildPhase
    print("⚙️ Adding to build phase...")

    # Find the PBXSourcesBuildPhase section and add build file references
    pattern = r'(/\* Begin PBXSourcesBuildPhase section \*/.*?files = \()(.*?)(\);)'

    def add_to_build_phase(match):
        prefix = match.group(1)
        existing = match.group(2)
        suffix = match.group(3)

        new_entries = []
        for file_path, build_uuid in build_files.items():
            file_name = os.path.basename(file_path)
            new_entries.append(f'\n\t\t\t\t{build_uuid} /* {file_name} in Sources */,')

        return prefix + existing + ''.join(new_entries) + suffix

    content = re.sub(pattern, add_to_build_phase, content, flags=re.DOTALL)

    # 4. Add group entries (for Data/* groups)
    print("📁 Adding group entries...")

    # Find where to add Data group (after Models group)
    # This is complex, so we'll add a comment for manual verification

    print("\n✅ File references and build phases updated!")
    print("\n⚠️  NOTE: Group hierarchy needs manual verification in Xcode")
    print("   The files are added to build, but folder structure may need adjustment")

    # Write back
    with open(PROJECT_FILE, 'w') as f:
        f.write(content)

    print(f"\n📦 Added {len(file_refs)} files to {PROJECT_FILE}")
    print("\nFiles added:")
    for group, files in FILES_TO_ADD.items():
        print(f"\n  {group}:")
        for file_path in files:
            print(f"    ✓ {os.path.basename(file_path)}")

if __name__ == '__main__':
    if not os.path.exists(PROJECT_FILE):
        print(f"❌ Error: {PROJECT_FILE} not found")
        print("   Run this script from the Talkie directory")
        exit(1)

    print("🚀 Adding GRDB data layer files to Xcode project...\n")
    add_files_to_project()
    print("\n✨ Done! Open Xcode to verify the files are in the project.")
