# Multi-Provider Sync Architecture - Implementation Status

## ✅ Phase 1: Foundation (COMPLETE)

We've set up the core multi-provider sync architecture. Here's what exists now:

### 1. Database Layer (`sync_operations` table)

**Location**: `apps/macos/Talkie/Data/Database/DatabaseManager.swift` (migration v15)

Tracks local changes that need to be synced to cloud providers:

```sql
CREATE TABLE sync_operations (
    id TEXT PRIMARY KEY,
    memoId TEXT NOT NULL REFERENCES voice_memos(id),
    operation TEXT NOT NULL,      -- "create", "update", "delete"
    timestamp DATETIME NOT NULL,
    provider TEXT NOT NULL,        -- "icloud", "s3", "vercel"
    status TEXT NOT NULL,          -- "pending", "synced", "failed"
    retryCount INTEGER DEFAULT 0,
    errorMessage TEXT
);
```

### 2. ChangeTracker Service

**Location**: `apps/macos/Talkie/Services/Sync/ChangeTracker.swift`

Logs local changes and manages sync operations:

```swift
// Log changes
await ChangeTracker.shared.logCreate(memoId: memo.id)
await ChangeTracker.shared.logUpdate(memoId: memo.id)
await ChangeTracker.shared.logDelete(memoId: memo.id)

// Query pending operations
let pending = try await ChangeTracker.shared.pendingOperations(for: .s3)

// Mark as synced
try await ChangeTracker.shared.markSynced(operationIds: ids)
```

### 3. SyncCoordinator

**Location**: `apps/macos/Talkie/Services/Sync/SyncCoordinator.swift`

Orchestrates multi-provider sync:

```swift
// Register providers
SyncCoordinator.shared.registerProvider(iCloudProvider())
SyncCoordinator.shared.registerProvider(S3Provider())

// Sync all providers
try await SyncCoordinator.shared.syncAll()

// Sync specific provider
try await SyncCoordinator.shared.sync(provider: .s3)
```

**Features**:
- Push local changes to providers (reads from `sync_operations`)
- Pull remote changes from providers
- Conflict resolution (last-write-wins for now)
- Per-provider error handling

### 4. SyncProvider Protocol

**Location**: `apps/macos/Talkie/Services/Sync/SyncProvider.swift` (already existed!)

Standard interface for all sync providers:

```swift
protocol SyncProvider {
    var method: SyncMethod { get }
    var isAvailable: Bool { get async }
    var lastSyncDate: Date? { get async }

    func checkConnection() async -> ConnectionStatus
    func pushChanges(_ changes: [MemoChange]) async throws
    func pullChanges(since: Date?) async throws -> [MemoChange]
    func fullSync() async throws
}
```

### 5. iCloud Provider

**Location**: `apps/macos/Talkie/Services/Sync/iCloudSyncProvider.swift` (already existed!)

Implements SyncProvider for iCloud/CloudKit:
- Delegates to existing TalkieSync XPC service
- Uses Core Data + CloudKit bridge
- Already functional for pull operations

## Architecture Diagram

```
┌────────────────────────────────────────────────────────────┐
│                   GRDB (Source of Truth)                   │
│              ~/Library/.../Talkie/talkie.sqlite            │
│                                                            │
│  Tables:                                                   │
│  - voice_memos (recordings)                                │
│  - sync_operations (local change log)  ← NEW               │
│  - sync_metadata (per-provider state)                      │
└────────────────┬───────────────────────────────────────────┘
                 │
                 ├─ ChangeTracker ← NEW
                 │  Logs create/update/delete operations
                 │
                 ↓
┌────────────────────────────────────────────────────────────┐
│              SyncCoordinator ← NEW                         │
│  - Manages multiple providers                              │
│  - Push: GRDB → Providers                                  │
│  - Pull: Providers → GRDB                                  │
│  - Conflict resolution                                     │
└────────────────┬───────────────────────────────────────────┘
                 │
        ┌────────┼────────┐
        ↓        ↓        ↓
    ┌────────┐ ┌────┐ ┌────────┐
    │ iCloud │ │ S3 │ │ Vercel │
    └────────┘ └────┘ └────────┘
         ↓
    CloudKit
    (via TalkieSync)
```

## Data Flow

### Outbound (Local → Cloud)

```
1. User creates/edits memo
   → RecordingRepository.saveRecording()

2. ChangeTracker logs operation
   → INSERT INTO sync_operations (provider='s3', status='pending')

3. SyncCoordinator.syncAll() called (periodic or manual)
   → Reads pending operations
   → Converts to MemoChange format
   → Calls provider.pushChanges()

4. Provider uploads to cloud
   → S3: Upload JSON + audio to S3 bucket
   → iCloud: Write to Core Data (auto-syncs to CloudKit)

5. Mark operations as synced
   → UPDATE sync_operations SET status='synced'
```

### Inbound (Cloud → Local)

```
1. SyncCoordinator.syncAll() called
   → Calls provider.pullChanges(since: lastSync)

2. Provider fetches remote changes
   → S3: Download manifest, check for new/updated files
   → iCloud: BridgeSync (CloudKit → Core Data → GRDB)

3. Provider returns MemoChange array

4. SyncCoordinator applies to GRDB
   → Check for conflicts (local vs remote lastModified)
   → INSERT/UPDATE/DELETE in GRDB
   → Update provider lastSyncDate
```

## 📋 Next Steps: Adding S3 Provider

### What's Needed

1. **S3Provider implementation**
   - File: `apps/macos/Talkie/Services/Sync/S3SyncProvider.swift`
   - AWS Signature v4 signing
   - Upload/download primitives
   - Manifest management

2. **Credential storage**
   - S3 access key, secret key, bucket, region
   - Store in Keychain via CredentialStore

3. **UI for provider selection**
   - Settings → Sync → Choose providers
   - Enable/disable S3, configure credentials

4. **Integration hooks**
   - Call ChangeTracker from RecordingRepository save/delete methods
   - Register S3Provider with SyncCoordinator
   - Periodic sync trigger

### S3 Bucket Structure

```
s3://talkie-sync/{userId}/
  manifest.json          ← Index of all memos + timestamps
  memos/
    {uuid}.json          ← Memo metadata (MemoSyncDTO)
  audio/
    {uuid}.m4a           ← Audio files
```

### Effort Estimate

- **S3Provider implementation**: ~12 hours
- **AWS Signature v4**: ~6 hours
- **Credential UI**: ~4 hours
- **Integration & testing**: ~8 hours
- **Total**: ~30 hours (~1 week)

## Alternative: Vercel Blob

Simpler than S3 (no AWS signing), already in `SyncMethod` enum:

```swift
class VercelBlobSyncProvider: SyncProvider {
    func upload(key: String, data: Data) async throws {
        // Simple PUT with Bearer token
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
}
```

**Pros**: Easier, faster to implement
**Cons**: Vendor lock-in, potentially higher cost

## Current Status

✅ **Foundation complete** - Ready to add providers!
⏳ **iCloud pull working** - via existing TalkieSync
❌ **iCloud push** - Needs reverse bridge sync (GRDB → Core Data)
❌ **S3** - Not implemented yet
❌ **Integration** - ChangeTracker not wired into save paths yet

## Key Files

| File | Purpose |
|------|---------|
| `DatabaseManager.swift` (v15 migration) | `sync_operations` table |
| `ChangeTracker.swift` | Log local changes |
| `SyncCoordinator.swift` | Orchestrate providers |
| `SyncProvider.swift` | Provider protocol |
| `iCloudSyncProvider.swift` | iCloud implementation |
| `RecordingRepository.swift` | Where to add ChangeTracker calls |

## Philosophy

> **"Bridge Sync" is just regular sync.**
> The old "Bridge Sync" (Core Data → GRDB) was a workaround for CloudKit limitations.
> The new architecture makes sync a first-class, provider-agnostic system.

**Old flow**: `CloudKit → Core Data → GRDB` (pull-only, iCloud-only)
**New flow**: `Providers ↔ GRDB` (bidirectional, multi-provider)

This is the foundation for true multi-cloud sync. S3, Dropbox, Google Drive - any provider can plug in.
