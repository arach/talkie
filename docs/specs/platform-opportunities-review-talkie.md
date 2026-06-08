# Platform Opportunities — Product/Spec Synthesis

**Date**: 2026-06-04
**Owner lane**: Talkie Scout product/spec synthesis
**Sibling lane**: Codex engineering triage (`docs/specs/platform-opportunities-engineering-triage-codex.md`)
**Scope**: Prioritize the six platform opportunities surfaced from the Claude/Talkie session review and map them to existing TLK specs.

## How to read this memo

Each opportunity gets a single-line product framing, a sequencing call (P0 / P1 / P2), the specs that already cover it, what needs spec work before engineering can start, and concrete dependencies. The final section is the cross-cutting sequencing decision and the open questions that genuinely block engineering today.

## Critical-path summary

```
P0 Bridge downgrade fix ─┐
                         ├─► P0 Agent Home runtime persistence (TLK-021) ─┐
P0 ActionRun primitive (TLK-023 Phase 1a) ───────────────────────────────┼─► P1 Media sidecar consumers (TLK-022 → TLK-018/021) ─► P1 Scopes Phase 1 (TLK-024) ─► P2 iOS shared components + memo-detail IA (TLK-019)
                         └─► P1 Agent Home page split + projection (TLK-021) ─┘
```

Three statements drive this order:

1. **Bridge security is small and ships independently** — codex has it landed; treat as P0 done pending review.
2. **Agent Home and Action Workbench must share a runtime model before agent-command runs flow through ActionRun** — sequencing TLK-021's persistent transport first prevents a second Activity/AI Results pile rebuilt on top of process-spawn polling.
3. **Scopes and Media sidecar consumers both consume ActionRun inputs** — without ActionRun first they invent parallel result histories.

## Opportunity-by-opportunity

### 1. Action Workbench / ActionRun platform — P0

**Frame.** Replace Activity / AI Results / scattered workflow-test surfaces with one durable run record (`ActionRunModel`) + evented console. The platform piece is the model, not the UI.

**Spec status.** `tlk-023-action-workbench.md` is the canonical product spec; `tlk-023-action-workbench-review.md` has prior review. Codex confirms `ActionRunModel`, `ActionEventModel`, `ActionInputPackage`, `ActionSubjectRef`, migration `v28_action_workbench`, `LocalRepository` accessors, and an `ActionWorkbenchView` mounted on the Actions route are all live. Phase 1a is substantially landed.

**Spec updates needed before next engineering slice.**
- TLK-023 §"Phasing → Phase 1a" should be updated to reflect what is already shipping (model + view + workflow-test/screenshot producers) so the remaining Phase 1a slice is just: replay/rerun affordances reusing `ActionInputPackage`, completion-notification → run navigation, and broadening producers beyond workflow-test + screenshot paths.
- Settle the open question in TLK-023 §"Open Questions" about whether **agent commands become ActionRuns now or after Agent Home's runtime stabilizes** — recommended deferral: hold agent-command ActionRuns until §2 lands, otherwise we will be writing the producer twice (once against polling, once against persistent IPC).
- Decide the "rendered model snapshot encryption" open question (TLK-023:507) before retention defaults are user-visible.

**Dependencies.** None upstream — the run record can ship more producers independently. Downstream **everything** else benefits: §3, §4, §5, §6 all reuse `ActionRunModel` as their durable event log.

### 2. Agent Home runtime / activity boundary — P0

**Frame.** Talkie Agent needs one place where the local agent's voice, sessions, routines, and follow-ups land, backed by a persistent runtime — not a process-per-poll Node spawn and a `jobs.json` backchannel.

**Spec status.** `tlk-021-agent-home-architecture.md` is the canonical spec; `tlk-021-review-claude.md` is the sibling review with concrete code references and a replacement implementation order. Codex flags the still-live issue: `TalkieAgentRuntime` is a persistent Node sidecar with stdin/stdout multiplexing, but UI paths (`AgentHomeActivityStore`, `WalkieSession`) still call `WalkieNodeRuntimeClient` per request. Two runtimes coexist; one is the right one.

**Spec updates needed before next engineering slice.**
- TLK-021 §"Implementation Plan" should be replaced by the "Suggested ordering" in `tlk-021-review-claude.md` §"Suggested ordering" (review item 9 of 9). Critical: persistent transport precedes view split.
- Resolve TLK-021 §"Critical Prerequisites → Typed Runtime Status IPC" by naming `jobs.json` as the contract or replacing it with a typed `jobs` op (review item 2).
- Add the activity projection (`ActivityItem` union over `job` / `dictation` / `routine` / `voiceCapture`) before the page split — currently undocumented (review item 3).
- Pick a model for Dispatcher / Runtime / Executor naming (review §"Architecture risks" item 4) — registry says sibling runtimes; UI taxonomy implies dispatcher + Scout bridge. They cannot both be right in the spec.
- Resolve TLK-021 open questions #1 (Home as opt-in vs default activation) and #2 (where completed executor output lives) — #2 blocks Activity/Now reads.

**Dependencies.** Upstream: §1's ActionRun + ActionEvent contracts are the right backing store for "where completed executor output lives" (review §"Missing boundaries"). Downstream: §1's agent-command ActionRun producer waits on this; §4 (Scopes) wants `scopeId` carried on every job, which requires fixing the existing dictation↔job join key gap (review §"Missing boundaries" item 1).

### 3. Media sidecar consumers and visual context — P1

**Frame.** `MediaAugmentationService` writes `TKSidecar`s to hidden `.tk/` next to each asset, fire-and-forget after the two protected paths. Sidecars exist; the next question is who reads them and how visual context (OCR, AX tree, VLM description, window metadata) reaches actions, workbench input packages, and scope grounding.

**Spec status.** `tlk-022-media-augmentation-pipeline.md` is mature — Phases 1–4 landed, OCR + window-meta live, catch-up sweep running on launch. `tlk-018-media-surface-roundup.md` covers the user-facing media surface IA cleanup. `tlk-021-capture-markup.md` covers user-state sidecars (annotations).

**Spec updates needed before next engineering slice.**
- TLK-023 §"Input Package" needs an explicit `derivedContextRefsJSON` schema that references sidecar augmentation kinds — today it's mentioned in passing but the wire format isn't defined. This blocks reusing OCR/AX/VLM output as ActionRun input.
- TLK-022 should add a **consumers** section enumerating: ActionRun input packages, Scope grounding queries, agent-context surfaces. Today the spec is producer-shaped; consumers are implicit.
- TLK-018 needs a decision on whether sidecar data ever appears in the media-surface UI (file size + dimensions are listed in current gaps; OCR snippets / AX summaries are not). Without this, the media surface drifts toward technical metadata while sidecars hold the user-meaningful context.

**Dependencies.** Upstream: §1 (ActionRun input package needs the consumer schema). Downstream: §4 (scope grounding reads sidecar context).

### 4. Scopes — P1

**Frame.** Bounded user-owned context (`ScopeDefinition`) above captures/skills/actions/sessions: declares resources, allowed skills/agents, permissions, memory policy. The product point is that the assistant knows what it can see, what tools it can use, and what "done" means inside the bounded context.

**Spec status.** `tlk-024-scopes-agent-context-model.md` is product exploration only. Data model is sketched but not implemented anywhere in the macOS or iOS targets.

**Spec updates needed before next engineering slice.**
- TLK-024 needs an explicit Phase 1 cut: which fields of `ScopeDefinition` ship in V1 vs. later. Recommend V1 = `id / slug / name / description / captureRules / skillIds`; defer `agents / permissions / memoryPolicy / retentionPolicy / views / automations`.
- TLK-024 should define how `scopeId` propagates: capture → ActionRun → ActionEvent → agent invocation payload. Today the spec shows the agent-invocation JSON (TLK-024 §"Agent Model") but not the persistence path on ActionRun.
- Reconcile with TLK-004 (file-based context roots) — TLK-024 references it but doesn't pick a side: is Scope a UI/product object that sits over `.talkie/` roots, or does it replace them? Engineering needs the answer.
- Decide whether the default scope (TLK-024 §"UX Principles") is `Inbox` or `Unscoped` and persist that choice — engineering will pick one if spec doesn't.

**Dependencies.** Upstream: §1 (ActionRun needs `scopeId`), §2 (Agent Home invocations carry `scopeId`), §3 (sidecar consumers query within scope). Downstream: none in V1.

### 5. Bridge / companion security hardening — P0 (engineering says landed)

**Frame.** WebSocket sealed-frame negotiation on screen + companion-event streams, and pre-pairing encryption pinning for already-paired Macs that re-pair via QR / nearby / credential refresh.

**Spec status.** `tlk-001-bridge-api-unification.md` covers the bridge API; `tlk-009-local-network-companion-mode.md` covers companion-mode wire format; `tlk-015-security-notifications.md` covers security UX. Codex memo §"Bridge Security" reports `apps/ios/Talkie iOS/Bridge/BridgeManager.swift` now resolves existing paired Macs by active key / host:port / stored server pubkey before pairing-time connect, applies `setEncryptionRequired(existingPinned)` before initial `connect()` on QR/nearby and credential-refresh pairing paths, and pins on approved encrypted pairing. Build verified.

**Spec updates needed before next engineering slice.**
- TLK-001 / TLK-009 should be updated with the re-pair encryption rule as a normative requirement (today it's a missing-edge-case footnote, not a stated invariant).
- TLK-015 should add a user-visible signal when a re-pair attempt is blocked because encryption is required but the peer can't negotiate it — currently the failure mode is silent at the UX layer.

**Dependencies.** None — this slice ships standalone. **Recommended action**: lock the spec invariant, then close P0 status on this opportunity.

### 6. iOS shared components + memo-detail IA cleanup — P2

**Frame.** Replace ad-hoc surface scaffolding in `apps/ios/Talkie iOS/Views/Next/` with `ChromeAwareHeaderBar` + a tokenized primitive set; fix the chrome-overlap bug where 14 modal/drill-down headers don't yield to `ShellChrome.occupiedZones`.

**Spec status.** `tlk-019-ios-shared-components.md` is a paint + token contract spec. `tlk-014-ios-keyboard-ux.md` covers keyboard UX. No dedicated memo-detail IA spec exists today — that's an open spec gap.

**Spec updates needed before next engineering slice.**
- TLK-019 is ready for engineering on the primitives side; the chrome-overlap fix is a bug fix not a platform shift.
- **Open spec gap**: memo-detail IA cleanup needs its own short spec. `tlk-026-visual-context-capture.md` already exists and is about visual context, so do not reuse TLK-026 for memo-detail IA.

**Dependencies.** Independent. P2 because no other opportunity unblocks on it and the chrome-overlap fix can land as a contained bug fix outside the platform sequencing.

## Sequencing decision

The recommended order, with rationale:

| Order | Slice | Owner-lane gating | Why this slot |
| --- | --- | --- | --- |
| 1 | Bridge re-pair invariant landed + spec'd (§5) | Engineering done; spec update next | Smallest, security-sensitive, no downstream coupling |
| 2 | Agent Home persistent transport + typed `jobs` op + activity projection (§2 critical prerequisites) | TLK-021 spec update precedes engineering | Unblocks §1 agent-command ActionRuns and §4 scope-carrying invocations |
| 3 | ActionRun consumer-schema definition for sidecar inputs (§1 + §3 contract) | TLK-023 spec edit, no engineering yet | One-time schema decision; everyone reads from it |
| 4 | ActionRun producer broadening + rerun via `ActionInputPackage` (§1 Phase 1a remainder) | Engineering | Shared observability layer for §3, §4 |
| 5 | TLK-022 consumers section + TLK-018 sidecar UX decision (§3) | Spec edits, then engineering | Visual context becomes routable, not just stored |
| 6 | Scopes V1 cut (§4) | TLK-024 phasing decision, then engineering | Sits on top of stable ActionRun + Agent Home |
| 7 | TLK-019 primitives + chrome-overlap fix; create a memo-detail IA spec (§6) | Spec creation, then engineering | Independent paint/IA polish |

## Specs needing updates before implementation

| Spec | Update | Blocking what |
| --- | --- | --- |
| `tlk-021-agent-home-architecture.md` | Replace Implementation Plan with `tlk-021-review-claude.md` ordering; resolve open Q #1 + #2 | §2 engineering start |
| `tlk-021-agent-home-architecture.md` | Pick Dispatcher / Runtime / Executor taxonomy | Inspector & Executor field naming |
| `tlk-023-action-workbench.md` | Update Phase 1a status to reflect what shipped; defer agent-command producer behind §2 | §1 next slice |
| `tlk-023-action-workbench.md` | Define `derivedContextRefsJSON` schema with sidecar kind references | §3 consumer wiring |
| `tlk-022-media-augmentation-pipeline.md` | Add Consumers section (ActionRun input, Scope grounding, agent context) | §3 + §4 grounding |
| `tlk-018-media-surface-roundup.md` | Decide which sidecar data surfaces in media UI | §3 UX |
| `tlk-024-scopes-agent-context-model.md` | Phase 1 field cut; `scopeId` propagation path; reconcile with TLK-004 | §4 engineering start |
| `tlk-001-bridge-api-unification.md` / `tlk-009-local-network-companion-mode.md` | Make re-pair encryption invariant normative | §5 spec closure |
| `tlk-015-security-notifications.md` | Add user-visible signal for blocked re-pair | §5 UX completeness |
| `tlk-019-ios-shared-components.md` | Ready as written; no blocking edits | — |
| **Missing: memo-detail IA cleanup spec** | Create a new short spec; do not reuse TLK-026 because it is already visual context capture | §6 scope |

## Open questions that block engineering today

These are the ones engineering cannot pick a side on without product input:

1. **What is the memo-detail IA spec?** `tlk-026-visual-context-capture.md` exists already, so memo-detail IA needs a new short spec or an explicit decision to fold into TLK-019. — Blocks §6 ownership.
2. **Where does completed executor output live?** TLK-021 open question #2. Recommendation in this memo: it lives in `ActionEventModel` (the workbench event stream), not in a separate `jobs.json` or sidecar SQLite table. Confirm or override before §2 step 2 ships, or risk dual-write. — Blocks §1 ↔ §2 integration.
3. **Do agent commands become ActionRuns now or after Agent Home stabilizes?** TLK-023 §"Action Workbench" item 4 in codex memo. Recommendation: defer to after §2 to avoid writing the producer twice. — Blocks §1 ordering decision.
4. **Default scope: `Inbox` or `Unscoped`?** TLK-024 §"UX Principles" lists both. Engineering will pick one if spec doesn't. — Blocks §4 V1 cut.
5. **Scope vs `.talkie/` context root** — is Scope the UI/product object over file-based roots (TLK-004), or does it replace them? — Blocks §4 persistence choice.
6. **Rendered model snapshot encryption at rest** — TLK-023:507. Affects user-visible retention defaults. — Blocks §1 Phase 1b/2 retention UX.
7. **Dispatcher / Runtime / Executor naming** — registry vs UI taxonomy mismatch (TLK-021 review §"Architecture risks" item 4). — Blocks §2 inspector/executor surface naming.

## Cross-references

- Engineering triage: `docs/specs/platform-opportunities-engineering-triage-codex.md`
- TLK-019: `docs/specs/tlk-019-ios-shared-components.md`
- TLK-021: `docs/specs/tlk-021-agent-home-architecture.md`, `docs/specs/tlk-021-review-claude.md`, `docs/specs/tlk-021-capture-markup.md`, `docs/specs/tlk-021-ux-review-runtime.md`
- TLK-022: `docs/specs/tlk-022-media-augmentation-pipeline.md`
- TLK-023: `docs/specs/tlk-023-action-workbench.md`, `docs/specs/tlk-023-action-workbench-review.md`
- TLK-024: `docs/specs/tlk-024-scopes-agent-context-model.md`
- TLK-026: `docs/specs/tlk-026-visual-context-capture.md`
- TLK-001 / TLK-009 / TLK-015: bridge + companion + security specs referenced for §5
- Bridge implementation: `apps/ios/Talkie iOS/Bridge/BridgeManager.swift` (per codex memo)
