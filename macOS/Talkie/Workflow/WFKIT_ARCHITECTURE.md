# WFKit Architecture Design

## Vision

**WFKit** is the Swift-native workflow definition and visualization layer for the workflow execution ecosystem.

### Core Principle
**Define once, execute anywhere** - Write workflows in Swift, execute on any backend (local, Vercel, Temporal, etc.)

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│              Application Layer (Talkie)                 │
│  • SwiftUI workflow builder                            │
│  • Visual workflow editor                              │
│  • Workflow execution monitoring                       │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│                  WFKit Core Layer                       │
│  ┌───────────────────────────────────────────────────┐  │
│  │ 1. Definition Layer                              │  │
│  │   • WorkflowDefinition (already exists!)         │  │
│  │   • WorkflowStep + StepType                      │  │
│  │   • StepConfig variants                          │  │
│  │   • Type-safe validation                         │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │ 2. Execution Abstraction (NEW)                   │  │
│  │   • ExecutionBackend protocol                    │  │
│  │   • WorkflowContext (already exists!)            │  │
│  │   • StepResult type                              │  │
│  │   • Error handling framework                     │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │ 3. Interoperability Layer (NEW)                  │  │
│  │   • Export to Vercel format                      │  │
│  │   • Export to YAML                               │  │
│  │   • Import from various formats                  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────┐
│               Backend Implementations                   │
│                                                         │
│  ┌─────────────────┐  ┌─────────────────┐             │
│  │ LocalSwiftBackend│ │  VercelBackend  │             │
│  │                  │  │                 │             │
│  │ • In-process     │  │ • HTTP API      │             │
│  │ • Fast           │  │ • TypeScript    │             │
│  │ • No network     │  │ • Serverless    │             │
│  └─────────────────┘  └─────────────────┘             │
│                                                         │
│  ┌─────────────────┐  ┌─────────────────┐             │
│  │ TemporalBackend  │  │  Future: n8n,   │             │
│  │                  │  │  Zapier, etc.   │             │
│  │ • Durable        │  │                 │             │
│  │ • State recovery │  │                 │             │
│  │ • Workflows      │  │                 │             │
│  └─────────────────┘  └─────────────────┘             │
└─────────────────────────────────────────────────────────┘
```

---

## Core Protocols

### 1. ExecutionBackend Protocol

```swift
/// Core protocol that all execution backends must implement
@MainActor
protocol ExecutionBackend {
    /// Execute a complete workflow
    func execute(
        workflow: WorkflowDefinition,
        context: WorkflowContext
    ) async throws -> [String: String]

    /// Execute a single step (optional for backends that want granular control)
    func executeStep(
        step: WorkflowStep,
        context: inout WorkflowContext
    ) async throws -> StepResult

    /// Backend capabilities
    var capabilities: BackendCapabilities { get }

    /// Backend metadata
    var metadata: BackendMetadata { get }
}

struct BackendCapabilities {
    let supportedStepTypes: Set<WorkflowStep.StepType>
    let supportsStreaming: Bool
    let supportsDurableExecution: Bool
    let supportsParallelSteps: Bool
    let requiresNetwork: Bool
}

struct BackendMetadata {
    let id: String
    let displayName: String
    let description: String
    let version: String
}

struct StepResult {
    let output: String
    let metadata: [String: Any]?
    let duration: TimeInterval
    let error: Error?
}
```

### 2. Backend Implementations

#### LocalSwiftBackend (Phase 1)

```swift
/// Wraps existing WorkflowExecutor logic for backward compatibility
@MainActor
final class LocalSwiftBackend: ExecutionBackend {
    private let executor: WorkflowExecutor

    init(executor: WorkflowExecutor = .shared) {
        self.executor = executor
    }

    func execute(
        workflow: WorkflowDefinition,
        context: WorkflowContext
    ) async throws -> [String: String] {
        // Delegate to existing executor
        // This keeps all your existing step implementations working!
        return try await executor.executeWorkflow(
            workflow,
            for: context.memo,
            context: context.coreDataContext
        )
    }

    var capabilities: BackendCapabilities {
        BackendCapabilities(
            supportedStepTypes: Set(WorkflowStep.StepType.allCases),
            supportsStreaming: false,
            supportsDurableExecution: false,
            supportsParallelSteps: false,
            requiresNetwork: false
        )
    }
}
```

#### VercelBackend (Phase 2)

```swift
/// Executes steps remotely on Vercel infrastructure
@MainActor
final class VercelBackend: ExecutionBackend {
    private let apiClient: VercelWorkflowClient
    private let projectId: String

    init(apiKey: String, projectId: String) {
        self.apiClient = VercelWorkflowClient(apiKey: apiKey)
        self.projectId = projectId
    }

    func execute(
        workflow: WorkflowDefinition,
        context: WorkflowContext
    ) async throws -> [String: String] {
        // Convert WorkflowDefinition to Vercel format
        let vercelWorkflow = workflow.toVercelFormat()

        // Start workflow run on Vercel
        let runHandle = try await apiClient.start(
            workflow: vercelWorkflow,
            input: context.toJSON()
        )

        // Stream results as they complete
        var outputs: [String: String] = [:]
        for await event in runHandle.events() {
            switch event {
            case .stepCompleted(let stepId, let output):
                outputs[stepId] = output
            case .workflowCompleted(let finalOutputs):
                return finalOutputs
            case .workflowFailed(let error):
                throw error
            }
        }

        return outputs
    }

    func executeStep(
        step: WorkflowStep,
        context: inout WorkflowContext
    ) async throws -> StepResult {
        // Convert step to Vercel step format
        let vercelStep = step.toVercelFormat()

        // Execute on Vercel (creates isolated API route)
        let result = try await apiClient.executeStep(
            vercelStep,
            input: context.toJSON()
        )

        return StepResult(
            output: result.output,
            metadata: result.metadata,
            duration: result.duration,
            error: nil
        )
    }

    var capabilities: BackendCapabilities {
        BackendCapabilities(
            supportedStepTypes: [.llm, .webhook, .transform], // Subset for remote
            supportsStreaming: true,
            supportsDurableExecution: true,
            supportsParallelSteps: true,
            requiresNetwork: true
        )
    }
}
```

#### TemporalBackend (Phase 3)

```swift
/// Executes workflows on Temporal for durable, fault-tolerant execution
@MainActor
final class TemporalBackend: ExecutionBackend {
    private let client: TemporalClient

    init(namespace: String = "default") async throws {
        self.client = try await TemporalClient.connect(namespace: namespace)
    }

    func execute(
        workflow: WorkflowDefinition,
        context: WorkflowContext
    ) async throws -> [String: String] {
        // Convert to Temporal workflow
        let temporalWorkflow = workflow.toTemporalWorkflow()

        // Execute with automatic state persistence and retry
        let handle = try await client.start(
            workflow: temporalWorkflow,
            input: context.toJSON()
        )

        // Wait for completion (survives crashes/deploys)
        let result = try await handle.result()
        return result.outputs
    }

    var capabilities: BackendCapabilities {
        BackendCapabilities(
            supportedStepTypes: Set(WorkflowStep.StepType.allCases),
            supportsStreaming: true,
            supportsDurableExecution: true,  // Key feature!
            supportsParallelSteps: true,
            requiresNetwork: true
        )
    }
}
```

---

## Hybrid Execution Pattern

**Your key insight:** Mix local and remote execution in a single workflow.

```swift
// Example: Brain Dump Processor with Hybrid Execution
let workflow = WorkflowDefinition(
    name: "Brain Dump (Hybrid)",
    steps: [
        // Local: Fast transcription
        WorkflowStep(
            type: .transcribe,
            config: .transcribe(TranscribeStepConfig(qualityTier: .balanced)),
            outputKey: "transcript"
        ),

        // Local: Quick LLM extraction
        WorkflowStep(
            type: .llm,
            config: .llm(LLMStepConfig(
                provider: .mlx,  // Local MLX model
                prompt: "Extract key ideas from: {{transcript}}"
            )),
            outputKey: "ideas"
        ),

        // REMOTE: Complex TypeScript processing on Vercel
        WorkflowStep(
            type: .vercelFunction(VercelFunctionConfig(
                functionName: "analyzeIdeas",
                input: "{{ideas}}",
                backend: .vercel  // Explicit backend override
            )),
            outputKey: "analysis"
        ),

        // Local: Save to file
        WorkflowStep(
            type: .saveFile,
            config: .saveFile(SaveFileStepConfig(
                directory: "@Obsidian",
                content: "{{analysis}}"
            )),
            outputKey: "saved"
        )
    ]
)

// Execution router automatically picks the right backend per step
let result = try await WorkflowRouter.execute(
    workflow,
    context: context,
    defaultBackend: .local,
    overrides: [
        .vercelFunction: .vercel  // Route specific step type to Vercel
    ]
)
```

---

## Migration Path

### Phase 1: Extract Core (Week 1)
1. ✅ Keep existing code working
2. Create `ExecutionBackend` protocol
3. Wrap `WorkflowExecutor` in `LocalSwiftBackend`
4. Update call sites to use backend abstraction

```swift
// Before (current)
let outputs = try await WorkflowExecutor.shared.executeWorkflow(workflow, for: memo, context: coreDataContext)

// After (with backend abstraction)
let backend = LocalSwiftBackend()
let outputs = try await backend.execute(workflow: workflow, context: workflowContext)
```

### Phase 2: Vercel Integration (Week 2-3)
1. Implement `VercelBackend`
2. Create Vercel format converters
3. Deploy sample TypeScript functions
4. Test hybrid execution

### Phase 3: Data Structure Migration (Week 4)
1. Adopt Vercel's `workflow_runs`, `workflow_steps`, `workflow_events` tables
2. Migrate existing `WorkflowRun` Core Data → new structure
3. Maintain backward compatibility with export/import

### Phase 4: Package Extraction (Week 5)
1. Create `WFKit` Swift Package
2. Extract core types and protocols
3. Publish to Swift Package Index
4. Document and promote

---

## Code Organization

```
WFKit/
├── Sources/
│   └── WFKit/
│       ├── Core/
│       │   ├── WorkflowDefinition.swift       (existing)
│       │   ├── WorkflowStep.swift             (extracted from existing)
│       │   ├── StepConfig.swift               (extracted from existing)
│       │   └── WorkflowContext.swift          (existing)
│       │
│       ├── Execution/
│       │   ├── ExecutionBackend.swift         (NEW protocol)
│       │   ├── StepResult.swift               (NEW)
│       │   ├── BackendCapabilities.swift      (NEW)
│       │   └── WorkflowRouter.swift           (NEW orchestrator)
│       │
│       ├── Backends/
│       │   ├── LocalSwift/
│       │   │   └── LocalSwiftBackend.swift    (wraps existing executor)
│       │   ├── Vercel/
│       │   │   ├── VercelBackend.swift
│       │   │   ├── VercelClient.swift
│       │   │   └── VercelFormatConverter.swift
│       │   └── Temporal/
│       │       ├── TemporalBackend.swift
│       │       └── TemporalWorkflowConverter.swift
│       │
│       ├── Interop/
│       │   ├── VercelExporter.swift
│       │   ├── YAMLExporter.swift
│       │   └── Importers/
│       │
│       └── Utilities/
│           ├── TemplateResolver.swift         (existing)
│           └── ValidationEngine.swift
│
└── Tests/
    └── WFKitTests/
```

---

## Key Benefits

### For Talkie
1. **Immediate value**: Hybrid execution (local + Vercel)
2. **Escape hatch**: Export to other platforms
3. **Future-proof**: Easy to add new backends
4. **Clean architecture**: Separation of concerns

### For Swift Ecosystem
1. **First Swift-native workflow framework**
2. **Multi-backend support** (unique positioning)
3. **Type safety** (catches errors at compile time)
4. **macOS/iOS first-class support** (unlike TypeScript alternatives)

### For Vercel Ecosystem
1. **Swift developers** can now use Vercel Workflows
2. **Mobile-first workflows** with native execution
3. **Hybrid cloud/edge/local** execution patterns

---

## Example: Complete Workflow with Hybrid Execution

```swift
// Define workflow in Swift (WFKit)
let workflow = WorkflowDefinition(
    name: "Meeting Notes Processor",
    steps: [
        // Local: Transcribe audio (fast, private)
        .transcribe(qualityTier: .balanced),

        // Local: Extract quick summary (MLX)
        .llm(provider: .mlx, prompt: "Summarize: {{transcript}}"),

        // Remote: Advanced analysis (Vercel + GPT-5)
        .vercelFunction(
            name: "analyzeWithGPT5",
            input: "{{transcript}}",
            backend: .vercel
        ),

        // Local: Save to Obsidian
        .saveFile(directory: "@Obsidian/Meetings", content: "{{analysis}}"),

        // Remote: Share to team (Vercel handles auth/permissions)
        .vercelFunction(
            name: "shareWithTeam",
            input: "{{analysis}}",
            backend: .vercel
        )
    ]
)

// Execute (WFKit router handles backend switching automatically)
let outputs = try await workflow.execute(
    context: context,
    defaultBackend: .local
)

// Or export for pure Vercel execution
let vercelWorkflow = workflow.export(to: .vercel)
// Deploy to Vercel and run entirely in cloud
```

---

## Next Steps

1. ✅ Get user approval on architecture
2. Create `ExecutionBackend` protocol
3. Implement `LocalSwiftBackend` wrapper
4. Test with existing workflows
5. Start `VercelBackend` implementation

---

## Open Questions

1. **Step Type Routing**: Should certain step types automatically route to specific backends?
   - E.g., `.vercelFunction` → always Vercel
   - E.g., `.transcribe` → always local (privacy)

2. **State Persistence**: Should WFKit handle state persistence or delegate to backends?
   - Option A: WFKit provides unified state storage
   - Option B: Each backend handles its own state

3. **Streaming**: How should streaming work across backends?
   - AsyncSequence for all backends?
   - Callback-based for compatibility?

4. **Error Handling**: Unified error types or backend-specific?
   - WFKitError wrapping backend errors?
   - Or expose raw backend errors?
