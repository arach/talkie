# Recordings Unification: Implementation Game Plan

## Prerequisites

Before starting:
- [ ] Backup `talkie_grdb.sqlite`
- [ ] Backup `live.sqlite`
- [ ] Backup `Audio/` folder
- [ ] Backup `_EXTERNAL_DATA/` folder
- [ ] Commit current branch state

---

## Step 1: Create Recording Model (Day 1)

**Goal:** Define the new `Recording` Swift struct without touching the database yet.

### Tasks
1. Create `Data/Models/Recording.swift` with full model definition
2. Create `RecordingType`, `RecordingSource`, `TranscriptionStatus` enums
3. Create `RecordingMetadata` and nested structs
4. Add GRDB conformances (`FetchableRecord`, `PersistableRecord`, `TableRecord`)
5. Add computed properties (`audioURL`, `audioData`, `isMemo`, etc.)

### Validation
- Model compiles
- No runtime changes yet

---

## Step 2: Create Database Schema (Day 1)

**Goal:** Add the `recordings` table via GRDB migration.

### Tasks
1. Add migration v8 to `DatabaseManager.swift`:
   ```swift
   migrator.registerMigration("v8_unified_recordings") { db in
       // Create recordings table
       // Create indexes
   }
   ```
2. Run migration on empty database to validate schema
3. Write migration tests

### Validation
- Migration runs successfully
- Table schema matches spec
- Indexes created

---

## Step 3: Create Recording Repository (Day 1-2)

**Goal:** Build the data access layer for recordings.

### Tasks
1. Create `Data/Database/RecordingRepository.swift`
2. Implement core CRUD:
   - `fetchRecordings(filter:sort:limit:offset:search:)`
   - `fetchRecording(id:)`
   - `saveRecording(_:)`
   - `deleteRecording(id:)` (soft delete for memos)
   - `hardDeleteRecording(id:)` (TTL cleanup for dictations)
3. Implement promotion:
   - `promoteToMemo(id:)`
4. Implement queries:
   - `fetchByType(_:)`
   - `fetchBySource(_:)`
   - `countRecordings(filter:)`
   - `searchRecordings(query:)`

### Validation
- Unit tests pass
- Can create/read/update/delete recordings
- Promotion works correctly

---

## Step 4: Migrate Memo Data (Day 2)

**Goal:** Copy existing memos to the new recordings table.

### Tasks
1. Add data migration in v8:
   ```swift
   // Copy voice_memos to recordings
   try db.execute(sql: """
       INSERT INTO recordings (id, type, text, title, ...)
       SELECT id, 'memo', transcription, title, ...
       FROM voice_memos
   """)
   ```
2. Update `transcript_versions` foreign key
3. Update `workflow_runs` foreign key
4. Verify row counts match

### Validation
- All memos migrated
- Related records (transcript_versions, workflow_runs) preserved
- No data loss

---

## Step 5: Migrate Dictation Data (Day 2)

**Goal:** Import dictations from live.sqlite to recordings table.

### Tasks
1. Create one-time migration script:
   ```swift
   func migrateDictationsToRecordings() async throws {
       let dictations = LiveDatabase.all()
       for dictation in dictations {
           let recording = Recording(from: dictation)
           try await repository.saveRecording(recording)
       }
   }
   ```
2. Handle audio file references (already in `Audio/` folder)
3. Map dictation fields to recording fields
4. Convert metadata to JSON format

### Validation
- All dictations migrated
- Audio files accessible
- Metadata preserved

---

## Step 6: Update TalkieAgent (Day 3)

**Goal:** TalkieAgent writes to unified database.

### Tasks
1. Update TalkieAgent to connect to `talkie_grdb.sqlite`
2. Write new dictations as `Recording` with `type = 'dictation'`
3. Remove `live.sqlite` writes
4. Test concurrent access (TalkieAgent writes while Talkie reads)

### Validation
- New dictations appear in recordings table
- No SQLITE_BUSY errors
- Talkie sees dictations immediately

---

## Step 7: Create Unified RecordingsScreen (Day 3-4)

**Goal:** Single view for all recordings.

### Tasks
1. Create `Views/Recordings/RecordingsScreen.swift`
2. Implement:
   - List of recordings (sorted by createdAt)
   - Type filter (All / Memos / Dictations)
   - Search
   - Selection handling
3. Borrow UI patterns from existing MemosScreen
4. Add to navigation (replace Memos + Dictations)

### Validation
- All recordings visible
- Filtering works
- Search works
- Selection works

---

## Step 8: Create Unified RecordingDetail (Day 4)

**Goal:** Single detail view for all recording types.

### Tasks
1. Create `Views/Recordings/RecordingDetail.swift`
2. Implement:
   - Transcript display/edit (memos only edit)
   - Title/notes (memos only)
   - Metadata display (dictations)
   - Playback section
   - Actions section
3. Conditional sections based on `type`

### Validation
- Detail view works for both types
- Editing works for memos
- Metadata visible for dictations

---

## Step 9: Create Unified Audio Player (Day 4)

**Goal:** Single audio player component.

### Tasks
1. Create `Components/AudioPlayer.swift`
2. Implement:
   - Play/pause
   - Seek
   - Progress bar
   - Duration display
   - Volume control
3. Load audio from `AudioStorage.url(for: recording.id)`

### Validation
- Playback works for all recordings
- Seek works
- Volume works

---

## Step 10: Update CloudKit Sync (Day 5)

**Goal:** Sync only memos, materialize audio correctly.

### Tasks
1. Update sync query: `recordings WHERE type = 'memo'`
2. When receiving from CloudKit:
   - Save to recordings table
   - Materialize audio from Core Data to `Audio/{id}.m4a`
   - Set `hasAudio = 1`
3. Test bidirectional sync

### Validation
- Memos sync to/from CloudKit
- Dictations stay local
- Audio files created correctly

---

## Step 11: Update Workflows (Day 5)

**Goal:** Workflows work with Recording model.

### Tasks
1. Update `WorkflowExecutor` to use `Recording`
2. Update workflow input/output to reference recordings
3. Ensure transcript versions created for recordings

### Validation
- Workflows execute on recordings
- Outputs saved correctly
- Transcript versions created

---

## Step 12: Cleanup (Day 6)

**Goal:** Remove deprecated code and files.

### Tasks
1. Remove `voice_memos` table (keep in migration history)
2. Remove `MemoModel.swift` (or alias to Recording)
3. Remove `LiveDictation.swift`
4. Remove `LiveDatabase.swift`
5. Remove `DictationStore.swift`
6. Remove `MemosScreen.swift`
7. Remove `DictationsScreen.swift`
8. Update all imports/references
9. Run full test suite

### Validation
- App builds without deprecated files
- All tests pass
- No runtime errors

---

## Step 13: Final Testing (Day 6)

**Goal:** Full QA pass.

### Test Cases
- [ ] Create memo via recording
- [ ] Create dictation via TalkieAgent
- [ ] View all recordings
- [ ] Filter by type
- [ ] Search recordings
- [ ] Play audio (memo)
- [ ] Play audio (dictation)
- [ ] Edit memo title/notes
- [ ] Run workflow on recording
- [ ] Promote dictation to memo
- [ ] Soft delete memo
- [ ] CloudKit sync (push)
- [ ] CloudKit sync (pull)
- [ ] iOS memo appears on Mac
- [ ] Watch memo appears on Mac

---

## Rollback Plan

If critical issues found:

1. **Before v8 migration runs:** No action needed, old code still works
2. **After migration:** Restore from backup databases
3. **Partial migration:** Keep both tables, add feature flag to switch

---

## Timeline Summary

| Day | Focus |
|-----|-------|
| 1 | Model, Schema, Repository |
| 2 | Data Migration (memos + dictations) |
| 3 | TalkieAgent update, RecordingsScreen start |
| 4 | RecordingsScreen, RecordingDetail, AudioPlayer |
| 5 | CloudKit sync, Workflows |
| 6 | Cleanup, Testing |

---

## Files to Create

```
Data/Models/Recording.swift
Data/Database/RecordingRepository.swift
Views/Recordings/RecordingsScreen.swift
Views/Recordings/RecordingDetail.swift
Views/Recordings/RecordingRow.swift
Components/AudioPlayer.swift
```

## Files to Modify

```
Data/Database/DatabaseManager.swift (migration v8)
Views/AppNavigation.swift (sidebar)
Workflow/WorkflowExecutor.swift (use Recording)
Services/CloudKitSyncManager.swift (sync recordings)
TalkieAgent/Database/* (write to unified DB)
```

## Files to Remove (after migration)

```
Data/Models/MemoModel.swift
Database/LiveDictation.swift
Database/LiveDatabase.swift
Stores/DictationStore.swift
Views/Memos/MemosScreen.swift
Views/Live/DictationsScreen.swift
```

---

## Questions to Resolve Before Starting

1. Keep `voice_memos` table as archive or drop entirely?
2. Feature flag for gradual rollout?
3. Handle in-flight dictations during migration?
4. Waveform rendering strategy?
