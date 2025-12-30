# AGENTS.md

Instructions for AI coding agents working on this repository.

---

## Project Overview

**Talkie** is a voice memo app with AI-powered workflows:

- **iOS** (`iOS/`): SwiftUI + SwiftData mobile app
- **macOS** (`macOS/`): SwiftUI desktop companion with workflow execution
- **Landing** (`Landing/`): Marketing website (React/Next.js)

Voice memos recorded on iOS sync via CloudKit to macOS, where workflows process transcripts through LLMs, extract tasks, create reminders, and more.

---

## Target Platforms

| Platform | Minimum | Language | UI Framework |
|----------|---------|----------|--------------|
| iOS | 26.0 | Swift 6.2 | SwiftUI |
| macOS | 26.0 (Tahoe) | Swift 6.2 | SwiftUI |
| Landing | - | TypeScript | React/Next.js |

---

## Build Commands

### iOS

```bash
cd iOS
open "Talkie iOS.xcodeproj"

# Build
xcodebuild -scheme "Talkie iOS" -destination 'platform=iOS Simulator,name=iPhone 16' build

# Test
xcodebuild -scheme "Talkie iOS" -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### macOS

```bash
cd macOS
open Talkie.xcodeproj

# Build
xcodebuild -scheme Talkie -destination 'platform=macOS' build

# Test
xcodebuild -scheme Talkie -destination 'platform=macOS' test
```

### Landing Page

```bash
cd Landing
pnpm install
pnpm dev      # Development server
pnpm build    # Production build
```

---

## Code Style

### Swift 6.2 Concurrency

Use `-default-isolation MainActor` compiler flag. All code runs on main actor by default.

```swift
// Runs on MainActor (no annotation needed)
class MemoryService {
    func query(question: String) async -> [MemoryResult] { }
}

// Explicitly run off main thread for CPU-heavy work
@concurrent
func generateEmbeddings(for texts: [String]) async -> [[Float]] { }

// @Observable classes: mark @MainActor for clarity
@MainActor @Observable
final class AudioRecorderManager {
    var isRecording = false
}
```

**Do:**
```swift
try await Task.sleep(for: .seconds(1))
```

**Don't:**
```swift
try await Task.sleep(nanoseconds: 1_000_000_000)
DispatchQueue.main.async { }
```

### SwiftUI

**Navigation:**
```swift
// Use NavigationStack + navigationDestination
NavigationStack(path: $path) {
    MemoListView()
        .navigationDestination(for: VoiceMemo.self) { memo in
            MemoDetailView(memo: memo)
        }
}

// Never use NavigationView (deprecated)
```

**Tabs (iOS 26):**
```swift
TabView {
    Tab("Memos", systemImage: "waveform") {
        MemoListView()
    }
    Tab(role: .search) {
        SearchView()
    }
}

// Never use tabItem()
```

**Styling:**
```swift
// Do
Text("Hello").foregroundStyle(.secondary)
Image(systemName: "star").clipShape(.rect(cornerRadius: 8))
Button("Save", systemImage: "checkmark") { save() }
    .glassEffect()  // iOS 26 Liquid Glass

// Don't
.foregroundColor(.red)  // Deprecated
.cornerRadius(12)       // Deprecated
```

**Buttons vs Gestures:**
```swift
// Always use Button for tappable elements
Button("Play", systemImage: "play") { play() }

// Only use onTapGesture for tap count or location
Image("photo").onTapGesture(count: 2) { doubleTapped() }
```

**Layout:**
```swift
// Prefer containerRelativeFrame over GeometryReader
ScrollView(.horizontal) {
    ForEach(items) { item in
        ItemView(item)
            .containerRelativeFrame(.horizontal, count: 3, spacing: 16)
    }
}

// Never use UIScreen.main.bounds
```

**onChange:**
```swift
// Two parameters (access old/new values)
.onChange(of: searchText) { oldValue, newValue in }

// Zero parameters (just react)
.onChange(of: selectedMemo) { loadDetails() }

// Never use single-parameter variant
```

**Formatting:**
```swift
// Use format parameter
Text(duration, format: .number.precision(.fractionLength(2)))
Text(date, format: .dateTime.month().day())

// Never use String(format:)
Text(String(format: "%.2f", duration))  // Wrong
```

**ForEach with enumerated:**
```swift
// Swift 6.2: enumerated() conforms to Collection
ForEach(memos.enumerated(), id: \.element.id) { index, memo in }

// Don't convert to Array
ForEach(Array(memos.enumerated()), id: \.element.id) { }  // Unnecessary
```

**Views:**
```swift
// Extract subviews as separate structs
struct MemoListView: View {
    var body: some View {
        MemoHeader()
        MemoContent()
    }
}

private struct MemoHeader: View { ... }
private struct MemoContent: View { ... }

// Don't use computed properties for subviews
private var headerView: some View { }  // Wrong
```

### Swift Language

**Strings:**
```swift
// Swift-native methods
let cleaned = text.replacing("um", with: "")

// Localized search for user input
if title.localizedStandardContains(searchText) { }

// Don't use Foundation equivalents
text.replacingOccurrences(of: "um", with: "")  // Wrong
title.contains(searchText)  // Not localized
```

**URLs:**
```swift
// Modern APIs
let docs = URL.documentsDirectory
let file = docs.appending(path: "file.txt")

// Don't use deprecated methods
FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
url.appendingPathComponent("file.txt")
```

**Optionals:**
```swift
// Safe unwrapping
guard let data = memo.audioData else { throw MemoError.missingAudio }
let title = memo.title ?? "Untitled"

// String interpolation defaults (Swift 6.2)
Text("Title: \(memo.title, default: "Untitled")")

// Avoid force unwraps except impossible nil cases
```

**InlineArray (Swift 6.2):**
```swift
// Fixed-size stack-allocated arrays
var levels: InlineArray<64, Float> = .init(repeating: 0)
```

### SwiftData / CloudKit

CloudKit-compatible models require:

```swift
@Model
final class VoiceMemo {
    // All properties need defaults or be optional
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var transcription: String?  // Optional OK

    // External storage for large data
    @Attribute(.externalStorage)
    var audioData: Data?

    // Relationships MUST be optional
    @Relationship(deleteRule: .cascade)
    var versions: [TranscriptVersion]?

    init() { }
}

// Never use with CloudKit:
@Attribute(.unique)  // Not supported
var requiredField: String  // Must have default or be optional
var relationship: [Child]  // Must be optional
```

### Observable Pattern

```swift
// Always @MainActor + @Observable
@MainActor @Observable
final class WorkflowExecutor {
    var isRunning = false
    var progress: Double = 0
}

// Never use ObservableObject
class OldModel: ObservableObject {  // Wrong
    @Published var value = 0
}
```

---

## Testing

```swift
// Swift Testing (preferred)
@Test("Chunking splits at sentence boundaries")
func chunkingSplits() {
    let chunks = ChunkingService().chunk(text: "First. Second.")
    #expect(chunks.count == 2)
}

// Exit tests (Swift 6.2)
@Test func crashOnNil() async {
    await #expect(exitsWith: .failure) {
        let x: String? = nil
        _ = x!
    }
}

// Attachments for debugging
@Test func transcriptionQuality() async throws {
    let result = try await transcribe(audio)
    if result.confidence < 0.8 {
        #attach(result.output, named: "transcript")
    }
    #expect(result.confidence >= 0.8)
}
```

Only write UI tests when unit tests aren't possible.

---

## Project Structure

```
iOS/
├── Talkie iOS/
│   ├── App/           # TalkieApp.swift, AppDelegate
│   ├── Models/        # SwiftData models, Persistence
│   ├── Views/         # SwiftUI views by feature
│   ├── Services/      # Audio, Transcription, Sync
│   └── Resources/     # Assets, Info.plist
└── Talkie iOS.xcodeproj

macOS/
├── Talkie/
│   ├── App/
│   ├── Models/
│   ├── Views/
│   ├── Services/
│   │   └── LLM/       # Provider implementations
│   ├── Workflow/      # TWF execution engine
│   └── Resources/
│       └── StarterWorkflows/
└── Talkie.xcodeproj
```

**Rules:**
- One type per file
- Group by feature, not layer
- Private helpers can share file with parent view

---

## Talkie Workflow Format (TWF)

TWF is the source of truth for workflow logic. JSON files stored in `~/Documents/Workflows/`.

```json
{
  "slug": "quick-summary",
  "name": "Quick Summary",
  "icon": "text.alignleft",
  "color": "blue",
  "steps": [
    {
      "id": "summarize",
      "type": "LLM Generation",
      "config": {
        "prompt": "Summarize: {{TRANSCRIPT}}",
        "costTier": "fast"
      }
    }
  ]
}
```

**ID Rules:**
- Workflow slug: `kebab-case`, unique across workflows
- Step id: `kebab-case`, unique within workflow
- Variables: `{{TRANSCRIPT}}`, `{{step-id}}`, `{{step-id.field}}`
- No UUIDs in TWF (generated at runtime)

**Step Types:**
`LLM Generation`, `Transcribe Audio`, `Transform Data`, `Conditional Branch`, `Create Reminder`, `Run Shell Command`, `Save to File`, `Notify iPhone`, `Trigger Detection`, `Extract Intents`, `Execute Workflows`, `Webhook`, `Email`, `Apple Notes`, `Apple Calendar`, `Clipboard`, `Notification`, `Speak`

**Validation:**
- Never add required fields without migration
- Use `decodeIfPresent` for new optional fields
- Test round-trip: encode → decode must be lossless

---

## Git Conventions

```bash
# Gitmoji + clear message
git commit -m "✨ Add semantic memory search"
git commit -m "🐛 Fix audio playback in background"
git commit -m "♻️ Refactor to async/await"
```

| Emoji | Purpose |
|-------|---------|
| ✨ | New feature |
| 🐛 | Bug fix |
| ♻️ | Refactor |
| 🎨 | UI/style |
| ⚡️ | Performance |
| 📝 | Docs |
| ✅ | Tests |
| 🔥 | Remove code |

**Never:**
- Add "Generated with Claude Code" footers
- Add co-author attributions
- Push secrets to the repo

---

## Dependencies

- Do not introduce third-party frameworks without asking first
- Prefer Swift Package Manager for iOS/macOS
- Prefer pnpm for Node.js projects
- Avoid UIKit unless specifically requested

---

## Pre-Commit Checklist

- [ ] SwiftLint passes (if installed)
- [ ] No force unwraps (unless truly impossible nil)
- [ ] No force try
- [ ] No GCD usage
- [ ] No deprecated SwiftUI modifiers
- [ ] Tests pass
- [ ] No hardcoded strings (use Localizable.strings)
- [ ] No secrets in code
- [ ] No hardcoded file paths (see below)
- [ ] No direct os.log usage (use TalkieLogger)

---

## Logging

**ALWAYS use TalkieLogger. NEVER use os.log directly.**

```swift
import TalkieKit

private let log = Log(.database)

// Usage
log.info("Starting operation")
log.debug("Details: \(value)")
log.warning("Something unexpected")
log.error("Failed: \(error)")
log.info("Critical startup", critical: true)  // Synchronous, crash-safe
```

**Categories:** `.system`, `.audio`, `.transcription`, `.database`, `.xpc`, `.sync`, `.ui`, `.workflow`

**Do NOT use:**
- `import os.log` or `import os`
- `Logger(subsystem:category:)`
- `os_log()` / `os_signpost()`
- `print()` (except temporary debugging)
- `NSLog()`

TalkieLogger routes to Console.app, file logs, and handles critical startup logging. SwiftLint will flag violations.

---

## Never Hardcode Paths

**Do NOT hardcode file system paths like `/Applications/Talkie.app` or DerivedData paths.**

```swift
// ❌ Wrong
let appPath = "/Applications/Talkie.app"
let debugPath = "\(NSHomeDirectory())/Library/Developer/Xcode/DerivedData/.../Talkie.app"

// ✅ Correct - URL scheme (macOS finds registered handler)
NSWorkspace.shared.open(URL(string: "talkie://live/recent")!)

// ✅ Correct - Bundle identifier lookup
if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "jdi.talkie") {
    NSWorkspace.shared.openApplication(at: appURL, configuration: config)
}

// ✅ Correct - Environment detection
let env = TalkieEnvironment.current  // .production, .staging, .dev
```

This ensures dev, staging, and production builds work correctly without code changes.
