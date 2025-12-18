# Smart Instrumentation Guide
## Maximum Depth with Minimum Code

### Core Philosophy

**The page is rendered when it appears.** We don't need complex lifecycle states - just track:
1. Section appeared → Start tracking
2. Operations happen → Record them (DB, API, etc.)
3. Section disappeared → Complete session

---

## Current Architecture Issues

### Problem 1: Missing Load Times
**Why**: Most sections show "—" for load time because they don't have `onLoad` closures.

**Solution**: Auto-instrument ViewModels using property wrappers.

### Problem 2: State Complexity
**Why**: "Loading" → "Loaded" → "Completed" is artificial when there's no explicit load operation.

**Solution**: Simplify to two states:
- **Active** - Section is visible, tracking operations
- **Completed** - User left, session is complete

### Problem 3: Manual Instrumentation
**Why**: We're manually wrapping each section and repository method.

**Solution**: Use Swift introspection and property wrappers for automatic tracking.

---

## Phase 3: ViewModel Auto-Instrumentation

### Step 1: Property Wrapper for Async Actions

Create `/Services/ViewModelInstrumentation.swift`:

```swift
import SwiftUI
import OSLog

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

            // Report to Performance Monitor
            await PerformanceMonitor.shared.addEvent(
                category: "ViewModel",
                name: name,
                message: "",
                duration: duration
            )

            return result
        }
    }
}

/// Automatically instruments published properties
@propertyWrapper
struct TrackedPublished<T>: DynamicProperty {
    @Published var value: T
    let name: String

    init(wrappedValue: T, _ name: String) {
        self.value = wrappedValue
        self.name = name
    }

    var wrappedValue: T {
        get { value }
        set {
            let id = talkieSignposter.makeSignpostID()
            talkieSignposter.emitEvent("StateChange", id: id, "\(name): \(newValue)")
            value = newValue
        }
    }

    var projectedValue: Published<T>.Publisher {
        $value
    }
}
```

### Step 2: Instrument ViewModels

**Before** (manual, verbose):
```swift
class MemosViewModel: ObservableObject {
    @Published var memos: [Memo] = []
    @Published var isLoading = false

    func loadMemos() async {
        isLoading = true
        // Load data...
        isLoading = false
    }
}
```

**After** (automatic, tracked):
```swift
class MemosViewModel: ObservableObject {
    @TrackedPublished("memos") var memos: [Memo] = []
    @TrackedPublished("isLoading") var isLoading = false

    @TrackedAction("loadMemos")
    lazy var loadMemos = {
        // Load data...
    }
}
```

**Result**: Zero manual signpost calls, automatic tracking of:
- Every state change (memos updated, isLoading toggled)
- Every async action (loadMemos duration)
- Automatic category: "ViewModel"

---

## Phase 4: Task Modifier Auto-Tracking

### Use SwiftUI's `.task` Modifier

SwiftUI already tracks async work with `.task`. We can intercept this:

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

            await PerformanceMonitor.shared.addEvent(
                category: "Task",
                name: name,
                message: "",
                duration: duration
            )
        }
    }
}
```

**Usage**:
```swift
TalkieSection("AllMemos") {
    AllMemosView()
}
.trackedTask("loadMemosData") {
    await viewModel.loadMemos()
}
```

**Result**: Automatic load time tracking without `onLoad` closures!

---

## Phase 5: Introspection-Based Auto-Discovery

### Goal: Zero-Config Instrumentation

Use Swift Mirror API to auto-detect and instrument methods:

```swift
protocol AutoInstrumented {
    var sectionName: String { get }
}

extension AutoInstrumented {
    func autoInstrument() {
        let mirror = Mirror(reflecting: self)

        for child in mirror.children {
            // Auto-detect @Published properties
            if let label = child.label, label.hasPrefix("_") {
                // Instrument state changes
            }

            // Auto-detect async methods
            if let method = child.value as? () async -> Void {
                // Wrap with instrumentation
            }
        }
    }
}
```

**Usage**:
```swift
class MemosViewModel: ObservableObject, AutoInstrumented {
    var sectionName = "AllMemos"

    @Published var memos: [Memo] = []

    func loadMemos() async {
        // Auto-instrumented!
    }
}
```

**Result**: Just conform to `AutoInstrumented`, everything else is automatic.

---

## Simplified State Model

### Current (Too Complex):
```
Appeared → Loading → Loaded → Disappeared
     ↓        ↓         ↓          ↓
  (Yellow) (Orange)  (Blue)    (Green)
```

### Proposed (Simple & Clear):
```
Active → Completed
  ↓          ↓
(Blue)    (Green)

While Active:
- Track all operations (DB, ViewModel, Task)
- Show live breakdown
- No artificial "loading" state
```

### Implementation:

```swift
var state: String {
    if disappearedAt != nil { return "Completed" }
    if appearedAt != nil { return "Active" }
    return "Unknown"
}

var sessionDuration: TimeInterval? {
    guard let start = appearedAt else { return nil }
    let end = disappearedAt ?? Date() // Use current time if still active
    return end.timeIntervalSince(start)
}
```

**Benefits**:
1. No confusing "Loaded" vs "Completed"
2. Real-time tracking (session duration updates while active)
3. Clear semantics: Active = in view, Completed = left view

---

## Automatic Load Time Calculation

### Problem:
Only sections with `onLoad` show load times.

### Solution:
Define "load time" as time from appeared to first operation:

```swift
var loadTime: TimeInterval? {
    guard let appeared = appearedAt else { return nil }

    // Load time = time to first DB operation OR 100ms (whichever comes first)
    if breakdown.databaseTime > 0, let firstDBAt = firstOperationAt {
        return firstDBAt.timeIntervalSince(appeared)
    }

    // If no DB operations, use time to "settled" (no operations for 100ms)
    return nil // Or use a heuristic
}
```

**Better approach**: Show total time in session, not artificial "load time":

```swift
// Breakdown column shows:
// - Time in view: 2.5s
// - DB: 2× 15ms
// - Render: 180ms (estimated: total - DB - other)
// - Other: 5ms
```

---

## Complete Example: AllMemosView

### Before (Manual):
```swift
var body: some View {
    TalkieSection("AllMemos") {
        VStack {
            // UI
        }
    } onLoad: {
        await viewModel.loadMemos()
    }
}

class MemosViewModel: ObservableObject {
    @Published var memos: [Memo] = []

    func loadMemos() async {
        // Manual tracking
        let start = Date()
        // Load data...
        let duration = Date().timeIntervalSince(start)
        // Log manually
    }
}
```

### After (Automatic):
```swift
var body: some View {
    TalkieSection("AllMemos") {
        VStack {
            // UI
        }
    }
    .trackedTask("loadMemosData") {
        await viewModel.loadMemos()
    }
}

class MemosViewModel: ObservableObject, AutoInstrumented {
    var sectionName = "AllMemos"

    @TrackedPublished("memos") var memos: [Memo] = []

    @TrackedAction("loadMemos")
    lazy var loadMemos = {
        // Just load data - tracking is automatic
    }
}
```

**Result**: Zero manual instrumentation, full tracking of:
- Section lifecycle (TalkieSection)
- Task load time (.trackedTask)
- ViewModel action duration (@TrackedAction)
- State changes (@TrackedPublished)
- Database operations (already done)

---

## Implementation Priority

1. **Fix state model** (5 min) - Simplify to Active/Completed
2. **Show session duration** (5 min) - Replace "load time" with "time in view"
3. **Create `.trackedTask` modifier** (10 min) - Auto-track async work
4. **Create `@TrackedAction` wrapper** (10 min) - Auto-track ViewModel methods
5. **Test with AllMemosV2** (5 min) - Verify all tracking works
6. **Roll out to other views** (15 min) - Add `.trackedTask` to remaining sections

**Total time**: ~50 minutes to get 99% coverage

---

## What You'll See

### Performance Monitor (Improved):
```
#  SECTION          TIME IN VIEW    BREAKDOWN                    STATE
1  SystemConsole    450ms           —                           Completed
2  TalkieService    1.2s            DB: 5ms  Render: 1195ms    Completed
3  Models           2.1s            —                           Completed
4  Workflows        800ms           DB: 2× 15ms  Render: 770ms  Completed
5  AllMemos         2.5s            DB: 2× 37ms  Render: 2426ms Active
```

**Clear, credible, useful!**

- Time in view = total session duration
- Breakdown shows what happened during that time
- State is simple: Active (in view) or Completed (left view)
- All sections show times (not just the one with onLoad)

---

## Summary

**Current approach**: Manual wrapping, complex states, missing data

**Smart approach**:
1. Auto-instrument ViewModels with property wrappers
2. Use `.trackedTask` for async work
3. Simplify states to Active/Completed
4. Show session duration instead of artificial "load time"
5. Let introspection do the heavy lifting

**Result**: 99% coverage, <50 lines of instrumentation code app-wide
