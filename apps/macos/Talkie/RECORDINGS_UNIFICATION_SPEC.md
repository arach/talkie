# Unified Recordings Schema Specification

## Overview

Unify `voice_memos` (GRDB) and `dictations` (live.sqlite) into a single `recordings` table with file-based audio storage. This simplifies the data model, eliminates hidden Core Data dependencies, and enables a unified UI.

## Goals

1. **One table** - All recordings in `recordings` table
2. **File-based audio** - All audio in `Audio/` folder, referenced by ID
3. **Type field for behavior** - `memo` vs `dictation` controls sync, TTL, AI processing
4. **Source field for provenance** - Where the recording originated
5. **Clean sync** - CloudKit syncs `type = 'memo'` only, ignores dictations
6. **Unified UI** - One RecordingsScreen, one player component, one detail view

---

## Schema: `recordings` table

```sql
CREATE TABLE recordings (
    -- Identity
    id TEXT PRIMARY KEY,                    -- UUID string
    type TEXT NOT NULL DEFAULT 'dictation', -- 'memo' | 'dictation'

    -- Content
    text TEXT,                              -- Transcript text
    title TEXT,                             -- User-set title (memos)
    notes TEXT,                             -- User annotations (memos)

    -- Audio (file-based, derived path from ID)
    duration DOUBLE NOT NULL DEFAULT 0,     -- Duration in seconds
    hasAudio INTEGER NOT NULL DEFAULT 0,    -- 1 if audio file exists

    -- Timestamps
    createdAt DATETIME NOT NULL,            -- When recorded
    lastModified DATETIME,                  -- Last user edit
    deletedAt DATETIME,                     -- Soft delete (memos only)

    -- Origin/Provenance (immutable after creation)
    source TEXT NOT NULL,                   -- 'mac' | 'iphone' | 'watch' | 'live'
    sourceDeviceId TEXT,                    -- Device identifier

    -- Promotion tracking
    promotedAt DATETIME,                    -- When dictation became memo (NULL if always memo or still dictation)

    -- Transcription state
    transcriptionStatus TEXT DEFAULT 'success', -- 'pending' | 'success' | 'failed'
    transcriptionError TEXT,                    -- Error message if failed
    transcriptionModel TEXT,                    -- Which STT model was used

    -- AI Processing (memos only)
    summary TEXT,                           -- AI-generated summary
    tasks TEXT,                             -- Extracted tasks (JSON array)
    reminders TEXT,                         -- Extracted reminders (JSON array)
    isProcessingSummary INTEGER DEFAULT 0,  -- Processing flags
    isProcessingTasks INTEGER DEFAULT 0,
    isProcessingReminders INTEGER DEFAULT 0,
    autoProcessed INTEGER DEFAULT 0,        -- Was AI auto-triggered

    -- Sync (memos only)
    cloudSyncedAt DATETIME,                 -- Last CloudKit sync

    -- Workflows
    pendingWorkflowIds TEXT,                -- JSON array of workflow UUIDs

    -- Context metadata (JSON blob for dictation-specific data)
    metadata TEXT                           -- See metadata schema below
);

-- Indexes
CREATE INDEX idx_recordings_type ON recordings(type);
CREATE INDEX idx_recordings_createdAt ON recordings(createdAt DESC);
CREATE INDEX idx_recordings_source ON recordings(source);
CREATE INDEX idx_recordings_deletedAt ON recordings(deletedAt) WHERE deletedAt IS NOT NULL;
CREATE INDEX idx_recordings_cloudSync ON recordings(cloudSyncedAt) WHERE type = 'memo';
CREATE INDEX idx_recordings_transcriptionStatus ON recordings(transcriptionStatus) WHERE transcriptionStatus != 'success';
```

---

## Metadata JSON Schema (for `metadata` column)

Dictation-specific context stored as JSON:

```json
{
  "app": {
    "bundleId": "com.tinyspeck.slackmacgap",
    "name": "Slack",
    "windowTitle": "#general - Slack"
  },
  "endApp": {
    "bundleId": "com.tinyspeck.slackmacgap",
    "name": "Slack",
    "windowTitle": "#general - Slack"
  },
  "context": {
    "browserURL": "https://example.com",
    "terminalWorkingDir": "/Users/example/dev",
    "documentURL": "file:///path/to/doc.md"
  },
  "performance": {
    "engineMs": 245,
    "endToEndMs": 312,
    "inAppMs": 67,
    "sessionId": "uuid-string"
  },
  "routing": {
    "mode": "typing",
    "wasRouted": true,
    "pasteTimestamp": 1705276800.0
  },
  "audio": {
    "peakAmplitude": 0.8,
    "averageAmplitude": 0.3
  }
}
```

Memos typically have `metadata = NULL` or minimal context.

---

## Audio Storage

### Location
```
~/Library/Application Support/Talkie/Audio/{recording-id}.m4a
```

### Rules
1. Audio path is **derived from recording ID** - no path column needed
2. `hasAudio` flag indicates if file exists (avoids filesystem checks)
3. All recordings use same folder - no separate dictation/memo audio
4. Audio files created at recording time, never moved

### Helper
```swift
enum AudioStorage {
    static let audioDirectory: URL = // ~/Library/Application Support/Talkie/Audio/

    static func url(for recordingId: UUID) -> URL {
        audioDirectory.appendingPathComponent("\(recordingId.uuidString).m4a")
    }

    static func exists(for recordingId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: recordingId).path)
    }
}
```

---

## Type Behaviors

| Behavior | `type = 'memo'` | `type = 'dictation'` |
|----------|-----------------|----------------------|
| CloudKit sync | Yes | No |
| TTL/auto-delete | No (soft delete only) | Yes (configurable) |
| AI processing | Available | Not available |
| Transcript versions | Yes | No |
| Workflow runs | Yes | No |
| Editable title/notes | Yes | No |
| Waveform stored | Optional | No |

---

## Promotion Flow

When user promotes a dictation to memo:

```sql
UPDATE recordings SET
    type = 'memo',
    promotedAt = CURRENT_TIMESTAMP,
    cloudSyncedAt = NULL  -- Triggers sync on next pass
WHERE id = ?
```

- **One record** - no duplication
- **Source preserved** - `source = 'live'` stays forever
- **Provenance clear** - `promotedAt IS NOT NULL` means "was dictation"

---

## Swift Model

```swift
struct Recording: Identifiable, Codable, Hashable, FetchableRecord, PersistableRecord {
    // Identity
    let id: UUID
    var type: RecordingType

    // Content
    var text: String?
    var title: String?
    var notes: String?

    // Audio
    var duration: Double
    var hasAudio: Bool

    // Timestamps
    var createdAt: Date
    var lastModified: Date?
    var deletedAt: Date?

    // Origin
    let source: RecordingSource
    let sourceDeviceId: String?

    // Promotion
    var promotedAt: Date?

    // Transcription
    var transcriptionStatus: TranscriptionStatus
    var transcriptionError: String?
    var transcriptionModel: String?

    // AI (memos)
    var summary: String?
    var tasks: String?
    var reminders: String?
    var isProcessingSummary: Bool
    var isProcessingTasks: Bool
    var isProcessingReminders: Bool
    var autoProcessed: Bool

    // Sync
    var cloudSyncedAt: Date?

    // Workflows
    var pendingWorkflowIds: String?

    // Metadata
    var metadata: RecordingMetadata?

    // MARK: - Computed

    var audioURL: URL? {
        guard hasAudio else { return nil }
        return AudioStorage.url(for: id)
    }

    var audioData: Data? {
        guard let url = audioURL else { return nil }
        return try? Data(contentsOf: url)
    }

    var isMemo: Bool { type == .memo }
    var isDictation: Bool { type == .dictation }
    var wasPromoted: Bool { promotedAt != nil }
    var isDeleted: Bool { deletedAt != nil }
}

enum RecordingType: String, Codable {
    case memo
    case dictation
}

enum RecordingSource: String, Codable {
    case mac
    case iphone
    case watch
    case live
}

enum TranscriptionStatus: String, Codable {
    case pending
    case success
    case failed
}

struct RecordingMetadata: Codable, Hashable {
    var app: AppContext?
    var endApp: AppContext?
    var context: RichContext?
    var performance: PerformanceMetrics?
    var routing: RoutingInfo?
    var audio: AudioMetrics?
}

struct AppContext: Codable, Hashable {
    var bundleId: String?
    var name: String?
    var windowTitle: String?
}

struct RichContext: Codable, Hashable {
    var browserURL: String?
    var terminalWorkingDir: String?
    var documentURL: String?
}

struct PerformanceMetrics: Codable, Hashable {
    var engineMs: Int?
    var endToEndMs: Int?
    var inAppMs: Int?
    var sessionId: String?
}

struct RoutingInfo: Codable, Hashable {
    var mode: String?
    var wasRouted: Bool?
    var pasteTimestamp: Double?
}

struct AudioMetrics: Codable, Hashable {
    var peakAmplitude: Float?
    var averageAmplitude: Float?
}
```

---

## Related Tables

### `transcript_versions` (unchanged, FK to recordings)
```sql
CREATE TABLE transcript_versions (
    id TEXT PRIMARY KEY,
    recordingId TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
    version INTEGER NOT NULL,
    content TEXT,
    engine TEXT,
    sourceType TEXT,
    createdAt DATETIME,
    transcriptionDurationMs INTEGER
);
```

### `workflow_runs` (unchanged, FK to recordings)
```sql
CREATE TABLE workflow_runs (
    id TEXT PRIMARY KEY,
    recordingId TEXT NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
    workflowId TEXT,
    workflowName TEXT,
    workflowIcon TEXT,
    status TEXT,
    output TEXT,
    stepOutputsJSON TEXT,
    providerName TEXT,
    modelId TEXT,
    runDate DATETIME
);
```

---

## Migration Plan

### Phase 1: Create New Schema (GRDB migration v8)

1. Create `recordings` table with full schema
2. Migrate data from `voice_memos`:
   ```sql
   INSERT INTO recordings (id, type, text, title, notes, ...)
   SELECT id, 'memo', transcription, title, notes, ...
   FROM voice_memos;
   ```
3. Update `transcript_versions` FK from `memoId` to `recordingId`
4. Update `workflow_runs` FK from `memoId` to `recordingId`

### Phase 2: TalkieAgent Writes to Unified DB

1. TalkieAgent connects to `talkie_grdb.sqlite` (read-write)
2. Writes new dictations to `recordings` table with `type = 'dictation'`
3. Remove `live.sqlite` dependency

### Phase 3: Import Historical Dictations

1. One-time migration of `live.sqlite` → `recordings`
2. Copy audio files to unified `Audio/` folder (or leave in place if already there)
3. Deprecate `live.sqlite`

### Phase 4: Update UI Layer

1. Create `RecordingRepository` (replaces `LocalRepository` + `LiveDatabase`)
2. Create `RecordingsScreen` (replaces `MemosScreen` + `DictationsScreen`)
3. Create unified `RecordingDetail` view
4. Create unified `AudioPlayer` component

### Phase 5: Update Sync Layer

1. Core Data bridge syncs `recordings WHERE type = 'memo'`
2. Materialize audio from Core Data `audioData` → `Audio/{id}.m4a`
3. Set `hasAudio = 1` after materialization

### Phase 6: Cleanup

1. Remove `voice_memos` table
2. Remove `LiveDatabase.swift`, `LiveDictation.swift`
3. Remove `DictationStore.swift`
4. Remove duplicate audio storage code
5. Archive `live.sqlite` migration code

---

## File Changes Summary

### New Files
- `Data/Models/Recording.swift` - Unified model
- `Data/Database/RecordingRepository.swift` - Unified repository
- `Views/Recordings/RecordingsScreen.swift` - Unified list view
- `Views/Recordings/RecordingDetail.swift` - Unified detail view
- `Components/AudioPlayer.swift` - Unified player component

### Modified Files
- `Data/Database/DatabaseManager.swift` - Add migration v8
- `Workflow/WorkflowExecutor.swift` - Use Recording instead of MemoModel
- `Services/CloudKitSyncManager.swift` - Sync recordings where type = 'memo'
- `Views/AppNavigation.swift` - Update sidebar
- `TalkieAgent/` - Write to unified database

### Deprecated/Removed Files
- `Data/Models/MemoModel.swift` → Replaced by Recording
- `Database/LiveDictation.swift` → Replaced by Recording
- `Database/LiveDatabase.swift` → Replaced by RecordingRepository
- `Stores/DictationStore.swift` → Replaced by RecordingRepository
- `Views/Memos/MemosScreen.swift` → Replaced by RecordingsScreen
- `Views/Live/DictationsScreen.swift` → Replaced by RecordingsScreen

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Data loss during migration | Backup databases before migration, keep originals for rollback |
| TalkieAgent write conflicts | Use WAL mode, short transactions, SQLITE_BUSY retry |
| CloudKit sync breaks | Test sync thoroughly, keep Core Data bridge intact initially |
| Audio files orphaned | Audit script to find orphaned files, don't delete originals |
| Performance regression | Index key columns, test with production data volume |

---

## Success Criteria

1. All recordings visible in unified RecordingsScreen
2. Audio playback works for all recording types
3. Promotion (dictation → memo) works with single UPDATE
4. CloudKit sync only syncs memos
5. TalkieAgent writes without conflicts
6. No duplicate audio storage
7. Clean codebase with single Recording model

---

## Open Questions

1. **Waveform data** - Compute on demand or cache to disk?
2. **TTL for dictations** - Keep existing TTL logic or simplify?
3. **live.sqlite retention** - Delete after migration or keep as backup?
4. **Rollout strategy** - Big bang or incremental feature flag?
