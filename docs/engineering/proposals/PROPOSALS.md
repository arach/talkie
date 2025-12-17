# Architecture Improvement Proposals

> Last updated: December 2025

This document contains detailed proposals for architecture improvements identified in [ARCHITECTURE.md](../ARCHITECTURE.md). Each proposal maps to items in the "Future Considerations" section and is ordered by risk (safest first).

---

## Mapping to Architecture Doc

| Proposal | Architecture Doc Reference |
|----------|---------------------------|
| 001 | "Data Flow Documentation" in Future Considerations |
| 002 | "Data Flow Documentation" - logging aspect |
| 003 | "Testing Considerations" section |
| 004 | Large view files (not explicitly listed, but general code health) |
| 005 | "Error Handling" patterns section |
| 006 | "Service Initialization" in Future Considerations |
| 007 | "Error Observability" in Future Considerations |
| 008 | "Settings Organization" in Future Considerations |
| 009 | "Concurrency" patterns - threading edge case |

---

## 001 - Document Data Flow Patterns

> Status: **Documented** | Maps to: Future Considerations → Data Flow Documentation

### Impact Assessment

| Category | Assessment |
|----------|------------|
| **Code Changes** | None (documentation only) |
| **Critical Path** | Not affected |
| **Performance** | No impact |
| **Rollback** | Trivial |

### Problem

The codebase uses two patterns for view-service communication without explicit guidance:
- Direct singleton observation: `@ObservedObject private var store = UtteranceStore.shared`
- NotificationCenter: `.onReceive(NotificationCenter.default.publisher(for: .transcriptionComplete))`

New contributors don't know which to use when.

### Implementation

**Already implemented** - Added to ARCHITECTURE.md section 3 "View-Service Communication" with:
- Pattern descriptions with code examples
- Decision guide flowchart
- List of current notification names
- Anti-patterns to avoid

---

## 002 - Unify Logging (TalkieLive)

> Status: **Proposed** | Maps to: Future Considerations → Data Flow Documentation (observability aspect)

### Impact Assessment

| Category | Assessment |
|----------|------------|
| **Code Changes** | Moderate - consolidate logging + build log viewer |
| **Critical Path** | Not affected (logging is fire-and-forget) |
| **Performance** | Slight improvement (remove duplicate work) |
| **Rollback** | Easy (git revert) |

### Problem

TalkieLive has two logging systems that sometimes log the same event:

```swift
// In LiveController.swift - BOTH are called for the same error:
logger.error("Transcription failed: \(error)")
SystemEventManager.shared.log(.error, "Transcription failed", detail: "\(error)")
```

**Current logging systems:**

1. **os.log (Logger)** - Apple's structured logging
   - Goes to Console.app (which is hard to use)
   - Filterable by subsystem/category
   - Used throughout: `Logger(subsystem: "jdi.talkie.live", category: "LiveController")`

2. **SystemEventManager** - Custom event logger
   - Stores events in memory
   - Can display in debug UI
   - Provides convenient in-app viewing

### Proposed Solution

**Consolidate on os.log + Build In-App Log Viewer**

Use `Logger` as the single logging mechanism, but build a nice in-app log viewer using `OSLogStore` (available since macOS 10.15). This gives us:
- Single source of truth (os.log)
- Structured logging with categories
- **In-app viewer** with tail + grep + filters (no Console.app needed)

### Architecture

```swift
// 1. All logging goes through Logger (no change to existing pattern)
private let logger = Logger(subsystem: "jdi.talkie.live", category: "LiveController")
logger.info("Transcription started")
logger.error("Transcription failed: \(error)")

// 2. New: LogViewer reads from OSLogStore
@MainActor
final class LogViewer: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    @Published var filter: LogFilter = .all

    private let subsystem = "jdi.talkie.live"

    struct LogEntry: Identifiable {
        let id: UUID
        let timestamp: Date
        let level: OSLogEntryLog.Level
        let category: String
        let message: String
    }

    struct LogFilter {
        var level: OSLogEntryLog.Level?
        var category: String?
        var searchText: String?

        static let all = LogFilter()
    }

    func refresh() async {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(timeIntervalSinceEnd: -300) // Last 5 min

            let entries = try store
                .getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == subsystem }
                .map { entry in
                    LogEntry(
                        id: UUID(),
                        timestamp: entry.date,
                        level: entry.level,
                        category: entry.category,
                        message: entry.composedMessage
                    )
                }

            self.entries = applyFilter(entries)
        } catch {
            // Handle error
        }
    }

    private func applyFilter(_ entries: [LogEntry]) -> [LogEntry] {
        entries.filter { entry in
            if let level = filter.level, entry.level.rawValue < level.rawValue {
                return false
            }
            if let category = filter.category, entry.category != category {
                return false
            }
            if let search = filter.searchText, !search.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(search)
            }
            return true
        }
    }
}
```

### Log Viewer UI Features

```swift
struct LogViewerView: View {
    @StateObject private var viewer = LogViewer()
    @State private var searchText = ""
    @State private var selectedLevel: OSLogEntryLog.Level? = nil
    @State private var selectedCategory: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                // Search (grep equivalent)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                // Level filter
                Picker("Level", selection: $selectedLevel) {
                    Text("All").tag(nil as OSLogEntryLog.Level?)
                    Text("Error").tag(OSLogEntryLog.Level.error)
                    Text("Info").tag(OSLogEntryLog.Level.info)
                    Text("Debug").tag(OSLogEntryLog.Level.debug)
                }

                // Category filter
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(nil as String?)
                    Text("LiveController").tag("LiveController" as String?)
                    Text("Audio").tag("Audio" as String?)
                    Text("Engine").tag("Engine" as String?)
                }

                // Refresh
                Button(action: { Task { await viewer.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            // Log entries (tail equivalent)
            List(viewer.entries) { entry in
                LogEntryRow(entry: entry)
            }
        }
        .task {
            await viewer.refresh()
        }
    }
}

struct LogEntryRow: View {
    let entry: LogViewer.LogEntry

    var body: some View {
        HStack {
            // Timestamp
            Text(entry.timestamp, style: .time)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)

            // Level indicator
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)

            // Category
            Text(entry.category)
                .font(.caption.monospaced())
                .foregroundColor(.secondary)

            // Message
            Text(entry.message)
                .font(.body.monospaced())
        }
    }

    var levelColor: Color {
        switch entry.level {
        case .error: return .red
        case .fault: return .red
        case .info: return .blue
        case .debug: return .gray
        default: return .secondary
        }
    }
}
```

### Files to Change

**Remove/Refactor:**
- `TalkieLive/Services/SystemEventManager.swift` → Delete or repurpose

**Audit for duplicate logging:**
- `TalkieLive/App/LiveController.swift`
- `TalkieLive/App/AppDelegate.swift`
- `TalkieLive/Services/EngineClient.swift`
- `TalkieLive/Services/Audio/AudioCapture.swift`

**Create:**
- `TalkieLive/Debug/LogViewer.swift` - OSLogStore reader
- `TalkieLive/Debug/LogViewerView.swift` - SwiftUI log viewer

### Implementation Steps

1. [ ] Create `LogViewer` class using OSLogStore
2. [ ] Create `LogViewerView` with search/filter UI
3. [ ] Add log viewer to app (Settings → Debug section, or dedicated view)
4. [ ] Grep for `SystemEventManager.shared.log` - list all occurrences
5. [ ] Remove duplicate logging calls (keep `logger.` calls)
6. [ ] Remove or deprecate `SystemEventManager`
7. [ ] Test log viewer shows entries correctly
8. [ ] Test filters (level, category, search) work

### Notes

- `OSLogStore` requires macOS 10.15+ (we're on 14+, so fine)
- Logs are read-only from OSLogStore (can't delete)
- Consider auto-refresh option (poll every N seconds)
- Could add "Copy logs" button for bug reports

---

## 003 - Add Test Seams

> Status: **Proposed** | Maps to: Testing Considerations section

### Impact Assessment

| Category | Assessment |
|----------|------------|
| **Code Changes** | Minor - add `#if DEBUG` blocks |
| **Critical Path** | Not affected (DEBUG code stripped in release) |
| **Performance** | No impact in release builds |
| **Rollback** | Easy (remove DEBUG blocks) |

### Problem

Singleton pattern with `private init()` prevents testing:

```swift
// Current - can't reset or mock
@MainActor
final class LiveSettings: ObservableObject {
    static let shared = LiveSettings()
    private init() { /* loads from UserDefaults */ }
}

// In tests - stuck with whatever state exists
func testSomething() {
    // LiveSettings.shared already has state from previous tests
    // Can't inject mock settings
}
```

### Proposed Solution

Add DEBUG-only reset capability:

```swift
@MainActor
final class LiveSettings: ObservableObject {
    static var shared = LiveSettings()  // var instead of let
    private init() { /* ... */ }

    #if DEBUG
    /// Reset to fresh state for testing
    static func resetForTesting() {
        shared = LiveSettings()
    }

    /// Configure with specific values for testing
    static func configureForTesting(
        selectedModelId: String = "default",
        routingMode: RoutingMode = .clipboard
    ) {
        resetForTesting()
        shared.selectedModelId = selectedModelId
        shared.routingMode = routingMode
    }
    #endif
}
```

### Singletons to Add Test Seams

| Singleton | Location | Priority |
|-----------|----------|----------|
| `LiveSettings` | `TalkieLive/Models/LiveSettings.swift` | High |
| `UtteranceStore` | `TalkieLive/Stores/UtteranceStore.swift` | High |
| `LiveController` | `TalkieLive/App/LiveController.swift` | Medium |
| `SettingsManager` | `Talkie/Services/SettingsManager.swift` | Medium |

### Implementation Steps

1. [ ] Change `static let shared` to `static var shared` in target files
2. [ ] Add `#if DEBUG` block with `resetForTesting()`
3. [ ] Add `configureForTesting()` with common test configurations
4. [ ] Create `TestUtilities.swift` documenting the pattern
5. [ ] Verify release builds don't include DEBUG code

---

## 004 - Decompose Large View Files

> Status: **Proposed** | Maps to: General code health

### Impact Assessment

| Category | Assessment |
|----------|------------|
| **Code Changes** | Moderate - file reorganization |
| **Critical Path** | Not affected (UI layer only) |
| **Performance** | Possible slight improvement (smaller compilation units) |
| **Rollback** | Moderate (need to recombine) |

### Problem

Several TalkieLive view files are very large:

| File | Size | Approx Lines |
|------|------|--------------|
| `Views/HistoryView.swift` | 142 KB | ~4000 |
| `Views/Settings/SettingsView.swift` | 120 KB | ~3500 |
| `Views/OnboardingView.swift` | 83 KB | ~2400 |
| `Views/HomeView.swift` | 59 KB | ~1700 |

Large files are hard to navigate, slow to compile, and difficult to review in PRs.

### Proposed Solution

Extract logical sections into subviews. Example for SettingsView:

**Before:**
```
Views/Settings/
└── SettingsView.swift (3500 lines - everything)
```

**After:**
```
Views/Settings/
├── SettingsView.swift           (~150 lines - container + navigation)
├── GeneralSettingsSection.swift (~400 lines)
├── AudioSettingsSection.swift   (~500 lines)
├── ModelSettingsSection.swift   (~600 lines)
├── PermissionsSettingsSection.swift (already exists)
└── AdvancedSettingsSection.swift (~400 lines)
```

**SettingsView.swift becomes a thin coordinator:**
```swift
struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsSection()
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)

            AudioSettingsSection()
                .tabItem { Label("Audio", systemImage: "waveform") }
                .tag(SettingsTab.audio)

            // ... etc
        }
    }
}
```

### Implementation Steps (per file)

1. [ ] Read file, identify logical sections (look for `// MARK:` comments)
2. [ ] Create new file for first section
3. [ ] Move code, keeping all dependencies
4. [ ] Build and verify no errors
5. [ ] Test the UI still works
6. [ ] Commit
7. [ ] Repeat for next section

### Suggested Order

1. **SettingsView** - Already has clear tab structure
2. **HistoryView** - Likely has list/detail/search sections
3. **HomeView** - Evaluate structure first
4. **OnboardingView** - Likely has step-based sections

---

## 005 - Audit `try?` Usage

> Status: **Proposed** | Maps to: Error Handling patterns

### Impact Assessment

| Category | Assessment |
|----------|------------|
| **Code Changes** | Moderate - add do/catch blocks |
| **Critical Path** | ⚠️ Some occurrences are on critical path |
| **Performance** | Negligible |
| **Rollback** | Easy |

### Problem

~178 `try?` occurrences silently swallow errors:

```swift
// Silent failure - if this fails, we have no idea why
_ = keychain.save(apiKey, for: .openAI)

// Silent failure - task might not start
try? task.run()
```

### Categorization Framework

**Category A: Keep as `try?`** (truly ignorable)
```swift
// Sleep failures are fine
try? await Task.sleep(for: .milliseconds(100))

// Optional cleanup in defer
defer { try? tempFile.delete() }
```

**Category B: Add logging** (should know if it fails)
```swift
// Before
_ = keychain.save(apiKey, for: .openAI)

// After
do {
    try keychain.save(apiKey, for: .openAI)
} catch {
    logger.error("Failed to save API key: \(error)")
}
```

**Category C: Propagate error** (caller needs to know)
```swift
// Before
func saveSettings() {
    try? persistToDisk()  // Silent failure
}

// After
func saveSettings() throws {
    try persistToDisk()  // Caller handles
}
```

### High-Priority Files (Critical Path)

These need careful review before changes:

| File | Why Critical |
|------|--------------|
| `LiveController.swift` | Core transcription pipeline |
| `EngineClient.swift` | XPC communication |
| `AudioCapture.swift` | Audio recording |
| `TranscriptRouter.swift` | Output routing |

### Implementation Steps

1. [ ] Run: `grep -r "try?" --include="*.swift" TalkieLive/ | wc -l` to get count
2. [ ] Export list with context: `grep -r -n "try?" --include="*.swift" TalkieLive/`
3. [ ] Categorize each into A/B/C in a spreadsheet
4. [ ] Review critical path items with extra scrutiny
5. [ ] Implement Category B changes first (safest)
6. [ ] Test thoroughly
7. [ ] Implement Category C changes if appropriate

---

## 006 - Standardize Service Initialization

> Status: **Proposed** | Maps to: Future Considerations → Service Initialization

### Impact Assessment

| Category | Assessment |
|----------|------------|
| **Code Changes** | Moderate - refactor init patterns |
| **Critical Path** | ⚠️ Startup sequence affects time-to-ready |
| **Performance** | Could improve or regress - needs measurement |
| **Rollback** | Moderate |

### Problem

Three different init patterns exist:

**Pattern 1: Eager (auto-start)**
```swift
// LiveDataStore - does work in init
private init() {
    connectToDatabase()  // Immediately queries filesystem
    startRefreshTimer()  // Starts timer
}
```

**Pattern 2: Lazy (explicit start)**
```swift
// TalkieServiceMonitor - does nothing until called
private init() {
    logger.info("Monitor initialized (lazy)")
}

func startMonitoring() {
    // Actual work here
}
```

**Pattern 3: Configured (needs external data)**
```swift
// CloudKitSyncManager - needs context passed in
private init() {}

func configure(with context: NSManagedObjectContext) {
    self.context = context
    // Now can start working
}
```

This inconsistency makes it unclear:
- When services become active
- What order they initialize
- What depends on what

### Proposed Solution

Standardize on **lazy with explicit start**:

```swift
@MainActor
final class SomeService: ObservableObject {
    static let shared = SomeService()

    @Published private(set) var isRunning = false

    private init() {
        // ONLY store references, no side effects
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        // Do actual initialization
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        // Cleanup
    }
}
```

**Create explicit boot sequence:**

```swift
// App/BootSequence.swift
@MainActor
enum BootSequence {
    static func boot() async {
        // Phase 1: Infrastructure (no dependencies)
        _ = PersistenceController.shared

        // Phase 2: Settings
        await LiveSettings.shared.start()

        // Phase 3: Services (depend on settings)
        await EngineClient.shared.start()
        await UtteranceStore.shared.start()

        // Phase 4: Monitors (depend on services)
        AudioDeviceManager.shared.startMonitoring()
    }
}

// In AppDelegate
func applicationDidFinishLaunching(_ notification: Notification) {
    Task {
        await BootSequence.boot()
        // Now safe to show UI
    }
}
```

### Services to Refactor

| Service | Current Pattern | Change Needed |
|---------|-----------------|---------------|
| `LiveSettings` | Eager | Add `start()` |
| `UtteranceStore` | Eager | Add `start()` |
| `LiveDataStore` | Eager | Add `start()` |
| `EngineClient` | Configured | Standardize to `start()` |
| `AudioDeviceManager` | Lazy | Already correct |

### Implementation Steps

1. [ ] Document current actual initialization order (add logging)
2. [ ] Map dependencies between services
3. [ ] Create `BootSequence.swift` with current implicit order
4. [ ] Refactor one service at a time to new pattern
5. [ ] Measure startup time before/after
6. [ ] Test cold start thoroughly

---

## 007 - Observable Error State

> Status: **Proposed** | Maps to: Future Considerations → Error Observability

### Impact Assessment

| Category | Assessment |
|----------|------------|
| **Code Changes** | Moderate |
| **Critical Path** | ⚠️ Errors occur on critical path |
| **Performance** | Minimal (one @Published property) |
| **Rollback** | Easy |

### Problem

Errors are logged but not shown to users:

```swift
// Current: User sees nothing when this fails
catch {
    logger.error("Transcription failed: \(error)")
    // No UI update - user just sees... nothing happening
}
```

User can't distinguish:
- Still processing vs failed
- Transient error vs persistent problem
- Whether retry would help

### Proposed Solution

Add observable error state to `LiveController`:

```swift
@MainActor
final class LiveController: ObservableObject {
    // Existing
    @Published private(set) var state: LiveState = .idle

    // New
    @Published private(set) var lastError: LiveError?

    struct LiveError: Identifiable, Equatable {
        let id: UUID
        let message: String
        let timestamp: Date
        let category: ErrorCategory
        let isRecoverable: Bool

        enum ErrorCategory {
            case transcription
            case engine
            case audio
            case routing
        }
    }

    func clearError() {
        lastError = nil
    }

    // In catch blocks:
    private func handleError(_ error: Error, category: LiveError.ErrorCategory) {
        logger.error("\(category): \(error)")
        lastError = LiveError(
            id: UUID(),
            message: error.localizedDescription,
            timestamp: Date(),
            category: category,
            isRecoverable: true  // or determine from error type
        )
    }
}
```

**UI Integration (FloatingPill):**
```swift
struct FloatingPill: View {
    @ObservedObject var controller = LiveController.shared

    var body: some View {
        PillShape()
            .overlay {
                if let error = controller.lastError {
                    ErrorIndicator(error: error)
                } else {
                    NormalContent()
                }
            }
    }
}
```

### Design Decisions Needed

1. **Auto-dismiss?** Should errors clear after N seconds or require explicit dismiss?
2. **Display style?** Inline in pill vs alert vs toast?
3. **Error indicator?** Red tint on pill? Icon? Text?
4. **Clear on success?** Should next successful transcription clear the error?

### Implementation Steps

1. [ ] Define `LiveError` struct
2. [ ] Add `@Published lastError` to LiveController
3. [ ] Create `handleError()` helper method
4. [ ] Update catch blocks to use `handleError()`
5. [ ] Add error indicator to FloatingPill
6. [ ] Add error display to HomeView
7. [ ] Test various error scenarios
8. [ ] Decide on auto-dismiss behavior

---

## 008 - Split SettingsManager

> Status: **Proposed** | Maps to: Future Considerations → Settings Organization

### Impact Assessment

| Category | Assessment |
|----------|------------|
| **Code Changes** | Significant - refactor 1400 line file |
| **Critical Path** | ⚠️ Theme colors read on every render |
| **Performance** | Must maintain or improve - theme access is hot path |
| **Rollback** | Difficult (many file references) |

### Problem

`Talkie/Services/SettingsManager.swift` (~1400 lines) handles too much:

- User preferences (~30 @Published properties)
- Theme calculations (~200 lines of computed colors)
- Font calculations
- API key management (Keychain)
- Settings migration
- Batching logic for theme updates

### Current Structure (simplified)

```swift
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // === User Preferences ===
    @Published var appearanceMode: AppearanceMode
    @Published var uiFontSize: FontSizeOption
    @Published var accentColor: AccentColorOption
    // ... 25+ more @Published properties

    // === Theme Calculations ===
    var background: Color { /* complex calculation */ }
    var foreground: Color { /* ... */ }
    var tacticalBackground: Color { /* ... */ }
    // ... 50+ computed color properties

    // === Font Calculations ===
    var bodyFont: Font { /* ... */ }
    var headingFont: Font { /* ... */ }
    // ... 20+ font properties

    // === API Keys ===
    func saveApiKey(_ key: String, for provider: Provider) { /* keychain */ }
    func apiKey(for provider: Provider) -> String? { /* keychain */ }

    // === Migration ===
    private func migrateFromLegacySettings() { /* 150 lines */ }

    // === Batching ===
    private var isBatchingUpdates = false  // Anti-pattern
}
```

### Proposed Structure

```
Talkie/Services/Settings/
├── SettingsManager.swift       # Core preferences only (~300 lines)
├── ThemeManager.swift          # Colors, computed theme values (~400 lines)
├── FontManager.swift           # Font calculations (~200 lines)
├── APIKeyManager.swift         # Keychain operations (~150 lines)
└── SettingsMigration.swift     # One-time migration (~150 lines)
```

**SettingsManager (slimmed):**
```swift
@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // Raw preference values only
    @Published var appearanceMode: AppearanceMode
    @Published var uiFontSize: FontSizeOption
    @Published var accentColor: AccentColorOption
    // ... other user-facing settings

    private init() {
        SettingsMigration.runIfNeeded()
        // Load preferences from UserDefaults
    }
}
```

**ThemeManager (new):**
```swift
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    // Cached computed values
    private(set) var background: Color
    private(set) var foreground: Color
    // ... etc

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Calculate initial values
        recalculate()

        // Observe settings changes
        SettingsManager.shared.$appearanceMode
            .sink { [weak self] _ in self?.recalculate() }
            .store(in: &cancellables)
    }

    private func recalculate() {
        // Batch all updates
        background = calculateBackground()
        foreground = calculateForeground()
        // ...
    }
}
```

### Migration Strategy

1. **Phase 1:** Extract `SettingsMigration` (lowest coupling)
2. **Phase 2:** Extract `APIKeyManager` (moderate coupling)
3. **Phase 3:** Extract `FontManager` (used by many views)
4. **Phase 4:** Extract `ThemeManager` (highest coupling - touches everything)

### Performance Considerations

- Theme colors are accessed on every view render
- Current: Computed on access (potentially recalculated often)
- Proposed: Cached, recalculated only when settings change
- **Must verify:** No performance regression in view rendering

### Implementation Steps

1. [ ] Analyze which views use which SettingsManager properties
2. [ ] Create `Settings/` subdirectory
3. [ ] Extract `SettingsMigration.swift` - test migrations still work
4. [ ] Extract `APIKeyManager.swift` - test API key storage
5. [ ] Extract `FontManager.swift` - test font rendering
6. [ ] Extract `ThemeManager.swift` - test theme changes
7. [ ] Update all import statements
8. [ ] Profile view rendering performance before/after

---

## 009 - Hotkey Threading Safety

> Status: **Proposed** | Maps to: Concurrency patterns

### Impact Assessment

| Category | Assessment |
|----------|------------|
| **Code Changes** | Small but critical |
| **Critical Path** | ⚠️ **THE entry point** - hotkey triggers everything |
| **Performance** | Must not add perceptible latency |
| **Rollback** | Easy |

### Problem

Carbon hotkey callbacks run on system threads, but our code assumes @MainActor:

```swift
// This C function is called by Carbon - on ANY thread
func globalHotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    // We're on a system thread here!
    HotKeyRegistry.shared.handleEvent(event)  // Calls into Swift
    return noErr
}
```

```swift
// In HotKeyRegistry or HotKeyManager
func handleEvent(_ event: EventRef?) {
    // Still on system thread!
    Task { @MainActor in
        // NOW we're on main... but there's a gap
        await liveController.toggleListening()
    }
}
```

**Race condition:** If user presses hotkey twice rapidly:
1. First event: Task queued to main thread
2. Second event: Another Task queued
3. Both execute, both try to toggle state
4. State corruption possible

### Current Flow

```
User presses hotkey
    ↓
Carbon posts event (system thread)
    ↓
globalHotKeyEventHandler() ← runs on unknown thread
    ↓
HotKeyRegistry.handleEvent() ← still on unknown thread
    ↓
Task { @MainActor in ... } ← dispatch to main
    ↓
[... time gap - not serialized ...]
    ↓
LiveController.toggleListening() ← finally on main
```

### Proposed Solution

**Option A: Guard in LiveController (Simplest)**

```swift
@MainActor
final class LiveController: ObservableObject {
    private var isTransitioning = false

    func toggleListening() async {
        // Reject if already processing a toggle
        guard !isTransitioning else {
            logger.debug("Toggle rejected - already transitioning")
            return
        }

        isTransitioning = true
        defer { isTransitioning = false }

        // ... existing toggle logic
    }
}
```

**Option B: Debounce at Carbon level**

```swift
class HotKeyManager {
    private var lastEventTime: Date = .distantPast
    private let minimumInterval: TimeInterval = 0.2  // 200ms

    func handleEvent(_ event: EventRef?) {
        let now = Date()
        guard now.timeIntervalSince(lastEventTime) >= minimumInterval else {
            return  // Debounce - too fast
        }
        lastEventTime = now

        Task { @MainActor in
            await liveController.toggleListening()
        }
    }
}
```

**Option C: Serial dispatch queue**

```swift
class HotKeyManager {
    private let eventQueue = DispatchQueue(label: "live.talkie.hotkey")

    func handleEvent(_ event: EventRef?) {
        eventQueue.async {
            Task { @MainActor in
                await self.processEvent(event)
            }
        }
    }
}
```

### Recommendation

Start with **Option A** (guard in LiveController):
- Simplest change
- Protects against the race regardless of source
- Easy to verify works
- Can add Option B later if needed

### Testing Approach

1. Add logging to measure time between events:
   ```swift
   logger.debug("Hotkey event received at \(Date())")
   logger.debug("toggleListening entered at \(Date())")
   ```

2. Try to reproduce race:
   - Press hotkey rapidly (5+ times per second)
   - Use a macro/script to automate rapid presses

3. Verify guard works:
   - Confirm logs show rejected duplicate events
   - Confirm state doesn't corrupt

4. Measure latency:
   - Time from keypress to `toggleListening` entry
   - Before/after comparison
   - Target: <50ms added latency (imperceptible)

### Implementation Steps

1. [ ] Add detailed logging to current hotkey path
2. [ ] Attempt to reproduce race condition
3. [ ] If reproducible, implement Option A guard
4. [ ] If not reproducible, still add guard (defensive)
5. [ ] Measure latency impact
6. [ ] Test normal usage patterns
7. [ ] Test rapid hotkey scenarios
