# AGENTS.md — macOS

macOS-specific instructions. See root `/AGENTS.md` for shared conventions.

---

## Overview

SwiftUI desktop app that receives voice memos from iOS via CloudKit, runs transcription locally, and executes AI-powered workflows.

## Build

```bash
open Talkie.xcodeproj

# Build
xcodebuild -scheme Talkie -destination 'platform=macOS' build

# Test
xcodebuild -scheme Talkie -destination 'platform=macOS' test

# Archive
xcodebuild -scheme Talkie -configuration Release archive
```

## Project Structure

```
Talkie/
├── App/
│   ├── TalkieApp.swift
│   └── AppDelegate.swift
├── Models/
│   ├── Persistence.swift
│   ├── talkie.xcdatamodeld/     # Core Data model
│   └── VoiceMemo+Transcripts.swift
├── Views/
│   ├── NavigationView.swift     # Sidebar navigation
│   ├── VoiceMemoListView.swift
│   ├── WorkflowListView.swift
│   ├── SystemConsoleView.swift  # Debug logs
│   └── DebugToolbar.swift
├── Services/
│   ├── CloudKitSyncManager.swift
│   ├── TranscriptFileManager.swift
│   ├── SettingsManager.swift
│   ├── WhisperService.swift     # Local transcription
│   ├── ParakeetService.swift    # NVIDIA Parakeet
│   └── LLM/
│       ├── LLMProvider.swift    # Protocol
│       ├── LLMProviderRegistry.swift
│       ├── OpenAIProvider.swift
│       ├── AnthropicProvider.swift
│       ├── GeminiProvider.swift
│       ├── GroqProvider.swift
│       └── MLXProvider.swift    # Local models
├── Workflow/
│   ├── WorkflowDefinition.swift # TWF schema
│   ├── WorkflowExecutor.swift   # Step execution
│   ├── AutoRunProcessor.swift   # Auto-run on sync
│   └── Steps/                   # Step implementations
└── Resources/
    ├── StarterWorkflows/        # Bundled TWF files
    │   ├── TWF_GENERATION_PROMPT.md
    │   ├── quick-summary.twf.json
    │   ├── hey-talkie.twf.json
    │   └── ...
    └── LLMConfig.json           # Provider/model config
```

## Key Services

### CloudKitSyncManager

Handles delta sync from iOS:

```swift
class CloudKitSyncManager {
    let syncInterval: TimeInterval = 60  // Foreground
    let backgroundInterval: TimeInterval = 120

    func fetchChanges() async {
        // Token-based delta sync
        // Triggers AutoRunProcessor on new memos
    }
}
```

### Transcription Services

Multiple engines available:

| Service | Model | Notes |
|---------|-------|-------|
| `WhisperService` | WhisperKit (CoreML) | Local, models in `~/Library/Application Support/Talkie/WhisperModels/` |
| `ParakeetService` | NVIDIA Parakeet | Local |
| `AppleSpeechService` | Apple Speech | Free, on-device |

```swift
protocol TranscriptionService {
    var engineId: String { get }
    func transcribe(audioURL: URL) async throws -> TranscriptionResult
}
```

### LLM Providers

Protocol-based provider system:

```swift
protocol LLMProvider {
    var providerId: String { get }
    func generate(prompt: String, options: LLMOptions) async throws -> String
    func generateStream(prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error>
}
```

Providers: OpenAI, Anthropic, Gemini, Groq, MLX (local)

Cost tiers for automatic routing:
- `fast` → gemini-2.0-flash
- `balanced` → claude-sonnet
- `quality` → claude-opus

### Workflow Executor

Executes TWF workflows step-by-step:

```swift
@MainActor @Observable
final class WorkflowExecutor {
    var isRunning = false
    var currentStep: WorkflowStep?

    func execute(_ workflow: Workflow, context: WorkflowContext) async throws -> WorkflowRun {
        for step in workflow.steps {
            currentStep = step
            let output = try await executeStep(step, context: context)
            context.outputs[step.id] = output
        }
        return WorkflowRun(...)
    }
}
```

### AutoRunProcessor

Triggers workflows when new memos sync:

```swift
class AutoRunProcessor {
    func processPendingMemos() async {
        // Phase 1: Transcription workflows
        // Phase 2: Post-transcription workflows (summary, tasks, etc.)
    }
}
```

## Workflow Development

### Adding a New Step Type

1. Add case to `WorkflowStepType` enum in `WorkflowDefinition.swift`
2. Create config struct (e.g., `NewStepConfig: Codable`)
3. Add execution logic in `WorkflowExecutor.executeStep()`
4. Update `TWF_GENERATION_PROMPT.md` with examples

### Variable Resolution

```swift
// In prompts: {{TRANSCRIPT}}, {{TITLE}}, {{step-id}}, {{step-id.field}}
func resolveVariables(_ template: String, context: WorkflowContext) -> String
```

### Testing Workflows

```bash
# Create test workflow in ~/Documents/Workflows/test.twf.json
# Run via UI or trigger with test memo
```

## Data Flow

```
iOS Recording
     │
     ▼ CloudKit
macOS Sync (CloudKitSyncManager)
     │
     ▼ New memo detected
AutoRunProcessor
     │
     ├─▶ Phase 1: Transcribe (WhisperService)
     │        │
     │        ▼ TranscriptVersion created
     │
     └─▶ Phase 2: Post-transcription workflows
              │
              ▼ WorkflowRun saved
         UI updates
```

## Local Storage

| Path | Content |
|------|---------|
| `~/Documents/Workflows/` | User TWF files |
| `~/Documents/Transcripts/` | Optional Markdown export |
| `~/Library/Application Support/Talkie/WhisperModels/` | Downloaded models |
| Core Data | `~/Library/Containers/.../Data/Library/Application Support/` |

## Debugging

- **System Console**: View in-app at `NavigationView` → System Console
- **Debug Toolbar**: Toggle features, force sync, clear caches
- **Logs**: `log show --predicate 'subsystem == "jdi.talkie-os-mac"' --last 5m`

## Notes

- macOS receives memos, iOS creates them
- Transcription runs locally (no cloud ASR)
- Workflows are macOS-only (iOS displays results after sync back)
- LLM API keys stored in Keychain via `SettingsManager`
