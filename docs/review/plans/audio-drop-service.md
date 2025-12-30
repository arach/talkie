# Plan: AudioDropService Extraction

**Status:** ✅ Implemented
**Source:** `Views/Live/DictationListView.swift` (lines 100-266) - THE ACTIVE VIEW
**Legacy:** `Views/Live/History/HistoryView.swift` (2983 lines) - VESTIGIAL, NOT USED
**Target:** `Services/AudioDropService.swift`

---

## Context

- **DictationListView** (871 lines) is the actual view used in the unified Talkie sidebar
- **HistoryView** (2983 lines) is from standalone TalkieLive era - no longer used
- Drop handling currently creates `LiveDictation` but should create `VoiceMemo`

---

## Goal

Extract audio file drop handling into a reusable, app-wide service that:
1. Accepts dropped audio files from anywhere in the app
2. Validates, copies, extracts metadata, and transcribes
3. Creates a VoiceMemo (not a LiveDictation)

---

## Current State

DictationListView has ~165 lines of drop handling (cleaner than HistoryView):

```
handleAudioDrop()           → Validates file, copies to temp, dispatches processing
processDroppedAudio()       → Transcribes, creates LiveDictation
showDropError()             → Error feedback with timeout
dropZoneOverlay             → Visual overlay UI
```

**Problems:**
- Creates LiveDictation instead of VoiceMemo
- Callback-based async in handleAudioDrop (should be async/await)
- Hardcoded model ID ("parakeet:v3")
- Only works in DictationListView (should be app-wide)

---

## Proposed Design

### Service Interface

```swift
/// App-wide audio file drop handling
actor AudioDropService {
    static let shared = AudioDropService()

    /// Supported audio formats
    static let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "aac", "flac", "ogg", "mp4", "caf"]

    /// Process a dropped audio file and create a memo
    /// - Parameters:
    ///   - providers: NSItemProviders from the drop
    ///   - onProgress: Optional progress callback (for UI updates)
    /// - Returns: The created MemoModel, or throws on failure
    func processDroppedAudio(
        providers: [NSItemProvider],
        onProgress: ((DropProgress) -> Void)? = nil
    ) async throws -> MemoModel

    /// Progress states for UI feedback
    enum DropProgress {
        case validating
        case copying
        case extractingMetadata
        case transcribing(filename: String, size: String)
        case complete
    }

    /// Errors that can occur during drop processing
    enum DropError: LocalizedError {
        case noValidProvider
        case unsupportedFormat(String)
        case copyFailed
        case transcriptionFailed(Error)
    }
}
```

### Internal Structure

```swift
// MARK: - Private Implementation

extension AudioDropService {
    /// Extract and validate file from provider
    private func extractFile(from provider: NSItemProvider) async throws -> URL

    /// Copy temp file to permanent storage
    private func copyToStorage(_ url: URL) async throws -> String  // returns filename

    /// Extract audio metadata (fixed async - no race conditions)
    private func extractMetadata(from url: URL) async -> AudioMetadata

    /// Transcribe and create memo
    private func transcribeAndCreateMemo(
        storedFilename: String,
        originalFilename: String,
        metadata: AudioMetadata
    ) async throws -> MemoModel
}

/// Structured metadata (replaces ad-hoc dictionary)
struct AudioMetadata {
    let duration: TimeInterval?
    let sampleRate: Int?
    let channels: Int?
    let bitrate: Int?
    let fileSize: Int64
    let sourceFilename: String
    let fileExtension: String
    let createdAt: Date?
    let modifiedAt: Date?
    // Optional ID3/iTunes tags
    let title: String?
    let artist: String?
    let album: String?
}
```

---

## App-Level Drop Zone

### Option A: Window-level modifier

```swift
// In TalkieApp.swift or main ContentView
.onDrop(of: [.audio, .fileURL], isTargeted: $isDropTargeted) { providers in
    Task {
        do {
            let memo = try await AudioDropService.shared.processDroppedAudio(providers: providers)
            // Navigate to new memo or show confirmation
        } catch {
            // Show error toast
        }
    }
    return true
}
```

### Option B: Dedicated drop zone view

```swift
struct AppDropZone<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var isTargeted = false
    @State private var progress: AudioDropService.DropProgress?

    var body: some View {
        content()
            .onDrop(of: [.audio, .fileURL], isTargeted: $isTargeted) { ... }
            .overlay { if isTargeted || progress != nil { DropOverlay(progress: progress) } }
    }
}
```

---

## Migration Steps

### Step 1: Create AudioDropService
- [ ] Create `Services/AudioDropService.swift`
- [ ] Define actor with interface above
- [ ] Implement `extractFile(from:)` with proper async/await
- [ ] Implement `copyToStorage(_:)` using existing AudioStorage
- [ ] Implement `extractMetadata(from:)` with proper async

### Step 2: Wire to MemoRepository
- [ ] Implement `transcribeAndCreateMemo()`
- [ ] Create MemoModel with audio data
- [ ] Save via MemoRepository.saveMemo()
- [ ] Handle transcription via EngineClient
- [ ] Use SettingsManager for model selection (not hardcoded)

### Step 3: Add App-Level Drop Zone
- [ ] Decide: Window modifier vs dedicated view
- [ ] Add to NavigationViewNative.swift (the unified shell)
- [ ] Implement progress overlay UI
- [ ] Add success/error feedback
- [ ] Navigate to new memo after creation

### Step 4: Clean Up DictationListView
- [ ] Remove `handleAudioDrop()` (~60 lines)
- [ ] Remove `processDroppedAudio()` (~55 lines)
- [ ] Remove `showDropError()` (~12 lines)
- [ ] Remove `dropZoneOverlay` (~32 lines)
- [ ] Remove drop-related @State properties (3 properties)
- [ ] Total: ~160 lines removed

### Step 5: Deprecate HistoryView
- [ ] Verify HistoryView is not referenced anywhere
- [ ] Add deprecation comment or move to Legacy/
- [ ] Consider deleting entirely (2983 lines of dead code)

---

## Open Questions

1. **Where should the drop zone live?**
   - TalkieApp.swift (truly global)
   - NavigationView (main content area only)
   - Both main app and TalkieLive?

2. **Post-drop navigation:**
   - Auto-navigate to new memo?
   - Show toast with "View" button?
   - Just add to list, no navigation?

3. **Audio storage:**
   - Use existing AudioStorage (shared with Live)?
   - Create memo-specific storage path?

4. **Progress UI:**
   - Full-screen overlay (current)?
   - Corner notification/toast?
   - Status bar indicator?

---

## Dependencies

- `AudioStorage` - file copying (existing)
- `EngineClient` - transcription (existing)
- `MemoRepository` - memo creation (existing)
- `SettingsManager` - selected transcription model (existing)

---

## Estimated Scope

- **New code:** ~200 lines (AudioDropService)
- **Removed from HistoryView:** ~300 lines
- **Net change:** -100 lines, cleaner architecture
