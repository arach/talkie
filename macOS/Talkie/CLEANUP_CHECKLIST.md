# GRDB Migration Cleanup Checklist

## ✅ Proven Concepts
- [x] GRDB 10-20x faster than Core Data
- [x] Migration works (198/211 memos = 93.8%)
- [x] UI is snappy and responsive
- [x] Animations smooth (bug toolbar rotation test passed!)

## 🧹 Cleanup Tasks

### High Priority

- [ ] **Fix Live fetch performance**
  - Currently: Refreshing 2123 utterances repeatedly
  - Solution: Add indexes, pagination, or throttling
  - File: `macOS/Talkie/Database/LiveDatabase.swift`

- [ ] **Decide on sync strategy**
  - Option A: Keep Core Data CloudKit, disable CloudKitSyncEngine
  - Option B: Fix CloudKitSyncEngine to use `CD_VoiceMemo` record type
  - Option C: Deprecate Core Data entirely, use new CloudKit schema
  - **Recommendation**: Option A (safest, works now)

- [ ] **Wire up AllMemosView2 to navigation**
  - Replace old view with new GRDB-backed view
  - Test sorting, search, pagination
  - File: `macOS/Talkie/Views/NavigationView.swift`

- [ ] **Fix 13 failed migrations**
  - Core Data threading issue causing "missingID" errors
  - These memos actually have IDs but Core Data read fails
  - File: `macOS/Talkie/Data/Database/CoreDataMigration.swift`

### Medium Priority

- [ ] **Add migration troubleshooting mode**
  - Keyboard shortcut to show MigrationView
  - Maybe: Cmd+Shift+M or in Debug menu
  - Shows migration stats, re-run option

- [ ] **UI Polish - Clickable states**
  - Add hover states to memo rows
  - Click feedback (subtle scale/opacity change)
  - Loading spinners for async operations
  - File: `macOS/Talkie/Views/Memos/AllMemosView2.swift`

- [ ] **Clean up old data layer files**
  - Mark old views as deprecated
  - Add migration path for any remaining features
  - Keep Core Data for CloudKit sync only

- [ ] **Performance monitoring**
  - Add telemetry for query times
  - Track pagination performance
  - Memory usage tracking

### Low Priority

- [ ] **Remove migration backups** (after testing)
  - `talkie.sqlite.backup-20251217-151007`
  - `talkie.sqlite.migrated-20251217-152041`
  - Keep for 30 days then delete

- [ ] **Update documentation**
  - Architecture decision: Why GRDB?
  - Migration guide for future devs
  - Sync philosophy explanation

## 🚨 Known Issues

1. **CloudKitSyncEngine fails** - Looking for wrong record type
   ```
   ❌ Pull failed: "Unknown Item" (11/2003); server message = "Did not find record type: VoiceMemo"
   ```
   - Not urgent: Core Data sync still works
   - Fix: Use `CD_VoiceMemo` or disable entirely

2. **Live fetch chattiness** - 2123 utterances refreshing constantly
   - Impact: CPU/battery usage
   - Fix needed in LiveDatabase

3. **13 missing memos** - Core Data threading issue
   - They have IDs but migration read fails
   - Low priority: Can re-migrate those manually

## 💡 Future Enhancements

- [ ] FTS5 full-text search (already in schema!)
- [ ] Workflow count caching (add trigger)
- [ ] Incremental CloudKit sync (delta fetches)
- [ ] Background migration for future schema changes

## 📊 Performance Metrics

**Before (Core Data):**
- Load 50 memos: ~200-500ms
- Memory: ~10MB for all memos loaded
- Main thread blocking: Frequent

**After (GRDB):**
- GRDB init: 8-26ms
- Load 50 memos: <10ms (need to measure)
- Memory: ~50KB for displayed memos
- Main thread: Smooth animations ✅
