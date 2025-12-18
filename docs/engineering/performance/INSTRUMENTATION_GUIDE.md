# Performance Instrumentation Guide

## Philosophy

Talkie uses **os_signpost** for zero-overhead performance instrumentation. Components automatically emit signposts with **convention-based naming** - no manual section names needed.

**Single source of truth**: os_signpost → Instruments + In-App Debug View

## Quick Start

### 1. Wrap your view in TalkieSection

```swift
struct AllMemosView: View {
    var body: some View {
        TalkieSection("AllMemos") {
            VStack {
                // Your content
            }
        } onLoad: {
            await loadData()
        }
    }
}
```

**What you get:**
- Section lifecycle tracking in Instruments
- Automatic signpost intervals for section appearance/disappearance
- All child components inherit "AllMemos" as their section name

### 2. Use Talkie components (auto-inherit section name)

```swift
TalkieSection("AllMemos") {
    VStack {
        // Auto-named: AllMemos.Refresh
        TalkieButton("Refresh") {
            await viewModel.loadMemos()
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
        }

        // Auto-named: AllMemos.MemoList
        TalkieList("MemoList", items: memos) { memo in
            // Auto-named: AllMemos.MemoRow
            TalkieRow("MemoRow", id: memo.id.uuidString) {
                selectMemo(memo)
            } content: {
                MemoRowContent(memo)
            }
        }
    }
}
```

**No section parameter needed!** Components automatically inherit from parent TalkieSection.

## Convention-Based Naming

### Automatic Section Inheritance

Components inside a TalkieSection automatically inherit the section name via SwiftUI environment:

```swift
TalkieSection("AllMemos") {
    TalkieButton("Load") { ... }       // → AllMemos.Load
    TalkieButton("Delete") { ... }     // → AllMemos.Delete
    TalkieList("Memos", ...) { ... }   // → AllMemos.Memos
}
```

### Explicit Section Override (when needed)

```swift
// Outside of any TalkieSection, provide explicit section
TalkieButton("Save", section: "Settings") { ... }  // → Settings.Save
```

### Nested Sections

```swift
TalkieSection("MemoDetail") {
    TalkieButton("Edit") { ... }  // → MemoDetail.Edit

    // Nested section overrides parent
    TalkieSection("Metadata") {
        TalkieButton("UpdateTags") { ... }  // → Metadata.UpdateTags (not MemoDetail.UpdateTags)
    }
}
```

## Available Components

### TalkieSection

Top-level container that tracks section lifecycle and sets environment for children.

```swift
TalkieSection("AllMemos") {
    // Your content
} onLoad: {
    // Optional: Async data loading
    await loadData()
}
```

**Events emitted:**
- `Section Appeared` - When view appears
- `Data Loaded` - After onLoad completes
- Interval: Section lifecycle (appear → disappear)

### TalkieButton

Button with automatic click tracking and action timing.

```swift
// Async version
TalkieButton("LoadMemos") {
    await viewModel.loadMemos()
} label: {
    Text("Load")
}

// Sync version
TalkieButtonSync("ClearCache") {
    clearCache()
} label: {
    Text("Clear")
}
```

**Events emitted:**
- `Click` - When button clicked
- Interval: Action duration (begin → end)

### TalkieRow

Row component that tracks clicks.

```swift
TalkieRow("MemoRow", id: memo.id.uuidString) {
    selectMemo(memo)
} content: {
    MemoRowContent(memo)
}
```

**Events emitted:**
- `Row Click` - When row tapped

### TalkieList

List with pagination and lifecycle tracking.

```swift
TalkieList("MemosList", items: memos) { memo in
    RowView(memo)
} onLoadMore: {
    await loadNextPage()
}
```

**Events emitted:**
- `List Appeared` - When list first appears
- `Load More` - When scrolled to bottom (if onLoadMore provided)
- Interval: List lifecycle (appear → disappear)

## Viewing Performance Data

### In Xcode Instruments

1. **Product → Profile** (Cmd+I)
2. Select **"Blank"** template
3. Add **"Points of Interest"** instrument
4. Click record and use your app
5. Filter by subsystem: `live.talkie.performance`

You'll see all signpost intervals and events with hierarchical names:
- `AllMemos.lifecycle`
- `AllMemos.Refresh`
- `AllMemos.MemoList.lifecycle`

### In-App Debug View

Open `PerformanceDebugView` (add keyboard shortcut or debug menu):

```swift
// Add to your debug menu or settings
Button("Show Performance Monitor") {
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

Shows real-time events from OSLog (last 60 seconds):
```
12:34:56.123  🖱️ [AllMemos.Refresh] Click
12:34:56.145  💾 [AllMemos.fetchMemos] DB Read
12:34:56.153  ✅ [AllMemos.fetchMemos] DB Read (8ms)
```

## Manual Instrumentation (when needed)

For operations not covered by components:

### Database Operations

```swift
let memos = try await instrumentDatabaseRead(
    section: "AllMemos",
    operation: "fetchMemos"
) {
    try await repository.fetchMemos(sortBy: .timestamp, limit: 50)
}
```

### Click Tracking

```swift
Button("Custom Action") {
    trackClick(section: "AllMemos", component: "CustomButton")
    performAction()
}
```

### View Modifier

```swift
CustomView()
    .instrument(section: "CustomSection")
```

## Complete Example

```swift
struct AllMemosView: View {
    @StateObject private var viewModel = MemosViewModel()

    var body: some View {
        TalkieSection("AllMemos") {
            VStack(spacing: 0) {
                // Header with buttons
                HStack {
                    TalkieButton("Refresh") {
                        await viewModel.loadMemos()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }

                    Spacer()

                    TalkieButtonSync("ToggleSort") {
                        viewModel.toggleSort()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                .padding()

                // Memo list
                TalkieList("MemoList", items: viewModel.memos) { memo in
                    TalkieRow("MemoRow", id: memo.id.uuidString) {
                        viewModel.selectMemo(memo)
                    } content: {
                        MemoRowView(memo: memo)
                    }
                } onLoadMore: {
                    await viewModel.loadNextPage()
                }
            }
        } onLoad: {
            await viewModel.loadMemos()
        }
    }
}
```

**Signposts emitted (automatic):**
- `AllMemos` lifecycle interval
- `AllMemos.Refresh` click + action interval
- `AllMemos.ToggleSort` click
- `AllMemos.MemoList` lifecycle interval
- `AllMemos.MemoRow` row clicks
- `AllMemos.MemoList` load more events

## Zero Overhead

os_signpost has **zero runtime cost** when not profiling:
- No memory allocation
- No performance impact
- Compiled out in release builds (if desired)

Perfect for shipping to production!

## Troubleshooting

### "No events showing in Instruments"

- Ensure subsystem is `live.talkie.performance`
- Filter by "Points of Interest" category
- Check that view actually appeared (signposts only emit when view renders)

### "Section name is 'Unknown'"

- Ensure component is inside a TalkieSection
- Or provide explicit `section:` parameter

### "Can't see in-app view events"

- PerformanceMonitor polls OSLog every 2 seconds
- Events may take a moment to appear
- Ensure app has proper entitlements for OSLog reading

## Best Practices

1. **One TalkieSection per top-level view** - E.g., AllMemosView, MemoDetailView, SettingsView
2. **Use short, clear names** - "Load", "Refresh", "MemoRow" (not "LoadMemosButton")
3. **Let components auto-inherit** - Don't pass `section:` unless overriding
4. **Profile in Instruments first** - In-app view is for troubleshooting, not primary profiling
5. **Don't over-instrument** - Every button doesn't need tracking, focus on critical paths

## Migration from Old Telemetry

Replace old `PerformanceTracker` calls:

**Before:**
```swift
PerformanceTracker.shared.track(.clickReceived(section: "AllMemos"))
PerformanceTracker.shared.startSection("AllMemos")
```

**After:**
```swift
TalkieSection("AllMemos") {
    TalkieButton("Action") { ... } label: { ... }
}
// Convention-based, automatic!
```
