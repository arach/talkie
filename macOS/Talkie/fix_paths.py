#!/usr/bin/env python3
"""Fix file paths in Xcode project"""

import re

# Map filename → correct path
FILE_PATHS = {
    'VoiceMemo.swift': 'Data/Models/VoiceMemo.swift',
    'TranscriptVersion.swift': 'Data/Models/TranscriptVersion.swift',
    'WorkflowRun.swift': 'Data/Models/WorkflowRun.swift',
    'MemoSource.swift': 'Data/Models/MemoSource.swift',
    'DatabaseManager.swift': 'Data/Database/DatabaseManager.swift',
    'MemoRepository.swift': 'Data/Database/MemoRepository.swift',
    'GRDBRepository.swift': 'Data/Database/GRDBRepository.swift',
    'CoreDataMigration.swift': 'Data/Database/CoreDataMigration.swift',
    'MemosViewModel.swift': 'Data/ViewModels/MemosViewModel.swift',
    'CloudKitSyncEngine.swift': 'Data/Sync/CloudKitSyncEngine.swift',
    'AllMemosView2.swift': 'Views/Memos/AllMemosView2.swift',
    'MigrationView.swift': 'Views/Migration/MigrationView.swift',
    'DataLayerIntegration.swift': 'App/DataLayerIntegration.swift',
}

PROJECT_FILE = 'Talkie.xcodeproj/project.pbxproj'

with open(PROJECT_FILE, 'r') as f:
    content = f.read()

# Fix each file reference
for filename, full_path in FILE_PATHS.items():
    # Find pattern: path = VoiceMemo.swift;
    # Replace with: path = Data/Models/VoiceMemo.swift;
    pattern = f'path = {re.escape(filename)};'
    replacement = f'path = {full_path};'

    old_count = content.count(pattern)
    content = content.replace(pattern, replacement)
    new_count = content.count(replacement)

    if new_count > 0:
        print(f"✅ Fixed: {filename} → {full_path}")

# Write back
with open(PROJECT_FILE, 'w') as f:
    f.write(content)

print(f"\n✨ Fixed all file paths in {PROJECT_FILE}")
