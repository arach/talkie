# Talkie System Architecture
**Quick reference for understanding the system when loading fresh without context**

---

## Process Model (3 Independent Apps)

```
TalkieLive (menu bar)          TalkieEngine (XPC)         Talkie (main UI)
     │                                │                          │
     │  Detects voice                 │  Inference              │  Memo management
     │  Records audio                 │  WhisperKit             │  Workflows
     │  Runs independently            │  Parakeet (NVIDIA)      │  Settings
     │                                │                          │
     └────────┬──────────────────────┼──────────────────────────┘
              │                      │                          │
              │        XPC calls with priority                  │
              │                      │                          │
              ↓                      ↓                          ↓
         Saves dictation      Transcribes audio        Reads dictations
              │                                               │
              └───────────────────────────────────────────────┘
                                    │
                                    ↓
              ~/Library/Application Support/Talkie/live.sqlite
                        (shared database)
```

### TalkieLive
- **Runs independently** - can be active when Talkie main app is closed
- **Always-on recorder** - detects voice, records, transcribes
- **Priority**: Calls Engine with `.high` for real-time feel
- **Communication**: Saves to shared DB + XPC callbacks (when Talkie running)
- **Location**: `macOS/TalkieLive/`

### TalkieEngine
- **XPC service** - isolates GPU/ML crashes from main apps
- **Models**: WhisperKit (CoreML), Parakeet (NVIDIA FluidAudio)
- **Priority-aware**: Caller specifies `.high`/`.userInitiated`/`.medium`/`.low`
- **Why XPC?** Crash isolation + process-level resource control
- **Location**: `macOS/TalkieEngine/`
- **Protocol**: `TalkieEngineProtocol` in `EngineProtocol.swift`

### Talkie (Main UI)
- **SwiftUI app** - memo management, workflows, settings
- **Lazy loading** - only loads 50 recent dictations (not all 3K)
- **Data sync**: XPC callbacks (real-time) + 30s polling (fallback)
- **Location**: `macOS/Talkie/`

---

## Critical Architecture Decisions

### 1. Caller-Specified Priority (RECENT CHANGE - Dec 2025)

**Problem**: Xcode builds starve inference → unpredictable transcription times

**Solution**: Callers declare priority via XPC parameter:
```swift
// TalkieLive - real-time dictation (user is waiting)
engine.transcribe(audioPath, model, priority: .high, reply: ...)

// Talkie scratch pad - interactive but can wait
engine.transcribe(audioPath, model, priority: .userInitiated, reply: ...)

// Batch/async operations
engine.transcribe(audioPath, model, priority: .low, reply: ...)
```

**See**: `TalkieEngine/EngineProtocol.swift` - `TranscriptionPriority` enum with full docs

### 2. Shared Database (Non-Real-Time Communication)

**Path**: `~/Library/Application Support/Talkie/live.sqlite`

**Why?**
- TalkieLive can write dictations when Talkie isn't running
- Simple, async, survives process crashes
- GRDB for Swift-native access

**XPC vs Database**:
- **XPC**: Real-time state updates (Live → Talkie callbacks)
- **Database**: Async persistence (Live writes, Talkie reads)
- **Polling**: 30s fallback when XPC fails

### 3. Lazy Loading (Performance Critical)

**Problem**: Loading 3,076 dictations at startup = ~160ms blocked render

**Solution**:
```swift
// DictationStore.swift
static let initialLoadSize = 50  // Configurable constant

// DictationListView.swift
.task {
    // Loads in background when user navigates to page
    store.refresh()  // Gets last 50, not all 3K
}
```

**Incremental updates**: After initial load, `since(timestamp)` only fetches new records

### 4. Phased Startup (StartupCoordinator)

**Goal**: UI renders in ~50-100ms, defer everything else

**Phases**:
1. **Critical** (sync): Window appearance only
2. **Database** (async): GRDB init, migration check
3. **Deferred** (300ms delay): CloudKit, notifications
4. **Background** (1s delay): Helper apps, XPC connections

**Result**: ~700ms faster perceived startup

**Instrumentation**: `os_signpost` with subsystem `"jdi.talkie.performance"` category `"Startup"`

---

## Data Flow Examples

### Live Dictation (Real-Time)
1. TalkieLive detects voice → starts recording
2. User stops speaking → audio saved to temp file
3. TalkieLive → `engine.transcribe(path, model, priority: .high, ...)`
4. Engine transcribes (high priority, not starved by builds)
5. TalkieLive saves to `live.sqlite` with transcript
6. If Talkie running → XPC callback `utteranceWasAdded()` → UI updates
7. If Talkie closed → polling will pick it up when user launches Talkie

### Talkie Views Dictations
1. User navigates to "Live" tab
2. `DictationListView.onAppear` → `.task { store.refresh() }`
3. `DictationStore` checks `lastRefreshTimestamp`:
   - First load? → `LiveDatabase.recent(limit: 50)`
   - Subsequent? → `LiveDatabase.since(lastRefresh)` (incremental)
4. View renders with data

### Build Interference (SOLVED)
- **Before**: Xcode build → starves inference → slow/inconsistent transcription
- **After**: `.high` priority ensures Live transcription beats build tasks
- **Monitoring**: Check variance in Engine logs or Instruments trace

---

## Communication Patterns

### Real-Time (XPC)
**When**: Talkie is running
**What**: State changes, audio levels, transcription completion
**Example**: `TalkieLiveStateMonitor.utteranceWasAdded()` → `DictationStore.refresh()`

### Async (Database + Polling)
**When**: Always (works even if Talkie closed)
**What**: Dictation persistence
**Polling**: 30s timer as safety net (reduced from 5s for performance)

### Future (Planned)
**URL Notifications** (`feature/live-notifications` branch):
- Replace XPC callbacks with `talkie://dictation/new` URL scheme
- Fire-and-forget, no connection management
- See `TalkieNotifier.swift` in that branch

---

## Performance Optimizations (Dec 2025)

**Problem**: App took 600-800ms to render UI, loaded 3K records at startup

**Solutions**:
1. **Lazy loading**: 0 dictations at startup, 50 on page navigation
2. **Reduced polling**: 5s → 30s (6x less CPU/memory churn)
3. **Phased startup**: Critical path only, defer CloudKit/helpers
4. **Priority system**: Live gets `.high`, builds don't starve it
5. **Instrumentation**: os_signpost for profiling in Instruments

**Results**:
- Startup: ~700ms faster (50-100ms vs 600-800ms)
- Memory: 99.7% reduction in DB operations/hour (2.2M → 6K)
- Initial load: 97% less data (50 vs 3,076 records)

**See**: `/tmp/performance-summary.md` for detailed metrics

---

## Key Files to Read

### Architecture
- `macOS/SYSTEM_ARCHITECTURE.md` (this file) - System overview
- `macOS/AGENTS.md` - Build commands, project structure
- `macOS/Talkie/ARCHITECTURE_REVIEW.md` - SwiftUI performance patterns

### Startup & Performance
- `macOS/Talkie/App/StartupCoordinator.swift` - Phased initialization
- `macOS/Talkie/App/AppDelegate.swift` - Main app lifecycle
- `macOS/Talkie/Stores/DictationStore.swift` - Lazy loading, polling

### Transcription Priority
- `macOS/TalkieEngine/EngineProtocol.swift` - XPC protocol, priority enum
- `macOS/TalkieEngine/EngineService.swift` - Priority → Task priority conversion

### Database
- `macOS/Talkie/Database/LiveDatabase.swift` - Shared GRDB interface
- `macOS/TalkieLive/Database/LiveDatabase.swift` - Mirror (same file)

### XPC Communication
- `macOS/Talkie/Services/TalkieLiveStateMonitor.swift` - Receives callbacks
- `macOS/TalkieLive/Services/TalkieLiveXPCService.swift` - Broadcasts updates

---

## Common Patterns

### Singleton Services (Observable)
```swift
@Observable
final class MyService {
    static let shared = MyService()
    // Published properties update views automatically
}
```

### View Performance (Selective Caching)
```swift
// DON'T: Full redraw on any property change
@ObservedObject private var manager = Manager.shared

// DO: Cache only what you display
private let manager = Manager.shared
@State private var cachedValue: String = ""
.onReceive(manager.$value) { cachedValue = $0 }
```

### Priority Declaration
```swift
// Real-time user interaction
engine.transcribe(..., priority: .high, ...)

// User-facing but can wait
engine.transcribe(..., priority: .userInitiated, ...)

// Background/batch
engine.transcribe(..., priority: .low, ...)
```

---

## Debugging Tips

### Startup Performance
```bash
# Profile with Instruments (os_signpost template)
# Filter by subsystem: "jdi.talkie.performance"
# Look for "App Launch", "Phase 1: Critical", etc.
```

### Inference Variance
```bash
# Check Engine logs
tail -f ~/Library/Logs/TalkieEngine/TalkieEngine.log

# Look for "SLOW INFERENCE" warnings (>5s)
# Check if builds are running concurrently
```

### Database Issues
```bash
# Inspect shared database
sqlite3 ~/Library/Application\ Support/Talkie/live.sqlite
> SELECT COUNT(*) FROM LiveDictation;
> SELECT * FROM LiveDictation ORDER BY createdAt DESC LIMIT 5;
```

### XPC Connection
```bash
# Check if Engine is running
launchctl list | grep talkie.engine

# View XPC logs
log show --predicate 'subsystem == "jdi.talkie.core"' --last 5m
```

---

## When Things Break

### "Transcription is slow/inconsistent"
→ Check if Xcode is building (competes for CPU)
→ Verify caller is passing correct priority (`.high` for Live)
→ Check Engine logs for "SLOW INFERENCE" warnings

### "Dictations not updating in UI"
→ Check XPC connection: `TalkieLiveStateMonitor.shared.isXPCConnected`
→ Verify polling is running (30s timer in `DictationStore`)
→ Check database: `LiveDatabase.all().count`

### "App startup is slow"
→ Use Instruments with os_signpost template
→ Look for blocking work in Phase 1 (should be <100ms)
→ Check if dictations are loading at startup (should be 0)

### "Memory growing over time"
→ Check polling frequency (should be 30s, not 5s)
→ Verify incremental refresh is working (`since(timestamp)`)
→ Look for retain cycles in @Observable objects

---

**Last Updated**: 2025-12-25
**Major Changes**: Added caller-specified priority system, lazy loading, phased startup
