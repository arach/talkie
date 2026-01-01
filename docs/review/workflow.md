# Workflow Module Review

`macOS/Talkie/Workflow/` - TWF (Talkie Workflow Format) automation engine

**Status**: CRITICAL - Needs refactoring
**Total LOC**: ~9,000 lines across 11 files

---

## Critical Issue: WorkflowViews.swift (5,688 lines)

This is the largest file in the entire codebase. It contains the entire workflow UI:
- Workflow list view
- Workflow editor view
- Workflow execution view
- Workflow results display
- Workflow settings
- Action configuration forms
- Trigger configuration

**Risk**: High maintenance burden, difficult to test, slow compilation.

### Recommended Split

```
Workflow/Views/
├── WorkflowListView.swift       # List of workflows with search (~800 lines)
├── WorkflowEditorView.swift     # Step editor with drag-drop (~1200 lines)
├── WorkflowExecutionView.swift  # Execution progress UI (~1000 lines)
├── WorkflowResultsView.swift    # Run history and logs (~600 lines)
├── WorkflowSettingsView.swift   # Global workflow settings (~400 lines)
├── ActionConfigViews.swift      # Per-action configuration forms (~800 lines)
├── TriggerConfigViews.swift     # Trigger setup UI (~400 lines)
└── WorkflowComponents.swift     # Shared components (~500 lines)
```

---

## Files Overview

| File | Lines | Purpose | Risk |
|------|-------|---------|------|
| **WorkflowViews.swift** | 5,688 | ALL workflow UI | 🔴 CRITICAL |
| **WorkflowDefinition.swift** | 2,312 | Schema, validation, types | 🟠 HIGH |
| **WorkflowExecutor.swift** | 2,289 | Execution engine | 🟠 HIGH |
| **TalkieWorkflowSchema.swift** | 941 | JSON schema for .twf format | 🟡 MEDIUM |
| **TWFLoader.swift** | 623 | Workflow file parser | 🟡 MEDIUM |
| TalkieWorkflowConverter.swift | 285 | Format conversion | LOW |
| AutoRunProcessor.swift | 251 | Auto-run triggers | LOW |
| ExecutionBackend.swift | 216 | Backend abstraction | LOW |
| WorkflowAction.swift | 177 | Action definitions | LOW |
| WorkflowWorld.swift | 162 | Variable context | LOW |
| LocalSwiftBackend.swift | 114 | Local execution | LOW |

---

## WorkflowDefinition.swift (2,312 lines)

Contains:
- Workflow schema structures
- Step type definitions (18 types)
- Validation logic
- Serialization

**Recommended Split**:
```
Models/
├── WorkflowDefinition.swift    # Core types (~600 lines)
├── WorkflowStepTypes.swift     # Step type enum and configs (~800 lines)
├── WorkflowValidation.swift    # Validation logic (~500 lines)
└── WorkflowSerialization.swift # JSON encoding/decoding (~400 lines)
```

---

## WorkflowExecutor.swift (2,289 lines)

Contains:
- Task queue management
- Step execution dispatch
- Error handling
- Result collection
- Progress reporting

**Recommended Split**:
```
Execution/
├── WorkflowExecutor.swift      # Main coordinator (~500 lines)
├── StepExecutors/              # Per-step type executors
│   ├── TranscribeExecutor.swift
│   ├── PolishExecutor.swift
│   ├── SaveExecutor.swift
│   ├── NotifyExecutor.swift
│   └── HTTPExecutor.swift
├── ExecutionQueue.swift        # Task queueing (~300 lines)
└── ExecutionLogger.swift       # Progress/result logging (~200 lines)
```

---

## Architecture

### Data Flow
```
.twf file
    ↓ TWFLoader
WorkflowDefinition
    ↓ TalkieWorkflowConverter
Executable Workflow
    ↓ WorkflowExecutor
    ↓ StepExecutors
Results → WorkflowRunModel (Core Data)
```

### Step Types (18)
1. Transcribe
2. Polish (LLM)
3. Summarize
4. Extract entities
5. Translate
6. Save to file
7. Copy to clipboard
8. Send notification
9. Run AppleScript
10. Run shell command
11. HTTP request
12. Open URL
13. Create reminder
14. Add to calendar
15. Send email
16. Post to Slack
17. Save to Notes
18. Custom action

---

## Action Items

### Immediate (P0)
- [ ] 🔴 **CRITICAL:** Split WorkflowViews.swift into 6-8 files
- [ ] Add file-level documentation

### Short-term (P1)
- [ ] Split WorkflowDefinition.swift by concern
- [ ] Extract step executors from WorkflowExecutor.swift
- [ ] Add unit tests for validation logic

### Medium-term (P2)
- [ ] Integrate WFKit for visual editing
- [ ] Add workflow versioning
- [ ] Improve error recovery

---

## Dependencies

```
Workflow/
├── imports: TalkieKit, DebugKit
├── uses: Core Data (results), GRDB (context)
└── provides: WorkflowExecutor, WorkflowDefinition
```

---

## Related Files

- `Views/Settings/WorkflowSettings.swift` - Settings UI
- `Views/Workflows/WorkflowColumnViews.swift` - Navigation
- `Views/Workflows/WorkflowContentViews.swift` - Content area

---

## Done

- Initial review complete (2024-12-29)
- Deep analysis complete (2024-12-31)
- Identified 3 files needing refactoring
- Created detailed split recommendations
