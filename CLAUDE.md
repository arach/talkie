# Talkie

Voice-first productivity suite for macOS.

**The user actively uses Talkie, TalkieLive, and TalkieEngine for live dictation.**

- **NEVER** run `pkill Talkie`, `pkill TalkieLive`, or `pkill TalkieEngine`
- **NEVER** kill apps in `/Applications/` - user may be mid-recording
- **OK** to kill debug builds in DerivedData if specifically testing
- When testing, launch debug builds alongside running XCode builds - don't replace them

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Talkie (Swift)                           │
│              UI • Workflows • Data • Orchestration          │
└────────────────┬────────────────┬────────────────┬──────────┘
                 │ XPC            │ XPC            │ HTTP
                 ▼                ▼                ▼
        ┌────────────────┐ ┌─────────────┐ ┌──────────────────┐
        │  TalkieLive    │ │ TalkieEngine│ │  TalkieGateway   │
        │    (Swift)     │ │   (Swift)   │ │   (TypeScript)   │
        │  Ears & Hands  │ │ Local Brain │ │  External Brain  │
        └────────────────┘ └─────────────┘ └──────────────────┘
          Mic → Keyboard    Whisper         OpenAI, Anthropic
                            Transcription   Google, Groq
```

**Talkie** owns user intent — what to do and why.
**TalkieLive** owns real-time I/O — listening and typing.
**TalkieEngine** owns local compute — on-device transcription.
**TalkieGateway** owns external APIs — protocol translation to cloud services.

### The Gateway Rule

> **Gateway translates protocols, not intent.**

- ✅ `POST /inference { provider, model, messages }` — generic, any app could use this
- ❌ `POST /polish-memo { memoId }` — Talkie-specific, belongs in main app

**Litmus test:** Could a different app use Gateway unchanged? If yes → Gateway. If no → Talkie.

## Projects

- **macOS/Talkie** - Main macOS app (SwiftUI)
- **macOS/TalkieLive** - Background helper for live dictation
- **macOS/TalkieEngine** - Transcription engine service
- **macOS/TalkieGateway** - Web layer for external APIs (TypeScript/Bun)
- **iOS/Talkie iOS** - iOS companion app (SwiftUI)
- **Packages/** - Shared Swift packages (WFKit, TalkieKit, DebugKit)

## Build

```bash
# Build main app
cd macOS/Talkie
xcodebuild -scheme Talkie -configuration Debug build

# Build TalkieLive
cd macOS/TalkieLive
xcodebuild -scheme TalkieLive -configuration Debug build

# Run TalkieGateway (TypeScript/Bun)
cd macOS/TalkieGateway
bun install
bun run src/server.ts          # Normal mode (requires Tailscale)
bun run src/server.ts --local  # Local mode (no Tailscale required)
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

## Data Architecture: GRDB-Primary

**GRDB is the local source of truth. CloudKit is a sync layer.**

```
┌─────────────────────────────────────────────┐
│              App Layer (UI)                 │
│         reads/writes from GRDB only         │
└─────────────────┬───────────────────────────┘
                  │
┌─────────────────▼───────────────────────────┐
│                  GRDB                       │
│         ~/Library/.../Talkie/*.sqlite       │
│            LOCAL SOURCE OF TRUTH            │
└─────────────────┬───────────────────────────┘
                  │ bridge sync (background)
┌─────────────────▼───────────────────────────┐
│            Sync Providers                   │
│  ┌────────────────────────────────────────┐ │
│  │ CloudKit (via Core Data bridge)        │ │
│  │ - NSPersistentCloudKitContainer        │ │
│  │ - Syncs changes TO GRDB                │ │
│  └────────────────────────────────────────┘ │
│  ┌────────────────────────────────────────┐ │
│  │ Future: other sync providers           │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Evolution
Started with Core Data + CloudKit as source of truth, evolved to GRDB-primary for:
- **Performance**: GRDB is 10-20x faster for local queries
- **Flexibility**: Sync layer is now pluggable
- **Reliability**: App works offline-first, sync catches up

### Startup Order
1. **GRDB first** - App shows immediately with local data
2. **CloudKit deferred** - Syncs in background after UI is ready

### Key Files
- `Data/Database/DatabaseManager.swift` - GRDB for memos
- `Database/LiveDatabase.swift` - GRDB for live dictations
- `Models/Persistence.swift` - Core Data + CloudKit bridge
- `Services/TalkieData.swift` - Bridge sync (CloudKit → GRDB)

## Data Ownership

Each database has a single writer to prevent corruption:

| Database | Writer | Readers |
|----------|--------|---------|
| `talkie_grdb.sqlite` (memos) | Talkie | Talkie |
| `live.sqlite` (dictations) | TalkieLive | Talkie (read-only) |

**If Talkie needs to mutate live.sqlite:** Use XPC → `TalkieLiveXPCProtocol` → TalkieLive writes it.

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
