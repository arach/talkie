# Talkie macOS - Getting Started
**TLDR: Don't read a million files. Read this first.**

---

## The 3 Apps (Process Model)

Talkie is **3 separate macOS apps** that work together:

### 1. **TalkieLive** - Always-On Voice Recorder
**What**: Menu bar app that captures voice in real-time
**Runs**: Independently, can be active when Talkie (main) is closed
**Does**:
- Detects voice, records audio
- Sends to TalkieEngine for transcription
- Pastes text or saves to queue
- Saves all dictations to shared database

**Location**: `macOS/TalkieLive/`
**Runs via**: `./macOS/TalkieLive/run.sh`

### 2. **TalkieEngine** - ML Inference XPC Service
**What**: Background XPC service that runs Whisper/Parakeet models
**Runs**: Launched by TalkieLive or Talkie (main) on-demand
**Does**:
- Transcribes audio files → text
- WhisperKit (CoreML) or Parakeet (NVIDIA) models
- Isolated process (crashes don't kill main apps)
- Caller-specified priority (`.high` for real-time, `.low` for batch)

**Location**: `macOS/TalkieEngine/`
**Runs via**: `./macOS/TalkieEngine/run.sh`
**Protocol**: `EngineProtocol.swift` - see `TranscriptionPriority` for priority system

### 3. **Talkie** - Main UI & Workflow Engine
**What**: SwiftUI app for managing memos and running AI workflows
**Runs**: User launches, can close while TalkieLive keeps running
**Does**:
- Display Live dictations (from shared database)
- Manage voice memos (via CloudKit sync from iOS)
- Run workflows (transcribe → summarize → extract tasks, etc.)
- Settings, model management, debugging tools

**Location**: `macOS/Talkie/`
**Runs via**: `./macOS/Talkie/run.sh` or `open Talkie.xcodeproj`

---

## How They Communicate

```
TalkieLive                    TalkieEngine                 Talkie (main)
    │                              │                            │
    │  XPC: transcribe(priority)   │                            │
    │─────────────────────────────→│                            │
    │                              │ Inference (.high/.low)     │
    │←─────────────────────────────│                            │
    │  Reply: transcript           │                            │
    │                              │                            │
    │  Save to DB                  │                            │
    ↓                              │                            │
~/Library/Application Support/Talkie/live.sqlite                │
    │                              │                            │
    │                              │        XPC callback        │
    │──────────────────────────────┼───────────────────────────→│
    │  (if Talkie running)         │    utteranceWasAdded()     │
    │                              │                            │
    │                              │      30s polling (fallback)│
    │←─────────────────────────────┼────────────────────────────│
    │                              │      refresh dictations    │
```

**Key Points**:
- **Shared Database**: All dictations stored in `~/Library/Application Support/Talkie/live.sqlite`
- **XPC for Real-Time**: State updates, transcription requests, callbacks
- **Polling as Fallback**: 30-second timer catches missed XPC callbacks
- **Priority System**: Caller declares `.high` (Live), `.userInitiated` (scratch pad), `.low` (batch)

---

## Project Structure

### TalkieLive (`macOS/TalkieLive/`)
```
TalkieLive/
├── App/
│   ├── TalkieLiveApp.swift           # SwiftUI app entry
│   ├── AppDelegate.swift             # Menu bar, hotkeys
│   └── LiveController.swift          # Recording state machine
├── Database/
│   ├── LiveDatabase.swift            # GRDB shared database
│   └── AudioStorage.swift            # Audio file management
├── Services/
│   ├── TalkieLiveXPCService.swift    # Broadcasts state to Talkie
│   ├── AudioLevelMonitor.swift       # Voice detection
│   └── ContextCaptureService.swift   # Captures app/window context
└── Views/
    └── Overlay/                      # Floating UI when recording
```

**Key Files**:
- `LiveController.swift:731` - Where dictations are saved + XPC broadcast
- `TalkieLiveXPCService.swift` - State broadcasting to Talkie
- `LiveDatabase.swift` - Shared database access

### TalkieEngine (`macOS/TalkieEngine/`)
```
TalkieEngine/
├── EngineProtocol.swift              # XPC protocol (TranscriptionPriority enum)
├── EngineService.swift               # WhisperKit + Parakeet inference
├── XPCServiceWrapper.swift           # XPC server implementation
└── Views/
    └── EngineStatusView.swift        # Debug UI for engine
```

**Key Files**:
- `EngineProtocol.swift` - See `TranscriptionPriority` enum + docs
- `EngineService.swift:226` - Priority → Task priority conversion
- Priority levels: `.high` > `.userInitiated` > `.medium` > `.low` > `.utility` > `.background`

### Talkie (`macOS/Talkie/`)
```
Talkie/
├── App/
│   ├── TalkieApp.swift               # SwiftUI app entry
│   ├── AppDelegate.swift             # Push notifications, URL handlers
│   └── StartupCoordinator.swift      # Phased initialization (performance)
├── Models/
│   ├── Persistence.swift             # Core Data stack
│   └── talkie.xcdatamodeld/          # Core Data model (memos, workflows)
├── Views/
│   ├── NavigationView.swift          # Main sidebar navigation
│   ├── Live/                         # Live dictations UI
│   ├── MemoDetail/                   # Voice memo detail view
│   ├── Settings/                     # Settings screens
│   └── DebugToolbar.swift            # Debug overlay (⌘⇧D in DEBUG)
├── Services/
│   ├── TalkieLiveStateMonitor.swift  # Receives XPC from TalkieLive
│   ├── EngineClient.swift            # Calls TalkieEngine
│   ├── CloudKitSyncManager.swift     # iOS → macOS sync
│   ├── SettingsManager.swift         # App settings
│   └── Router.swift                  # URL routing (talkie://...)
├── Stores/
│   └── DictationStore.swift          # Live dictations data (lazy loading)
├── Database/
│   └── LiveDatabase.swift            # Read from shared DB
├── Workflow/
│   ├── WorkflowDefinition.swift      # TWF schema
│   ├── WorkflowExecutor.swift        # Step execution
│   └── Steps/                        # Step implementations
├── Debug/
│   ├── DesignMode/                   # Design Tools (⌘⇧D)
│   └── DebugCommandHandler.swift     # CLI debug commands
└── Resources/
    └── StarterWorkflows/             # Bundled .twf.json files
```

**Key Files**:
- `StartupCoordinator.swift` - Phased app initialization (performance optimizations)
- `DictationStore.swift` - Lazy loading (50 recent, not all 3K), 30s polling
- `TalkieLiveStateMonitor.swift:172` - XPC callback handler `utteranceWasAdded()`
- `EngineClient.swift` - How Talkie calls TalkieEngine (set priority here)
- `Router.swift` - URL scheme routing (`talkie://...`)

---

## Shared Packages (Monorepo)

Talkie uses **3 local Swift packages** developed in the monorepo:

### 1. **TalkieKit** - Shared Components (3 Apps)
**Location**: `macOS/TalkieKit/` *(not in `/Packages/`)*
**Purpose**: Shared components used across Talkie, TalkieLive, and TalkieEngine

**Features**:
- **Console** - System console viewer (`ConsoleView.swift`)
- **AudioPlayer** - Seekable waveform player (`AudioPlaybackManager.swift`)
- **SharedSettings** - Cross-app settings sync
- **TalkieEnvironment** - Environment detection (dev/staging/prod)
- **UI Components** - LivePill status indicator

**Used by**: All 3 apps (Talkie, TalkieLive, TalkieEngine)

**Why separate from `/Packages/`**: App-specific shared code, tightly coupled to Talkie's architecture

### 2. **DebugKit** - Debugging Toolkit
**Location**: `/Packages/DebugKit/`
**Purpose**: Comprehensive debugging components for macOS SwiftUI apps

**Features**:
- **DebugToolbar** - Floating debug toolbar with actions/controls
- **DebugShelf** - Sliding shelf for step-based flows (onboarding)
- **LayoutGrid** - Visual grid overlay showing layout zones
- **StoryboardGenerator** - Multi-screen screenshot compositor
- **CLICommandHandler** - Generic `--debug=<command>` headless system

**Used by**: Talkie (main app), WFKit (workflow editor)

**Example**:
```bash
# Generate storyboard with layout grid overlay
Talkie.app/Contents/MacOS/Talkie --debug=onboarding-storyboard ~/Desktop/out.png
```

### 3. **WFKit** - Visual Workflow Editor
**Location**: `/Packages/WFKit/`
**Purpose**: Canvas-based node editor component library

**Features**:
- Canvas-based node editor with pan/zoom
- Visual node connections (Bezier curves)
- Node property inspector
- Multiple layout modes (freeform, vertical)
- JSON export/import
- Minimap overview
- Built-in debug toolbar (via DebugKit)

**Used by**: Talkie (workflow visualization - planned v1: read-only viewer)

**Demo App**:
```bash
cd Packages/WFKit
swift run Workflow  # Standalone demo
```

**Dependency Chain**:
```
Talkie, TalkieLive, TalkieEngine
  ├─→ TalkieKit (shared components)
  └─→ DebugKit (debug tools)

Talkie (only)
  └─→ WFKit
        └─→ DebugKit
```

### Why Monorepo?

These packages are:
- ✅ **Developed for Talkie** - Built alongside Talkie features
- ✅ **Modular** - Structured as proper SPM packages
- ✅ **Fast iteration** - No context switching between repos
- ✅ **Potentially publishable** - DebugKit/WFKit could extract to separate repos later

**Referenced by**: Relative paths in `Package.swift` (`.package(path: "../DebugKit")`)

**Development**: Make changes in package source, test immediately in apps - no commits needed

**See**: `/Packages/README.md` for DebugKit/WFKit workflow

---

## Essential Scripts

### Build & Run
```bash
# Run each app individually (from repo root)
./macOS/Talkie/run.sh              # Main UI
./macOS/TalkieLive/run.sh          # Menu bar recorder
./macOS/TalkieEngine/run.sh        # Inference service

# Or run all 3 together
./macOS/run.sh                     # Launches all apps

# Build release
cd macOS/Talkie
xcodebuild -scheme Talkie -configuration Release build
```

### Development Tools
```bash
# Keep Xcode project in sync with file system
./scripts/sync-xcode-files.py      # Add missing .swift files to project
./scripts/sync-xcode-files.py --check  # Preview changes
./scripts/sync-xcode-files.py --diff   # Show diff

# Find latest build output
./scripts/find-build.sh            # Locates DerivedData build

# Profile Engine
./macOS/TalkieEngine/profile-engine.sh  # Instruments profiling
```

### Common Workflows
```bash
# Debug mode with CLI command
./macOS/Talkie/run.sh --debug=settings-screenshots ~/Desktop/screenshots

# Install debug Engine (for testing)
./scripts/install-debug-engine.sh

# Create app icon
./scripts/create-app-icon.sh icon.png
```

### Build, Sign, Notarize & Release

**Location**: `Installer/build.sh` (656-line comprehensive script)

```bash
# Full installer (3 separate apps)
./Installer/build.sh --version {{VERSION}}

# Unified bundle (helpers embedded in Talkie.app/LoginItems)
./Installer/build.sh unified --version {{VERSION}}

# Specific installers
./Installer/build.sh core --version {{VERSION}}   # Engine + Core only
./Installer/build.sh live --version {{VERSION}}   # Engine + Live only
./Installer/build.sh all --version {{VERSION}}    # All installers

# Fast iteration (skip clean build, reuse exports)
SKIP_CLEAN=1 ./Installer/build.sh --version {{VERSION}}

# Skip notarization (for local testing)
SKIP_NOTARIZE=1 ./Installer/build.sh --version {{VERSION}}

# Interactive release (pre-flight checks + confirmation)
./Installer/release.sh {{VERSION}}
```

**Process**:
1. Verify signing identities (Developer ID App + Installer)
2. Build all 3 apps (Release, arm64, signed)
3. Create component packages (.pkg)
4. Sign distribution packages (productsign)
5. Notarize (xcrun notarytool with "notarytool" profile)
6. Staple ticket (xcrun stapler)
7. Archive to `Installer/releases/{{VERSION}}/`

**Output**:
- `Talkie-for-Mac.pkg` - Full installer (3 apps)
- `Talkie-Unified.pkg` - Single bundle with helpers embedded
- `Talkie-Core.pkg` - Engine + Core only
- `Talkie-Live.pkg` - Engine + Live only

**Key Features**:
- Proper iCloud signing (archive → export workflow)
- Incremental builds (SKIP_CLEAN=1 reuses exports)
- LaunchAgent installation (/Library/LaunchAgents/)
- Gatekeeper verification

**Setup notarization**:
```bash
xcrun notarytool store-credentials "notarytool" \
  --apple-id {{YOUR_APPLE_ID}} \
  --team-id {{TEAMID}}
```

---

## DEBUG-Only Toolbars (⌘⇧D)

### 1. Debug Toolbar (Red Ant Icon)
**Activation**: Automatically appears in DEBUG builds
**Location**: `Views/DebugToolbar.swift`
**Features**:
- Quick actions (force sync, clear caches, test workflows)
- System console viewer
- Copy debug info to clipboard
- App state inspection

**How to Use**:
```swift
// In any view:
TalkieDebugToolbar {
    // Your custom debug content
    Text("Custom debug info")
} debugInfo: {
    ["Key": "Value", "State": "Active"]
}
```

### 2. Design Tools (Grid/Ruler Icon)
**Activation**: Press **⌘⇧D** to toggle Design God Mode
**Location**: `Debug/DesignMode/`
**Features**:
- Layout grid overlay (8pt baseline grid)
- Spacing decorator (shows padding/margins)
- Design system compliance audit
- Color/typography inspection

**Files**:
- `DesignModeManager.swift` - Global enable/disable
- `DesignOverlay.swift` - Main overlay UI
- `SpacingDecoratorOverlay.swift` - Visual spacing hints
- `Tools/DesignAuditor.swift` - Design system compliance checking

**How to Use**:
- Press **⌘⇧D** anywhere in app → toggles Design Mode
- Click toolbar to show/hide grid, spacing, bounds
- Audit button shows design token compliance report

---

## Common Tasks

### Fix a Bug in Live Dictations

1. **Where to Look**:
   - Recording issues → `TalkieLive/App/LiveController.swift`
   - Transcription issues → `TalkieEngine/EngineService.swift`
   - UI display issues → `Talkie/Views/Live/DictationListView.swift`
   - Database issues → `LiveDatabase.swift` (either TalkieLive or Talkie)

2. **Debug Tools**:
   - TalkieLive logs: `~/Library/Logs/TalkieLive/TalkieLive.log`
   - Engine logs: `~/Library/Logs/TalkieEngine/TalkieEngine.log`
   - Database: `sqlite3 ~/Library/Application\ Support/Talkie/live.sqlite`
   - XPC connection: `log show --predicate 'subsystem == "jdi.talkie.core"' --last 5m`

3. **Common Issues**:
   - **Slow transcription during builds** → Check priority (should be `.high` in TalkieLive)
   - **Dictations not updating** → Check XPC connection (`TalkieLiveStateMonitor.isXPCConnected`)
   - **Database empty** → Check path (moved from Group Containers to Application Support)

### Add a New Workflow Step

1. **Define Step Type**: `Talkie/Workflow/WorkflowDefinition.swift`
   ```swift
   enum WorkflowStepType: String, Codable {
       case myNewStep = "my-new-step"
   }
   ```

2. **Add Config Struct**:
   ```swift
   struct MyNewStepConfig: Codable {
       var parameter: String
   }
   ```

3. **Implement Execution**: `Talkie/Workflow/WorkflowExecutor.swift`
   ```swift
   case .myNewStep:
       let config = try step.decodeConfig(MyNewStepConfig.self)
       return try await executeMyNewStep(config, context: context)
   ```

4. **Create Step File**: `Talkie/Workflow/Steps/MyNewStep.swift`

5. **Update Docs**: `Resources/StarterWorkflows/TWF_GENERATION_PROMPT.md`

### Debug Startup Performance

1. **Use Instruments**:
   ```bash
   # Build and profile
   xcodebuild -scheme Talkie -configuration Release build
   # Open in Instruments → "os_signpost" template
   # Filter by subsystem: "jdi.talkie.performance"
   ```

2. **Key Signposts**:
   - `App Launch` - Overall app initialization
   - `Phase 1: Critical` - Window appearance (~50ms target)
   - `Phase 2: Database` - GRDB init
   - `UI First Render` - SwiftUI render time

3. **Files to Check**:
   - `StartupCoordinator.swift` - Phased initialization logic
   - `AppDelegate.swift` - Has signpost instrumentation
   - `TalkieApp.swift` - SwiftUI lifecycle

### Add Files to Xcode Project

```bash
# After adding/moving .swift files:
./scripts/sync-xcode-files.py --check    # Preview what will be added
./scripts/sync-xcode-files.py            # Add missing files to project

# The script:
# - Finds .swift files not in project.pbxproj
# - Adds them to correct PBXGroup (preserves folder structure)
# - Creates backup before changes
```

---

## Data Storage

| Path | What | Access |
|------|------|--------|
| `~/Library/Application Support/Talkie/live.sqlite` | Live dictations database | TalkieLive (RW), Talkie (RW) |
| `~/Library/Application Support/Talkie/Audio/` | Audio files (uuid.m4a) | TalkieLive (RW), Talkie (R) |
| `~/Library/Application Support/Talkie/WhisperModels/` | Downloaded ML models | TalkieEngine |
| `~/Documents/Workflows/` | User TWF files | Talkie |
| `~/Documents/Transcripts/` | Optional Markdown export | Talkie |
| Core Data | Voice memos (from iOS) | Talkie only |

---

## Architecture Principles

### Performance
- **Lazy loading**: Don't load data until user navigates to it
- **Phased startup**: Critical path first, defer everything else
- **Priority-aware**: Real-time work gets `.high`, batch gets `.low`
- **Polling as fallback**: XPC is primary, polling catches failures

### Communication
- **XPC for real-time**: State updates, callbacks, interactive requests
- **Database for async**: Persistence, works when apps are closed
- **No tight coupling**: TalkieLive can run without Talkie

### Code Patterns
- **Observable singletons**: `@Observable final class MyService { static let shared }`
- **Selective caching in views**: Cache only properties you display, use `.onReceive()`
- **MainActor isolation**: XPC services use `@MainActor` for thread safety
- **Fail-safe XPC**: Broadcast to N observers, silently ignore if none connected

### Design System (See `DESIGN_SYSTEM_REVIEW.md`)
- **No emojis in UI** - SF Symbols only (emojis OK in user content)
- **Design tokens**: Use `Theme.current.*` not hardcoded values
- **Spacing**: Use `Spacing.sm/md/lg` not raw numbers
- **Debug compliance**: Press ⌘⇧D → Audit button

### Logging (TalkieLogger)

**ALWAYS use TalkieLogger. NEVER use os.log directly.**

```swift
import TalkieKit

private let log = Log(.database)

log.info("Starting operation")
log.debug("Details: \(value)")
log.warning("Something unexpected")
log.error("Failed: \(error)")
log.info("Critical startup", critical: true)  // Synchronous, crash-safe
```

**Categories**: `.system`, `.audio`, `.transcription`, `.database`, `.xpc`, `.sync`, `.ui`, `.workflow`

**Never use**: `import os.log`, `Logger(subsystem:)`, `os_log()`, `print()`, `NSLog()`

TalkieLogger routes to Console.app + file logs. SwiftLint flags violations.

---

## User Preferences

- **No emojis in app UI** - Use SF Symbols for icons/buttons
- **Design system compliance** - Use tokens, not hardcoded values
- **Performance obsessed** - Instrument everything, minimize blocking work
- **Clean commits** - No "Generated with Claude Code" footers (see `CLAUDE.md`)
- **Pnpm preferred** - For Node.js projects (check for `pnpm-lock.yaml` first)
- **Gitmoji in commits** - Add emoji prefixes (✨ features, 🐛 bugs, ⚡️ performance)

---

## Key Documentation

- **This file** (`macOS/AGENTS.md`) - Start here
- `macOS/Talkie/ARCHITECTURE_REVIEW.md` - SwiftUI performance patterns
- `macOS/Talkie/DESIGN_SYSTEM_REVIEW.md` - Design tokens, compliance
- `macOS/TalkieEngine/EngineProtocol.swift` - Priority system (see comments)
- `macOS/Talkie/CLAUDE.md` - Build commands, project-specific conventions
- `/CLAUDE.md` (repo root) - Workspace-wide conventions

---

## Quick Reference

### "Where do I find...?"

| What | Where |
|------|-------|
| Recording logic | `TalkieLive/App/LiveController.swift` |
| Transcription | `TalkieEngine/EngineService.swift` |
| Priority system | `TalkieEngine/EngineProtocol.swift` (see `TranscriptionPriority`) |
| Live dictations UI | `Talkie/Views/Live/DictationListView.swift` |
| Dictation data store | `Talkie/Stores/DictationStore.swift` |
| Shared database | `LiveDatabase.swift` (in both TalkieLive and Talkie) |
| XPC callbacks | `Talkie/Services/TalkieLiveStateMonitor.swift` |
| Engine client | `Talkie/Services/EngineClient.swift` |
| Startup phases | `Talkie/App/StartupCoordinator.swift` |
| Workflow executor | `Talkie/Workflow/WorkflowExecutor.swift` |
| Debug toolbar | `Talkie/Views/DebugToolbar.swift` (uses `/Packages/DebugKit/`) |
| Design tools | `Talkie/Debug/DesignMode/` |
| Settings | `Talkie/Services/SettingsManager.swift` |
| CloudKit sync | `Talkie/Services/CloudKitSyncManager.swift` |
| TalkieKit package | `macOS/TalkieKit/` (shared components for 3 apps) |
| DebugKit package | `/Packages/DebugKit/` (debug components) |
| WFKit package | `/Packages/WFKit/` (workflow editor library) |
| TalkieLogger | `TalkieKit/Sources/TalkieKit/Logging/TalkieLogger.swift` |

### "How do I...?"

| Task | Command/File |
|------|--------------|
| Run Talkie | `./macOS/Talkie/run.sh` |
| Run TalkieLive | `./macOS/TalkieLive/run.sh` |
| Run Engine | `./macOS/TalkieEngine/run.sh` |
| Run WFKit demo | `cd Packages/WFKit && swift run Workflow` |
| Test DebugKit changes | Make changes in `/Packages/DebugKit/`, build Talkie |
| Build release installer | `./Installer/build.sh --version {{VERSION}}` |
| Build unified bundle | `./Installer/build.sh unified --version {{VERSION}}` |
| Interactive release | `./Installer/release.sh {{VERSION}}` |
| Sync Xcode project | `./scripts/sync-xcode-files.py` |
| Profile startup | Instruments → os_signpost → filter "jdi.talkie.performance" |
| View Engine logs | `tail -f ~/Library/Logs/TalkieEngine/TalkieEngine.log` |
| Toggle Design Mode | Press ⌘⇧D |
| Check DB | `sqlite3 ~/Library/Application\ Support/Talkie/live.sqlite` |
| Find build output | `./scripts/find-build.sh` |

---

**Last Updated**: 2025-12-25
**Major Topics**: 3-app process model, priority system, lazy loading, toolbars, packages (TalkieKit, DebugKit, WFKit)
