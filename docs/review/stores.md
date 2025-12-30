# Stores Module

`macOS/Talkie/Stores/` - State management

---

## Overview

The Stores module provides client-side state management that bridges TalkieLive's GRDB database with Talkie's UI. Uses incremental sync for efficient updates.

---

## Files

### DictationStore.swift (~618 lines)
Local cache for live dictations with incremental sync from GRDB database.

**Discussion:**
- **Singleton:** `DictationStore.shared`
- **Pattern:** @Observable for SwiftUI integration
- **Data Source:** Polls `LiveDatabase` (GRDB) for dictations
- **Incremental Sync:** Uses `lastSeenID` high water mark to only fetch new records
- **Initial Load:** Lazy loading of first 50 dictations for fast startup
- **TTL:** 48-hour default expiration, configurable

**Key Properties:**
- `dictations: [Dictation]` - Local cache of dictations
- `cachedCount: Int` - Persisted to UserDefaults for instant load
- `ttlHours: Int` - Time-to-live for auto-pruning

**Key Methods:**
- `add(_:durationSeconds:metadata:)` - Add new dictation
- `addLive(_:)` - Add LiveDictation directly
- `update(_:)` / `updateText(for:newText:modelId:)` - Update existing
- `delete(_:)` - Remove dictation
- `clear()` - Remove all dictations
- `pruneExpired()` - Remove old dictations past TTL
- `refresh()` - Incremental sync from database
- `search(_:)` - Full-text search via LiveDatabase

**Monitoring:**
- `startMonitoring()` - Begin 30s polling fallback + XPC callbacks
- `stopMonitoring()` - Cancel polling timer

**Incremental Sync Algorithm:**
1. Track `lastSeenID` (highest database ID processed)
2. On refresh, fetch only records with `id > lastSeenID`
3. Merge new records with existing cache
4. Preserve UUID stability for SwiftUI diffing

---

### DictationMetadata
Rich context captured during dictation.

**Discussion:**
- **Start Context:** App/window where recording started
- **End Context:** App/window where recording stopped
- **Rich Context:**
  - `documentURL` - File path or web URL
  - `browserURL` - Full URL for browsers (from AX)
  - `focusedElementRole` - AXTextArea, AXWebArea, etc.
  - `focusedElementValue` - Truncated content
  - `terminalWorkingDir` - For terminal apps

- **Performance Metrics (perf prefix):**
  - `perfEngineMs` - Time in TalkieEngine
  - `perfEndToEndMs` - Stop recording → delivery
  - `perfInAppMs` - TalkieLive processing
  - `perfPreMs` / `perfPostMs` - Debug timing

- **Audio:**
  - `audioFilename` - Reference to stored audio file
  - `audioURL` - Computed full path
  - `hasAudio` - File existence check

- **Engine Trace:**
  - `sessionID` - 8-char hex for Engine trace deep linking

---

### Dictation
Dictation data model for UI display.

**Discussion:**
- UUID-identified for SwiftUI list stability
- `liveID: Int64?` - Link to database record
- `timestamp: Date` - Creation time
- `durationSeconds: Double?` - Recording duration
- `wordCount` / `characterCount` - Computed properties

---

### ContextCapture
Helper for capturing app context during recording.

**Discussion:**
- Uses `NSWorkspace` for frontmost app detection
- Uses Accessibility APIs (`AXUIElement`) for window title
- `captureCurrentContext()` - Delegates to `ContextCaptureService`
- `fillEndContext(in:)` - Capture where user is when recording stops
- `getFrontmostApp()` / `activateApp(_:)` - App activation helpers

---

## Architecture Notes

**Why Incremental Sync:**
- Full database refresh is expensive with many dictations
- UI only needs to know about new records
- Preserves UUID stability for smooth SwiftUI animations

**TTL Management:**
- Automatic pruning of old dictations
- Respects `ttlHours` setting (default 48)
- Called periodically or on demand

**Caching Strategy:**
- `cachedCount` persisted to UserDefaults
- Enables instant count display before DB loads
- Synced after each mutation

---

## TODO

- [ ] Consider replacing polling with pure XPC callbacks
- [ ] Add pagination for very large dictation lists
- [ ] Consider moving metadata building to extension

## Done

- [x] Complete documentation
- [x] Document incremental sync algorithm
- [x] Document metadata structure
