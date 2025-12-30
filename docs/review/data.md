# Data Module

`macOS/Talkie/Data/` - GRDB persistence for memos, transcripts, workflows

---

## Structure

```
Data/
├── Database/
│   ├── DatabaseManager.swift      - GRDB setup, migrations
│   ├── MemoRepository.swift       - Repository protocol
│   ├── GRDBRepository.swift       - GRDB implementation
│   ├── CoreDataMigration.swift    - Legacy migration
│   ├── SyncRecordSerializer.swift - CloudKit serialization
│   ├── RepositoryInstrumentation.swift
│   └── ExternalDataAuditor.swift
├── Models/
│   ├── MemoModel.swift            - Voice memo model
│   ├── MemoModel+CloudKit.swift   - CloudKit extensions
│   ├── TranscriptVersionModel.swift
│   ├── WorkflowRunModel.swift
│   ├── WorkflowStepModel.swift
│   ├── WorkflowEventModel.swift
│   ├── SyncMetadata.swift
│   └── CloudSyncActionModel.swift
├── ViewModels/
│   └── MemosViewModel.swift       - Observable memo list
└── Sync/
    └── CloudKitSyncEngine.swift   - CloudKit sync
```

---

## Database

### DatabaseManager.swift
GRDB setup with migrations, WAL mode, performance tuning.

**Discussion:**
- Explicit WAL mode + NORMAL sync (good perf/safety balance)
- 64MB cache configured
- Foreign keys enabled
- Thread-safe initialization with NSLock

---

### MemoRepository.swift (Protocol)
Clean repository abstraction with Actor isolation.

**Discussion:**
- Good separation of concerns
- Soft delete support built-in
- Pagination at query level (LIMIT/OFFSET)
- MemoWithRelationships for eager loading

---

### GRDBRepository.swift
GRDB implementation of MemoRepository.

**Discussion:**

---

## Models

### MemoModel.swift
Voice memo with GRDB conformance.

**Discussion:**
- Soft delete via `deletedAt` field
- Processing state flags (isTranscribing, isProcessingSummary, etc.)
- Provenance tracking (originDeviceId, macReceivedAt)
- Pending workflow tracking

---

### TranscriptVersionModel.swift
Versioned transcripts with source tracking.

**Discussion:**

---

### WorkflowRunModel.swift
Workflow execution records.

**Discussion:**

---

## Sync

### CloudKitSyncEngine.swift
CloudKit synchronization.

**Discussion:**

---

## TODO

- [ ] Review GRDBRepository implementation
- [ ] Review CloudKitSyncEngine for edge cases
- [ ] Check CoreDataMigration is still needed

## Done

- Initial structure review complete
- Clean repository pattern identified
