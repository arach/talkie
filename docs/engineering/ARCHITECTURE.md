# Talkie macOS Architecture

> Last updated: December 2025

This document describes the architecture patterns used across the Talkie macOS apps (Talkie and TalkieLive). It serves as a guide for understanding the codebase and making consistent decisions when adding new features.

---

## Overview

The Talkie ecosystem consists of two macOS applications:

| App | Purpose | Key Responsibility |
|-----|---------|-------------------|
| **Talkie** | Main app | Voice memo management, workflows, transcription, AI processing |
| **TalkieLive** | Always-on companion | Real-time transcription, quick capture, floating UI |

Both apps share common patterns but have different architectural needs due to their distinct purposes.

---

## Directory Structure

### Talkie
```
Talkie/
├── App/           # Entry points (TalkieApp, AppDelegate)
├── Models/        # Core Data models, data types
├── Views/         # SwiftUI views, organized by feature
│   ├── Settings/  # Settings UI (split into focused files)
│   ├── Memos/     # Memo list and detail views
│   ├── Models/    # Model management views
│   └── ...
├── Services/      # Business logic, external integrations
│   ├── LLM/       # AI provider implementations
│   └── Migrations/# Data migration logic
├── Workflow/      # Workflow engine
├── Interstitial/  # Dictation overlay system
├── Design/        # Design system, theming
└── Resources/     # Static assets, configs
```

### TalkieLive
```
TalkieLive/
├── App/           # Entry points, LiveController, dependencies
├── Models/        # Settings, transcription types
├── Views/         # SwiftUI views
│   ├── Settings/  # Settings UI
│   ├── Overlay/   # Floating pill, recording overlay
│   └── Components/# Reusable components
├── Services/      # Business logic
│   └── Audio/     # Audio capture, playback, diagnostics
├── Stores/        # Observable state containers
├── Design/        # Design system
├── Database/      # GRDB database layer
└── Debug/         # Debug utilities
```

---

## Core Patterns

### 1. Singleton Services

Both apps use singleton services for app-scoped, long-lived resources:

```swift
@MainActor
final class ServiceName: ObservableObject {
    static let shared = ServiceName()
    private init() { }

    @Published private(set) var someState: SomeType
}
```

**Why singletons:**
- Services represent app-wide resources (settings, database, audio)
- Simple mental model - one instance, one source of truth
- No DI container complexity

**Guidelines:**
- All singletons should be `@MainActor` for thread safety
- Use `private init()` to enforce singleton pattern
- Expose state via `@Published` for SwiftUI reactivity
- Use `private(set)` for state that views shouldn't modify directly

**Current singletons (Talkie):** SettingsManager, CloudKitSyncManager, PersistenceController, EngineClient, WorkflowManager, and others

**Current singletons (TalkieLive):** LiveSettings, UtteranceStore, LiveController, EngineClient, AudioDeviceManager, and others

---

### 2. State Management

#### Pattern: @Published + ObservableObject

Services expose observable state:

```swift
@MainActor
final class LiveController: ObservableObject {
    @Published private(set) var state: LiveState = .idle
    @Published private(set) var currentUtterance: LiveUtterance?
}
```

Views observe this state:

```swift
struct HomeView: View {
    @ObservedObject private var controller = LiveController.shared

    var body: some View {
        // Reacts to controller.state changes
    }
}
```

#### State Machines (TalkieLive)

LiveController uses an explicit state machine:

```swift
enum LiveState {
    case idle
    case listening
    case transcribing
    case routing
}
```

State transitions are controlled through methods, not direct assignment.

---

### 3. View-Service Communication

**Primary pattern:** Direct singleton observation

```swift
struct SettingsView: View {
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        Toggle("Feature", isOn: $settings.featureEnabled)
    }
}
```

**Secondary pattern:** NotificationCenter for one-way events

```swift
// Service posts
NotificationCenter.default.post(name: .transcriptionComplete, object: nil)

// View observes
.onReceive(NotificationCenter.default.publisher(for: .transcriptionComplete)) { _ in
    // Handle event
}
```

**Guideline:** Prefer direct observation for state. Use notifications for discrete events that don't represent ongoing state.

---

### 4. Dependency Injection (TalkieLive)

TalkieLive uses constructor injection for its core controller:

```swift
// LiveDependencies.swift defines protocols
protocol LiveAudioCapture { ... }
protocol TranscriptionService { ... }
protocol LiveRouter { ... }

// AppDelegate constructs concrete implementations
let audio = MicrophoneCapture()
let transcription = EngineTranscriptionService(modelId: settings.selectedModelId)
let router = TranscriptRouter(mode: settings.routingMode)

liveController = LiveController(
    audio: audio,
    transcription: transcription,
    router: router
)
```

This allows for stub implementations during development/testing while keeping production initialization explicit.

---

### 5. Error Handling

#### Service Layer
Services throw typed errors:

```swift
enum EngineTranscriptionError: Error {
    case engineNotRunning
    case transcriptionFailed(String)
}

func transcribe() async throws -> Transcript {
    guard connected else {
        throw EngineTranscriptionError.engineNotRunning
    }
    // ...
}
```

#### Controller Layer
Controllers catch and handle errors, often storing failed operations for retry:

```swift
do {
    let transcript = try await transcription.transcribe(audio)
    // Success path
} catch {
    logger.error("Transcription failed: \(error)")
    await storeForRetry(audio, error: error)
}
```

#### Logging
All services use structured logging:

```swift
private let logger = Logger(subsystem: "jdi.talkie.core", category: "ServiceName")
```

---

### 6. Concurrency

#### @MainActor
All UI-facing services and controllers are `@MainActor`:

```swift
@MainActor
final class LiveController: ObservableObject { ... }
```

This ensures all state mutations happen on the main thread.

#### Async/Await
Long-running operations use async/await:

```swift
func process() async {
    state = .transcribing
    let result = try await transcriptionService.transcribe(audio)
    state = .routing
    await router.route(result)
    state = .idle
}
```

#### Background Work
For work that shouldn't block UI, use Task with explicit actor isolation:

```swift
Task { @MainActor in
    await heavyOperation()
}
```

---

### 7. Data Persistence

#### Core Data (Talkie)
- `PersistenceController` manages the Core Data stack
- CloudKit sync via `NSPersistentCloudKitContainer`
- Views access context via `@Environment(\.managedObjectContext)`

#### GRDB (TalkieLive)
- `LiveDatabase` manages SQLite via GRDB
- `UtteranceStore` provides observable access to data
- Simpler than Core Data, appropriate for TalkieLive's needs

---

### 8. Design System

Both apps share a design system pattern:

```swift
// Design/DesignSystem.swift
struct Theme {
    static var background: Color { ... }
    static var foreground: Color { ... }
    static var accent: Color { ... }
}
```

Settings-driven theming allows user customization while maintaining consistency.

---

## App-Specific Patterns

### TalkieLive: Critical Path

The transcription pipeline is latency-sensitive:

```
Hotkey → Audio Capture → Transcription → Routing → Paste
```

**Performance considerations:**
- Audio capture starts immediately on hotkey
- Transcription uses pre-loaded models when possible
- Routing (paste) happens as soon as text is ready
- Context enrichment happens async, after the critical path

### Talkie: Workflow Engine

Workflows are composable action sequences:

```
Trigger → Action 1 → Action 2 → ... → Output
```

Defined in `Workflow/` with separate files for:
- `WorkflowDefinition.swift` - Data model
- `WorkflowExecutor.swift` - Runtime execution
- `WorkflowViews.swift` - UI components

---

## Testing Considerations

Current architecture uses singletons which requires care in testing:

```swift
// For unit tests, singletons can be reset
#if DEBUG
extension SettingsManager {
    static func resetForTesting() {
        shared = SettingsManager()
    }
}
#endif
```

Protocol-based dependencies (like in TalkieLive's LiveController) enable mock injection.

---

## Future Considerations

The following areas have been identified for potential refinement. Each should be evaluated carefully before implementation:

### Error Observability
Currently errors are logged but not always surfaced to UI. Consider adding observable error state to key controllers.

### Settings Organization
SettingsManager in Talkie is large (~1400 lines). Could potentially be split into focused managers (theme, API keys, preferences).

### Service Initialization
Some services auto-initialize, others require explicit start. Documenting or standardizing the boot sequence could improve clarity.

### Data Flow Documentation
The mix of direct observation and NotificationCenter could be documented more explicitly to help new contributors understand when to use each.

---

## Contributing

When adding new features:

1. **Follow existing patterns** - Consistency matters more than perfection
2. **Use @MainActor** for anything touching UI state
3. **Log meaningfully** - Use the structured logger with appropriate category
4. **Consider the critical path** - Don't add latency to transcription pipeline
5. **Test on device** - Performance characteristics differ from Simulator

---

## Appendix: Key Files

| File | Purpose |
|------|---------|
| `Talkie/App/AppDelegate.swift` | App initialization, CloudKit setup |
| `Talkie/Services/SettingsManager.swift` | User preferences, theming |
| `TalkieLive/App/LiveController.swift` | Core state machine, transcription pipeline |
| `TalkieLive/App/LiveDependencies.swift` | Protocol definitions for DI |
| `TalkieLive/Services/HotKeyManager.swift` | Global hotkey handling |

---

## Proposals

Architecture improvement proposals are tracked in `proposals/PROPOSALS.md`:

| # | Proposal | Status |
|---|----------|--------|
| 001 | Data Flow Patterns | Documented |
| 002 | Unify Logging | Proposed |
| 003 | Test Seams | Proposed |
| 004 | Decompose Large Views | Proposed |
| 005 | Audit try? Usage | Proposed |
| 006 | Standardize Service Init | Proposed |
| 007 | Observable Error State | Proposed |
| 008 | Split SettingsManager | Proposed |
| 009 | Hotkey Threading Safety | Proposed |
