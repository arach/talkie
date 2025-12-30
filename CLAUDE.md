# Talkie

Voice-first productivity suite for macOS.

## ⚠️ CRITICAL: Never Kill Production Apps

**The user actively uses Talkie, TalkieLive, and TalkieEngine for live dictation.**

- **NEVER** run `pkill Talkie`, `pkill TalkieLive`, or `pkill TalkieEngine`
- **NEVER** kill apps in `/Applications/` - user may be mid-recording
- **OK** to kill debug builds in DerivedData if specifically testing
- When testing, launch debug builds alongside production - don't replace them
- If you need to restart an app, ASK the user first

## Projects

- **macOS/Talkie** - Main macOS app (SwiftUI)
- **macOS/TalkieLive** - Background helper for live dictation
- **macOS/TalkieEngine** - Transcription engine service
- **Packages/** - Shared Swift packages (WFKit, TalkieKit, DebugKit)

## Build

```bash
# Build main app
cd macOS/Talkie
xcodebuild -scheme Talkie -configuration Debug build

# Build TalkieLive
cd macOS/TalkieLive
xcodebuild -scheme TalkieLive -configuration Debug build
```

## Scripts & Utilities

### Xcode Project Sync (`scripts/sync-xcode-files.py`)

Keeps Swift files in sync with Xcode project. Use when adding/moving files.

```bash
# Check what's missing
./scripts/sync-xcode-files.py --check

# Preview changes (no write)
./scripts/sync-xcode-files.py --diff

# Add missing files
./scripts/sync-xcode-files.py
```

The script:
- Finds .swift files not in project.pbxproj
- Adds them to the correct PBXGroup (preserves folder structure)
- Creates backup before changes

## Data Ownership: Talkie ↔ TalkieLive

**TalkieLive owns all writes to `live.sqlite`. Talkie is read-only.**

```
~/Library/Application Support/Talkie/live.sqlite
├── TalkieLive: READ + WRITE (schema migrations, all mutations)
└── Talkie:     READ-ONLY (queries only, opened with config.readonly = true)
```

### Why This Matters
- **Single writer** prevents corruption and race conditions
- **SQLite enforces it** - Talkie's read-only config rejects any write attempts
- **XPC for mutations** - Talkie routes delete/update requests through TalkieLive XPC

### What Each App Does

| Operation | Talkie | TalkieLive |
|-----------|--------|------------|
| Schema migrations | ❌ | ✅ |
| Insert dictations | ❌ | ✅ |
| Update transcription | ❌ | ✅ |
| Delete dictations | ❌ (stub + XPC) | ✅ |
| Update live_state | ❌ | ✅ |
| Query dictations | ✅ | ✅ |
| Prune old data | ❌ | ✅ |

### Adding Write Operations
If Talkie needs to trigger a write (e.g., delete, retranscribe):
1. Add method to `TalkieLiveXPCProtocol`
2. Implement in TalkieLive's XPC service
3. Call via XPC from Talkie (don't touch LiveDatabase directly)

## Key Patterns

- **Observable migration** - Moving from ObservableObject to @Observable
- **Midnight theme** - Dark UI via SettingsManager color properties
- **XPC communication** - Talkie <-> TalkieLive via TalkieLiveXPCProtocol

## Logging

**ALWAYS use TalkieLogger, NEVER use os.log directly.**

```swift
import TalkieKit

private let log = Log(.database)  // or .system, .audio, .transcription, .xpc, .sync, .ui, .workflow

// Usage
log.info("Starting operation")
log.debug("Details: \(value)")
log.warning("Something unexpected")
log.error("Failed: \(error)")
```

Categories: `.system`, `.audio`, `.transcription`, `.database`, `.xpc`, `.sync`, `.ui`, `.workflow`

Do NOT use:
- `import os.log`
- `Logger(subsystem:category:)`
- `os_log()`

## Common Tasks

When moving/adding Swift files:
1. Move the file in Finder/Xcode
2. Run `./scripts/sync-xcode-files.py --check` to verify
3. Run `./scripts/sync-xcode-files.py` to add missing files
