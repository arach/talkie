# Repository Instrumentation Example

## Before (Manual Logging)

```swift
actor GRDBRepository: MemoRepository {
    func fetchMemos(
        sortBy: MemoModel.SortField,
        ascending: Bool,
        limit: Int,
        offset: Int,
        searchQuery: String? = nil
    ) async throws -> [MemoModel] {
        let startTime = Date()
        let db = try await dbManager.database()

        print("🔍 [GRDB] Executing query: sort=\(sortBy), limit=\(limit), offset=\(offset)")

        let result = try await db.read { db in
            // ... query logic ...
        }

        let elapsed = Date().timeIntervalSince(startTime)
        print("✅ [GRDB] Query completed in \(Int(elapsed * 1000))ms, returned \(result.count) memos")

        return result
    }
}
```

## After (Automatic Signposting)

```swift
actor GRDBRepository: MemoRepository {
    func fetchMemos(
        sortBy: MemoModel.SortField,
        ascending: Bool,
        limit: Int,
        offset: Int,
        searchQuery: String? = nil
    ) async throws -> [MemoModel] {
        try await instrumentRepositoryRead("fetchMemos") {
            let db = try await dbManager.database()

            return try await db.read { db in
                // ... query logic ...
            }
        }
    }
}
```

**What changed:**
- ❌ Removed manual timing (`startTime`, `elapsed`)
- ❌ Removed manual print statements
- ✅ Added `instrumentRepositoryRead("fetchMemos")`
- ✅ Automatic signposts with duration tracking

**Signpost name:** `GRDBRepository.fetchMemos`

---

## All Repository Methods

### Reads (Use `instrumentRepositoryRead`)

```swift
func fetchMemos(...) async throws -> [MemoModel] {
    try await instrumentRepositoryRead("fetchMemos") {
        // query logic
    }
}

func countMemos(searchQuery: String?) async throws -> Int {
    try await instrumentRepositoryRead("countMemos") {
        // count logic
    }
}

func fetchMemo(id: UUID) async throws -> MemoWithRelationships? {
    try await instrumentRepositoryRead("fetchMemo") {
        // fetch by ID logic
    }
}

func fetchTranscriptVersions(for memoId: UUID) async throws -> [TranscriptVersionModel] {
    try await instrumentRepositoryRead("fetchTranscriptVersions") {
        // fetch transcripts logic
    }
}

func fetchWorkflowRuns(for memoId: UUID) async throws -> [WorkflowRunModel] {
    try await instrumentRepositoryRead("fetchWorkflowRuns") {
        // fetch workflows logic
    }
}
```

### Writes (Use `instrumentRepositoryWrite`)

```swift
func saveMemo(_ memo: MemoModel) async throws {
    try await instrumentRepositoryWrite("saveMemo") {
        let db = try await dbManager.database()
        try await db.write { db in
            try memo.save(db)
        }
    }
}

func deleteMemo(id: UUID) async throws {
    try await instrumentRepositoryWrite("deleteMemo") {
        let db = try await dbManager.database()
        try await db.write { db in
            try MemoModel.deleteOne(db, id: id)
        }
    }
}

func saveTranscriptVersion(_ version: TranscriptVersionModel) async throws {
    try await instrumentRepositoryWrite("saveTranscriptVersion") {
        let db = try await dbManager.database()
        try await db.write { db in
            try version.save(db)
        }
    }
}

func saveWorkflowRun(_ run: WorkflowRunModel) async throws {
    try await instrumentRepositoryWrite("saveWorkflowRun") {
        let db = try await dbManager.database()
        try await db.write { db in
            try run.save(db)
        }
    }
}
```

### Transactions (Use `instrumentRepositoryTransaction`)

```swift
// Example: Save memo with initial transcript
func createMemoWithTranscript(memo: MemoModel, transcript: TranscriptVersionModel) async throws {
    try await instrumentRepositoryTransaction("createMemoWithTranscript") {
        try await saveMemo(memo)
        try await saveTranscriptVersion(transcript)
    }
}

// Example: Delete memo and all related data
func deleteMemoCompletely(id: UUID) async throws {
    try await instrumentRepositoryTransaction("deleteMemoCompletely") {
        try await deleteWorkflowRuns(for: id)
        try await deleteTranscriptVersions(for: id)
        try await deleteMemo(id: id)

        // Mark logical completion
        markTransactionComplete("deleteMemoCompletely")
    }
}
```

---

## What You See in Instruments

### Timeline View

```
GRDBRepository.fetchMemos       |----------| 8ms
GRDBRepository.countMemos       |-| 2ms
GRDBRepository.fetchMemo        |----| 4ms
GRDBRepository.saveMemo         |------| 6ms  (DB Write)
```

### Grouped by Type

**DB Read:**
- GRDBRepository.fetchMemos (8ms)
- GRDBRepository.countMemos (2ms)
- GRDBRepository.fetchMemo (4ms)

**DB Write:**
- GRDBRepository.saveMemo (6ms)
- GRDBRepository.saveWorkflowRun (3ms)

**DB Transaction:**
- GRDBRepository.createMemoWithTranscript (12ms total)

---

## Convention-Based Naming Benefits

### Automatic Categorization

All repository operations are prefixed with `GRDBRepository.`, so you can:
- Filter Instruments by "GRDBRepository" to see only DB operations
- Group all database activity together
- Separate DB performance from UI performance

### Hierarchical Naming

```
GRDBRepository.fetchMemos
GRDBRepository.countMemos
GRDBRepository.saveMemo
```

vs. manual custom names (requires thinking):

```
AllMemos.fetchMemosWithWorkflows
Search.fullTextSearchQuery
MemoDetail.updateMemoTitle
```

### Best of Both Worlds

- **Repository layer**: Convention-based (GRDBRepository.methodName)
- **Special queries**: Custom names when needed

```swift
// Convention-based (automatic)
func fetchMemos(...) async throws -> [MemoModel] {
    try await instrumentRepositoryRead("fetchMemos") { ... }
}

// Custom name for special complex query
func searchMemosWithFullText(query: String) async throws -> [MemoModel] {
    try await instrumentRepositoryRead("fullTextSearch_\(query.prefix(20))") {
        // Complex FTS5 query
    }
}
```

---

## Migration Checklist

- [ ] Update `fetchMemos` → wrap with `instrumentRepositoryRead`
- [ ] Update `countMemos` → wrap with `instrumentRepositoryRead`
- [ ] Update `fetchMemo` → wrap with `instrumentRepositoryRead`
- [ ] Update `fetchTranscriptVersions` → wrap with `instrumentRepositoryRead`
- [ ] Update `fetchWorkflowRuns` → wrap with `instrumentRepositoryRead`
- [ ] Update `saveMemo` → wrap with `instrumentRepositoryWrite`
- [ ] Update `deleteMemo` → wrap with `instrumentRepositoryWrite`
- [ ] Update `saveTranscriptVersion` → wrap with `instrumentRepositoryWrite`
- [ ] Update `saveWorkflowRun` → wrap with `instrumentRepositoryWrite`
- [ ] Remove manual `print` statements (replaced by signposts)
- [ ] Remove manual timing code (automatic with signposts)

---

## Final Result

**Zero boilerplate, automatic instrumentation:**

```swift
// Developer writes:
func fetchMemos(...) async throws -> [MemoModel] {
    try await instrumentRepositoryRead("fetchMemos") {
        // Just the query logic
    }
}

// Instruments sees:
// - Signpost: GRDBRepository.fetchMemos
// - Category: DB Read
// - Duration: 8ms
// - Timeline position: exact timestamp
```

**No manual:**
- ❌ Timing code
- ❌ Print statements
- ❌ Section naming
- ❌ Duration calculations

**Just:**
- ✅ Wrap method body in `instrumentRepositoryRead/Write`
- ✅ Use method name as operation name
- ✅ Automatic signposts everywhere
