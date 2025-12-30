# Workflow Module

`macOS/Talkie/Workflow/` - TWF (Talkie Workflow Format) automation (11 files)

---

## ⚠️ Critical: Large Files

| File | Lines | Priority |
|------|-------|----------|
| **WorkflowViews.swift** | 5688 | 🔴 Critical - needs immediate split |
| **WorkflowDefinition.swift** | 2307 | 🟠 High - review for split |
| **WorkflowExecutor.swift** | 2226 | 🟠 High - review for split |
| TalkieWorkflowSchema.swift | 941 | Medium |
| TWFLoader.swift | 623 | OK |

---

## Files

### WorkflowViews.swift (5688 lines)
UI for workflow builder.

**Discussion:**
- **CRITICAL:** This is the largest file in the codebase
- Needs splitting into separate view files:
  - WorkflowListView
  - WorkflowEditorView
  - WorkflowNodeView
  - WorkflowCanvasView
  - WorkflowInspectorView
  - etc.

---

### WorkflowDefinition.swift (2307 lines)
Workflow data structures and definitions.

**Discussion:**
- Large but may be justified for type definitions
- Consider splitting by concern

---

### WorkflowExecutor.swift (2226 lines)
Workflow execution engine.

**Discussion:**
- Core execution logic
- May need splitting by step type handlers

---

### TalkieWorkflowSchema.swift (941 lines)
TWF JSON schema definition.

**Discussion:**

---

### TWFLoader.swift (623 lines)
TWF file loading and parsing.

**Discussion:**

---

### TalkieWorkflowConverter.swift (285 lines)
Format conversion utilities.

**Discussion:**

---

### AutoRunProcessor.swift (251 lines)
Auto-run workflow handling.

**Discussion:**

---

### ExecutionBackend.swift (216 lines)
Execution backend abstraction.

**Discussion:**

---

### WorkflowAction.swift (177 lines)
Action definitions.

**Discussion:**

---

### WorkflowWorld.swift (162 lines)
Workflow execution context.

**Discussion:**

---

### LocalSwiftBackend.swift (114 lines)
Local Swift execution backend.

**Discussion:**

---

## TODO

- [ ] 🔴 **CRITICAL:** Split WorkflowViews.swift (5688 lines) into multiple files
- [ ] Review WorkflowDefinition.swift for potential split
- [ ] Review WorkflowExecutor.swift for potential split
- [ ] Add unit tests for workflow execution

## Done

- Initial review complete
- Identified 3 files needing refactoring
