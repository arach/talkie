# Performance Guide

> Last updated: December 2025

This guide covers performance measurement and optimization patterns for Talkie macOS apps.

---

## Table of Contents

1. [Measuring Performance](#measuring-performance)
2. [Auto-Instrumentation Patterns](#auto-instrumentation-patterns)
3. [Performance Best Practices](#performance-best-practices)

---

## Measuring Performance

### Using Instruments (The Simple Way)

Instruments is powerful but overwhelming. Here's what actually matters.

#### Quick Start (2 minutes)

**Step 1: Open Instruments**
```
Product → Profile (Cmd+I)
```

**Step 2: Setup (ONE TIME ONLY)**
1. Select **"Blank"** template
2. Click **"+"** button (top left)
3. Search for: **"Points of Interest"**
4. Double-click to add it
5. Click **Record** button (red circle)

**Step 3: Use Your App**
Click around, load data, do whatever feels slow

**Step 4: Stop Recording**
Click **Stop** button (red square)

#### The ONLY View That Matters: Timeline

You'll see this:

```
┌─────────────────────────────────────────────────────────────┐
│ Points of Interest                                          │
├─────────────────────────────────────────────────────────────┤
│ ViewLifecycle              |----------| 145ms               │
│   DatabaseRead                |--| 8ms                      │
│   DatabaseRead                  |-| 2ms                     │
│ Click                      •                                │
│ DatabaseRead                  |--| 6ms                      │
└─────────────────────────────────────────────────────────────┘
```

**What this means:**
- **Horizontal bars** = How long something took
- **Dots** = Instant events (clicks)
- **Nested/indented** = Happened during the parent event

#### Reading the Data

**Good Example:**
```
ViewLoad              |---| 45ms
  DatabaseFetch       |--| 12ms
  Render              |-| 8ms
```
✅ Total time is reasonable
✅ Database is fast
✅ Render is fast

**Bad Example:**
```
ViewLoad              |------------------| 2500ms
  DatabaseFetch       |----------------| 2200ms
  Render              |-| 8ms
```
⚠️ Database fetch is the bottleneck (2.2s!)

**Fix: Add indexes, use pagination, or cache data**

---

## Auto-Instrumentation Patterns

### Philosophy

Manual instrumentation is tedious and error-prone. Use Swift property wrappers and modifiers to automatically track performance.

### Pattern 1: Tracked Actions

Automatically measure async ViewModel methods:

```swift
import OSLog

private let talkieSignposter = OSSignposter(subsystem: "jdi.talkie", category: "Performance")

/// Automatically instruments async ViewModel actions
@propertyWrapper
struct TrackedAction<T> {
    let name: String
    let action: () async throws -> T

    init(_ name: String, action: @escaping () async throws -> T) {
        self.name = name
        self.action = action
    }

    var wrappedValue: () async throws -> T {
        return {
            let startTime = Date()
            let id = talkieSignposter.makeSignpostID()
            let state = talkieSignposter.beginInterval("ViewModelAction", id: id)

            let result = try await action()

            let duration = Date().timeIntervalSince(startTime)
            talkieSignposter.endInterval("ViewModelAction", state, name)

            return result
        }
    }
}
```

**Usage:**
```swift
class MemosViewModel: ObservableObject {
    @Published var memos: [Memo] = []

    @TrackedAction("loadMemos")
    lazy var loadMemos = {
        // Load data - tracking is automatic!
        let memos = await repository.fetchMemos()
        self.memos = memos
    }
}
```

**Result:** Zero manual signpost calls, automatic tracking in Instruments!

### Pattern 2: Tracked Tasks

Track SwiftUI `.task` operations:

```swift
extension View {
    func trackedTask(
        _ name: String,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @Sendable () async -> Void
    ) -> some View {
        self.task(priority: priority) {
            let startTime = Date()
            let id = talkieSignposter.makeSignpostID()
            let state = talkieSignposter.beginInterval("TaskLoad", id: id)

            await action()

            let duration = Date().timeIntervalSince(startTime)
            talkieSignposter.endInterval("TaskLoad", state, name)
        }
    }
}
```

**Usage:**
```swift
var body: some View {
    AllMemosView()
        .trackedTask("loadMemosData") {
            await viewModel.loadMemos()
        }
}
```

**Result:** Automatic load time tracking visible in Instruments!

### Pattern 3: Repository Instrumentation

Track database operations automatically:

```swift
actor GRDBRepository: MemoRepository {
    func fetchMemos(limit: Int, offset: Int) async throws -> [MemoModel] {
        let id = talkieSignposter.makeSignpostID()
        let state = talkieSignposter.beginInterval("DatabaseRead", id: id)
        defer { talkieSignposter.endInterval("DatabaseRead", state, "fetchMemos") }

        return try await db.read { db in
            try MemoModel
                .order(Column("createdAt").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }
}
```

**Result:** Every database operation automatically shows up in Instruments timeline!

### Complete Example

**Before (Manual, Verbose):**
```swift
class MemosViewModel: ObservableObject {
    @Published var memos: [Memo] = []

    func loadMemos() async {
        let start = Date()
        let id = OSSignposter.shared.makeSignpostID()
        let state = OSSignposter.shared.beginInterval("LoadMemos", id: id)

        // Load data...

        let duration = Date().timeIntervalSince(start)
        OSSignposter.shared.endInterval("LoadMemos", state)
        print("Loaded in \(duration)s")
    }
}
```

**After (Automatic, Clean):**
```swift
class MemosViewModel: ObservableObject {
    @Published var memos: [Memo] = []

    @TrackedAction("loadMemos")
    lazy var loadMemos = {
        // Just load data - tracking is automatic!
    }
}
```

**Result in Instruments:**
```
TaskLoad: loadMemosData       |--------| 150ms
  ViewModelAction: loadMemos     |------| 140ms
    DatabaseRead: fetchMemos        |--| 75ms
```

Perfect hierarchy showing exactly where time is spent!

---

## Performance Best Practices

### Database Performance

#### Use Indexes
```swift
// In DatabaseManager migrations
try db.create(index: "memos_by_created", on: "memos", columns: ["createdAt"])
```

**Impact:** 20x faster sorting on large datasets

#### Pagination Over Full Fetch
```swift
// ❌ Bad: Loads everything
let allMemos = try await repository.fetchAllMemos()

// ✅ Good: Loads 50 at a time
let page1 = try await repository.fetchMemos(limit: 50, offset: 0)
```

**Impact:** Reduces memory from 10MB to 50KB for 10k memos

#### Batch Reads
```swift
// ❌ Bad: N+1 query problem
for memo in memos {
    let transcript = try await repository.fetchTranscript(memoId: memo.id)
}

// ✅ Good: Single query with JOIN
let memosWithTranscripts = try await repository.fetchMemosWithTranscripts()
```

**Impact:** 100x faster for 100 memos (1 query vs 100 queries)

### View Performance

#### Lazy Loading
```swift
// ✅ Use LazyVStack for long lists
LazyVStack {
    ForEach(memos) { memo in
        MemoRow(memo: memo)
    }
}
```

#### Avoid Expensive Computed Properties
```swift
// ❌ Bad: Recalculated on every render
var background: Color {
    calculateComplexColor()  // 5ms each time!
}

// ✅ Good: Cache and update only when needed
@Published private(set) var background: Color

func updateTheme() {
    background = calculateComplexColor()  // Only when theme changes
}
```

### Async/Await Best Practices

#### Don't Block Main Thread
```swift
// ❌ Bad: Blocks UI
func loadData() {
    let data = repository.fetchData()  // Synchronous!
}

// ✅ Good: Async, non-blocking
func loadData() async {
    let data = await repository.fetchData()  // UI stays responsive
}
```

#### Use Task Groups for Parallel Work
```swift
// ❌ Bad: Sequential (2s total)
let memos = await fetchMemos()       // 1s
let workflows = await fetchWorkflows()  // 1s

// ✅ Good: Parallel (1s total)
async let memos = fetchMemos()
async let workflows = fetchWorkflows()
let (memosResult, workflowsResult) = await (memos, workflows)
```

### Critical Path Optimization

The transcription pipeline is latency-sensitive. Keep it lean:

```
Hotkey → Audio Capture → Transcription → Routing → Paste
  ↓         ↓              ↓              ↓          ↓
 <1ms     <10ms        500ms (model)   <5ms      <5ms
```

**Rules:**
1. Pre-load models when possible
2. Don't do I/O on critical path
3. Defer non-essential work (logging, analytics) to after paste
4. Use signposts to measure each step

### Memory Management

#### Avoid Retain Cycles
```swift
// ❌ Bad: Retain cycle
NotificationCenter.default.addObserver(forName: ...) { _ in
    self.update()  // Strong capture!
}

// ✅ Good: Weak self
NotificationCenter.default.addObserver(forName: ...) { [weak self] _ in
    self?.update()
}
```

#### Clean Up Resources
```swift
class AudioCapture {
    private var engine: AVAudioEngine?

    deinit {
        engine?.stop()
        engine = nil
    }
}
```

---

## Tools Reference

### Signposting Subsystems

Use these subsystems for different categories:

| Subsystem | Category | Use For |
|-----------|----------|---------|
| `jdi.talkie` | Performance | General app performance |
| `jdi.talkie.db` | Database | Database operations |
| `jdi.talkie.live` | LiveController | TalkieLive state machine |
| `jdi.talkie.engine` | EngineService | Transcription engine |

### Common Signpost Patterns

**Interval (Duration):**
```swift
let id = signposter.makeSignpostID()
let state = signposter.beginInterval("OperationName", id: id)
// ... do work ...
signposter.endInterval("OperationName", state)
```

**Event (Instant):**
```swift
let id = signposter.makeSignpostID()
signposter.emitEvent("ButtonClicked", id: id)
```

**Event with Metadata:**
```swift
let id = signposter.makeSignpostID()
signposter.emitEvent("DatabaseQuery", id: id, "Table: memos, Count: \(count)")
```

---

## Measuring Success

### Key Metrics

| Metric | Target | Critical? |
|--------|--------|-----------|
| Transcription overhead | <50ms | ⚠️ Critical path |
| Database fetch (50 memos) | <10ms | High |
| View load | <100ms | Medium |
| Settings save | <20ms | Low |

### Performance Regression Testing

1. Profile before changes
2. Save Instruments trace
3. Make changes
4. Profile again
5. Compare traces side-by-side

**Instruments tip:** Use "Comparison View" to see before/after differences automatically

---

## Additional Resources

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Overall app architecture
- [2025-12-14-path-based-xpc-architecture.md](./2025-12-14-path-based-xpc-architecture.md) - XPC performance case study
- [proposals/PROPOSALS.md](./proposals/PROPOSALS.md) - Future performance improvements

---

## Summary

**To measure performance:**
1. Use Instruments with "Points of Interest"
2. Look at the timeline (ignore everything else)
3. Find the longest bars - those are your bottlenecks

**To instrument code:**
1. Use `@TrackedAction` for ViewModel methods
2. Use `.trackedTask()` for view load operations
3. Add signposts to repositories and services
4. Let the tools do the heavy lifting

**To optimize:**
1. Profile first (measure, don't guess)
2. Fix the biggest bottleneck
3. Profile again to verify improvement
4. Repeat

**Remember:** The transcription model takes 95% of the time. Everything else should be <50ms overhead.
