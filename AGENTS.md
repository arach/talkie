# AGENTS.md

Instructions for AI coding agents working on this repository.

---

## Project Overview

**Talkie** is a voice memo app with AI-powered workflows:

- **iOS** (`apps/ios/`): SwiftUI + SwiftData mobile app
- **macOS** (`apps/macos/`): SwiftUI desktop companion with workflow execution

Voice memos recorded on iOS sync via CloudKit to macOS, where workflows process transcripts through LLMs, extract tasks, create reminders, and more.

---

## Target Platforms

| Platform | Minimum | Language | UI Framework |
|----------|---------|----------|--------------|
| iOS | 26.0 | Swift 6.2 | SwiftUI |
| macOS | 26.0 (Tahoe) | Swift 6.2 | SwiftUI |

---

## Engineering Docs and Studio Review

Numbered engineering docs live in `docs/specs/tlk-NNN-*.md`. They are the
source of truth; Studio can provide the review and discussion surface for them.

When creating or substantially updating a TLK doc:

- Add `**Studio**: /eng/tlk-NNN` in the metadata block so dev agents know where
  to bring the document back for review.
- If the doc has a concrete Studio visual study, add `**Surface**: /route-name`
  beside the Studio doc route.
- Treat the Studio route as the place to discuss architecture and product
  implications, instead of leaving that context only in chat.
- If the doc drives a new visual surface, link or create the relevant Studio
  route before Swift polish when practical. If the work is code-first, call out
  the Studio follow-up explicitly.
- For architecture-significant docs, consider asking a Scout sibling for review
  and write useful review artifacts beside the doc, for example
  `docs/specs/tlk-NNN-review-<reviewer>.md`.

---

## Build Commands

### iOS

```bash
cd apps/ios
open "Talkie-iOS.xcodeproj"

# Build
xcodebuild -project Talkie-iOS.xcodeproj -scheme Talkie \
  -destination 'platform=iOS Simulator,name=iPhone 16' build

# Test
xcodebuild -project Talkie-iOS.xcodeproj -scheme Talkie \
  -destination 'platform=iOS Simulator,name=iPhone 16' test
```

### macOS

Prefer the consolidated macOS script for rebuilding or relaunching the main apps. It knows the workspace shape, app aliases, local build output, signing defaults, dev app install path, and how to stop conflicting instances.

```bash
cd apps/macos

# Build both main macOS apps without launching
./run.sh TalkieAgent Talkie --clean --no-launch

# Build and launch one app
./run.sh TalkieAgent --clean
./run.sh Talkie --clean

# See aliases and options
./run.sh --list
```

Use raw `xcodebuild` when you specifically need lower-level diagnostics, tests, or a project-only build:

```bash
cd apps/macos/Talkie
open Talkie.xcodeproj

# Build
xcodebuild -scheme Talkie -destination 'platform=macOS' build

# Test
xcodebuild -scheme Talkie -destination 'platform=macOS' test
```

---

## Codex Xcode Build Hygiene

When running `xcodebuild` from Codex, do not place DerivedData under `/tmp` or `/private/tmp` and do not use ad hoc paths such as `/private/tmp/talkie-*`.

Use a stable, reusable DerivedData directory for each project/scheme under the
user cache area. Keep the environment override so specialized workflows can
select a different stable cache without editing commands:

```bash
mkdir -p "$HOME/Library/Caches/codex-builds"
DERIVED_DATA_DIR="${TALKIE_IOS_DERIVED_DATA_DIR:-$HOME/Library/Caches/codex-builds/talkie-ios-talkie}"
xcodebuild ... -derivedDataPath "$DERIVED_DATA_DIR"
```

Reuse that path across normal builds; do not create a fresh directory for every
invocation. Serialize builds that target the same cache. If an isolated cache is
truly required to diagnose cache state or run concurrently, give it a precise
purpose-specific name and install a mandatory cleanup trap before building:

```bash
DERIVED_DATA_DIR="$HOME/Library/Caches/codex-builds/talkie-ios-isolated"
trap 'rm -rf -- "$DERIVED_DATA_DIR"' EXIT
```

Delete disposable build caches with `rm -rf -- "$DERIVED_DATA_DIR"`; never move
them to Trash because that does not reclaim disk space. Never delete a cache
while `xcodebuild` or another process is using it.

The repository provides `scripts/tmp-janitor.sh` and the daily launchd job
`scripts/launchd/com.user.tmp-janitor.plist`. The janitor removes positively
identified Talkie Xcode DerivedData older than 24 hours from legacy temporary
locations and `$HOME/Library/Caches/codex-builds/`. It also scans
`$HOME/.Trash` when macOS privacy permissions allow it, but agents must never
depend on Trash cleanup. It skips open or inaccessible directories and defaults
to a dry run when invoked manually.

Install or refresh the safety net with:

```bash
mkdir -p "$HOME/bin" "$HOME/Library/LaunchAgents"
install -m 755 scripts/tmp-janitor.sh "$HOME/bin/tmp-janitor.sh"
install -m 644 scripts/launchd/com.user.tmp-janitor.plist "$HOME/Library/LaunchAgents/com.user.tmp-janitor.plist"
launchctl bootout "gui/$UID" "$HOME/Library/LaunchAgents/com.user.tmp-janitor.plist" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$HOME/Library/LaunchAgents/com.user.tmp-janitor.plist"
```

### Disk hygiene: investigate, then act

Agents drive builds and tests on this machine, so agents own the forensic trail.
Caution about deleting other projects' work is correct. Skipping investigation is
not.

When asked to free disk (or after a large parallel test run):

1. **Investigate** — inventory sizes, mtimes, and ownership signals before deleting.
2. **Classify** each candidate: this-project / other-project / unknown / in-use.
3. **Act** only on strong evidence. Leave unknowns alone and list them.
4. **Delete with `rm -rf`**, never `mv` to Trash (Trash does not free space until emptied).

**High-signal locations**

| Path | What it is | Typical owner signal |
|------|------------|----------------------|
| `~/Library/Developer/XCTestDevices/` | Parallel-test simulator clones (often multi‑GB each) | Installed app bundle IDs (`to.talkie.app`, UITests runner), parent sim name, mtime vs recent `xcodebuild test` |
| `~/Library/Caches/codex-builds/` | Stable/purpose DerivedData for agent builds | Directory name (`talkie-ios-talkie`, purpose-specific); only drop caches you finished and nothing is using |
| `~/.codex/worktrees/` | Codex worktrees | `git remote` / branch; only remove finished Talkie worktrees you can prove abandoned |
| `~/Library/Developer/Xcode/DerivedData/` | Xcode default DerivedData | Prefer thinning finished project folders; do not mass-wipe active builds |
| `~/Library/Developer/Xcode/iOS DeviceSupport/` | On-device debug symbols | Keep unless explicitly told to prune old devices |

**XCTestDevices (common failure mode)**

Talkie test schemes set `parallelizable = YES`. Parallel `xcodebuild test` clones
the destination sim into `XCTestDevices` and often leaves the clones behind.
Clones are not labeled with a session id; attribute them by installed apps,
destination name (e.g. iPhone 17 Pro), and timing. Prefer
`-parallel-testing-enabled NO` for one-off agent test runs when parallel speed
is not required. After tests finish, prune leftover clones you can attribute to
Talkie and that are not in use.

**Do not**

- Delete another project's worktrees, builds, or clearly other-owned clones.
- Touch physical DeviceSupport unless the operator asked.
- Treat "unclear session ownership" as a reason to skip the investigation table.

---

## Video Clip Context

When inspecting Talkie tray clips, screen recordings, recently shared videos, or
visual context captured during dictation, prefer the repo skill in
`skills/video-context/`. Default to:

1. `ffprobe` for duration, size, dimensions, frame rate, and codec.
2. A 4x4 `ffmpeg` contact sheet.
3. Visual inspection of the contact sheet before making claims about the clip.

Talkie tray clips usually live under:

```text
~/Library/Application Support/Talkie/Tray/clips/
```

Use temporary contact-sheet outputs unless preserving the artifact is useful for
review.

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
apps/ios/
├── Talkie iOS/
│   ├── App/           # TalkieApp.swift, AppDelegate
│   ├── Models/        # SwiftData models, Persistence
│   ├── Views/         # SwiftUI views by feature
│   ├── Services/      # Audio, Transcription, Sync
│   └── Resources/     # Assets, Info.plist
├── Talkie-iOS.xcodeproj
└── archived-talkie-os/ # old Talkie OS.xcodeproj (see archived-talkie-os/README.md)

apps/macos/
├── Talkie/
│   ├── App/
│   ├── Models/
│   ├── Views/
│   ├── Services/
│   │   └── LLM/       # Provider implementations
│   ├── Workflow/      # TWF execution engine
│   ├── Resources/
│   │   └── StarterWorkflows/
│   └── Talkie.xcodeproj
├── TalkieAgent/
└── TalkieServer/
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
- Prefer Swift Package Manager for apps/ios/macOS
- Prefer Bun for Node.js projects
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
if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "to.talkie.app") {
    NSWorkspace.shared.openApplication(at: appURL, configuration: config)
}

// ✅ Correct - Environment detection
let env = TalkieEnvironment.current  // .production, .staging, .dev
```

This ensures dev, staging, and production builds work correctly without code changes.
