# TLK-023 — Senior Review (Action Workbench)

**Reviewer**: talkie-action-workbench-review.codex-fix-dictation-tray-links
**Date**: 2026-05-26
**Reviewing**: `docs/specs/tlk-023-action-workbench.md`
**Verdict**: Direction is right; primitives are roughly right; spec under-specifies the two things most likely to bite at build time (subject model, input-package storage). Spec is shippable after addressing the Blocker + High items below.

---

## Are `ActionRun` / `ActionEvent` / `InputPackage` the right primitives?

Yes, with caveats:

- **ActionRun as the umbrella** is the right call. The existing `WorkflowRunModel` is fundamentally workflow- and memo-shaped; trying to bend it into "screenshot Describe-UI" or "agent-command" runs without an explicit umbrella will keep producing scattered surfaces (which is exactly what this spec is rejecting).
- **ActionEvent / event sourcing** is the right backbone for the console UX. `WorkflowEventModel` already gets you 80% of the way there — but the spec doesn't acknowledge it, which creates ambiguity about whether `ActionEvent` is a new table or a relabel.
- **InputPackage as a first-class record** is the right call *if* it's actually durable. The open question "store model-ready prompt text, or refs plus render logic?" is load-bearing — leaving it open means the "rerun against the same screenshot" AC has two incompatible meanings.

The three primitives together correctly model the create → run → inspect → rerun → automate loop. The risk is not the primitives; it's the gap between the spec and the existing code those primitives have to land in.

---

## Findings (severity-tagged)

### Blocker — resolve in Phase 0

**B1. Subject model conflict with existing `WorkflowRunModel`.**
`WorkflowRunModel.memoId: UUID` is non-optional and referenced across `MemoRepository`, `RecordingRepository`, `CoreDataMigration`, ~10 views, and the CloudKit extension. The spec calls for `subjectRefs: [ActionSubjectRef]` (plural, polymorphic, optional for `agent-command` runs). "May wrap or supersede" papers over a real fork:

- Option A — make `memoId` optional + add a `subject_refs` table joined on `run_id`. Real schema migration; need to audit every `belongsTo(MemoModel)` reader.
- Option B — keep `WorkflowRunModel` memo-only, add a parallel `ActionRunModel` table, and use a UNION view for the rail. Avoids schema churn but doubles the read path.

*Suggested edit*: Add a "Subject model" subsection under **Data Model Sketch** picking one option. Add a Phase 0 task "scope memoId-removal migration" or "design ActionRun/WorkflowRun read union."

**B2. `WorkflowInputContract` already exists; spec proposes a parallel JSON shape.**
`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:18` defines `WorkflowInputContract` with `acceptedRecordTypes`, `requiredAssets`, `surfaces`, `parameters`. The spec's example JSON uses `accepts`, `min`, `max`, `sources` — none of those keys exist today. Without a mapping, "the UI only offers `Describe UI` when the contract can be satisfied" is ambiguous against the contract already shipping in `.skill.md` starters.

*Suggested edit*: Replace the JSON sketch in **Input Contract** with the Swift type from `WorkflowDefinition.swift`. Below it, list the net-new fields the spec is adding (`min`, `max`, per-asset `sources`) and call them out as additive migration.

### High

**H1. Phase 1 silently bundles two phases.**
Phase 1 ("Vertical slice") says: add `ActionRun`/`ActionEvent` tables, route screenshot Describe-UI through the workbench, persist failed runs, build console-first run view. But **V1 Surface** describes a three-region window (rail / console / inspector). That's not a vertical slice — that's the full UI.

*Suggested edit*: Split Phase 1 into:
- **Phase 1a — Plumbing**: ActionRun/ActionEvent backing, screenshot Describe-UI routing, failed-run persistence, single-pane console (no rail, no inspector).
- **Phase 1b — Three-region layout**: rail + inspector + multi-run navigation.

Otherwise the "vertical slice" estimate will quietly expand to "ship the workbench."

**H2. Event taxonomy is not mapped to existing events.**
`WorkflowEventModel.EventType` already defines `runStarted`, `stepStarted`, `stepCompleted`, etc. The spec proposes `run.queued`, `step.started`, `step.log`, `artifact.created`, `input.resolved`. The first two are renames; the last three are net-new with no payload schema. Without payload schemas (level/source/data for `step.log`; refs/kind/size for `artifact.created`), the console "structured logs" promise can't be implemented.

*Suggested edit*: Add a table mapping legacy → new event names. Define payload schemas for the three new events (especially `step.log` — needs at least `{ level, source, message }` to render as a console).

**H3. InputPackage storage decision is in Open Questions, but acceptance criteria depend on it.**
AC: "The user can revise the workflow prompt and rerun against the same screenshot." This has two readings:
- *Refs-only InputPackage*: rerun re-resolves through the current workflow → prompt text changes if the workflow changed.
- *Rendered-text InputPackage*: rerun replays the same model input → workflow edits are ignored until re-resolved.

Both are valid; they imply different UIs ("Edit and rerun" affordance behaves differently in each case). Picking later forces a rewrite of the rerun affordance.

*Suggested edit*: Pin it. Recommend: **refs + render-logic version**; rerun re-resolves through the current workflow and shows a one-line diff when the rendered prompt differs from the original run. Add an AC that names this behavior.

**H4. Migration Notes references "TWF" files; the format is `.skill.md`.**
`Existing TWF files remain source of truth for workflow logic` — but `SkillFileFormat.swift` and `Resources/Starters/*.skill.md` are the actual on-disk source. Either a stale name or a rename being floated quietly.

*Suggested edit*: Replace "TWF" with `.skill.md` throughout, or add a Naming subsection if a rename is intended.

### Medium

**M1. Retention is in Open Questions; schema design depends on it.**
Per-run InputPackage + sidecar context + step logs can grow fast. No default retention. Promote to a Phase 0 decision — even "keep all forever in V1, revisit Phase 3" is a decision.

**M2. Missing AC: cancellation.**
Runtime Requirements says "support cancellation"; AC list doesn't. Add: *"Cancelling a running action produces a `cancelled` run with the partial event stream intact."*

**M3. Missing AC: concurrent runs.**
Workbench is implicitly multi-run (rail shows "Running now"). AC should state: *"The user can start run B while run A is streaming; both appear in the rail and can be selected independently."* Otherwise the console-as-singleton assumption sneaks in.

**M4. Missing AC: missing-subject rerun.**
If a screenshot is deleted between runs, rerun must fail visibly with a recoverable error. Add an AC; also state which side owns the durability promise (does the InputPackage retain a copy of the screenshot bytes, or just the asset ref?).

**M5. `actionId: String` vs existing `workflowId: UUID`.**
The data model sketch uses `actionId: String`. Workflows are UUID-keyed; skills/agent commands are slug-keyed. Worth stating the rule explicitly: *action IDs are strings; for workflow-backed actions the string is `workflowId.uuidString`; for skills/agent commands the string is a route slug.* Saves a round of "why is this typed as String" later.

**M6. Agent-first goal lacks acceptance.**
Goal #6 names agent-first interaction (NL command input, "fix this run" loops). Open Question #3 asks "how much NL command routing belongs in V1?" — and AC list is silent on it. Either add an AC ("the user can type `rerun with MiniMax` and the runtime routes it") or move agent-first to a Phase 2 goal so V1 isn't measured against it.

### Low

**L1. Naming undecided.**
"Actions / Workbench / Console / Skills" is the nav slot question — it will be referenced in menus, the keyboard shortcut, onboarding, and existing settings. Decide before Phase 1 starts; don't ship Phase 1a with a placeholder.

**L2. Compatibility-view ambiguity.**
"Old Activity/AI Results surfaces can be represented as compatibility views over `ActionRun`, **or** deprecated after the workbench covers their jobs." Pick one. Recommend: deprecate after Phase 2; don't build compatibility shims over 1.3k lines of existing view code.

**L3. Multi-device automations have no data-model story.**
Phase 4 names multi-device. Automations triggered from iOS that execute on Mac need an `originDeviceId` and a routing concept. Not blocking V1, but a sentence in **Migration Notes** would prevent a Phase 4 schema panic.

---

## Concrete spec edits (checklist)

- [ ] Add **Data Model → Subject model** subsection picking Option A (optional memoId + subject_refs table) or Option B (parallel ActionRunModel + union view).
- [ ] Replace the JSON in **Input Contract** with the existing `WorkflowInputContract` Swift type; list additive fields (`min`, `max`, `sources`).
- [ ] Add **Event taxonomy mapping** table (legacy → new) + payload schemas for `input.resolved`, `step.log`, `artifact.created`.
- [ ] Pin **InputPackage** storage: refs + render-logic version; rerun re-resolves; show diff on render change. Add AC.
- [ ] Split **Phasing → Phase 1** into 1a (plumbing) and 1b (three-region layout).
- [ ] Rename `TWF` → `.skill.md` in **Migration Notes**.
- [ ] Add ACs: cancellation, concurrent runs, missing-subject rerun, agent-first scope (or defer goal).
- [ ] Promote **retention** from Open Questions to a Phase 0 decision.
- [ ] State the `actionId: String` type rule.
- [ ] Decide the nav-slot name before Phase 1a starts.
- [ ] Resolve compatibility-view ambiguity (recommend: deprecate, don't shim).

---

## Scope assessment for V1

V1 as written (per the V1 Surface section) is **too big** for one slice; as written in **Phase 1**, it's **about right** if you split out the three-region layout per H1. The minimum viable workbench is:

1. ActionRun/ActionEvent backing (wrapping `WorkflowRunModel` initially, with the subject model fork resolved per B1).
2. Screenshot `Describe UI` routed through the workbench.
3. Failed runs persisted with input package visible.
4. Single-pane console with streaming events + result + error rendering.

Everything else (inspector panel, action rail, inline workflow editing, NL command routing, save-as-skill, automations) should live in later phases. Resist letting "vertical slice" mean "the V1 Surface section."

---

## Code anchors used in this review

- `apps/macos/Talkie/Data/Models/WorkflowRunModel.swift:14` — existing run model (memo-bound)
- `apps/macos/Talkie/Data/Models/WorkflowEventModel.swift:14,34` — existing event taxonomy
- `apps/macos/Talkie/Workflow/WorkflowDefinition.swift:18` — existing `WorkflowInputContract`
- `apps/macos/Talkie/Workflow/SkillFileFormat.swift:12` — `.skill.md` parser (not TWF)
- `apps/macos/Talkie/Views/Activity/ActivityLogViews.swift` (675 lines) + `apps/macos/Talkie/Views/AIResults/AIResultsViews.swift` (677 lines) — the 1.3k lines the spec proposes to replace
