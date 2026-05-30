# TLK-023 - Action Workbench

**Status**: Draft (Claude review incorporated)
**Owner**: Talkie macOS
**Date**: 2026-05-26
**Reviewed by**: `talkie-action-workbench-review` via Scout
**Related**: [TLK-018](tlk-018-media-surface-roundup.md) (media surface unification), [TLK-021](tlk-021-capture-markup.md) (agentic capture markup), [TLK-022](tlk-022-media-augmentation-pipeline.md) (sidecar-derived context)

## Summary

Replace the scattered "Activity", "Actions", and "AI Results" surfaces with one agent-first workbench for creating, editing, running, inspecting, rerunning, and automating Talkie actions.

The workbench should feel closer to a calm CLI session than a dashboard: the user says what they want, Talkie routes it to a workflow or skill, the run streams progress as structured logs, results appear inline, and the same place lets the user revise the workflow and run it again.

This is a clean-slate product spec. It does not try to patch the existing Activity table into shape; it defines the primitives we should build toward.

## Problem

The current flow breaks the loop that workflow users need:

1. Create or discover a workflow.
2. Run it against a memo, capture, screenshot, selected text, or spoken request.
3. See what happened, including errors.
4. Edit the workflow or prompt.
5. Rerun quickly.
6. Promote a useful run into a reusable skill or automation.

Today those steps are split across the workflow editor, screenshot menus, transient "AI Results" windows, logs, and the Activity table. Errors can be invisible unless the user checks logs. Inputs are under-specified, so workflows that expect screenshots, transcripts, or sidecar context fail in ways the UI cannot explain.

## Goals

- Make one primary place for agentic work: authoring, runtime, inspection, and automation.
- Treat every run as a first-class, inspectable `ActionRun`, not just a row in a table.
- Make inputs explicit: workflows declare what record types and parameters they accept.
- Give every run a live console with structured logs, step events, errors, and artifacts.
- Make screenshot and capture actions feel native: right-click `Describe UI` opens the same workbench run.
- Keep the surface simple for a normal user while scaling to power-user workflow iteration.
- Support an agent-first interaction style: command input, suggested edits, and "fix this run" loops.

## Non-goals

- Re-skinning the existing Activity table as the final product.
- Building a generic IDE with many panels and modes in the first slice.
- Replacing the `.skill.md` workflow/skill file format in one jump.
- Making automations fully featured in the first vertical slice.
- Hiding logs from users. The goal is readable logs, not no logs.

## Product Principle

The workbench is the place where Talkie work happens.

A user should be able to start from any object - memo, screenshot, capture, selected text, deck command, or spoken request - and land in the same run loop:

```
ask -> run -> inspect -> revise -> rerun -> save or automate
```

The UI should be quiet and stable, but the agent should be active. The user should mostly feel like they are working with a capable CLI that understands Talkie objects.

## Product Name

Use **Actions** as the user-facing nav slot and menu language.

Use **Action Workbench** in internal docs for the whole surface. Avoid shipping placeholder labels like "AI Results" or "Activity" once the workbench is covering that job.

## Core Concepts

### Action

An executable thing the user can run. In V1 this includes:

| Kind | Examples |
| --- | --- |
| Workflow | Describe UI, Research, Daily Standup |
| Skill | Hey Talkie, capture markup, future saved agent capabilities |
| Direct agent command | "Summarize this screenshot and send it to the Mac" |

The UI can call these "actions" even when the backing implementation is a workflow, skill, or agent route.

### ActionRun

The durable runtime record for one execution.

`ActionRun` is the umbrella record the workbench reads from. It should be designed as the right model for the future product, not as a cautious wrapper around legacy workflow tables.

Phase 1 chooses the fastest correct path:

- Add `ActionRunModel` as the canonical run record for the workbench.
- Route new workflow, skill, screenshot, and agent-command executions through `ActionRunModel`.
- Store polymorphic subjects in an `ActionSubjectRef` table keyed by `actionRunId`.
- Feed the workbench rail from `ActionRunModel`.
- Use old workflow/event models only as implementation shortcuts when they speed up the first slice; do not let their shape constrain the product model.
- Deprecate old Activity and AI Results destinations once the workbench covers their job.

Minimum fields:

| Field | Purpose |
| --- | --- |
| `id` | Stable run id |
| `actionId` | String action id; workflow actions use `workflowId.uuidString`, skills and agent commands use route slugs |
| `actionKind` | `workflow`, `skill`, `agent-command` |
| `title` | Human-readable run title |
| `inputPackageId` | Snapshot of resolved inputs |
| `status` | `queued`, `running`, `completed`, `failed`, `cancelled` |
| `originDeviceId` | Optional origin device for future iOS/Mac routed actions |
| `startedAt`, `completedAt` | Timing |
| `summary` | Short result or failure summary |
| `primaryResultRef` | Markdown/text/file/artifact pointer |
| `error` | User-readable error payload |

### ActionSubjectRef

The polymorphic subjects a run was executed against.

Examples:

| Field | Purpose |
| --- | --- |
| `actionRunId` | Owning action run |
| `kind` | `memo`, `capture`, `note`, `screenshot`, `audio`, `selection`, `device` |
| `id` | Record id when there is one |
| `assetURL` | File URL for asset-backed subjects |
| `titleSnapshot` | Human-readable title at run time |
| `sha256` | Optional durability check for asset-backed subjects |

Phase 1 does not duplicate screenshot bytes into the run record. If the source asset is deleted, rerun fails visibly with a missing-subject error and the original event stream remains intact.

### ActionEvent

Append-only event stream for a run.

Events should be readable in order and cheap to render as a console. Existing `WorkflowEventModel` already has useful lifecycle events; the workbench should adapt those where possible and add the events needed for input resolution, logs, and artifacts.

| Workbench event | Existing `WorkflowEventModel.EventType` | Notes |
| --- | --- | --- |
| `run.queued` | `runCreated` | New name in workbench UI |
| `run.started` | `runStarted` | Direct mapping |
| `run.completed` | `runCompleted` | Direct mapping |
| `run.failed` | `runFailed` | Direct mapping plus recovery hint |
| `run.cancelled` | `runCancelled` | Direct mapping |
| `step.started` | `stepStarted` | Existing event may need broader emission |
| `step.completed` | `stepCompleted` | Direct mapping |
| `step.failed` | `stepFailed` | Existing event may need broader emission |
| `input.resolved` | new | Required before runtime work begins |
| `step.log` | new | Structured console log |
| `artifact.created` | new | Durable result pointer |

New payload schemas:

```json
{
  "input.resolved": {
    "subjectRefs": ["..."],
    "parameters": {},
    "assets": [
      { "kind": "screenshot", "ref": "file:///...", "source": "selected" }
    ],
    "missing": []
  },
  "step.log": {
    "level": "debug|info|warning|error",
    "source": "runtime|provider|agent|tool",
    "message": "short readable line",
    "detail": "optional technical detail",
    "stepId": "optional-step-id"
  },
  "artifact.created": {
    "artifactId": "uuid-or-route",
    "kind": "text|markdown|file|image|sidecar|url",
    "title": "optional title",
    "url": "optional durable URL",
    "mimeType": "optional MIME type",
    "byteCount": 1234,
    "preview": "optional short preview"
  }
}
```

### Input Contract

Every action declares what it can accept. Do not introduce a parallel contract shape; use the existing `WorkflowInputContract` in `WorkflowDefinition.swift`:

```swift
struct WorkflowInputContract: Codable, Hashable {
    var acceptedRecordTypes: [WorkflowRecordType]
    var requiredAssets: [WorkflowAssetKind]
    var surfaces: [WorkflowInvocationSurface]
    var parameters: [WorkflowParameterSpec]
}
```

`Describe UI` should be represented by the existing capture-image contract shape:

```swift
WorkflowInputContract(
    acceptedRecordTypes: [.capture, .memo, .note],
    requiredAssets: [.screenshot],
    surfaces: [.captureContextMenu, .library, .memoDetail, .manual, .automation],
    parameters: [
        WorkflowParameterSpec(
            key: "screenshots",
            label: "Screenshots",
            valueType: .imageSet,
            required: true,
            templateKey: "SCREENSHOT_CONTEXT",
            help: "Screenshots and capture metadata supplied by the selected memo, note, or capture."
        )
    ]
)
```

Additive fields needed for the workbench:

| Field | Where | Purpose |
| --- | --- | --- |
| `minCount` | `WorkflowParameterSpec` | Minimum required values, e.g. 1 screenshot |
| `maxCount` | `WorkflowParameterSpec` | Maximum accepted values, e.g. 6 screenshots |
| `sources` | `WorkflowParameterSpec` | Valid sources: `selected`, `captureTray`, `memoAttachments`, `sidecar`, `manualUpload` |
| `assetKind` | `WorkflowParameterSpec` | Explicit asset kind for value types like `imageSet` |

This is how `Describe UI` becomes available from a screenshot context menu and why it can fail before runtime with a useful message when no image is present.

### Input Package

The resolved snapshot passed into an action run.

V1 pins the storage model:

- Store durable refs plus metadata, not duplicate primary asset bytes.
- Store `renderLogicVersion` so a rerun can explain which renderer produced the model input.
- Store enough rendered model-input snapshot for audit/debug, with retention limits below.
- Rerun re-resolves refs through the current workflow/skill definition by default.
- If the rendered prompt/messages differ from the original run, show a compact diff before or during rerun.

It should include:

- Object refs: memo ids, capture ids, screenshot asset URLs.
- Text refs: transcript, selected text, user instruction.
- Derived context refs: OCR, VLM description, window metadata, AX tree, sidecar entries.
- Provider/model choices.
- Run-time parameters.
- `renderLogicVersion`.
- Optional rendered request snapshot for "what did the model receive?"

## Retention

Phase 0 decision for V1:

- Keep `ActionRun`, `ActionSubjectRef`, and high-level `ActionEvent` metadata indefinitely unless the user clears action history.
- Keep rendered model-input snapshots and verbose provider/tool payloads for 30 days by default.
- Do not copy source screenshot/audio bytes into the run in Phase 1.
- Artifacts keep their own lifetimes; deleting a source asset preserves the run log but makes rerun fail with a recoverable missing-subject error.

## Target Surface

The target workbench has three calm regions:

| Region | Role |
| --- | --- |
| Action rail | Recent runs, saved actions, starters, filters |
| Session console | Command input, streaming events, results, errors |
| Inspector | Inputs, outputs, artifacts, workflow definition, automation affordances |

This is the direction, not the Phase 1a minimum. Phase 1a ships a single-pane console first; the rail and inspector arrive in Phase 1b.

### Console

The console is a chronological transcript of a run and its follow-up commands.

It should show:

- The user request or invocation source.
- Input resolution summary.
- Step progress and logs.
- Tool/model/provider calls at a readable level.
- Errors inline with recovery hints.
- Final result with copy/share/open affordances.
- Compact `cancel`, `rerun`, and `edit and rerun` affordances.

### Command Input

The bottom input should accept deterministic commands in Phase 1a:

- `rerun`
- `rerun with <model>`
- `cancel`
- `show raw logs`

Free-form natural-language workflow editing and "fix this run" agent loops are Phase 2 unless they fall out cheaply from existing agent routing.

### Action Rail

The Phase 1b rail should show:

- Running now.
- Recent runs.
- Saved actions / skills.
- Starters.

The rail is navigation, not the product. It should stay compact.

### Inspector

The Phase 1b inspector should explain the selected run without making the console dense:

- Input package.
- Step graph.
- Raw logs.
- Artifacts.
- `.skill.md` source / workflow definition.
- Model/provider details.
- Automation trigger options.

## Invocation Surfaces

The same workbench run model should back these entry points:

| Surface | Example |
| --- | --- |
| Screenshot context menu | `Describe UI` |
| Capture detail | `Annotate`, `Describe`, `Send to Mac` |
| Memo detail | `Refine`, `Compose from memo`, `Ask agent` |
| Workflow editor | `Run test`, `Use starter`, `Rerun last input` |
| Home/deck | Natural command or quick action |
| Automation | Scheduled or context-triggered run |

Every entry point should either open the workbench immediately or create a run that is visible there.

## Data Model Sketch

```swift
struct ActionDefinition: Identifiable, Codable {
    var id: String
    var kind: ActionKind
    var name: String
    var icon: String?
    var inputContract: WorkflowInputContract
    var workflow: WorkflowDefinition?
    var skillRoute: String?
}

struct ActionRunModel: Identifiable, Codable {
    var id: UUID
    var actionId: String
    var actionKind: ActionKind
    var title: String
    var inputPackageId: UUID
    var status: ActionRunStatus
    var originDeviceId: String?
    var startedAt: Date?
    var completedAt: Date?
    var summary: String?
    var primaryResultRef: ActionArtifactRef?
    var error: ActionError?
}

struct ActionSubjectRef: Identifiable, Codable {
    var id: UUID
    var actionRunId: UUID
    var kind: ActionSubjectKind
    var recordId: UUID?
    var assetURL: URL?
    var titleSnapshot: String?
    var sha256: String?
}

struct ActionEventModel: Identifiable, Codable {
    var id: UUID
    var runId: UUID
    var sequence: Int
    var kind: ActionEventKind
    var message: String
    var payloadJSON: String?
    var createdAt: Date
}

struct ActionInputPackage: Identifiable, Codable {
    var id: UUID
    var actionRunId: UUID
    var subjectRefs: [ActionSubjectRef]
    var parametersJSON: String
    var derivedContextRefsJSON: String
    var renderLogicVersion: String
    var renderedSnapshotRef: ActionArtifactRef?
}
```

The exact storage can remain GRDB-backed. The important product contract is that the workbench reads one evented action-run stream.

## Runtime Requirements

- Runs must emit events before, during, and after execution.
- Failed runs must be persisted with enough detail to inspect and retry.
- Input validation failures should be persisted as failed runs, not disappear as transient alerts.
- Cancellation produces a `cancelled` run with partial event stream intact.
- Concurrent runs are allowed; each has an independent event stream.
- Provider/model errors should be normalized into user-readable errors plus technical detail.
- Artifacts should be durable refs, not copied blindly into text fields.
- Rerun reuses and re-resolves the prior input package by default, with a visible diff if the workflow changed.

## Workflow Authoring Requirements

- Starters can load into the editor without leaving the workbench.
- A workflow can be edited while a previous run remains visible.
- "Save as skill" should promote a tested action into the saved action rail.
- Input contracts should be editable in structured form, with open fields and preset suggestions.
- Model slots should be open fields with suggested providers/models, not closed enums.
- A workflow should be able to declare record-type associations like `screenshot`, `memo`, `capture`, `audio`, or `selected-text`.

## Agent Responsibilities

The agent layer should help with:

- Creating a workflow from a user request.
- Explaining a failed run.
- Suggesting input-contract fixes.
- Editing prompts and step configs.
- Choosing a model/provider when the action declares a target capability such as VLM.
- Proposing automations from repeated behavior.

The agent should not be required for deterministic affordances such as rerun, open artifact, delete run, cancel run, or view raw logs.

## Acceptance Criteria

### Phase 1a

- A user can right-click a screenshot, choose `Describe UI`, and immediately see a single-pane workbench console run.
- The run shows input resolution, model call, result, and any error without requiring Console.app or log viewer.
- A failed VLM run appears as a failed run with the screenshot input package visible.
- `Describe UI` declares a screenshot input contract using `WorkflowInputContract`, and the UI only offers it when the contract can be satisfied or can explain what is missing.
- The user can cancel a running action; the run becomes `cancelled` and keeps the partial log.
- The user can start run B while run A is streaming; both are persisted independently even before the rail UI ships.
- If the source screenshot is deleted before rerun, rerun fails visibly with a recoverable missing-subject error.
- Rerun re-resolves the prior input refs through the current workflow definition and shows a compact diff when rendered model input changed.
- Deterministic console commands support at least `rerun`, `rerun with <model>`, `cancel`, and `show raw logs`.

### Phase 1b

- Recent runs, saved actions, and starters are reachable from the workbench rail.
- The inspector shows input package, artifacts, model/provider details, raw logs, and `.skill.md` source without crowding the console.
- The user can open the workflow home from a focused workflow/run view without losing context.

### Phase 2

- The user can revise the workflow prompt and rerun against the same screenshot from the workbench.
- The user can ask the agent to explain or fix a failed run.
- A tested action can be saved or pinned as a skill.
- Activity and AI Results are deprecated as primary destinations; old routes open the relevant `ActionRun` in the workbench.

## Phasing

### Phase 0 - Spec and design

- Land this spec.
- Produce a tighter visual direction from the CLI-like sketch.
- Create GRDB backing for `ActionRunModel`, `ActionSubjectRef`, `ActionEventModel`, and `ActionInputPackage`.
- Finalize additive `WorkflowInputContract` fields.
- Confirm retention defaults.
- Confirm `Actions` as the nav name.

### Phase 1a - Plumbing and single-pane console

- Add `ActionRun` / `ActionEvent` backing.
- Route new workflow-backed runs through canonical `ActionRunModel`.
- Route screenshot `Describe UI` through the workbench.
- Persist failed input/model runs.
- Build single-pane console with streaming events, result rendering, error rendering, rerun, cancel, and raw-log affordances.

### Phase 1b - Workbench layout

- Add rail for running/recent/saved/starters.
- Add inspector for input package, artifacts, raw logs, and `.skill.md` source.
- Add multi-run navigation and selection.

### Phase 2 - Authoring loop

- Add inline workflow editing.
- Add rerun with same input package and render diff.
- Add input-contract editor.
- Add "save as skill" or "pin action".
- Add agent help for "explain this failure" and "fix this run".

### Phase 3 - Automation loop

- Add trigger suggestions.
- Add scheduled/contextual automations.
- Show automation runs in the same workbench stream.

### Phase 4 - Multi-device action stream

- Sync action visibility across paired iOS/macOS surfaces where appropriate.
- Let iOS invoke a Mac-backed action and inspect the run state.
- Use `originDeviceId` and explicit execution routing so iOS-triggered, Mac-executed runs remain understandable.

## Implementation Notes

- Current `WorkflowRunModel` and `WorkflowEventModel` contain useful event-sourcing pieces, but they are not product constraints.
- Prefer direct `ActionRunModel` writes for new runs. Use adapters or one-time import only when that is faster than duplicating runtime code.
- Existing `.skill.md` files remain source of truth for workflow/skill logic. Legacy starter JSON remains compatibility input only.
- Current "AI Results" windows should become thin openers for the selected `ActionRun`.
- The Activity table should not receive new product investment; deprecate it as soon as the workbench handles recent-run navigation.

## Open Questions

- Do we need a visible "archive action history" control in V1, or is clear-history enough?
- Which automation triggers are needed first: scheduled, object-created, app/window context, or voice command?
- Should rendered model snapshots be encrypted at rest separately from existing local storage?
