# Performance Instrumentation Progress

## Summary

Successfully replaced high-traffic buttons with TalkieButton/TalkieButtonSync to enable comprehensive performance tracking.

## Instrumented Buttons

### AllMemosView2 ✅
All buttons now tracked - will show processing time for DB operations:

1. **ClearSearch** (TalkieButtonSync)
   - Action: `AllMemos.ClearSearch`
   - Triggers: Search query reset → new DB query

2. **Sort Buttons** (TalkieButton x4)
   - Actions: `AllMemos.Sort.Date`, `AllMemos.Sort.Title`, `AllMemos.Sort.Duration`, `AllMemos.Sort.Workflows`
   - Triggers: `viewModel.changeSortField()` → DB operations tracked automatically

3. **LoadMore** (TalkieButton)
   - Action: `AllMemos.LoadMore`
   - Triggers: `viewModel.loadNextPage()` → DB pagination query

### Performance Monitor ✅
Clear button now tracked:

1. **Clear** (TalkieButtonSync)
   - Action: `Performance.Clear`
   - Triggers: Clears all performance monitoring data

### Settings Views ✅
Critical settings buttons now tracked:

1. **SaveAPIKey** (TalkieButtonSync) - in APISettings.swift
   - Action: `Settings.SaveAPIKey`
   - Triggers: `settingsManager.saveSettings()` → Saves API key to keychain

2. **DeleteAPIKey** (TalkieButtonSync) - in APISettings.swift
   - Action: `Settings.DeleteAPIKey`
   - Triggers: `settingsManager.saveSettings()` → Deletes API key from keychain

3. **TogglePin** (TalkieButtonSync) - in QuickActionsSettings.swift
   - Action: `Settings.TogglePin`
   - Triggers: `workflowManager.updateWorkflow()` → Updates workflow pinned state

## Expected Performance Monitor Output

When clicking these buttons, the Performance Monitor (Cmd+Shift+P) will now show:

```
#   ACTION                     PROCESSING TIME    BREAKDOWN
1   CLICK AllMemos.Sort.Date   42ms              DB (37ms) • Processing (5ms)
2   CLICK AllMemos.LoadMore    125ms             2 DB (120ms) • Processing (5ms)
3   CLICK Settings.SaveAPIKey  8ms               Processing (8ms)
4   CLICK AllMemos.ClearSearch 35ms              DB (35ms)
```

## Convention-Based Naming

All buttons automatically inherit section context from parent `TalkieSection`:

```swift
TalkieSection("AllMemos") {
    TalkieButton("LoadMore") { ... }  // → "AllMemos.LoadMore"
}

// Or explicit section override:
TalkieButton("Save", section: "Settings") { ... }  // → "Settings.Save"
```

## Next Steps

Per `/docs/engineering/performance/NEXT_STEPS.md`:

### Phase 2: Add Missing Operation Categories
- [ ] Network calls (instrument API client)
- [ ] Workflow runs (instrument WorkflowExecutor)
- [ ] LLM calls (instrument OpenAI/Claude API calls)
- [ ] Engine tasks (instrument EngineClient)

### Phase 3: More UI Buttons
Other button-heavy views to consider:
- Workflow views (Run, Edit, Delete)
- Memo detail view actions
- Model management buttons
- Live view controls

## Testing

To verify instrumentation:
1. Run the app
2. Press Cmd+Shift+P to open Performance Monitor
3. Click any instrumented button
4. Verify action appears in the list with processing time breakdown

All DB operations are automatically tracked via `GRDBRepository` instrumentation.
