# AGENTS.md — iOS

iOS-specific instructions. See root `/AGENTS.md` for shared conventions.

---

## Overview

SwiftUI + SwiftData app for recording voice memos. Syncs to macOS via CloudKit for workflow processing.

## Build

```bash
open "Talkie iOS.xcodeproj"

# Simulator
xcodebuild -scheme "Talkie iOS" \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Device (requires signing)
xcodebuild -scheme "Talkie iOS" \
  -destination 'generic/platform=iOS' build

# Tests
xcodebuild -scheme "Talkie iOS" \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Project Structure

```
Talkie iOS/
├── App/
│   ├── talkieApp.swift       # @main entry point
│   ├── AppDelegate.swift     # UIKit lifecycle hooks
│   ├── AppIntents.swift      # Siri/Shortcuts intents
│   └── DeepLinkManager.swift # URL handling
├── Models/
│   ├── Persistence.swift     # SwiftData container setup
│   └── VoiceMemo+Extensions.swift
├── Views/
│   ├── VoiceMemoListView.swift
│   ├── RecordingView.swift
│   └── VoiceMemoDetailView.swift
├── Services/
│   ├── AudioRecorderManager.swift
│   ├── AudioPlayerManager.swift
│   └── TranscriptionService.swift
├── Resources/
│   ├── Assets.xcassets
│   ├── Info.plist
│   └── ThemeManager.swift
└── talkie.entitlements
```

## Key Files

| File | Purpose |
|------|---------|
| `App/talkieApp.swift` | App entry, scene setup |
| `Models/Persistence.swift` | SwiftData + CloudKit config |
| `Views/RecordingView.swift` | Main recording interface |
| `Services/AudioRecorderManager.swift` | AVAudioRecorder wrapper |

## iOS-Specific Patterns

### Recording

```swift
@MainActor @Observable
final class AudioRecorderManager {
    var isRecording = false
    var duration: TimeInterval = 0

    private var recorder: AVAudioRecorder?

    func startRecording() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        // ...
    }
}
```

### CloudKit Sync

iOS is the primary source for voice memos. Data syncs automatically via `NSPersistentCloudKitContainer`.

```swift
// Persistence.swift
let container = NSPersistentCloudKitContainer(name: "Talkie")
container.persistentStoreDescriptions.first?.cloudKitContainerOptions =
    NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.jdi.talkie")
```

### Widgets

Widget target in `TalkieWidget/`:
- `TalkieWidget.swift` — Timeline provider
- `TalkieControlWidget.swift` — Control Center widget

### App Intents

```swift
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"

    func perform() async throws -> some IntentResult {
        // ...
    }
}
```

## Testing

```swift
// Unit tests in TalkieTests/
@Test func audioRecorderStartsCleanly() async throws {
    let recorder = AudioRecorderManager()
    try await recorder.startRecording()
    #expect(recorder.isRecording)
}
```

## Entitlements

Required capabilities in `talkie.entitlements`:
- `com.apple.developer.icloud-container-identifiers`
- `com.apple.developer.icloud-services` (CloudKit)
- `com.apple.security.application-groups`

## Notes

- Audio stored as M4A in `audioData` field (external storage enabled)
- Transcription happens on macOS after sync
- Pull-to-refresh triggers CloudKit sync
