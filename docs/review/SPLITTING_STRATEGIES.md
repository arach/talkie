# Smart Splitting Strategies for Large Files

**Generated**: 2024-12-31

This document presents concrete splitting strategies for files over 2,000 lines that preserve the key benefits identified in the devil's advocate analysis.

---

## Summary

| File | Current | Strategy | After Split | Key Preservation |
|------|---------|----------|-------------|------------------|
| WorkflowViews.swift | 5,688 | Split by view type | 6 files (~800-2400 each) | Switch dispatch locality |
| TalkieLive/SettingsView.swift | 4,274 | Split by section | 12 files (~150-550 each) | Singleton access patterns |
| WorkflowDefinition.swift | 2,312 | Split by concern | 5 files (~200-1200 each) | Codable synthesis |
| WorkflowExecutor.swift | 2,289 | Extension-based | 10 files (~80-500 each) | WorkflowContext flow |

---

## 1. WorkflowViews.swift (5,688 lines)

### Strategy: Split by View Type

**Key insight**: Keep all 18 variants of each view type together, not split by step type. The polymorphic switch dispatch references all types, so they benefit from locality.

```
Workflow/
├── WorkflowViews.swift              (~800 lines) - Core components
├── WorkflowEditors.swift            (~500 lines) - Editing containers
├── WorkflowStepEditor.swift         (~400 lines) - Step container + dispatch
├── WorkflowStepDetails.swift        (~500 lines) - 18 compact detail views
├── WorkflowStepReadViews.swift      (~1,300 lines) - 18 read-only views
└── WorkflowStepConfigEditors.swift  (~2,400 lines) - 18 config editors
```

**Why this works**:
- Switch dispatch in `WorkflowStepEditor` can reference types from other files (same module)
- All "read views" together = similar structure, same purpose
- Adding new step type: edit 4 files in predictable locations

**Alternative for smaller files** (if ~2,400 lines is too large):
```
WorkflowStepConfigEditors/
├── AIStepConfigEditors.swift        (~500) - LLM, Transcribe, Speak, IntentExtract
├── IntegrationStepConfigEditors.swift (~400) - Webhook, Email, Apple*, Clipboard
├── ControlFlowStepConfigEditors.swift (~400) - Trigger, Conditional, Transform
└── ShellStepConfigEditor.swift      (~270) - Complex security logic
```

---

## 2. TalkieLive/SettingsView.swift (4,274 lines)

### Strategy: Split by Settings Section

**Key insight**: Each section is ~300-500 lines with clear boundaries. All sections access singletons (`LiveSettings.shared`, `EngineClient.shared`), so no environment objects need passing.

```
Views/Settings/
├── SettingsView.swift               (~400 lines) - Navigation coordinator
├── SettingsComponents.swift         (~400 lines) - Reusable UI components
├── AppearanceSettingsSection.swift  (~550 lines) - Theme, color, font
├── ShortcutsSettingsSection.swift   (~200 lines) - Hotkey config
├── SoundsSettingsSection.swift      (~250 lines) - Sound selection grid
├── OutputSettingsSection.swift      (~200 lines) - Paste/routing options
├── OverlaySettingsSection.swift     (~200 lines) - Visual feedback
├── AudioSettingsSection.swift       (~150 lines) - Microphone selection
├── EngineSettingsSection.swift      (~450 lines) - Model management
├── StorageSettingsSection.swift     (~400 lines) - Data management
├── AboutSettingsSection.swift       (~200 lines) - Version info
└── ConnectionsSettingsSection.swift (~200 lines) - XPC status
```

**Implementation order** (minimize conflicts):
1. About, Connections (no internal dependencies)
2. Sounds, Storage (shared components)
3. Engine, Audio (engine client)
4. Appearance (most interdependencies)
5. Create SettingsComponents.swift and slim main file

**Note**: `PermissionsSettingsSection.swift` already extracted.

---

## 3. WorkflowDefinition.swift (2,312 lines)

### Strategy: Same-Module File Split

**Key insight**: Swift's Codable synthesis works when all types are in the same module, even across files. The StepConfig enum stays in the core file, but individual config structs can be extracted.

```
Workflow/
├── WorkflowDefinition.swift         (~400 lines) - Core types + StepConfig enum
├── WorkflowStepConfigs.swift        (~1,200 lines) - All 18 config structs
├── WorkflowLLMTypes.swift           (~250 lines) - Provider/model types
├── WorkflowSystemDefinitions.swift  (~350 lines) - Static workflows (as extension)
└── WorkflowManager.swift            (~200 lines) - Manager class
```

### File Details

**WorkflowDefinition.swift** (core - ~400 lines):
```swift
// Keep together:
struct WorkflowDefinition: Identifiable, Codable, Hashable { ... }
struct WorkflowStep: Identifiable, Codable { ... }
enum StepType: String, Codable, CaseIterable { ... }
enum StepCategory: String, CaseIterable { ... }

// StepConfig enum MUST see all associated types at compile time
// Types defined in WorkflowStepConfigs.swift (same module = works)
enum StepConfig: Codable {
    case llm(LLMStepConfig)
    case shell(ShellStepConfig)
    // ... 16 more cases
}

struct StepCondition: Codable { ... }
enum WorkflowColor: String, Codable { ... }
```

**WorkflowStepConfigs.swift** (~1,200 lines):
```swift
// Each config struct is independently Codable
struct LLMStepConfig: Codable { ... }
struct ShellStepConfig: Codable { ... }  // Including security logic
struct WebhookStepConfig: Codable { ... }
// ... all 18 config structs
```

**WorkflowSystemDefinitions.swift** (~350 lines):
```swift
extension WorkflowDefinition {
    static let heyTalkieWorkflowId = UUID(...)
    static let heyTalkie = WorkflowDefinition(...)
    static let systemTranscribe = WorkflowDefinition(...)
    // ... static workflow definitions
}
```

**Why Codable still works**:
```
Xcode compiles all .swift files in target together:
  WorkflowDefinition.swift     ← StepConfig enum here
  WorkflowStepConfigs.swift    ← LLMStepConfig, etc. here

StepConfig sees all types → Codable synthesis succeeds
```

---

## 4. WorkflowExecutor.swift (2,289 lines)

### Strategy: Extension-Based Split

**Key insight**: Swift allows extending a class across files in the same module. Keep orchestration in core file, extract step executors to extensions.

```
Workflow/
├── WorkflowExecutor.swift           (~500 lines) - Core orchestration
├── WorkflowExecutor+LLM.swift       (~80 lines)
├── WorkflowExecutor+Shell.swift     (~200 lines)
├── WorkflowExecutor+Communication.swift (~150 lines)
├── WorkflowExecutor+Apple.swift     (~180 lines)
├── WorkflowExecutor+Transcription.swift (~180 lines)
├── WorkflowExecutor+Speech.swift    (~170 lines)
├── WorkflowExecutor+Triggers.swift  (~280 lines)
├── WorkflowExecutor+Output.swift    (~100 lines)
└── WorkflowExecutor+Legacy.swift    (~150 lines)
```

### Core File Contents

**WorkflowExecutor.swift** (~500 lines):
```swift
// Keep together - the "what happens when":
struct WorkflowContext { ... }  // Template resolution
class WorkflowExecutor {
    // Properties, initialization
    // executeWorkflow(_:for:) - Main orchestration loop
    // executeStep(_:context:) - Dispatch switch
    // saveWorkflowRun(...) - Persistence
    // evaluateCondition(...) - Used by multiple steps
}
enum WorkflowError { ... }
```

### Extension Files

Each extension file contains step executor methods:

**WorkflowExecutor+Shell.swift** (~200 lines):
```swift
extension WorkflowExecutor {
    func executeShellStep(_ config: ShellStepConfig,
                          context: WorkflowContext) async throws -> String {
        // Process execution with timeout, env handling
    }
}
```

**WorkflowExecutor+Communication.swift** (~150 lines):
```swift
extension WorkflowExecutor {
    func executeWebhookStep(...) async throws -> String
    func executeEmailStep(...) async throws -> String
    func executeNotificationStep(...) async throws -> String
    func executeiOSPushStep(...) async throws -> String
}
```

**Why context flow is preserved**:
```swift
// In core file - dispatch remains visible:
private func executeStep(_ step: WorkflowStep,
                         context: inout WorkflowContext) async throws -> String {
    switch step.config {
    case .llm(let config):
        return try await executeLLMStep(config, context: context)  // In +LLM.swift
    case .shell(let config):
        return try await executeShellStep(config, context: context) // In +Shell.swift
    // ...
    }
}
```

### Implementation Order

1. **Phase 1**: Extract `+Legacy.swift` (rarely touched)
2. **Phase 2**: Extract `+Output.swift` (simple, self-contained)
3. **Phase 3**: Extract `+Apple.swift` (AppleScript methods)
4. **Phase 4**: Extract `+Communication.swift` (webhook, email)
5. **Phase 5**: Extract `+Shell.swift` (largest single method)
6. **Phase 6**: Extract `+Transcription.swift` and `+Speech.swift`
7. **Phase 7**: Extract `+Triggers.swift` and `+LLM.swift`

---

## Migration Checklist

For each file split:

1. **Create new files** with extracted content
2. **Update Xcode project**: `./scripts/sync-xcode-files.py`
3. **Build and verify**: Ensure compilation succeeds
4. **Test runtime**: Run existing tests, manual verification
5. **Delete old content**: Remove extracted code from original file
6. **Commit**: One commit per logical extraction phase

---

## What We Preserved

| Original Concern | How It's Preserved |
|-----------------|-------------------|
| **Codable synthesis** | StepConfig enum stays in core file, configs in same module |
| **@Observable batching** | SettingsManager stays unified (not split) |
| **Switch dispatch locality** | All 18 step variants in dedicated type files |
| **WorkflowContext flow** | Extensions share context via parameters |
| **Security coherence** | ShellStepConfig stays together with allowlist/blocklist |
| **Developer discoverability** | Clear file naming, predictable locations |

---

## Files That Should NOT Be Split

Based on analysis, these files should remain unified:

1. **SettingsManager.swift** (1,732 lines) - @Observable batching + Theme coordination
2. **EngineService.swift** (999 lines) - XPC service boundary + shared state
3. **LiveController.swift** (1,195 lines) - State machine requires visibility

For these, improve organization via MARK sections and documentation instead.
