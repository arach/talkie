# WFKit Usage Examples

## Phase 1: Backward Compatible - Everything Still Works! ✅

Your existing code **continues to work exactly as before**. The backend abstraction is purely additive.

### Before WFKit (Still Works)

```swift
// Existing code - NO CHANGES NEEDED
let workflow = WorkflowDefinition(
    name: "Summarize Meeting",
    steps: [
        .transcribe(qualityTier: .balanced),
        .llm(provider: .mlx, prompt: "Summarize: {{transcript}}")
    ]
)

// Execute as before
let outputs = try await WorkflowExecutor.shared.executeWorkflow(
    workflow,
    for: memo,
    context: coreDataContext
)
```

### With WFKit (New Way - Same Result)

```swift
// Same workflow definition
let workflow = WorkflowDefinition(
    name: "Summarize Meeting",
    steps: [
        .transcribe(qualityTier: .balanced),
        .llm(provider: .mlx, prompt: "Summarize: {{transcript}}")
    ]
)

// Create context (now explicit)
var context = WorkflowContext(
    transcript: memo.currentTranscript ?? "",
    title: memo.title ?? "Untitled",
    date: memo.createdAt ?? Date(),
    memo: memo,
    coreDataContext: coreDataContext
)

// Execute via backend abstraction
let backend = LocalSwiftBackend(coreDataContext: coreDataContext)
let outputs = try await backend.execute(workflow: workflow, context: context)

// outputs is exactly the same as before!
```

## What Changed Under the Hood

### WorkflowContext - Now Includes Backend Support

```swift
// Before
struct WorkflowContext {
    var transcript: String
    var title: String
    var date: Date
    var outputs: [String: String] = [:]
}

// After (backward compatible - just added fields)
struct WorkflowContext {
    var transcript: String
    var title: String
    var date: Date
    var outputs: [String: String] = [:]

    // NEW: Backend support
    unowned var memo: VoiceMemo
    unowned var coreDataContext: NSManagedObjectContext
}
```

### WorkflowExecutor - Still Works, Now Backend-Aware

The existing `WorkflowExecutor.executeWorkflow()` method **still works exactly as before**. Under the hood, it now creates a `WorkflowContext` that includes the memo and context references.

```swift
// In WorkflowExecutor.swift
func executeWorkflow(
    _ workflow: WorkflowDefinition,
    for memo: VoiceMemo,
    context: NSManagedObjectContext
) async throws -> [String: String] {
    // NEW: Create WorkflowContext with backend support
    var workflowContext = WorkflowContext(
        transcript: transcript,
        title: memo.title ?? "Untitled",
        date: memo.createdAt ?? Date(),
        memo: memo,                    // NEW
        coreDataContext: context       // NEW
    )

    // Rest of the code is UNCHANGED
    // ...
}
```

## Phase 2 Preview: Hybrid Execution (Coming Soon)

Once we add `VercelBackend`, you'll be able to do this:

```swift
// Define workflow with MIXED local and remote steps
let workflow = WorkflowDefinition(
    name: "Brain Dump (Hybrid)",
    steps: [
        // Local: Fast, private transcription
        .transcribe(qualityTier: .balanced),

        // Local: Quick MLX model
        .llm(provider: .mlx, prompt: "Extract ideas: {{transcript}}"),

        // REMOTE: Complex TypeScript function on Vercel!
        .vercelFunction(VercelFunctionConfig(
            functionName: "analyzeIdeas",
            input: "{{ideas}}",
            timeout: 30
        )),

        // Local: Save to Obsidian
        .saveFile(directory: "@Obsidian", content: "{{analysis}}")
    ]
)

// Execute with automatic backend routing
let router = WorkflowRouter(
    defaultBackend: LocalSwiftBackend(),
    remoteBackend: VercelBackend(apiKey: settings.vercelApiKey)
)

let outputs = try await router.execute(workflow, context: context)
// → Steps 1-2: Run locally (fast, no network)
// → Step 3: Pushed to Vercel (runs TypeScript)
// → Step 4: Runs locally (file system access)
```

## Phase 3 Preview: Export to Vercel Format (Escape Hatch)

```swift
// Export your Swift workflow to pure Vercel TypeScript
let workflow = WorkflowDefinition(...)

let vercelWorkflow = workflow.export(to: .vercel)
// → Generates TypeScript workflow definition
// → Can run entirely on Vercel without macOS

let yamlWorkflow = workflow.export(to: .yaml)
// → Portable format for other tools (n8n, etc.)
```

## Testing Your Workflows

### Before WFKit

```swift
// Test in-app only (need full Core Data stack)
let memo = createTestMemo()
let outputs = try await WorkflowExecutor.shared.executeWorkflow(
    workflow,
    for: memo,
    context: testContext
)
XCTAssertEqual(outputs["summary"], expectedSummary)
```

### With WFKit (More Testable!)

```swift
// Test without Core Data using mock backend!
class MockBackend: ExecutionBackend {
    func execute(workflow: WorkflowDefinition, context: WorkflowContext) async throws -> [String: String] {
        // Return test data
        return ["summary": "Test summary"]
    }
    // ...
}

// Test workflow logic independently
let backend = MockBackend()
let outputs = try await backend.execute(workflow: workflow, context: testContext)
XCTAssertEqual(outputs["summary"], "Test summary")
```

## Benefits Summary

### Immediate (Phase 1) ✅
- **Zero Breaking Changes**: All existing code works
- **Better Architecture**: Clean separation of concerns
- **More Testable**: Can mock backends for unit tests
- **Future-Proof**: Easy to add new backends

### Coming Soon (Phase 2)
- **Hybrid Execution**: Mix local and remote steps
- **No TypeScript Runtime**: Push complex steps to Vercel
- **Backend Routing**: Automatic step → backend mapping

### Future (Phase 3+)
- **Workflow Export**: Escape hatch to other platforms
- **Temporal Integration**: Durable, fault-tolerant execution
- **WFKit Package**: Open source for Swift community

## Migration Checklist

- [x] ExecutionBackend protocol created
- [x] LocalSwiftBackend wraps existing executor
- [x] WorkflowContext extended with backend support
- [x] All existing code still compiles ✅
- [x] Build succeeds with zero errors ✅
- [ ] VercelBackend implementation
- [ ] Workflow Router for multi-backend execution
- [ ] Export to Vercel format
- [ ] Extract as Swift Package

## Next Steps

1. **Test current implementation** - Run existing workflows to verify
2. **Design VercelBackend** - HTTP client for Vercel Workflow API
3. **Add step type: `.vercelFunction`** - For remote execution
4. **Build WorkflowRouter** - Automatic backend selection
5. **Export converters** - Vercel format, YAML, etc.
