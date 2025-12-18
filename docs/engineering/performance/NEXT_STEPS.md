# Performance Instrumentation: Next Steps

## What We Have Now ✅

### Working Infrastructure:
1. **Action-based tracking** - Focus on processing time, not user journey
2. **TalkieButton auto-tracking** - Every button click creates an action and tracks operations
3. **Automatic operation categorization** - DB, Network, LLM, Inference, Engine, Processing
4. **Real-time Performance Monitor** - Cmd+Shift+P shows all actions with breakdowns
5. **Optimized for snappiness** - All instrumentation work is async (no UI blocking)

### Current Coverage:
- ✅ Section loads (AllMemos, AllMemosV2, etc.)
- ✅ Database operations (all repository methods)
- ✅ Button clicks (via TalkieButton)
- ❌ Most buttons still use regular `Button`
- ❌ Network calls (not instrumented yet)
- ❌ Workflow runs (not instrumented yet)
- ❌ LLM calls (not instrumented yet)

---

## Phase 1: Replace Buttons (Quick Wins)

### Goal: Make existing UI interactions trackable

**Strategy**: Replace `Button` with `TalkieButton` in high-traffic areas.

### Priority Areas:

#### 1. NavigationView (Settings, Clear, etc.)
```swift
// Before:
Button(action: { monitor.clear() }) {
    Text("Clear")
}

// After:
TalkieButton("Clear") {
    await monitor.clear()
} label: {
    Text("Clear")
}
```

#### 2. AllMemosView (Refresh, Sort, Filter)
Find all buttons in `/Views/Memos/AllMemosView2.swift` and wrap them.

#### 3. Settings (Save, Reset, etc.)
Find all buttons in `/Views/Settings/SettingsView.swift` and wrap them.

#### 4. Workflow views (Run, Edit, Delete)
Find buttons in `/Views/Workflows/` and wrap them.

---

## Phase 2: Add Missing Operation Categories

### 1. Network Calls

**Where to add**:
- Any API client calls
- Network requests to external services

**How to instrument**:
```swift
// In your network client:
func fetchData() async throws -> Data {
    let start = Date()
    let data = try await URLSession.shared.data(from: url)
    let duration = Date().timeIntervalSince(start)

    await PerformanceMonitor.shared.addOperation(
        category: .network,
        name: "fetchData",
        duration: duration
    )

    return data
}
```

### 2. Workflow Runs

**Where to add**:
- `WorkflowExecutor.swift`
- Workflow run methods

**How to instrument**:
```swift
func executeWorkflow(_ workflow: WorkflowDefinition) async throws {
    let start = Date()

    // Execute workflow...

    let duration = Date().timeIntervalSince(start)

    await PerformanceMonitor.shared.addOperation(
        category: .processing,
        name: "workflow:\(workflow.name)",
        duration: duration
    )
}
```

### 3. LLM Calls

**Where to add**:
- Any OpenAI/Claude API calls
- Model inference calls

**How to instrument**:
```swift
func callLLM(prompt: String) async throws -> String {
    let start = Date()

    let response = try await openai.chat.completions.create(...)

    let duration = Date().timeIntervalSince(start)

    await PerformanceMonitor.shared.addOperation(
        category: .llm,
        name: "gpt-4",
        duration: duration
    )

    return response
}
```

### 4. Engine Tasks

**Where to add**:
- `EngineClient.swift`
- Engine task execution

**How to instrument**:
```swift
func executeEngineTask(_ task: Task) async throws {
    let start = Date()

    // Execute...

    let duration = Date().timeIntervalSince(start)

    await PerformanceMonitor.shared.addOperation(
        category: .engine,
        name: task.name,
        duration: duration
    )
}
```

---

## Phase 3: Custom Actions (Beyond Buttons)

### 1. Sorting Operations

**When user sorts a list**:
```swift
func sortMemos(by field: SortField) {
    // Start a Sort action
    PerformanceMonitor.shared.startAction(
        type: "Sort",
        name: "by \(field)",
        context: "AllMemos"
    )

    // Do the sort (which might trigger DB operations)
    Task {
        await viewModel.sort(by: field)

        // Complete the action
        await PerformanceMonitor.shared.completeAction()
    }
}
```

### 2. Search Operations

**When user searches**:
```swift
func search(query: String) {
    PerformanceMonitor.shared.startAction(
        type: "Search",
        name: query,
        context: "AllMemos"
    )

    Task {
        await viewModel.search(query)
        await PerformanceMonitor.shared.completeAction()
    }
}
```

### 3. Filtering

**When user applies filters**:
```swift
func applyFilter(_ filter: Filter) {
    PerformanceMonitor.shared.startAction(
        type: "Filter",
        name: filter.description,
        context: "AllMemos"
    )

    Task {
        await viewModel.applyFilter(filter)
        await PerformanceMonitor.shared.completeAction()
    }
}
```

---

## Implementation Checklist

### Week 1: Buttons
- [ ] Find all `Button` instances: `grep -r "Button(" --include="*.swift"`
- [ ] Replace with `TalkieButton` in NavigationView
- [ ] Replace with `TalkieButton` in AllMemosView
- [ ] Replace with `TalkieButton` in SettingsView
- [ ] Replace with `TalkieButton` in Workflow views
- [ ] Test: All buttons create actions in Performance Monitor

### Week 2: Operations
- [ ] Find network call sites
- [ ] Instrument with `.network` category
- [ ] Find workflow execution sites
- [ ] Instrument with `.processing` category
- [ ] Find LLM call sites
- [ ] Instrument with `.llm` category
- [ ] Test: Operations show up in action breakdowns

### Week 3: Custom Actions
- [ ] Add sort action tracking
- [ ] Add search action tracking
- [ ] Add filter action tracking
- [ ] Test: Custom actions show in Performance Monitor

---

## Expected Results

### Before (Current State):
```
#   ACTION              PROCESSING TIME    BREAKDOWN
1   LOAD AllMemos       37ms               2 DB (37ms)
2   LOAD Settings       —                  —
3   LOAD Live           —                  —
```

### After Phase 1 (Buttons):
```
#   ACTION                   PROCESSING TIME    BREAKDOWN
1   CLICK Refresh            42ms               2 DB (37ms) • Processing (5ms)
2   CLICK Save               15ms               DB (15ms)
3   LOAD AllMemos            37ms               2 DB (37ms)
4   CLICK Sort by Date       20ms               DB (15ms) • Processing (5ms)
```

### After Phase 2 (All Operations):
```
#   ACTION                   PROCESSING TIME    BREAKDOWN
1   CLICK Run Workflow       2.3s               LLM (2.1s) • DB (150ms) • Processing (50ms)
2   CLICK Refresh            192ms              2 DB (37ms) • Network (150ms) • Processing (5ms)
3   CLICK Save               15ms               DB (15ms)
4   LOAD AllMemos            37ms               2 DB (37ms)
```

### After Phase 3 (Custom Actions):
```
#   ACTION                   PROCESSING TIME    BREAKDOWN
1   SORT by Date             20ms               DB (15ms) • Processing (5ms)
2   SEARCH "meeting notes"   45ms               DB (40ms) • Processing (5ms)
3   FILTER Unprocessed       12ms               DB (12ms)
4   CLICK Run Workflow       2.3s               LLM (2.1s) • DB (150ms) • Processing (50ms)
```

---

## Quick Reference: How to Instrument

### Button Click (Async):
```swift
TalkieButton("ActionName") {
    await doSomething()
} label: {
    Text("Click Me")
}
```

### Operation (DB, Network, LLM, etc.):
```swift
let start = Date()
let result = await doWork()
let duration = Date().timeIntervalSince(start)

await PerformanceMonitor.shared.addOperation(
    category: .database,  // or .network, .llm, .inference, .engine, .processing
    name: "operationName",
    duration: duration
)
```

### Custom Action (Sort, Search, Filter):
```swift
PerformanceMonitor.shared.startAction(
    type: "Sort",  // or "Search", "Filter", etc.
    name: "by field",
    context: "SectionName"
)

Task {
    await doWork()  // Operations auto-tracked
    await PerformanceMonitor.shared.completeAction()
}
```

---

## Performance Impact

All instrumentation is:
- ✅ **Async** - No UI blocking
- ✅ **Zero-overhead when not profiling** - os_signpost is free
- ✅ **Minimal overhead when profiling** - Just timestamp capture + in-memory append
- ✅ **Auto-throttled** - Keeps last 50 actions only

**Expected overhead**: < 1ms per action, completely async.

---

## Next Session Goals

1. **Replace top 10 buttons** with TalkieButton (30 min)
2. **Instrument workflow execution** (if exists) (15 min)
3. **Test and verify** all interactions show in Performance Monitor (10 min)
4. **Take screenshots** of rich action breakdowns (5 min)

**Total**: ~1 hour to get comprehensive coverage of UI interactions.
