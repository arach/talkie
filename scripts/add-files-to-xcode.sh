#!/bin/bash
# Script to add new Swift files to Talkie.xcodeproj

PROJECT_DIR="/Users/arach/dev/talkie/macOS/Talkie"
PROJECT_FILE="$PROJECT_DIR/Talkie.xcodeproj/project.pbxproj"

# Files to add
FILES=(
    "Database/AudioStorage.swift"
    "Database/LiveDatabase.swift"
    "Models/LiveSettings.swift"
    "Models/TranscriptionTypes.swift"
    "Services/ContextCaptureService.swift"
    "Stores/UtteranceStore.swift"
    "Views/Live/TalkieLiveHomeView.swift"
    "Views/Live/TalkieLiveHistoryView.swift"
    "Views/Live/History/WaveformViews.swift"
    "Views/Live/Navigation/SidebarComponents.swift"
    "Views/Live/Components/AudioTroubleshooterView.swift"
    "Views/Live/Components/FailedQueuePicker.swift"
    "Views/Live/Components/QueuePicker.swift"
    "Views/Live/Settings/AppearanceSettings.swift"
    "Views/Live/Settings/HotkeyRecorder.swift"
    "Views/Live/Settings/PermissionsSettingsSection.swift"
    "Views/Live/Settings/SettingsView.swift"
    "Views/Live/Settings/SoundSettings.swift"
)

# Generate random UUIDs for Xcode
function gen_uuid() {
    uuidgen | tr -d '-' | tr '[:lower:]' '[:upper:]' | cut -c1-24
}

echo "Generating UUIDs and preparing to add files..."

for file in "${FILES[@]}"; do
    FILE_UUID=$(gen_uuid)
    BUILD_UUID=$(gen_uuid)
    echo "  - $file"
    echo "    File UUID: $FILE_UUID"
    echo "    Build UUID: $BUILD_UUID"
done

echo ""
echo "Note: Automatic pbxproj modification is complex and error-prone."
echo "Please add files manually in Xcode:"
echo "  1. Right-click on each folder (Database, Models, Services, etc.)"
echo "  2. Select 'Add Files to Talkie...'"
echo "  3. Select the corresponding Swift files"
echo "  4. Ensure 'Copy items if needed' is UNCHECKED"
echo "  5. Ensure 'Talkie' target is selected"
