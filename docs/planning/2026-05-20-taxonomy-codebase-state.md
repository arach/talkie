# Talkie taxonomy codebase-state survey

_Date:_ 2026-05-20  
_Mode:_ research brief only. This document describes current code and data shape; it intentionally does **not** recommend a taxonomy.

## Scope and sources

Read against the planning prompt in `docs/planning/2026-05-20-workflows-skills-actions-taxonomy.md`, then surveyed:

- macOS workflow model/runtime under `apps/macos/Talkie/Workflow/`.
- App-bundled workflow JSON under `apps/macos/Talkie/Resources/SystemWorkflows/` and `apps/macos/Talkie/Resources/WorkflowTemplates/`.
- WFKit package/sample resources under `packages/swift/WFKit/`.
- iOS workflow-facing surfaces under `apps/ios/Talkie iOS/`.
- User-facing/internal uses of `Action` / `action` across macOS, TalkieAgent, and iOS Swift targets.

Notes on inventory boundaries:

- There are no standalone JSON workflow files inside `apps/macos/Talkie/Workflow/`; Swift seeds live in `WorkflowDefinition.swift`.
- The app loader treats `SystemWorkflows` and `WorkflowTemplates` differently: system workflows are synced into app support, while templates are loaded from the bundle on demand (`apps/macos/Talkie/Workflow/WorkflowFileRepository.swift:135-188`, `apps/macos/Talkie/Workflow/WorkflowFileRepository.swift:192-239`).
- The flat JSON loader generates UUIDs and forces `autoRun: false` for flat starter/template JSON (`apps/macos/Talkie/Workflow/SimpleWorkflowLoader.swift:176-204`).
- `apps/macos/TalkieKit/Sources/TalkieKit/Resources/Context/workflows/summarize-selection/workflow.json` is not a `WorkflowDefinition`: it has `id`, `mode`, `systemPromptFile`, `defaultProfile`, and `timeoutMs`, but no `steps` or `autoRun` (`apps/macos/TalkieKit/Sources/TalkieKit/Resources/Context/workflows/summarize-selection/workflow.json:1-7`).

## 1. Shape of existing workflows

### Bucket counts

Primary-bucket counts are mutually exclusive within each source set; `auto-run automation` takes precedence for Swift/static seeds that also have a linear shape.

| Source set | Single-trigger/simple linear | Multi-step linear/router | Branching/conditional | Auto-run automation | Total surveyed |
| --- | ---: | ---: | ---: | ---: | ---: |
| App-bundled flat JSON (`SystemWorkflows` + `WorkflowTemplates`) | 6 | 3 | 4 | 0 | 13 |
| Swift static seeds in `WorkflowDefinition.swift` | 4 | 0 | 1 | 2 | 7 |
| WFKit sample JSON/TWF resources | 3 | 2 | 5 | 1 | 11 |

### App-bundled flat JSON resources

These are the files loaded by `WorkflowFileRepository` / `SimpleWorkflowLoader`. None contains an `autoRun` key, and the flat loader converts all of them to `autoRun: false` (`apps/macos/Talkie/Workflow/SimpleWorkflowLoader.swift:192-204`).

| File | Steps | Step types | Conditional? | autoRun? | Bucket |
| --- | ---: | --- | --- | --- | --- |
| `apps/macos/Talkie/Resources/SystemWorkflows/hey-talkie.json:2` | 3 | `trigger`, `intentExtract`, `executeWorkflows` (`:9`, `:18`, `:24`) | No | Not declared | Multi-step linear/router |
| `apps/macos/Talkie/Resources/SystemWorkflows/transcribe.json:2` | 1 | `transcribe` (`:9`) | No | Not declared | Single-trigger/simple linear |
| `apps/macos/Talkie/Resources/WorkflowTemplates/brain-dump-processor.json:2` | 10 | `transcribe`, `llm`, `transform`, `conditional`, `appleReminders`, `shell`, `llm`, `llm`, `saveFile`, `iOSPush` (`:9`, `:17`, `:28`, `:37`, `:44`, `:53`, `:62`, `:72`, `:83`, `:91`) | Yes (`:39-41`) | Not declared | Branching/conditional |
| `apps/macos/Talkie/Resources/WorkflowTemplates/cloud-transcribe.json:2` | 6 | `shell`, `transform`, `conditional`, `llm`, `notification`, `notification` (`:9`, `:25`, `:34`, `:41`, `:49`, `:56`) | Yes (`:36-38`) | Not declared | Branching/conditional |
| `apps/macos/Talkie/Resources/WorkflowTemplates/extract-action-items.json:2` | 1 | `llm` (`:9`) | No | Not declared | Single-trigger/simple linear |
| `apps/macos/Talkie/Resources/WorkflowTemplates/feature-ideation.json:2` | 7 | `llm`, `transform`, `llm`, `saveFile`, `conditional`, `appleReminders`, `notification` (`:9`, `:18`, `:26`, `:34`, `:42`, `:49`, `:58`) | Yes (`:44-46`) | Not declared | Branching/conditional |
| `apps/macos/Talkie/Resources/WorkflowTemplates/hq-transcribe.json:2` | 3 | `transcribe`, `llm`, `notification` (`:9`, `:17`, `:25`) | No | Not declared | Multi-step linear |
| `apps/macos/Talkie/Resources/WorkflowTemplates/key-insights.json:2` | 1 | `llm` (`:9`) | No | Not declared | Single-trigger/simple linear |
| `apps/macos/Talkie/Resources/WorkflowTemplates/last-word.json:2` | 2 | `shell`, `speak` (`:9`, `:21`) | No | Not declared | Single-trigger/simple linear |
| `apps/macos/Talkie/Resources/WorkflowTemplates/learning-capture.json:2` | 8 | `llm`, `transform`, `llm`, `llm`, `saveFile`, `conditional`, `appleReminders`, `notification` (`:9`, `:18`, `:26`, `:34`, `:42`, `:50`, `:57`, `:66`) | Yes (`:52-54`) | Not declared | Branching/conditional |
| `apps/macos/Talkie/Resources/WorkflowTemplates/quick-summary.json:2` | 1 | `llm` (`:9`) | No | Not declared | Single-trigger/simple linear |
| `apps/macos/Talkie/Resources/WorkflowTemplates/speak-summary.json:2` | 2 | `llm`, `speak` (`:9`, `:18`) | No | Not declared | Single-trigger/simple linear |
| `apps/macos/Talkie/Resources/WorkflowTemplates/tweet-summary.json:2` | 4 | `llm`, `llm`, `clipboard`, `iOSPush` (`:9`, `:17`, `:25`, `:30`) | No | Not declared | Multi-step linear |

### Swift static workflow seeds

`WorkflowDefinition` stores core workflow fields including steps, pinning, and auto-run flags (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:25-38`). The static seeds are:

| Seed | Steps | Step types | Conditional? | autoRun? | Bucket |
| --- | ---: | --- | --- | --- | --- |
| `WorkflowDefinition.summarize` | 1 | `.llm` | No | Default false | Single-trigger/simple linear (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:126-150`) |
| `WorkflowDefinition.extractTasks` | 1 | `.llm` | No | Default false | Single-trigger/simple linear (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:152-178`) |
| `WorkflowDefinition.keyInsights` | 1 | `.llm` | No | Default false | Single-trigger/simple linear (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:180-206`) |
| `WorkflowDefinition.heyTalkie` | 3 | `.trigger`, `.intentExtract`, `.executeWorkflows` | No branch step; trigger gates execution | `true`, order 1 | Auto-run automation (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:214-258`) |
| `WorkflowDefinition.systemTranscribe` | 1 | `.transcribe` | No | `true`, order 0 | Auto-run automation (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:267-289`) |
| `WorkflowDefinition.brainDumpProcessor` | 10 | `.transcribe`, `.llm`, `.transform`, `.conditional`, `.appleReminders`, `.shell`, `.llm`, `.llm`, `.saveFile`, `.iOSPush` | Yes (`thenSteps`) | `false` | Branching/conditional (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:295-481`) |
| `WorkflowDefinition.speakSummary` | 2 | `.llm`, `.speak` | No | `false`; `isPinned: true` | Single-trigger/simple linear (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:486-528`) |

The default initial set is `[summarize, extractTasks, keyInsights, brainDumpProcessor, speakSummary]`; it excludes the two fixed-ID system auto-run seeds (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:530-531`).

### WFKit sample workflow resources

WFKit contains sample workflow JSON/TWF resources under `packages/swift/WFKit/Sources/WFKit/Resources/SampleWorkflows/`. These mirror several app templates but are not the macOS app loader path described above.

Inventory:

- Single-trigger/simple linear: `extract-action-items.twf.json`, `key-insights.twf.json`, `quick-summary.twf.json`.
- Multi-step linear/router: `hq-transcribe.twf.json`, `tweet-summary.twf.json`.
- Branching/conditional: `brain-dump-processor.json`, `brain-dump-processor.twf.json`, `cloud-transcribe.twf.json`, `feature-ideation.twf.json`, `learning-capture.twf.json`.
- Auto-run automation: `hey-talkie.twf.json` declares `autoRun: true`.

WFKit also embeds a `TWF_SPEC.md` stating that `.twf.json` has root `autoRun` and ordered `steps` fields (`packages/swift/WFKit/Sources/WFKit/Resources/SampleWorkflows/TWF_SPEC.md:1-7`, `packages/swift/WFKit/Sources/WFKit/Resources/SampleWorkflows/TWF_SPEC.md:12-23`).

## 2. Engine features that are load-bearing

### Data model breadth

Current `WorkflowStep` stores an ID, type, config union, `outputKey`, enabled flag, and optional step condition (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:536-542`). The Swift `StepType` enum has 19 raw step types (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:560-580`), grouped into categories and display names (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:630-670`). `StepConfig` has matching associated config cases plus defaults for each type (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:716-780`).

A constrained shape that only captures “prompt + output” would not represent most of the current step catalog: transcription, shell, webhook, email, notifications, iOS push, Apple apps, clipboard, save file, conditionals, transforms, speech, trigger detection, intent extraction, workflow execution, and cloud upload.

### Definition vs. preferences/configuration split

Workflow JSON is not the whole state. `WorkflowService` builds a registered `Workflow` by combining a file-backed `WorkflowDefinition` with preferences/configuration such as source, path, sort order, enabled, pinned, and auto-run state (`apps/macos/Talkie/Workflow/WorkflowService.swift:18-40`, `apps/macos/Talkie/Workflow/WorkflowService.swift:105-139`). It exposes setters for enabled, pinned, and auto-run flags (`apps/macos/Talkie/Workflow/WorkflowService.swift:277-312`) and syncs pinned workflow mirrors to iCloud for iOS (`apps/macos/Talkie/Workflow/WorkflowService.swift:326-344`).

A narrower shape would need somewhere else to carry per-user enablement, pinning, auto-run order, sort order, action contexts, and file source.

### Inter-step data flow and variable substitution

The runtime context has `transcript`, `title`, `date`, an `outputs` dictionary, and `outputOrder` (`apps/macos/Talkie/Workflow/WorkflowExecutor.swift:21-31`). Template resolution substitutes built-ins and exact output-key placeholders like `{{summary}}`, `{{PREVIOUS_OUTPUT}}`, and `{{OUTPUT}}` (`apps/macos/Talkie/Workflow/WorkflowExecutor.swift:47-69`). The TypeScript sidecar has the same output/order shape and exact-key resolution (`apps/macos/TalkieServer/packages/workflow-core/src/context.ts:34-82`).

Existing seeds use multi-step output keys heavily: the brain-dump seed writes `transcript`, `extracted`, `parsed`, `formattedIdeas`, `polished`, `research`, `savedFile`, and `notified` (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:301-477`). The LLM executor resolves prompts/system prompts just before generation (`apps/macos/Talkie/Workflow/WorkflowExecutor.swift:893-935`).

Current caveat from code: template resolution only replaces exact keys. Several seeds include dotted/indexed placeholders such as `{{parsed.nextActions[0]}}`, `{{parsed.connections}}`, and `{{parsed.ideas.length}}` (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:367-371`, `apps/macos/Talkie/Workflow/WorkflowDefinition.swift:396-406`, `apps/macos/Talkie/Workflow/WorkflowDefinition.swift:465-475`), but neither the Swift nor TypeScript resolver implements JSON-path lookup (`apps/macos/Talkie/Workflow/WorkflowExecutor.swift:54-57`, `apps/macos/TalkieServer/packages/workflow-core/src/context.ts:70-72`).

### Sidecar/host execution boundary

The macOS executor now sends complete workflow execution to TalkieServer via `/workflows/run` (`apps/macos/Talkie/Workflow/WorkflowExecutor.swift:375-385`, `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:443-505`). The TypeScript workflow core declares the same 19 step types (`apps/macos/TalkieServer/packages/workflow-core/src/types.ts:1-21`) but only runs `transform` and `conditional` as portable steps (`apps/macos/TalkieServer/packages/workflow-core/src/runtime.ts:16`, `apps/macos/TalkieServer/packages/workflow-core/src/runtime.ts:240-253`). Other steps call back into the Swift host (`apps/macos/TalkieServer/packages/workflow-core/src/runtime.ts:476-479`; `apps/macos/TalkieServer/src/workflows/index.ts:168-187`). The Swift host decodes the step config and invokes `WorkflowExecutor.shared.executeHostedStep` (`apps/macos/Talkie/Services/TalkieServer.swift:1329-1407`, `apps/macos/Talkie/Services/TalkieServer.swift:1409-1454`).

This makes host-native capabilities load-bearing: local memo/audio access, provider registry, Apple integrations, clipboard/filesystem, TTS, and notification pathways live outside the portable core.

### Conditionals, step conditions, and trigger gating

There are two condition mechanisms in the code:

- `ConditionalStepConfig` stores a condition plus `thenSteps` and `elseSteps` UUID lists (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:1802-1811`).
- `StepCondition` stores an expression and `skipOnFail` on any step (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:2287-2297`).

Condition evaluation supports simple string predicates such as `contains`, `equals`, `startsWith`, `endsWith`, `isEmpty`, and `isNotEmpty` (`apps/macos/Talkie/Workflow/WorkflowExecutor.swift:1922-1969`; `apps/macos/TalkieServer/packages/workflow-core/src/runtime.ts:202-238`). The sidecar executor honors per-step `condition` by skipping the step when false (`apps/macos/TalkieServer/packages/workflow-core/src/runtime.ts:421-433`).

Current caveat from code: `conditional` steps evaluate to the string output `"true"` or `"false"` in both Swift and TypeScript (`apps/macos/Talkie/Workflow/WorkflowExecutor.swift:867-869`; `apps/macos/TalkieServer/packages/workflow-core/src/runtime.ts:240-245`). The current execution loop remains linear (`apps/macos/TalkieServer/packages/workflow-core/src/runtime.ts:403-540`); it does not route through `thenSteps` / `elseSteps`. The flat JSON loader also converts conditional index references only against UUIDs generated so far, which drops forward references in templates that point to later steps (`apps/macos/Talkie/Workflow/SimpleWorkflowLoader.swift:176-185`, `apps/macos/Talkie/Workflow/SimpleWorkflowLoader.swift:325-342`).

Trigger gating is separate and active: trigger steps can throw `TriggerNotMatchedError` when `stopIfNoMatch` is set (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:2110-2129`; `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:1973-2035`). The Swift host converts that to a sidecar `halted` result (`apps/macos/Talkie/Services/TalkieServer.swift:1392-1400`), and the TypeScript loop breaks on halted host results (`apps/macos/TalkieServer/packages/workflow-core/src/runtime.ts:481-495`).

### Multi-step LLM chaining and intent routing

LLM steps resolve provider/model using explicit config or global cost tier, then resolve prompt/system prompt from runtime context (`apps/macos/Talkie/Workflow/WorkflowExecutor.swift:893-935`). Intent extraction can read a previous output, use keywords/LLM/hybrid extraction, filter by confidence, and emit JSON (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:2147-2181`; `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:2061-2105`). `executeWorkflows` reads that JSON, matches workflow ID/name, and recursively executes target workflows (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:2270-2284`; `apps/macos/Talkie/Workflow/WorkflowExecutor.swift:2252-2324`).

The `Hey Talkie` auto-run seed is specifically a trigger → intent extraction → execute workflows router (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:220-252`).

### Auto-run and scheduled automation

Auto-run is part of the workflow definition and preference layer (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:33-35`; `apps/macos/Talkie/Workflow/WorkflowService.swift:158-163`). `AutoRunProcessor` runs enabled auto-run workflows when a memo syncs, splits transcription-first workflows from post-transcription workflows, and lets trigger steps gate post-transcription automation (`apps/macos/Talkie/Workflow/AutoRunProcessor.swift:35-90`, `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:95-157`, `apps/macos/Talkie/Workflow/AutoRunProcessor.swift:176-212`).

There is also an `Automation` model for event-triggered and scheduled workflow execution (`apps/macos/Talkie/Workflow/Automation.swift:1-23`). Event triggers include memo sync, local memo creation, and dictation end (`apps/macos/Talkie/Workflow/Automation.swift:77-82`), and scheduled intervals include hourly/daily/weekly (`apps/macos/Talkie/Workflow/Automation.swift:151-160`). The scheduler manages timers (`apps/macos/Talkie/Workflow/AutomationScheduler.swift:17-45`, `apps/macos/Talkie/Workflow/AutomationScheduler.swift:121-160`) and calls `AutomationService.runAutomation` (`apps/macos/Talkie/Workflow/AutomationScheduler.swift:217-231`). Current scheduled runs without a memo context log completion but do not execute a workflow against actual input yet (`apps/macos/Talkie/Workflow/AutomationService.swift:182-192`).

## 3. `Action` / `action` overload in code

Generic SwiftUI `Button(action:)` occurrences are widespread and not product taxonomy; the table below focuses on domain/product senses.

| Sense | User-facing or internal? | Current code evidence | Collision risk if `Action` is top-level user-facing concept? |
| --- | --- | --- | --- |
| Legacy memo workflow action | Legacy/internal, but names are user-facing concepts | `WorkflowActionType` has cases like `Summarize`, `Extract Tasks`, `Key Insights`, `Remind`, `Share` (`apps/macos/Talkie/Workflow/WorkflowAction.swift:10-17`); legacy executor still has `execute(action: WorkflowActionType, ...)` (`apps/macos/Talkie/Workflow/WorkflowExecutor.swift:205-272`). | Yes: `Action` already means an older one-shot memo operation. |
| Context-aware Actions | User-facing settings/editor | `WorkflowService` calls them “Actions (Context-Aware Quick Actions)” and fetches workflows for interstitial/drafts (`apps/macos/Talkie/Workflow/WorkflowService.swift:170-241`). Preferences store `showInInterstitial`, `showInDrafts`, and app bundle scopes under “Action Context Fields” (`apps/macos/Talkie/Workflow/WorkflowPreferences.swift:27-73`, `apps/macos/Talkie/Workflow/WorkflowPreferences.swift:238-292`). Migration copy says actions are single-step workflows shown in specific UI contexts (`apps/macos/Talkie/Data/Database/DatabaseManager.swift:664-694`). | Yes: this is already a first-class UI/settings label. |
| Action editor | User-facing | `ActionEditorSheet` is explicitly “creating/editing actions (single-step LLM workflows)” (`apps/macos/Talkie/Views/Settings/ActionEditorSheet.swift:1-6`), labels the header “New Action” / “Edit Action” (`apps/macos/Talkie/Views/Settings/ActionEditorSheet.swift:117-123`), and saves a one-step `.llm` workflow described as “Custom action” (`apps/macos/Talkie/Views/Settings/ActionEditorSheet.swift:458-499`). | Yes: users can already create “Actions.” |
| Context settings explanation | User-facing | Settings copy says “Actions are workflows packaged as buttons” and consumer copy says “Buttons are one-tap workflows” (`apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3769-3782`); empty state says “Create a workflow to use it as an action” (`apps/macos/Talkie/Views/Settings/ContextSettingsView.swift:3863-3876`). | Yes: label collision is present in copy. |
| Quick Actions / pinned workflows | User-facing | Quick Actions settings title and copy say pinned workflows show as quick actions and sync to iOS (`apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:17-23`, `apps/macos/Talkie/Views/Settings/QuickActionsSettings.swift:123-130`). | Yes: `Quick Actions` is already a workflow-surfacing mechanism. |
| SmartAction chips | User-facing | `SmartAction` defines built-in text transforms and converts workflows into smart actions from first LLM step (`apps/macos/Talkie/VoiceEditor/SmartAction.swift:10-23`, `apps/macos/Talkie/VoiceEditor/SmartAction.swift:101-138`). Draft/compose surfaces show “SMART ACTIONS” and run the prompt (`apps/macos/Talkie/Views/Drafts/ScopeDraftsScreen.swift:136-138`, `apps/macos/Talkie/Views/Drafts/ScopeDraftsScreen.swift:884-893`, `apps/macos/Talkie/Views/Drafts/ScopeDraftsScreen.swift:925-936`; `apps/macos/Talkie/Views/TalkieObject/Sections/NoteComposeCard.swift:40-42`, `apps/macos/Talkie/Views/TalkieObject/Sections/NoteComposeCard.swift:415-434`). | Yes: `SmartAction` is a separate text-revision chip concept. |
| Pending/recent actions | User-facing runtime state | `PendingActionsManager` tracks running workflow executions and recent actions (`apps/macos/Talkie/Services/PendingActionsManager.swift:1-8`, `apps/macos/Talkie/Services/PendingActionsManager.swift:18-91`, `apps/macos/Talkie/Services/PendingActionsManager.swift:120-229`). `PendingActionsScreen` labels the screen “Pending”, sections running/failed/recent, and empty copy says “No actions yet” (`apps/macos/Talkie/Views/PendingActionsScreen.swift:1-7`, `apps/macos/Talkie/Views/PendingActionsScreen.swift:22-101`). | Yes: `action` means an in-flight or historical execution record. |
| Activity Log / AI Results action row instrumentation | Mixed user-facing/internal | Activity log is workflow-run history (`apps/macos/Talkie/Views/Activity/ActivityLogViews.swift:48-76`), emits an `ActionRowClick` signpost under `AIResults` (`apps/macos/Talkie/Views/Activity/ActivityLogViews.swift:220-225`), and exposes retry/delete run controls (`apps/macos/Talkie/Views/Activity/ActivityLogViews.swift:485-522`; `apps/macos/Talkie/Views/AIResults/AIResultsViews.swift:50-64`, `apps/macos/Talkie/Views/AIResults/AIResultsViews.swift:405-410`). | Moderate: action language appears around run rows, not authoring primitives. |
| Intent extraction `action` field | Internal runtime/output schema | `ExtractedIntent` has `action: String`, and the default prompt emits `ACTION: ...` lines (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:2183-2196`, `apps/macos/Talkie/Workflow/WorkflowDefinition.swift:2255-2267`). | Moderate: internal schema uses action as requested intent. |
| TalkieAgent QuickActionKind | User-facing adjacent app | TalkieAgent defines `QuickActionKind` with execute-only, promote-to-memo, promote-to-command, and meta actions (`apps/macos/TalkieAgent/TalkieAgent/Database/LiveDictation.swift:64-92`), and `QuickActionRunner` executes/chooses those actions (`apps/macos/TalkieAgent/TalkieAgent/Services/QuickActionRunner.swift:1-70`, `apps/macos/TalkieAgent/TalkieAgent/Services/QuickActionRunner.swift:213-250`). | Yes across the broader product suite. |
| iOS ComposeWorkflowAction | User-facing but not macOS workflow engine | iOS Compose defines prompt-chip `ComposeWorkflowAction` (`apps/ios/Talkie iOS/Views/ComposeView.swift:158-163`), has built-in actions such as Clean Up, Shorten, Tasks, Notes, Decision, Workflow (`apps/ios/Talkie iOS/Views/ComposeView.swift:880-959`), and applies them by submitting the prompt (`apps/ios/Talkie iOS/Views/ComposeView.swift:1124-1126`, `apps/ios/Talkie iOS/Views/ComposeView.swift:4490-4503`). | Yes on iOS: action already means local prompt chip. |
| iOS Mac Actions | User-facing remote workflow launcher | iOS detail view has a “Mac Actions” section with two pinned workflow slots plus Agent/CLI (`apps/ios/Talkie iOS/Views/VoiceMemoDetailView.swift:2157-2247`). | Yes: `Mac Actions` is already the iOS label for pinned remote workflows. |
| CloudSyncActionModel | Internal audit/sync | Sync audit records store `action: "create" | "update" | "skip"` (`apps/macos/Talkie/Data/Models/CloudSyncActionModel.swift:12-20`, `apps/macos/Talkie/Data/Models/CloudSyncActionModel.swift:64-83`). | Low user-facing risk, but another schema use. |
| WFKit `NodeType.action` | Public/editor model | WFKit public node types include `.action = "Action"` with default title “Action” (`packages/swift/WFKit/Sources/WFKit/Models/WorkflowNode.swift:30-76`). Talkie maps shell/webhook steps to WFKit `.action` nodes (`apps/macos/Talkie/Workflow/TalkieWorkflowConverter.swift:17-34`). | Yes for editor/visualization vocabulary. |

Code-state answer to the collision question: yes, `Action` is already overloaded across multiple user-facing surfaces: context buttons, action editor/settings, smart action chips, quick/pinned actions, pending/recent runtime state, iOS Mac Actions, and iOS compose prompt chips. It is also used internally for legacy action execution, intent extraction, sync audit records, and WFKit node categories.

## 4. iOS surface

The iOS app does **not** contain the macOS `WorkflowDefinition` / `WorkflowStep` / `StepType` model. The workflow-facing shared shape on iOS is a small pinned mirror:

- `TalkieAppConfiguration.PinnedWorkflow` has only `id`, `name`, and `icon` (`apps/ios/Talkie iOS/Services/TalkieAppConfiguration.swift:11-16`).
- `TalkieAppConfiguration.Workflows` stores `pinnedMacActions: [PinnedWorkflow]` (`apps/ios/Talkie iOS/Services/TalkieAppConfiguration.swift:52-54`).
- `TalkieAppConfigurationStore` synchronizes that mirror from `NSUbiquitousKeyValueStore` (`apps/ios/Talkie iOS/Services/TalkieAppConfigurationStore.swift:59-74`, `apps/ios/Talkie iOS/Services/TalkieAppConfigurationStore.swift:198-200`, `apps/ios/Talkie iOS/Services/TalkieAppConfigurationStore.swift:242-250`).
- `TalkieAppSettings` exposes it as `pinnedMacWorkflows` and refreshes from the store (`apps/ios/Talkie iOS/Services/TalkieAppSettings.swift:34`, `apps/ios/Talkie iOS/Services/TalkieAppSettings.swift:88-125`).

The primary workflow UI on iOS is the memo detail `Mac Actions` section. It renders up to two pinned workflows as remote quick-action buttons, plus Agent and CLI slots (`apps/ios/Talkie iOS/Views/VoiceMemoDetailView.swift:2157-2247`). Running a pinned workflow creates a live workflow run using `workflowId`, `workflowName`, `workflowIcon`, and `memoId` via `/api/workflow-runs` (`apps/ios/Talkie iOS/Views/VoiceMemoDetailView.swift:2292-2336`, `apps/ios/Talkie iOS/Views/VoiceMemoDetailView.swift:4674-4721`).

Separate from Mac workflows, iOS Compose has local prompt-chip “workflow actions” (`ComposeWorkflowAction`) that submit instructions to the compose/revision flow; they are not backed by the macOS workflow engine (`apps/ios/Talkie iOS/Views/ComposeView.swift:158-163`, `apps/ios/Talkie iOS/Views/ComposeView.swift:880-959`, `apps/ios/Talkie iOS/Views/ComposeView.swift:1124-1126`).

Observed iOS-side impact surface:

- Copy/labels: “Mac Actions”, fallback “Action”, fallback “Workflow”, and Compose “workflow action” chip language (`apps/ios/Talkie iOS/Views/VoiceMemoDetailView.swift:2160-2213`, `apps/ios/Talkie iOS/Views/VoiceMemoDetailView.swift:2292-2294`).
- Data/wire shape: pinned mirror key `pinnedMacActions` and live-run request fields. A macOS-only display taxonomy change does not touch a full workflow model on iOS, because iOS does not have that model. A rename of the persisted config key or API fields would touch iOS configuration/read paths.

## 5. WFKit boundary

### Location and package boundary

WFKit lives at `packages/swift/WFKit`. It is a local Swift package with a library product named `WFKit` and a demo executable named `Workflow` (`packages/swift/WFKit/Package.swift:4-14`, `packages/swift/WFKit/Package.swift:19-31`). The Talkie macOS Xcode project references it via `../../../packages/swift/WFKit` and depends on the `WFKit` product (`apps/macos/Talkie/Talkie.xcodeproj/project.pbxproj:2919-2923`, `apps/macos/Talkie/Talkie.xcodeproj/project.pbxproj:2985-2988`).

### Public API shape

The visible public API is an editor/canvas package, not the workflow executor:

- `WFWorkflowEditor` is a public SwiftUI view initialized with `CanvasState`, optional `WFSchemaProvider`, read-only flag, inspector style, and inspector binding (`packages/swift/WFKit/Sources/WFKit/WFWorkflowEditor.swift:30-77`).
- `CanvasState` exposes public `nodes`, `connections`, raw input capture, metadata, selection, and canvas transform state (`packages/swift/WFKit/Sources/WFKit/Models/CanvasState.swift:122-147`, `packages/swift/WFKit/Sources/WFKit/Models/CanvasState.swift:286-348`).
- `WorkflowNode` / `WorkflowConnection` are public Codable graph models (`packages/swift/WFKit/Sources/WFKit/Models/WorkflowNode.swift:102-176`; `packages/swift/WFKit/Sources/WFKit/Models/WorkflowConnection.swift:53-82`).
- `NodeConfiguration` is a public Codable bag with LLM, transform, condition, action, notification, and `customFields` slots (`packages/swift/WFKit/Sources/WFKit/Models/WorkflowNode.swift:198-259`).
- Schema is supplied by host apps via public `WFSchemaProvider`, `WFNodeTypeSchema`, `WFFieldSchema`, and field-type models (`packages/swift/WFKit/Sources/WFKit/Models/WFSchema.swift:5-13`, `packages/swift/WFKit/Sources/WFKit/Models/WFSchema.swift:23-49`, `packages/swift/WFKit/Sources/WFKit/Models/WFSchema.swift:51-100`).

WFKit's public `NodeType` enum has seven visual/editor categories: `Trigger`, `LLM`, `Transform`, `Condition`, `Action`, `Notification`, and `Output` (`packages/swift/WFKit/Sources/WFKit/Models/WorkflowNode.swift:30-76`). The README also describes WFKit as a native workflow editor and lists “Action” as a node type (`packages/swift/WFKit/README.md:1-17`, `packages/swift/WFKit/README.md:126-135`).

### Talkie integration boundary

Talkie converts `WorkflowDefinition` into WFKit `CanvasState` for visualization (`apps/macos/Talkie/Workflow/TalkieWorkflowConverter.swift:59-127`). The converter maps Talkie's 19 step types into WFKit's coarse node categories: trigger/intent/execute workflows → `.trigger`; llm/transcribe → `.llm`; conditional → `.condition`; shell/webhook → `.action`; notification/iOSPush/email/speak → `.notification`; Apple apps/clipboard/save/cloud upload → `.output` (`apps/macos/Talkie/Workflow/TalkieWorkflowConverter.swift:17-34`). It also stores raw encoded workflow JSON and metadata in the canvas state for capture/debugging (`apps/macos/Talkie/Workflow/TalkieWorkflowConverter.swift:110-124`) and flattens step config into `NodeConfiguration.customFields` (`apps/macos/Talkie/Workflow/TalkieWorkflowConverter.swift:138-188`).

The macOS visualizer uses WFKit read-only with `TalkieWorkflowSchema.shared` (`apps/macos/Talkie/Workflow/WorkflowViews.swift:532-593`). `TalkieWorkflowSchema` is Talkie's schema provider for WFKit (`apps/macos/Talkie/Workflow/TalkieWorkflowSchema.swift:15-24`); it builds nodes for LLM, transcribe, notification, iOS push, email, reminders, shell, webhook, clipboard, save file, conditional, transform, trigger, intent extract, and execute workflows (`apps/macos/Talkie/Workflow/TalkieWorkflowSchema.swift:41-71`). Its conditional schema exposes `condition`, `thenSteps`, and `elseSteps` fields (`apps/macos/Talkie/Workflow/TalkieWorkflowSchema.swift:686-724`).

Boundary answer:

- WFKit exposes a public graph/editor data model (`CanvasState`, `WorkflowNode`, `WorkflowConnection`, `NodeType`, `NodeConfiguration`) and a public schema API, so persisted or external WFKit canvas consumers would see labels/raw values such as `Action`, `Condition`, and `Output`.
- Talkie's execution/data source remains `WorkflowDefinition` / TWF plus the sidecar runtime, not WFKit. WFKit is currently a visualization/editor boundary for Talkie workflows, with raw Talkie workflow JSON stored inside `CanvasState.rawInput` for capture/debugging.
- WFKit sample docs use `.twf.json`, `autoRun`, and display-name step types (`packages/swift/WFKit/Sources/WFKit/Resources/SampleWorkflows/TWF_SPEC.md:1-7`, `packages/swift/WFKit/Sources/WFKit/Resources/SampleWorkflows/TWF_SPEC.md:42-58`), while the live Swift/TypeScript runtime uses raw 19-step identifiers (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:560-580`, `apps/macos/TalkieServer/packages/workflow-core/src/types.ts:1-21`). That is a boundary mismatch in current code state, not a recommendation.
