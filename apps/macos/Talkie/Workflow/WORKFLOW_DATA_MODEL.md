# Workflow Data Model Design

## Philosophy: Vercel-Compatible Event Sourcing

This design adopts **Vercel Workflow's event sourcing approach** while optimizing for:
- **SQLite + GRDB** (local, fast, no network)
- **Swift type safety** (Codable, enums)
- **Export compatibility** (can map to Vercel format later)
- **Clean migration** from existing Core Data

---

## Core Tables

### 1. `workflow_runs` - Workflow Execution Instances

```sql
CREATE TABLE workflow_runs (
    -- Identity
    id TEXT PRIMARY KEY,                    -- UUID as string
    workflow_id TEXT NOT NULL,              -- References workflow definition
    workflow_name TEXT NOT NULL,            -- Denormalized for queries
    workflow_version INTEGER DEFAULT 1,     -- For versioning workflows

    -- Association
    memo_id TEXT NOT NULL,                  -- References voice_memos.id

    -- Status
    status TEXT NOT NULL,                   -- 'pending', 'running', 'completed', 'failed', 'cancelled'

    -- Timestamps
    created_at DATETIME NOT NULL,           -- When run started
    updated_at DATETIME NOT NULL,           -- Last status change
    started_at DATETIME,                    -- When first step began
    completed_at DATETIME,                  -- When run finished

    -- Execution Context (snapshot)
    input_transcript TEXT,                  -- Initial transcript
    input_title TEXT,                       -- Memo title at start
    input_date DATETIME,                    -- Memo date

    -- Results
    final_outputs TEXT,                     -- JSON: {"summary": "...", "tasks": "..."}
    error_message TEXT,                     -- If status = 'failed'
    error_stack TEXT,                       -- Full error details

    -- Metadata
    duration_ms INTEGER,                    -- Total execution time
    step_count INTEGER DEFAULT 0,           -- Number of steps executed
    trigger_source TEXT,                    -- 'manual', 'auto', 'api', 'live'

    -- Execution Environment
    backend_id TEXT DEFAULT 'local-swift',  -- Which backend executed this

    -- Indexes
    INDEX idx_workflow_runs_memo_id (memo_id),
    INDEX idx_workflow_runs_status (status),
    INDEX idx_workflow_runs_created_at (created_at DESC),
    INDEX idx_workflow_runs_workflow_id (workflow_id)
);
```

### 2. `workflow_steps` - Individual Step Executions

```sql
CREATE TABLE workflow_steps (
    -- Identity
    id TEXT PRIMARY KEY,                    -- UUID as string
    run_id TEXT NOT NULL,                   -- References workflow_runs.id
    step_number INTEGER NOT NULL,           -- Execution order (0-indexed)

    -- Step Definition
    step_type TEXT NOT NULL,                -- 'llm', 'shell', 'transcribe', etc.
    step_config TEXT NOT NULL,              -- JSON config for this step
    output_key TEXT NOT NULL,               -- Variable name for output

    -- Execution
    status TEXT NOT NULL,                   -- 'pending', 'running', 'completed', 'failed', 'skipped'

    -- Timestamps
    created_at DATETIME NOT NULL,
    started_at DATETIME,
    completed_at DATETIME,

    -- Input/Output
    input_snapshot TEXT,                    -- Resolved input (after template vars)
    output_value TEXT,                      -- Step result

    -- Metadata
    duration_ms INTEGER,
    retry_count INTEGER DEFAULT 0,

    -- LLM-specific (nullable)
    provider_name TEXT,                     -- 'openai', 'gemini', 'mlx'
    model_id TEXT,                          -- 'gpt-4', 'gemini-flash', etc.
    tokens_used INTEGER,                    -- For cost tracking
    cost_usd REAL,                          -- Calculated cost

    -- Error Handling
    error_message TEXT,
    error_stack TEXT,

    -- Backend
    backend_id TEXT DEFAULT 'local-swift',  -- Where this step executed

    -- Indexes
    INDEX idx_workflow_steps_run_id (run_id),
    INDEX idx_workflow_steps_run_step (run_id, step_number),

    FOREIGN KEY (run_id) REFERENCES workflow_runs(id) ON DELETE CASCADE
);
```

### 3. `workflow_events` - Event Log (Event Sourcing)

This is Vercel's key innovation - **event sourcing** for workflow state.
Every state change is an immutable event.

```sql
CREATE TABLE workflow_events (
    -- Identity
    id TEXT PRIMARY KEY,                    -- UUID as string
    run_id TEXT NOT NULL,                   -- References workflow_runs.id
    sequence INTEGER NOT NULL,              -- Order within run (auto-increment)

    -- Event Type
    event_type TEXT NOT NULL,               -- See Event Types below

    -- Timestamps
    created_at DATETIME NOT NULL,

    -- Payload (event-specific data)
    payload TEXT NOT NULL,                  -- JSON: varies by event_type

    -- Optional Step Reference
    step_id TEXT,                           -- If event relates to a step

    -- Indexes
    INDEX idx_workflow_events_run_id (run_id),
    INDEX idx_workflow_events_run_seq (run_id, sequence),
    INDEX idx_workflow_events_type (event_type),
    INDEX idx_workflow_events_created_at (created_at DESC),

    FOREIGN KEY (run_id) REFERENCES workflow_runs(id) ON DELETE CASCADE,
    FOREIGN KEY (step_id) REFERENCES workflow_steps(id) ON DELETE SET NULL
);
```

#### Event Types

```swift
enum WorkflowEventType: String, Codable {
    // Run Lifecycle
    case runCreated         // Run initialized
    case runStarted         // First step began
    case runCompleted       // All steps successful
    case runFailed          // Run failed with error
    case runCancelled       // User cancelled

    // Step Lifecycle
    case stepCreated        // Step queued
    case stepStarted        // Step execution began
    case stepCompleted      // Step finished successfully
    case stepFailed         // Step failed
    case stepSkipped        // Step skipped (condition)
    case stepRetrying       // Retry attempt

    // Execution Events
    case outputGenerated    // Step produced output
    case variableResolved   // Template variable resolved
    case conditionEvaluated // Conditional evaluated

    // External Events
    case webhookReceived    // External webhook
    case userIntervention   // Manual input required

    // Backend Events
    case backendSwitched    // Execution moved to different backend
}
```

#### Example Event Payloads

```json
// runStarted
{
  "workflow_name": "Summarize Meeting",
  "trigger_source": "manual",
  "context": {
    "transcript_length": 5234,
    "memo_title": "Team Standup"
  }
}

// stepCompleted
{
  "step_number": 2,
  "step_type": "llm",
  "output_key": "summary",
  "output_length": 456,
  "duration_ms": 2340,
  "provider": "mlx",
  "model": "llama-3.2-1b"
}

// runFailed
{
  "error_type": "WorkflowError",
  "error_message": "LLM provider unavailable",
  "failed_step": 3,
  "step_type": "llm"
}
```

---

## Why Event Sourcing?

**Vercel's Approach**: Events are the **source of truth**. State is derived from events.

### Benefits

1. **Replay** - Reconstruct any past state
2. **Debugging** - Complete execution history
3. **Auditing** - Immutable log of what happened
4. **Analytics** - Rich data for insights
5. **Export** - Easy to convert to Vercel format

### How It Works

```swift
// Execute workflow
let run = WorkflowRun(...)
await world.saveEvent(.runCreated, run: run)
await world.saveEvent(.runStarted, run: run)

for step in workflow.steps {
    await world.saveEvent(.stepCreated, run: run, step: step)
    await world.saveEvent(.stepStarted, run: run, step: step)

    let output = try await executeStep(step)

    await world.saveEvent(.outputGenerated, run: run, step: step, payload: ["output": output])
    await world.saveEvent(.stepCompleted, run: run, step: step)
}

await world.saveEvent(.runCompleted, run: run)
```

---

## Migration from Core Data

### Existing `WorkflowRun` (Core Data)

```swift
class WorkflowRun: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var workflowId: UUID
    @NSManaged var workflowName: String
    @NSManaged var output: String
    @NSManaged var status: String
    @NSManaged var runDate: Date
    @NSManaged var stepOutputsJSON: String?  // Array of StepExecution
    @NSManaged var memo: VoiceMemo
    // ...
}
```

### Migration Strategy

```swift
// Convert existing WorkflowRun → new tables
func migrateWorkflowRun(_ oldRun: WorkflowRun) async throws {
    // 1. Create workflow_runs row
    let run = WorkflowRunModel(
        id: oldRun.id,
        workflowId: oldRun.workflowId,
        workflowName: oldRun.workflowName,
        status: oldRun.status,
        createdAt: oldRun.runDate,
        completedAt: oldRun.runDate,
        finalOutputs: oldRun.output,
        memoId: oldRun.memoId
    )
    try await db.save(run)

    // 2. Create workflow_steps from stepOutputsJSON
    if let stepsJSON = oldRun.stepOutputsJSON,
       let steps = try? JSONDecoder().decode([StepExecution].self, from: Data(stepsJSON.utf8)) {
        for (index, stepExec) in steps.enumerated() {
            let step = WorkflowStepModel(
                id: UUID(),
                runId: run.id,
                stepNumber: index,
                stepType: stepExec.stepType,
                outputKey: stepExec.outputKey,
                outputValue: stepExec.output,
                status: "completed",
                createdAt: run.createdAt,
                completedAt: run.completedAt
            )
            try await db.save(step)
        }
    }

    // 3. Create synthetic events (minimal event log)
    try await db.saveEvent(.runCreated, run: run)
    try await db.saveEvent(.runCompleted, run: run)
}
```

---

## World Protocol (Vercel Compatibility)

```swift
/// The "World" abstraction - how workflows persist state
/// Based on Vercel's @workflow/world interface
@MainActor
protocol WorkflowWorld {
    // Runs
    func createRun(_ run: WorkflowRunModel) async throws
    func updateRun(_ run: WorkflowRunModel) async throws
    func getRun(id: UUID) async throws -> WorkflowRunModel?
    func listRuns(memoId: UUID?, status: String?, limit: Int) async throws -> [WorkflowRunModel]

    // Steps
    func createStep(_ step: WorkflowStepModel) async throws
    func updateStep(_ step: WorkflowStepModel) async throws
    func getSteps(runId: UUID) async throws -> [WorkflowStepModel]

    // Events
    func saveEvent(_ event: WorkflowEventModel) async throws
    func getEvents(runId: UUID) async throws -> [WorkflowEventModel]

    // Replay (reconstruct state from events)
    func replayRun(id: UUID) async throws -> WorkflowRunModel
}
```

### SQLite Implementation

```swift
/// SQLite/GRDB implementation of WorkflowWorld
final class SQLiteWorkflowWorld: WorkflowWorld {
    private let db: DatabaseWriter

    init(database: DatabaseWriter) {
        self.db = database
    }

    func createRun(_ run: WorkflowRunModel) async throws {
        try await db.write { db in
            try run.insert(db)
        }

        // Also save event
        let event = WorkflowEventModel(
            eventType: .runCreated,
            runId: run.id,
            payload: ["workflow_name": run.workflowName]
        )
        try await saveEvent(event)
    }

    // ... implement rest of protocol
}
```

---

## Export to Vercel Format

```swift
extension WorkflowRunModel {
    /// Convert to Vercel Workflow format for remote execution
    func toVercelFormat() async throws -> VercelWorkflowRun {
        // Map our schema → Vercel's schema
        return VercelWorkflowRun(
            id: id.uuidString,
            workflowId: workflowId.uuidString,
            status: status,
            events: try await getEvents(),
            steps: try await getSteps()
        )
    }
}
```

---

## Next Steps

1. ✅ Design schema (this document)
2. Create GRDB models for all three tables
3. Add database migration v3
4. Implement `SQLiteWorkflowWorld`
5. Update `WorkflowExecutor` to use World
6. Migrate existing Core Data → new tables
7. Test local execution

---

## Benefits of This Approach

- ✅ **Vercel-compatible** structure (easy to export later)
- ✅ **Event sourcing** for debugging and replay
- ✅ **SQLite-optimized** (fast, local, no network)
- ✅ **Type-safe** Swift models with Codable
- ✅ **Clean migration** from existing Core Data
- ✅ **Foundation for hybrid execution** (local + remote)

This is the **data model foundation** that unlocks everything else!
