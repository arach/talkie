# Sync Migration Plan: Talkie → TalkieSync

## Goal
Remove all Core Data and sync implementations from Talkie main app. TalkieSync now owns:
- Core Data + CloudKit stack
- Bridge sync (Core Data → GRDB)
- Sync scheduling and orchestration

Talkie becomes a pure GRDB client that receives sync updates via XPC callbacks.

## Current State

```
┌─────────────────────────────────────────────────────────────┐
│                    Talkie (Now)                             │
│  ├── GRDB (talkie.sqlite) ─────────────── UI reads/writes  │
│  ├── Core Data (talkie_coredata.sqlite) ─ REMOVE           │
│  ├── CloudKitSyncManager ─────────────── REMOVE            │
│  ├── TalkieData (bridge sync) ─────────── REFACTOR         │
│  └── SyncClient (XPC to TalkieSync) ──── KEEP              │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    TalkieSync (Ready)                       │
│  ├── Core Data + CloudKit ─────────────── ✓ Working        │
│  ├── BridgeSync (CD → GRDB) ───────────── ✓ Working        │
│  ├── XPC Service ──────────────────────── ✓ Working        │
│  └── MemoRecord SDK ───────────────────── ✓ Working        │
└─────────────────────────────────────────────────────────────┘
```

## Target State

```
┌─────────────────────────────────────────────────────────────┐
│                    Talkie (After)                           │
│  ├── GRDB (talkie.sqlite) ─────────────── UI reads/writes  │
│  ├── SyncClient (XPC) ─────────────────── Sync control     │
│  └── Listens for .syncDataAvailable ───── Refresh UI       │
└─────────────────────────────────────────────────────────────┘
                           │ XPC
┌──────────────────────────▼──────────────────────────────────┐
│                    TalkieSync                               │
│  ├── Core Data + CloudKit                                   │
│  ├── Bridge Sync → GRDB                                     │
│  └── Notifies Talkie when data changes                      │
└─────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Remove Core Data Stack (High Impact)

### Files to Remove
- [ ] `Models/Persistence.swift` - Core Data container
- [ ] `Models/talkie.xcdatamodeld/` - Core Data model
- [ ] `Models/VoiceMemo+CoreDataClass.swift` (if exists)
- [ ] `Models/VoiceMemo+CoreDataProperties.swift` (if exists)

### Files to Update
- [ ] `App/TalkieApp.swift` - Remove `.environment(\.managedObjectContext)`
- [ ] `App/DataLayerIntegration.swift` - Remove Core Data initialization
- [ ] `App/AppDelegate.swift` - Remove `PersistenceController.shared` references

### Impact
- App no longer initializes Core Data
- ~50MB memory reduction
- Faster startup

---

## Phase 2: Remove CloudKitSyncManager (Sync Orchestration)

### Files to Remove
- [ ] `Services/CloudKitSyncManager.swift` - Main sync orchestrator
- [ ] `Services/Sync/CoreDataSyncGateway.swift` - Core Data sync ops

### Files to Update
- [ ] `Services/Sync/iCloudSyncProvider.swift` - Remove fallback path
- [ ] `App/StartupCoordinator.swift` - Remove `CloudKitSyncManager` references
- [ ] `App/AppDelegate.swift` - Remove CloudKit subscription setup

### Verification
- Trigger sync via UI → Should go through TalkieSync XPC
- Check Console.app for TalkieSync logs

---

## Phase 3: Refactor TalkieData (Keep GRDB, Remove CD)

### Current TalkieData responsibilities:
1. ✓ Count GRDB memos → KEEP
2. ✓ Count live dictations → KEEP
3. ✗ Count Core Data memos → GET FROM TALKIESYNC VIA XPC
4. ✗ Bridge sync → REMOVE (TalkieSync does this)
5. ✗ Configure with Core Data context → REMOVE

### Changes to TalkieData.swift
```swift
// BEFORE
func configure(with context: NSManagedObjectContext) {
    self.coreDataContext = context
    // ... bridge sync logic
}

// AFTER
func configure() {
    // Just count local data, no Core Data needed
    DatabaseManager.shared.afterInitialized { [weak self] in
        await self?.runStartupChecks()
    }
}

// Get Core Data count from TalkieSync instead of direct access
private func countCoreData() async -> Int {
    await SyncClient.shared.getRemoteMemoCount()
}
```

---

## Phase 4: Clean Up References

### Settings Views
- [ ] `Views/Settings/StorageSettings.swift` - Update Core Data size display
- [ ] `Views/Settings/DataInventoryView.swift` - Get counts from SyncClient
- [ ] `Views/Settings/DevControlPanel.swift` - Remove CD debug actions

### Debug/Migration
- [ ] `Debug/DebugCommandHandler.swift` - Remove CD commands
- [ ] `Data/Database/CoreDataMigration.swift` - Remove or archive
- [ ] `Views/Migration/MigrationManager.swift` - Update for new architecture

### Other Services
- [ ] `Services/SyncQueue.swift` - May not be needed
- [ ] `Services/PowerStateManager.swift` - Remove CD references
- [ ] `Workflow/WorkflowExecutor.swift` - Ensure uses GRDB only

---

## Phase 5: Testing & Verification

### Functional Tests
- [ ] Fresh install: App starts, GRDB empty, TalkieSync syncs from iCloud
- [ ] Existing data: App starts, reads from GRDB immediately
- [ ] New memo on iPhone: Syncs to Mac via TalkieSync → GRDB
- [ ] Memory: Verify ~60MB (down from ~130MB)

### Edge Cases
- [ ] TalkieSync not running: App still works (GRDB is local)
- [ ] TalkieSync crash: App continues, sync resumes when TalkieSync restarts
- [ ] Network offline: GRDB works, sync happens when online

---

## Execution Order

1. **Phase 1** - Remove Core Data stack (breaks most things temporarily)
2. **Phase 3** - Refactor TalkieData immediately after (restores functionality)
3. **Phase 2** - Remove CloudKitSyncManager (sync now 100% via TalkieSync)
4. **Phase 4** - Clean up remaining references
5. **Phase 5** - Test everything

**Alternative safer order:**
1. Phase 3 first (make TalkieData not depend on CD)
2. Phase 2 (remove CloudKitSyncManager)
3. Phase 1 (remove Core Data stack)
4. Phase 4 & 5

---

## Rollback Plan

If issues arise, the fallback sync path in `iCloudSyncProvider.fullSync()` still uses `CloudKitSyncManager`. Remove this fallback only after Phase 2 is verified working.

---

## Files Summary

### Remove (8 files)
- `Models/Persistence.swift`
- `Models/talkie.xcdatamodeld/`
- `Services/CloudKitSyncManager.swift`
- `Services/Sync/CoreDataSyncGateway.swift`
- `Services/SyncQueue.swift` (verify not needed)
- `Data/Database/CoreDataMigration.swift`

### Major Refactor (3 files)
- `Services/TalkieData.swift`
- `App/StartupCoordinator.swift`
- `App/DataLayerIntegration.swift`

### Minor Updates (10+ files)
- Various settings views
- Debug tools
- Migration views
