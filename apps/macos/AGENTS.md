# Talkie macOS - Getting Started
**TLDR: Don't read a million files. Read this first.**

---

## The 2 Apps + Embedded Engine

Talkie now runs as **2 macOS apps**, with the local engine embedded inside `TalkieAgent`:

### 1. **TalkieAgent** - Always-On Voice Recorder + Engine Host
**What**: Menu bar app that captures voice in real-time and hosts the local transcription runtime
**Runs**: Independently, can stay active when Talkie (main) is closed
**Does**:
- Detects voice, records audio
- Runs `TalkieEngineCore` for local transcription
- Exposes XPC services to Talkie
- Enables the WebSocket bridge only when bridge/remote-engine features are turned on
- Pastes text or saves to queue
- Saves all dictations to shared database

**Location**: `apps/macos/TalkieAgent/`
**Runs via**: `./apps/macos/TalkieAgent/run.sh`

### 2. **Talkie** - Main UI & Workflow Engine
**What**: SwiftUI app for managing memos and running AI workflows
**Runs**: User launches, can close while TalkieAgent keeps running
**Does**:
- Display Live dictations (from shared database)
- Manage voice memos (via CloudKit sync from iOS)
- Run workflows (transcribe → summarize → extract tasks, etc.)
- Settings, model management, debugging tools

**Location**: `apps/macos/Talkie/`
**Runs via**: `./apps/macos/Talkie/run.sh` or `open Talkie.xcodeproj`

### 3. **TalkieEngineCore** - Embedded Inference Runtime
**What**: Local Swift package that provides the engine implementation used by TalkieAgent
**Runs**: Inside TalkieAgent, not as a standalone app target
**Does**:
- Transcribes audio files → text
- Manages Whisper/Parakeet model lifecycle
- Provides optional WebSocket bridge support when remote engine access is enabled
- Runs streaming ASR in-process inside the embedded engine runtime
- Honors caller-specified priority (`.high` for real-time, `.low` for batch)

**Location**: `apps/macos/TalkieEngineCore/`
**Entry point**: `TalkieAgent/TalkieAgent/Services/EmbeddedEngineCoordinator.swift`
**Priority definitions**: `TalkieKit/Sources/TalkieKit/XPCProtocols.swift`

---

## How They Communicate

```
TalkieAgent (recording + embedded engine)                 Talkie (main)
    │                                                        │
    │  capture audio → transcribe(priority)                  │
    │  inside TalkieEngineCore                               │
    │                                                        │
    │  save to DB                                            │
    ↓                                                        │
~/Library/Application Support/Talkie/live.sqlite            │
    │                                                        │
    │  XPC callback: utteranceWasAdded()                     │
    ├───────────────────────────────────────────────────────→│
    │                                                        │
    │  30s polling (fallback)                                │
    │←───────────────────────────────────────────────────────┤
    │                                                        │
    │  Optional WebSocket bridge on :19821 only when         │
    │  remote engine access is enabled                       │
```

**Key Points**:
- **Shared Database**: All dictations stored in `~/Library/Application Support/Talkie/live.sqlite`
- **XPC for Real-Time**: Talkie talks to services hosted by TalkieAgent
- **Polling as Fallback**: 30-second timer catches missed XPC callbacks
- **No standalone engine app**: Local inference lives in `TalkieEngineCore` inside TalkieAgent
- **Optional bridge**: Port `19821` is only opened when remote engine features are enabled
- **Priority System**: Caller declares `.high` (Live), `.userInitiated` (scratch pad), `.low` (batch)

---

## Project Structure

### TalkieAgent (`apps/macos/TalkieAgent/`)
```
TalkieAgent/
├── App/
│   ├── TalkieAgentApp.swift           # SwiftUI app entry
│   ├── AppDelegate.swift             # Menu bar, hotkeys
│   └── LiveController.swift          # Recording state machine
├── Database/
│   ├── LiveDatabase.swift            # GRDB shared database
│   └── AudioStorage.swift            # Audio file management
├── Services/
│   ├── TalkieAgentXPCService.swift    # Broadcasts state to Talkie
│   ├── AudioLevelMonitor.swift       # Voice detection
│   └── ContextCaptureService.swift   # Captures app/window context
└── Views/
    └── Overlay/                      # Floating UI when recording
```

**Key Files**:
- `LiveController.swift:731` - Where dictations are saved + XPC broadcast
- `EmbeddedEngineCoordinator.swift` - Hosts and gates the embedded engine bridge
- `TalkieAgentXPCService.swift` - State broadcasting to Talkie
- `LiveDatabase.swift` - Shared database access

### TalkieEngineCore (`apps/macos/TalkieEngineCore/`)
```
TalkieEngineCore/
├── Sources/TalkieEngineCore/
│   ├── EngineService.swift           # WhisperKit + Parakeet inference
│   ├── EmbeddedEngineRuntime.swift   # Engine interface used by TalkieAgent
│   ├── EngineFactory.swift           # Factory for embedded runtime
│   └── StreamingASRService.swift     # In-process streaming ASR via FluidAudio
└── Package.swift
```

**Key Files**:
- `EngineService.swift` - Core engine implementation
- `EmbeddedEngineCoordinator.swift` - Bridge enable/disable and lifecycle inside TalkieAgent
- `TalkieKit/XPCProtocols.swift` - `TranscriptionPriority` enum + docs
- Priority levels: `.high` > `.userInitiated` > `.medium` > `.low` > `.utility` > `.background`

### Talkie (`apps/macos/Talkie/`)
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
│   ├── TalkieAgentStateMonitor.swift  # Receives XPC from TalkieAgent
│   ├── EngineClient.swift            # Calls engine hosted inside TalkieAgent
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
- `TalkieAgentStateMonitor.swift:172` - XPC callback handler `utteranceWasAdded()`
- `EngineClient.swift` - How Talkie calls the engine hosted inside TalkieAgent (set priority here)
- `Router.swift` - URL scheme routing (`talkie://...`)

---

## Shared Packages (Monorepo)

Talkie uses **4 local engine/shared components** developed in the monorepo:

### 1. **TalkieKit** - Shared Components
**Location**: `apps/macos/TalkieKit/` *(not in `/packages/swift/`)*
**Purpose**: Shared components used across Talkie, TalkieAgent, and TalkieEngineCore

**Features**:
- **Console** - System console viewer (`ConsoleView.swift`)
- **AudioPlayer** - Seekable waveform player (`AudioPlaybackManager.swift`)
- **SharedSettings** - Cross-app settings sync
- **TalkieEnvironment** - Environment detection (dev/staging/prod)
- **UI Components** - LivePill status indicator

**Used by**: Talkie, TalkieAgent, TalkieEngineCore

**Why separate from `/packages/swift/`**: App-specific shared code, tightly coupled to Talkie's architecture

### 2. **DebugKit** - Debugging Toolkit
**Location**: `/packages/swift/DebugKit/`
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
**Location**: `/packages/swift/WFKit/`
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
cd packages/swift/WFKit
swift run Workflow  # Standalone demo
```

### 4. **TalkieEngineCore** - Embedded Engine Runtime
**Location**: `apps/macos/TalkieEngineCore/`
**Purpose**: Engine implementation embedded inside TalkieAgent

**Features**:
- Batch transcription and model management
- Embedded runtime lifecycle for TalkieAgent
- Optional WebSocket bridge support
- Streaming ASR hosted directly inside `TalkieEngineCore`

**Used by**: TalkieAgent

**Dependency Chain**:
```
Talkie, TalkieAgent
  ├─→ TalkieKit (shared components)
  └─→ DebugKit (debug tools)

TalkieAgent
  └─→ TalkieEngineCore

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

**See**: `/packages/swift/README.md` for DebugKit/WFKit workflow

---

## Essential Scripts

### Build & Run
```bash
# Run each app individually (from repo root)
./apps/macos/Talkie/run.sh              # Main UI
./apps/macos/TalkieAgent/run.sh          # Menu bar recorder

# Or run both together
./apps/macos/run.sh                     # Launches TalkieAgent + Talkie

# Build release
cd apps/macos/Talkie
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
```

### Common Workflows
```bash
# Debug mode with CLI command
./apps/macos/Talkie/run.sh --debug=settings-screenshots ~/Desktop/screenshots

# Create app icon
./scripts/create-app-icon.sh icon.png
```

### Build, Sign, Notarize & Release

**Location**: `packaging/macos/build.sh` (656-line comprehensive script)

```bash
# Unified DMG
./packaging/macos/build.sh --version {{VERSION}}

# Fast iteration (skip clean build, reuse exports)
SKIP_CLEAN=1 ./packaging/macos/build.sh --version {{VERSION}}

# Skip notarization (for local testing)
SKIP_NOTARIZE=1 ./packaging/macos/build.sh --version {{VERSION}}

# Interactive release (pre-flight checks + confirmation)
./packaging/macos/release.sh {{VERSION}}
```

**Process**:
1. Verify signing identities (Developer ID App + Installer)
2. Build Talkie + TalkieAgent (Release, arm64, signed)
3. Create component packages (.pkg)
4. Sign distribution packages (productsign)
5. Notarize (xcrun notarytool with "notarytool" profile)
6. Staple ticket (xcrun stapler)
7. Archive to `packaging/macos/releases/{{VERSION}}/`

**Output**:
- `Talkie-for-Mac.pkg` - Full installer (Talkie + TalkieAgent)
- `Talkie-Unified.pkg` - Single bundle with helpers embedded
- `Talkie-Core.pkg` - Talkie + TalkieAgent core install
- `Talkie-Live.pkg` - TalkieAgent-only live dictation install

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
   - Recording issues → `TalkieAgent/App/LiveController.swift`
   - Transcription issues → `TalkieEngineCore/Sources/TalkieEngineCore/EngineService.swift`
   - Embedded engine lifecycle / bridge gating → `TalkieAgent/Services/EmbeddedEngineCoordinator.swift`
   - UI display issues → `Talkie/Views/Live/DictationListView.swift`
   - Database issues → `LiveDatabase.swift` (either TalkieAgent or Talkie)

2. **Debug Tools**:
   - TalkieAgent logs: `~/Library/Logs/TalkieAgent/TalkieAgent.log`
   - Database: `sqlite3 ~/Library/Application\ Support/Talkie/live.sqlite`
   - Unified engine/XPC logs: `log show --predicate 'subsystem == "to.talkie.app.mac"' --last 5m`

3. **Common Issues**:
   - **Slow transcription during builds** → Check priority (should be `.high` in TalkieAgent) and whether the embedded engine has finished warming up
   - **Dictations not updating** → Check XPC connection (`TalkieAgentStateMonitor.isXPCConnected`)
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
   # Filter by subsystem: "to.talkie.app.performance"
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
| `~/Library/Application Support/Talkie/live.sqlite` | Live dictations database | TalkieAgent (RW), Talkie (RW) |
| `~/Library/Application Support/Talkie/Audio/` | Audio files (uuid.m4a) | TalkieAgent (RW), Talkie (R) |
| `~/Library/Application Support/Talkie/WhisperModels/` | Downloaded ML models | TalkieAgent / TalkieEngineCore |
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
- **XPC for real-time**: State updates, callbacks, interactive requests between Talkie and TalkieAgent
- **Database for async**: Persistence, works when apps are closed
- **No tight coupling**: TalkieAgent can run without Talkie
- **Bridge only when needed**: Socket bridge stays off unless remote engine access is enabled

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
- **Bun preferred** - For Node.js projects
- **Gitmoji in commits** - Add emoji prefixes (✨ features, 🐛 bugs, ⚡️ performance)

---

## Key Documentation

- **This file** (`apps/macos/AGENTS.md`) - Start here
- `apps/macos/Talkie/ARCHITECTURE_REVIEW.md` - SwiftUI performance patterns
- `apps/macos/Talkie/DESIGN_SYSTEM_REVIEW.md` - Design tokens, compliance
- `apps/macos/TalkieKit/Sources/TalkieKit/XPCProtocols.swift` - Priority system (see comments)
- `apps/macos/Talkie/CLAUDE.md` - Build commands, project-specific conventions
- `/CLAUDE.md` (repo root) - Workspace-wide conventions

---

## Quick Reference

### "Where do I find...?"

| What | Where |
|------|-------|
| Recording logic | `TalkieAgent/App/LiveController.swift` |
| Embedded engine host | `TalkieAgent/Services/EmbeddedEngineCoordinator.swift` |
| Transcription | `TalkieEngineCore/Sources/TalkieEngineCore/EngineService.swift` |
| Priority system | `TalkieKit/Sources/TalkieKit/XPCProtocols.swift` (see `TranscriptionPriority`) |
| Live dictations UI | `Talkie/Views/Live/DictationListView.swift` |
| Dictation data store | `Talkie/Stores/DictationStore.swift` |
| Shared database | `LiveDatabase.swift` (in both TalkieAgent and Talkie) |
| XPC callbacks | `Talkie/Services/TalkieAgentStateMonitor.swift` |
| Engine client | `Talkie/Services/EngineClient.swift` |
| Startup phases | `Talkie/App/StartupCoordinator.swift` |
| Workflow executor | `Talkie/Workflow/WorkflowExecutor.swift` |
| Debug toolbar | `Talkie/Views/DebugToolbar.swift` (uses `/packages/swift/DebugKit/`) |
| Design tools | `Talkie/Debug/DesignMode/` |
| Settings | `Talkie/Services/SettingsManager.swift` |
| CloudKit sync | `Talkie/Services/CloudKitSyncManager.swift` |
| TalkieKit package | `apps/macos/TalkieKit/` (shared components for Talkie, TalkieAgent, and TalkieEngineCore) |
| TalkieEngineCore package | `apps/macos/TalkieEngineCore/` |
| DebugKit package | `/packages/swift/DebugKit/` (debug components) |
| WFKit package | `/packages/swift/WFKit/` (workflow editor library) |
| TalkieLogger | `TalkieKit/Sources/TalkieKit/Logging/TalkieLogger.swift` |

### "How do I...?"

| Task | Command/File |
|------|--------------|
| Run Talkie | `./apps/macos/Talkie/run.sh` |
| Run TalkieAgent | `./apps/macos/TalkieAgent/run.sh` |
| Run WFKit demo | `cd packages/swift/WFKit && swift run Workflow` |
| Test DebugKit changes | Make changes in `/packages/swift/DebugKit/`, build Talkie |
| Build release installer | `./packaging/macos/build.sh --version {{VERSION}}` |
| Build unified bundle | `./packaging/macos/build.sh unified --version {{VERSION}}` |
| Interactive release | `./packaging/macos/release.sh {{VERSION}}` |
| Sync Xcode project | `./scripts/sync-xcode-files.py` |
| Profile startup | Instruments → os_signpost → filter "to.talkie.app.performance" |
| Toggle Design Mode | Press ⌘⇧D |
| Check DB | `sqlite3 ~/Library/Application\ Support/Talkie/live.sqlite` |
| Find build output | `./scripts/find-build.sh` |

---

**Last Updated**: 2026-04-11
**Major Topics**: 2-app process model, embedded engine runtime, priority system, lazy loading, toolbars, packages (TalkieKit, TalkieEngineCore, DebugKit, WFKit)
