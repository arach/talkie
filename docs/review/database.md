# Database Module

`macOS/Talkie/Database/` - Live dictation SQLite (shared with TalkieLive)

---

## Files

### LiveDatabase.swift (~500 lines)
GRDB manager for live.sqlite. Handles dictation records, state sync, migrations.

**Discussion:**
- Clean GRDB setup with shared DatabaseQueue
- 5 migrations (v1-v5): table creation, column renames, indexes, live_state
- Excellent error handling: falls back to in-memory DB if disk fails
- Good pruning support with preview
- Orphan audio file cleanup

**Observations:**
- Uses static `shared` property (standard GRDB pattern)
- No explicit WAL mode - GRDB uses it by default
- Migration v1 handles both fresh install and legacy upgrade gracefully

---

### LiveDictation.swift (~364 lines)
Dictation record model with GRDB conformance.

**Discussion:**
- Clean enums: TranscriptionStatus, PromotionStatus, QuickActionKind
- Full GRDB protocols: FetchableRecord, PersistableRecord
- Good computed properties: `isQueued`, `canRetryTranscription`, `needsAction`
- Proper `didInsert` for auto-increment ID handling

**Observations:**
- Well-structured model with context (app, window) and metrics (perf*)
- Metadata stored as JSON blob for flexibility

---

### AudioStorage.swift (~248 lines)
Audio file management for dictation recordings.

**Discussion:**
- Shared directory: `~/Library/Application Support/Talkie/Audio/`
- Async storage calculation with 30s caching (avoids blocking UI)
- Orphan file pruning with preview
- Deprecated sync methods with proper warnings

**Observations:**
- Good pattern: apps unsandboxed so shared storage works
- UUID-based filenames prevent collisions
- Cache invalidation on delete

---

## TODO

- [ ] Consider adding WAL checkpoint calls for large databases

## Done

- Initial review pass complete - no major issues found
- Module is well-structured and production-ready
