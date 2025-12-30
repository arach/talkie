# Views Architecture Analysis

`macOS/Talkie/Views/` - SwiftUI view components (85 files, 43,644 lines)

This document analyzes the 5 most complex views in the codebase.

---

## Summary Table

| View | Lines | Complexity | Issues | Priority |
|------|-------|------------|--------|----------|
| **HistoryView** | 2,983 | VERY HIGH | God object, 11+ @State, audio handling in view | Critical |
| **HomeView** | 2,001 | HIGH | 37 nested structs, duplicate grid logic, dead code | High |
| **DebugToolbar** | 1,730 | HIGH | 5+ responsibilities, subprocess parsing, no error handling | Medium |
| **MemoDetailView** | 1,314 | HIGH | 18 @State, timer races, AVAudioPlayer leaks | High |
| **UnifiedDashboard** | 1,310 | MODERATE | Timer not cancelled, recomputes everything | Medium |

---

## 1. HistoryView.swift (2,983 lines)

**Location:** `Views/Live/History/HistoryView.swift`

### Core Responsibilities
Multi-modal navigation hub for TalkieLive:
- Dictation history list with detail view
- Audio drag-drop transcription
- Sidebar navigation (Home, History, Queue, Today, Logs, Settings)
- Multi-select batch operations
- Audio playback with seeking

### State Management
```swift
@State private var selectedSection: LiveNavigationSection?
@State private var selectedDictationIDs: Set<Dictation.ID>  // Multi-select
@State private var searchText: String
@State private var isSidebarCollapsed: Bool
@State private var isDropTargeted: Bool
@State private var dropMessage: String?
@State private var isTranscribingDrop: Bool
// ... 4 more @State properties
```
**11 @State properties** - excessive for a single view.

### Complexity Hotspots

1. **`extractAudioMetadata()`** (105 lines) - Race conditions with async Tasks modifying local dictionary
2. **`processDroppedAudioFromStorage()`** (84 lines) - Long error handling chain
3. **`handleAudioDrop()`** (57 lines) - Callback-based async (fragile)
4. **Nested components** - 15+ structs including DictationDetailView, MinimalAudioCard, SeekableWaveform

### Architectural Issues

- **God Object**: Handles navigation, data filtering, audio processing, playback - should be 5+ separate modules
- **Mixed Concerns**: UI, data fetching, audio handling all in one view
- **No Centralized State**: 11 @State scattered, multiple singletons
- **Async Inconsistency**: Mix of callbacks and async/await

### Recommendations
1. Extract `AudioDropHandler` service
2. Split into `HistorySidebarView`, `HistoryListView`, `HistoryDetailView`
3. Create proper ViewModel with state container

---

## 2. HomeView.swift (2,001 lines)

**Location:** `Views/Live/HomeView.swift`

### Core Responsibilities
Dashboard/statistics view showing:
- Voice stats (recordings, words, time saved)
- Activity streaks and today's count
- GitHub-style activity calendar (monthly/quarterly/yearly)
- Recent dictations and top apps
- Contextual AI-generated insights

### State Management
```swift
@State private var activityData: [DayActivity]  // 52 weeks of history
@State private var stats: HomeStats             // Computed statistics
@State private var debugActivityLevel: ActivityViewLevel?  // DEBUG only
```
**3 @State properties** - reasonable, but complex computed state.

### Complexity Hotspots

1. **`generateInsight()`** (140 lines) - 90+ hardcoded app names for categorization
2. **Activity grid building** - Duplicated 3 times across different grid components
3. **37 nested structs** - InsightCard, StreakCard, ActivityGrid, MonthLabels, etc.

### Architectural Issues

- **SRP Violation**: Handles UI layout, calculations, insight generation, grid building
- **Code Duplication**: Grid logic appears 3 times with minor variations
- **Dead Code**: `QuickStatsRow`, `RecentMemosCard`, `MonthlyActivityGrid` defined but unused
- **Hardcoded Values**: 90+ app names, date constants (7, 13, 52 weeks)

### Recommendations
1. Extract `InsightEngine` for insight generation
2. Create shared `ActivityGridBuilder` utility
3. Move 37 components to `Views/Live/Components/` folder
4. Remove dead code

---

## 3. DebugToolbar.swift (1,730 lines)

**Location:** `Views/DebugToolbar.swift`

### Core Responsibilities
DEBUG-only development tools:
- State inspection (app state, sync events, logs)
- Convenience actions (sync, reset, test)
- Design audit runner with HTML/Markdown reports
- Core Data object inspector
- Process management (TalkieEngine/TalkieLive)
- A/B test audio padding strategies

### State Management
Scattered across 5+ view components:
```swift
// TalkieDebugToolbar
@State private var showingConsole: Bool

// EngineProcessesDebugContent
@State private var processes: [RunningProcess]
@State private var isRestarting: Bool

// ManagedObjectInspector
@State private var showCopied: Bool
@State private var expandedRelationship: String?

// AudioPaddingTestView
@State private var selectedAudioPath: String
@State private var testResults: [PaddingTestResult]
@State private var isRunningTests: Bool
```

### Complexity Hotspots

1. **Design Audit** (250 lines) - File I/O, regex parsing, HTML generation
2. **Audio Padding Test** (440 lines) - A/B harness with AVAudioConverter
3. **Process Management** (235 lines) - `/bin/ps` subprocess parsing
4. **Core Data Inspector** (287 lines) - Recursive relationship expansion

### Architectural Issues

- **Massive Single File**: 5+ unrelated concerns
- **Fragile Subprocess Parsing**: Assumes `/bin/ps` output format
- **Index-based Mutations**: `testResults[index]` during async (race conditions)
- **Silent Failures**: Many `try?` without logging
- **Hardcoded Paths**: JFK audio sample path, Desktop paths

### Recommendations
1. Split into 6 files under `Views/Debug/`
2. Extract `DesignAuditService`, `ProcessManagerService`
3. Replace regex markdown parsing with structured JSON
4. Add error logging for silent failures

---

## 4. MemoDetailView.swift (1,314 lines)

**Location:** `Views/MemoDetail/MemoDetailView.swift`

### Core Responsibilities
Primary detail view for voice memos:
- Memo display (title, transcript, notes, metadata)
- Audio playback with seek controls
- Content editing with debounced saving
- Transcription/retranscription
- Workflow execution

### State Management
```swift
// Playback (4)
@State private var isPlaying, currentTime, duration, audioPlayer

// Editing (3)
@State private var editedTitle, editedNotes, editedTranscript

// Timers (3)
@State private var notesSaveTimer, playbackTimer, showNotesSaved

// Workflow (5)
@State private var selectedWorkflowRun, processingWorkflowIDs, showingWorkflowPicker...

// Retranscription (2)
@State private var showingRetranscribeSheet, isRetranscribing

// Focus (1)
@FocusState private var titleFieldFocused
```
**18 @State properties** - too many for one view.

### Complexity Hotspots

1. **Playback Management** (60 lines) - Manual timer polling at 0.1s intervals
2. **Notes Debouncing** (40 lines) - Custom debounce with manual Timer
3. **Lifecycle Management** (40 lines) - 5 separate `.onChange()` handlers
4. **Edit Mode Sync** (35 lines) - Multi-step save orchestration

### Architectural Issues

- **God Object**: Playback, editing, workflows, transcription all in one
- **Timer Race Conditions**: `notesInitialized` flag set after 0.1s delay
- **AVAudioPlayer Lifecycle**: No explicit disposal, potential memory leaks
- **18 Nested View Structs**: Deep component hierarchy with prop drilling
- **Non-compliant Logging**: Uses `os.log` instead of TalkieLogger

### Recommendations
1. Extract `PlaybackController` to encapsulate audio + timer
2. Create `MemoDetailViewModel` for state
3. Move transcript section to separate file (140+ lines)
4. Fix logging to use TalkieLogger

---

## 5. UnifiedDashboard.swift (1,310 lines)

**Location:** `Views/UnifiedDashboard.swift`

### Core Responsibilities
Home screen combining metrics from memos and dictations:
- Unified activity stream (memos + dictations merged)
- Metrics dashboard (today's count, totals, word count, streak)
- 13-week activity heatmap
- Quick access navigation
- System status monitoring (Live, AI, Sync)

### State Management
```swift
@State private var unifiedActivity: [UnifiedActivityItem]  // Merged stream
@State private var activityData: [DayActivity]            // Heatmap (90 days)
@State private var streak: Int
@State private var todayMemos, todayDictations: Int
@State private var totalWords: Int
@State private var isLiveRunning: Bool
@State private var serviceState: TalkieServiceState
@State private var pendingRetryCount: Int
```
**11 @State properties** plus FetchRequest and 5 singleton dependencies.

### Complexity Hotspots

1. **`loadData()`** (60 lines) - Recomputes everything on any data change
2. **`buildActivityData()`** (40 lines) - Calendar grid with date arithmetic
3. **`calculateStreak()`** (25 lines) - Creates temp Set every call
4. **Timer Leak**: `Timer.publish(every: 5)` never cancelled

### Architectural Issues

- **View Doing Data Work**: `loadData()`, `calculateStreak()` should be ViewModel
- **Timer Memory Leak**: autoconnect() never cleaned up on dismiss
- **NotificationCenter Navigation**: Raw strings, no type safety
- **5 Singletons**: DictationStore, ServiceManager, CloudKitSyncManager, SettingsManager
- **Magic Numbers**: `prefix(8)`, 13 weeks, 7 days hardcoded

### Recommendations
1. Extract `DashboardViewModel` with @Observable
2. Split into 5 child views (header, stats, activity, recent, status)
3. Cancel timer on view disappear
4. Replace NotificationCenter with NavigationStack

---

## Common Patterns & Issues

### Across All Views

1. **God Object Anti-Pattern**: All 5 views handle too many responsibilities
2. **Excessive Nesting**: 15-37 nested structs per file
3. **Singleton Coupling**: Heavy use of `.shared` singletons
4. **Timer Management**: Manual timers without proper cleanup
5. **State Sprawl**: 11-18 @State properties per view

### Recommended Refactoring Priority

1. **HistoryView** - Most critical, affects core user experience
2. **MemoDetailView** - Timer races and memory leaks
3. **HomeView** - Dead code and duplication
4. **UnifiedDashboard** - Timer leak
5. **DebugToolbar** - Lower priority (DEBUG only)

### Architecture Improvements Needed

1. **ViewModel Pattern**: Move data logic out of views
2. **Dependency Injection**: Replace singletons with protocol-based injection
3. **Component Library**: Extract reusable components to shared folder
4. **State Containers**: Centralize state management
5. **Consistent Async**: Standardize on async/await, remove callbacks

---

## Done

- [x] HistoryView analyzed
- [x] HomeView analyzed
- [x] DebugToolbar analyzed
- [x] MemoDetailView analyzed
- [x] UnifiedDashboard analyzed
