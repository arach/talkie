# Performance Instrumentation Implementation Summary

## What Was Built

A **zero-overhead performance instrumentation system** using native macOS `os_signpost` with:

1. **Convention-based automatic naming** - Components inherit section names via SwiftUI environment
2. **Single source of truth** - os_signpost feeds both Instruments AND in-app debug view
3. **Developer ergonomics** - Minimal boilerplate, just wrap views in TalkieSection

## Architecture

```
TalkieComponents (UI)
    ↓
os_signpost (native macOS logging)
    ↓
    ├──→ Instruments (when profiling)
    └──→ OSLogStore → PerformanceDebugView (real-time in-app)
```

**Key insight**: Database operations get custom names, UI components get automatic names.

## Files Created

### 1. `/Services/PerformanceInstrumentation.swift`
- **Purpose**: Core instrumentation infrastructure
- **Exports**:
  - `talkieSignposter` - OSSignposter for creating intervals
  - `talkiePerformanceLog` - OSLog for signpost events
  - `instrumentDatabaseRead()` - For manual DB operation tracking
  - `trackClick()` - For manual click tracking
  - `PerformanceMonitor` - Reads from OSLog for in-app display
  - `PerformanceDebugView` - Real-time event viewer

### 2. `/Components/TalkieComponents.swift`
- **Purpose**: UI components with built-in instrumentation
- **Exports**:
  - `TalkieSection` - Top-level container, sets environment
  - `TalkieButton` - Async button with click + action tracking
  - `TalkieButtonSync` - Sync button with click tracking
  - `TalkieRow` - Row with click tracking
  - `TalkieList` - List with pagination + lifecycle tracking

### 3. `/INSTRUMENTATION_GUIDE.md`
- **Purpose**: Developer documentation
- **Contains**: Usage examples, conventions, best practices

## Usage Pattern

### Simple Example

```swift
struct AllMemosView: View {
    var body: some View {
        TalkieSection("AllMemos") {
            VStack {
                // Auto-named: AllMemos.Refresh
                TalkieButton("Refresh") {
                    await loadData()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        } onLoad: {
            await initialLoad()
        }
    }
}
```

### Database Operation Example

```swift
func loadMemos() async {
    let memos = try await instrumentDatabaseRead(
        section: "AllMemos",
        operation: "fetchMemosWithWorkflows"
    ) {
        try await repository.fetchMemos(
            sortBy: .timestamp,
            includeWorkflows: true,
            limit: 50
        )
    }
}
```

## Convention-Based Naming

### Automatic Inheritance (Recommended)

```swift
TalkieSection("AllMemos") {
    TalkieButton("Load") { ... }      // → AllMemos.Load
    TalkieButton("Delete") { ... }    // → AllMemos.Delete
    TalkieList("Memos", ...) { ... }  // → AllMemos.Memos
}
```

### Explicit Override (When Needed)

```swift
// Outside TalkieSection or override needed
TalkieButton("Save", section: "Settings") { ... }  // → Settings.Save
```

### Nested Sections

```swift
TalkieSection("MemoDetail") {
    TalkieButton("Edit") { ... }  // → MemoDetail.Edit

    TalkieSection("Metadata") {
        TalkieButton("UpdateTags") { ... }  // → Metadata.UpdateTags
    }
}
```

## How to View Performance Data

### Option 1: Xcode Instruments (Primary)

1. Product → Profile (Cmd+I)
2. Select "Blank" template
3. Add "Points of Interest" instrument
4. Record and interact with app
5. Filter by subsystem: `live.talkie.performance`

**What you see:**
- Timeline with intervals (section lifecycle, button actions)
- Point-in-time events (clicks, data loaded)
- Hierarchical names (AllMemos.Refresh, AllMemos.MemoList.lifecycle)

### Option 2: In-App Debug View (Troubleshooting)

Add keyboard shortcut or debug menu item:

```swift
Button("Performance Monitor") {
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentView = NSHostingView(rootView: PerformanceDebugView())
    window.title = "Performance Monitor"
    window.center()
    window.makeKeyAndOrderFront(nil)
}
```

**What you see:**
- Real-time events from last 60 seconds
- Timestamps + event names
- Icon-coded events (🖱️ click, 💾 DB read, etc.)
- Useful for troubleshooting user-reported slowness

## Philosophy

### Automatic (Don't Think About It)
- **UI interactions** → Use TalkieSection, TalkieButton, TalkieRow, TalkieList
- Names inherit automatically via environment
- Zero boilerplate

### Manual (Worth Being Intentional)
- **Database operations** → Use `instrumentDatabaseRead(section:operation:)`
- Each query is unique and deserves a descriptive name
- Example names: `fetchMemosWithWorkflows`, `countUnreadMemos`, `fullTextSearchQuery`

## Zero Overhead

os_signpost has **zero runtime cost** when not profiling:
- No memory allocation
- No CPU impact
- Compiled out or disabled in release builds

Perfect for shipping to production.

## Migration Path

### Old PerformanceTelemetry (Removed)
```swift
// OLD - Manual tracking
PerformanceTracker.shared.track(.clickReceived(section: "AllMemos"))
PerformanceTracker.shared.startSection("AllMemos")
```

### New PerformanceInstrumentation (Current)
```swift
// NEW - Convention-based, automatic
TalkieSection("AllMemos") {
    TalkieButton("Action") { ... } label: { ... }
}
```

## Next Steps

1. **Start using in views**:
   - Wrap top-level views in `TalkieSection`
   - Replace Button with `TalkieButton`/`TalkieButtonSync`
   - Use `TalkieList` for scrolling lists

2. **Instrument database operations**:
   - Wrap repository calls with `instrumentDatabaseRead()`
   - Use descriptive operation names

3. **Profile in Instruments**:
   - Record a session
   - Identify slow operations
   - Optimize based on data

4. **Add debug menu item**:
   - Show PerformanceDebugView for troubleshooting
   - Users can screenshot performance events when reporting issues

## Benefits

✅ **Zero overhead** - Native os_signpost, no custom logging
✅ **Convention-based** - Automatic naming, less thinking
✅ **Single source of truth** - Same data in Instruments and in-app
✅ **Production-ready** - Can ship to users
✅ **Instruments integration** - Professional profiling tools
✅ **Troubleshooting-friendly** - Users can show performance issues

## Build Status

✅ **BUILD SUCCEEDED** - All files compile successfully
✅ **Zero warnings** - Clean build
✅ **Ready to use** - Start wrapping views in TalkieSection
