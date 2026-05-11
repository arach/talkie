# Multi-Backend Sync: Implementation Plan

> Goal: Give users visibility into their data sync status and the ability to choose where their data lives.

## Current State

```
iPhone → CloudKit → CoreData (_EXTERNAL_DATA/*.interim) → Bridge Sync → GRDB + Audio/*.m4a
```

- **GRDB** is the local source of truth (fast, reliable)
- **CloudKit** is the sync layer (opaque, Apple-managed)
- **Bridge sync** extracts audio from CoreData blobs to local files
- Users have no visibility into what's synced vs local-only

## Target State

```
┌─────────────────────────────────────────────────────────────┐
│                    GRDB (Source of Truth)                   │
│               Audio/*.m4a  +  talkie_grdb.sqlite            │
└─────────────────────────────┬───────────────────────────────┘
                              │
                     SyncProvider Protocol
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  CloudKit       │  │  S3/R2 Bucket   │  │  Vercel Blob    │
│  (legacy)       │  │  (BYOK)         │  │  (BYOK)         │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

---

## Phase 1: Data Inventory View

**Goal**: Full visibility into per-memo storage status across all layers.

### What Users See

A table view (not day-to-day UI, more like a diagnostic/bulk view) showing:

| Memo | Created | Local File | Local DB | Sync DB | Remote | Status |
|------|---------|------------|----------|---------|--------|--------|
| Morning standup | Jan 26 | ✓ 2.3MB | ✓ | ✓ | ✓ | Synced |
| Product review | Jan 25 | ✓ 1.8MB | ✓ | ✓ | ✓ | Synced |
| Quick note | Jan 24 | ✗ | ✓ | ✓ | ✓ | Audio missing locally |
| Test recording | Jan 20 | ✓ 0.5MB | ✓ | ✗ | ✗ | Local only |

**Columns explained**:
- **Local File**: Audio file exists in `~/Library/.../Talkie/Audio/{uuid}.m4a`
- **Local DB**: Record exists in GRDB (`talkie_grdb.sqlite`)
- **Sync DB**: Record exists in CoreData (CloudKit's local mirror)
- **Remote**: Record exists in CloudKit (iCloud)
- **Status**: Derived health status

### Implementation Tasks

#### 1.1 Data Layer: MemoStorageStatus Model
```swift
struct MemoStorageStatus: Identifiable {
    let id: UUID
    let title: String
    let createdAt: Date

    // Storage presence
    let hasLocalAudioFile: Bool
    let localAudioSize: Int64?
    let hasLocalDBRecord: Bool      // GRDB
    let hasSyncDBRecord: Bool       // CoreData
    let hasRemoteRecord: Bool?      // CloudKit (nil = unknown/checking)

    // Derived
    var status: SyncStatus { ... }

    enum SyncStatus {
        case synced           // All layers have it
        case localOnly        // GRDB only, not in CloudKit
        case pendingUpload    // In GRDB, not yet synced
        case pendingDownload  // In CloudKit, not yet in GRDB
        case audioMissing     // Record exists but audio file missing
        case conflict         // Mismatched data between layers
    }
}
```

#### 1.2 Data Layer: StorageInventoryService
```swift
@Observable
class StorageInventoryService {
    var memos: [MemoStorageStatus] = []
    var isLoading = false
    var lastRefresh: Date?

    // Counts
    var totalMemos: Int
    var syncedCount: Int
    var localOnlyCount: Int
    var issueCount: Int

    func refresh() async { ... }
    func checkCloudKitStatus(for id: UUID) async -> Bool? { ... }
}
```

**Data sources to query**:
1. GRDB: `SELECT id, title, createdAt, audioFilePath FROM voice_memos`
2. File system: Check `Audio/{uuid}.m4a` exists, get size
3. CoreData: Fetch VoiceMemo entities, check which IDs exist
4. CloudKit: Query CKDatabase for record existence (expensive, do lazily)

#### 1.3 UI: DataInventoryView
- Location: `Views/Settings/DataInventoryView.swift`
- Access: New tab in StorageSettingsView or dedicated settings page
- Features:
  - Sortable/filterable table
  - Bulk selection for actions
  - Summary stats at top
  - Refresh button
  - "Fix issues" actions (re-sync, re-download audio, etc.)

#### 1.4 UI: Integration into Settings
- Add "DATA INVENTORY" tab to `StorageSettingsView`
- Or add as section in Cloud Settings with "View All Records" expansion

### Phase 1 Deliverables
- [ ] `MemoStorageStatus` model
- [ ] `StorageInventoryService` with GRDB + FileSystem + CoreData queries
- [ ] `DataInventoryView` table UI
- [ ] Integration into Settings
- [ ] CloudKit status check (lazy, per-memo)
- [ ] Summary stats (synced/local-only/issues)

### Phase 1 Success Criteria
- User can see every memo and its storage status at a glance
- User can identify which memos are local-only vs synced
- User can see if any audio files are missing
- Provides peace of mind about CloudKit sync state

---

## Phase 2: SyncProvider Protocol Abstraction

**Goal**: Refactor CloudKit sync into a protocol-based architecture that supports multiple backends.

### Protocol Design

```swift
/// A backend that can store and retrieve memos
protocol SyncProvider: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var icon: String { get }  // SF Symbol

    // Connection
    var isConfigured: Bool { get }
    var connectionStatus: ConnectionStatus { get async }
    func configure(with credentials: SyncCredentials) throws
    func testConnection() async throws -> Bool

    // Sync operations
    func upload(memo: MemoModel, audio: Data?) async throws
    func download(memoId: UUID) async throws -> (MemoModel, Data?)?
    func delete(memoId: UUID) async throws
    func list() async throws -> [RemoteMemoRef]

    // Batch operations
    func syncAll(localMemos: [MemoModel]) async throws -> SyncResult

    // Status
    func exists(memoId: UUID) async throws -> Bool
    func lastModified(memoId: UUID) async throws -> Date?
}

struct RemoteMemoRef {
    let id: UUID
    let title: String
    let lastModified: Date
    let hasAudio: Bool
    let size: Int64?
}

struct SyncResult {
    let uploaded: Int
    let downloaded: Int
    let deleted: Int
    let conflicts: [UUID]
    let errors: [SyncError]
}

struct SyncCredentials {
    let provider: String
    let values: [String: String]  // API keys, bucket names, etc.
}
```

### Implementation Tasks

#### 2.1 Define Core Protocol
- `SyncProvider` protocol in `Services/Sync/SyncProvider.swift`
- Supporting types: `RemoteMemoRef`, `SyncResult`, `SyncCredentials`
- Error types: `SyncError`

#### 2.2 Refactor CloudKitSyncManager → CloudKitProvider
- Extract CloudKit-specific logic into `CloudKitProvider: SyncProvider`
- Keep `CloudKitSyncManager` as coordinator that uses the provider
- Maintain backward compatibility during transition

#### 2.3 Create SyncManager (Generic)
```swift
@Observable
class SyncManager {
    var activeProvider: (any SyncProvider)?
    var availableProviders: [any SyncProvider] = []

    func setActiveProvider(_ provider: any SyncProvider)
    func sync() async throws -> SyncResult
    func upload(memo: MemoModel) async throws
    func download(memoId: UUID) async throws
}
```

#### 2.4 Settings UI for Provider Selection
- List available providers
- Configure credentials per provider
- Show connection status
- Switch active provider

### Phase 2 Deliverables
- [ ] `SyncProvider` protocol definition
- [ ] `CloudKitProvider` implementation (refactored from CloudKitSyncManager)
- [ ] `SyncManager` generic coordinator
- [ ] Provider selection UI in Settings
- [ ] Credential storage (Keychain for API keys)
- [ ] Migration path from current CloudKit setup

### Phase 2 Success Criteria
- CloudKit sync works exactly as before (no regression)
- Architecture supports adding new providers
- User can see which provider is active
- Clean separation between sync logic and provider-specific code

---

## Phase 3: Alternative Providers (BYOK)

**Goal**: Add storage backends with "bring your own key/account" model.

### Provider Tiers

```
┌─────────────────────────────────────────────────────────────────────────┐
│  TIER 1: S3-Compatible (One Implementation)                             │
│  ─────────────────────────────────────────────                          │
│  • Cloudflare R2    - Free egress, dev favorite                         │
│  • AWS S3           - Enterprise standard                               │
│  • Google Cloud     - S3-compatible mode                                │
│  • Supabase Storage - S3-compatible, indie dev favorite                 │
│                                                                         │
│  Config: endpoint URL + access key + secret + bucket + region           │
├─────────────────────────────────────────────────────────────────────────┤
│  TIER 2: Simple API                                                     │
│  ─────────────────────                                                  │
│  • Vercel Blob      - Simple REST API, great for web devs               │
│                                                                         │
│  Config: just a token                                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  TIER 3: Consumer-Friendly (OAuth)                                      │
│  ─────────────────────────────────                                      │
│  • Dropbox          - No API keys, "Sign in with Dropbox"               │
│                       Files appear in familiar folder structure          │
│                                                                         │
│  Config: OAuth flow, user just logs in                                  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Provider: S3-Compatible (Universal Bucket)

**One implementation covers**:
- Cloudflare R2 (recommended - free egress)
- AWS S3
- Google Cloud Storage
- Supabase Storage
- (Also works with: Backblaze B2, DigitalOcean Spaces, Wasabi, MinIO)

**Storage structure**:
```
bucket/
├── memos/
│   ├── {uuid}/
│   │   ├── metadata.json    # MemoModel as JSON
│   │   └── audio.m4a        # Audio file
│   └── ...
└── manifest.json            # Index of all memos (optional, for fast listing)
```

**Configuration required**:
- Provider preset (R2, AWS, GCS, Supabase, Custom)
- Endpoint URL (auto-filled for presets)
- Access Key ID
- Secret Access Key
- Bucket name
- Region (optional for some)

#### 3.1 S3Provider Implementation
```swift
class S3Provider: SyncProvider {
    var id = "s3"
    var displayName: String  // "Cloudflare R2", "AWS S3", etc.
    var icon = "externaldrive.connected.to.line.below"

    // Presets for common providers
    enum Preset: String, CaseIterable {
        case cloudflareR2 = "Cloudflare R2"
        case awsS3 = "AWS S3"
        case googleCloud = "Google Cloud Storage"
        case supabase = "Supabase Storage"
        case custom = "Custom S3-Compatible"

        var endpointTemplate: String? { ... }
        var regionRequired: Bool { ... }
    }

    private var preset: Preset
    private var endpoint: URL
    private var accessKeyId: String
    private var secretAccessKey: String
    private var bucket: String
    private var region: String?

    func configure(with credentials: SyncCredentials) throws { ... }
    func upload(memo: MemoModel, audio: Data?) async throws { ... }
    // ... etc
}
```

#### 3.2 S3 Settings UI
- Provider picker (R2, AWS, GCS, Supabase, Custom)
- Credential inputs (context-aware based on provider)
- Test connection button
- Bucket browser preview
- Storage usage display
- Setup guide links per provider

### Provider: Vercel Blob

Simple blob storage for web developers.

```swift
class VercelBlobProvider: SyncProvider {
    var id = "vercel"
    var displayName = "Vercel Blob"
    var icon = "triangle.fill"

    private var token: String

    // Simple REST API
    // PUT https://blob.vercel-storage.com/memos/{uuid}.json
    // PUT https://blob.vercel-storage.com/memos/{uuid}.m4a
}
```

**Configuration**: Just a Vercel Blob token from dashboard.

### Provider: Dropbox

Consumer-friendly option - no API keys needed.

```swift
class DropboxProvider: SyncProvider {
    var id = "dropbox"
    var displayName = "Dropbox"
    var icon = "shippingbox.fill"

    // OAuth flow - user just logs in
    // Files stored in: Dropbox/Apps/Talkie/memos/{uuid}/
}
```

**Configuration**: OAuth sign-in, user authorizes Talkie app.

**Benefits for non-technical users**:
- No API keys or bucket setup
- Files visible in their existing Dropbox folder
- Works on any device with Dropbox
- Familiar mental model

### Phase 3 Deliverables

**3A: S3-Compatible Provider**
- [ ] `S3Provider` implementation with presets
- [ ] S3 credentials UI with provider picker
- [ ] Secure credential storage (Keychain)
- [ ] Connection test and bucket browser
- [ ] Upload/download with progress
- [ ] Conflict resolution strategy

**3B: Vercel Blob Provider**
- [ ] `VercelBlobProvider` implementation
- [ ] Simple token-based settings UI
- [ ] Connection test

**3C: Dropbox Provider**
- [ ] `DropboxProvider` implementation
- [ ] OAuth flow integration
- [ ] Folder structure in user's Dropbox

### Phase 3 Success Criteria
- User can pick from: R2, AWS, GCS, Supabase, Vercel, Dropbox
- S3-compatible: configure once, works with any S3 provider
- Vercel: just paste a token and go
- Dropbox: "Sign in" button, no API keys needed
- User can see their memos in their provider's dashboard
- Sync works bidirectionally (upload new, download existing)
- User can switch between providers
- Data is portable - user owns their storage

---

## Implementation Order

```
Phase 1: Visibility          Phase 2: Abstraction       Phase 3: Providers
─────────────────────────    ─────────────────────────  ─────────────────────────
[1.1] MemoStorageStatus      [2.1] SyncProvider proto   [3A] S3Provider (universal)
[1.2] StorageInventoryService [2.2] CloudKitProvider         - R2, AWS, GCS, Supabase
[1.3] DataInventoryView      [2.3] SyncManager          [3B] VercelBlobProvider
[1.4] Settings integration   [2.4] Provider selection   [3C] DropboxProvider (OAuth)
```

**Dependencies**:
- Phase 2 can start before Phase 1 is complete
- Phase 3 requires Phase 2's protocol
- Phase 1 benefits from Phase 2's abstractions but doesn't require them
- 3A (S3) should come first - covers most users
- 3B (Vercel) is quick win after 3A
- 3C (Dropbox) is nice-to-have for consumer audience

---

## Open Questions

1. **Conflict resolution**: What happens if memo edited on phone AND in S3 bucket?
   - Last-write-wins? User chooses? Merge?

2. **Migration**: User switches from CloudKit to S3 - do we copy all data?
   - Offer "export all to new provider" action?

3. **Multi-provider**: Can user have both CloudKit AND S3 active?
   - Primary + backup model?

4. **Audio-only vs full sync**: Some providers might only store audio (cheap), others full metadata
   - Provider capability flags?

5. **Offline behavior**: How does S3 sync work offline?
   - Queue uploads, sync when online (like CloudKit does)

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| CloudKit regression | Keep CloudKitSyncManager working during refactor, add tests |
| Credential security | Use Keychain, never log keys, encrypt at rest |
| S3 API complexity | Use battle-tested Swift AWS SDK or minimal HTTP client |
| Scope creep | Phase 1 first - visibility without backend changes |
| User confusion | Clear UI showing which provider is active, sync status |

---

## Success Metrics

**Phase 1**:
- User can answer "is my data synced?" in 5 seconds
- Zero support tickets about "where is my data?"

**Phase 2**:
- CloudKit works identically to before
- Adding a new provider requires only implementing protocol

**Phase 3**:
- User can set up R2 sync in under 2 minutes
- User can see their memos in R2 dashboard
- Data survives switching providers
