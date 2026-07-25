# TLK-034 — Product Vocabulary and Hardening Roadmap

**Status**: Working draft — vocabulary proposed; foundational audits complete
**Owner**: Talkie product + macOS platform
**Date**: 2026-07-25
**Studio**: /eng/tlk-034
**Surface**: /studio/studies/talkie-feature-atlas
**Related**: [TLK-002](tlk-002-talkie-object-refactor.md) (content model), [TLK-011](tlk-011-skill-presentation.md) (skill/workflow presentation), [TLK-018](tlk-018-media-surface-roundup.md) (media surfaces), [TLK-022](tlk-022-media-augmentation-pipeline.md) (media sidecars), [TLK-026](tlk-026-visual-context-capture.md) (visual context), [TLK-027](tlk-027-agent-owned-overlays-and-assistant-workflow.md) (prior ownership proposal), [TLK-032](tlk-032-memo-recording-safety.md) (memo recording safety)

## Summary

Talkie has accumulated several good capabilities faster than it has accumulated
one shared language for them. The same user journey can currently be described
as a capture, screenshot, tray item, attachment, queued image, or delivery,
depending on which surface or subsystem is speaking.

This document gives product and engineering one vocabulary for that journey and
turns the current feature inventory into a hardening roadmap.

The central model is:

```text
Acquire                         Hold                         Deliver

capture source ──► media item ──► tray / queue ──► delivery target
                      │                 │              │
                      └──► library      └── receipt ◄──┘
```

- A **capture** acquires context.
- A **screenshot** or **screen recording** is a resulting media item.
- The **tray** temporarily holds captured media for user-directed reuse.
- A **queue** holds items that Talkie intends to deliver automatically.
- A **delivery** moves one queued item toward a remembered **delivery target**.
- A **shelf** is only a view of held items; it is not another store.

This is a terminology and sequencing document, not an authorization to rename
persisted types or change process ownership. The 2026-07-25 P0.1 and P0.2 audits
ground the first two roadmap items, but their implementation and target-state
decisions remain separate work.

## Why this document exists

Three kinds of ambiguity currently compound each other:

1. **Product ambiguity** — users see adjacent nouns without a stable
   relationship between them.
2. **State ambiguity** — “in the tray,” “queued,” and “delivered” can sound like
   interchangeable success states even though they promise different things.
3. **Ownership ambiguity** — prior docs propose boundaries between Talkie,
   TalkieAgent, and TalkieKit, but a proposal is not evidence that the running
   system already follows that boundary.

The roadmap therefore starts with loss prevention and ownership evidence before
polishing labels or consolidating surfaces.

## Reading rules

This document uses three evidence labels:

| Label | Meaning |
| --- | --- |
| **Observed** | Supported by the checked-in repository or a reproducible runtime check. |
| **Proposed** | A product or architecture decision offered for review. |
| **Audit pending** | The question is active; this document must not imply an answer yet. |

Statements without one of these labels define vocabulary or acceptance criteria,
not current implementation behavior.

## Foundational audit snapshot — 2026-07-25

The P0.1 and P0.2 repository audits are complete. This section records only the
high-level findings needed to order the roadmap. It does not claim that a
particular failure has occurred in production.

### Capture-to-paste

**Observed:** The current delivery path is split across target locking, an
in-memory pending-capture collection, destination activation, and synthetic paste
dispatch. Dispatching Command-V is treated optimistically as completion even
though a generic destination does not acknowledge receipt. Queue and target
lifecycle are coupled in ways that can clear pending intent when the target is
lost, and the pending collection is not a durable restart boundary.

This establishes a contract gap. It does not, by itself, establish the frequency
or user impact of any production incident.

### Agent/Talkie ownership

**Observed:** Live capture execution, overlays, tray/history behavior, and
configuration are divided across Talkie and TalkieAgent. The audit found
duplicate schema or settings paths in this boundary. Prior ownership direction in
[TLK-027](tlk-027-agent-owned-overlays-and-assistant-workflow.md) remains useful,
but the target owner for each domain must be accepted explicitly rather than
inferred from that proposal.

This establishes ownership drift and duplicated responsibility. It does not
authorize moving a surface before its callers, storage contract, and recovery
behavior are accounted for.

## Canonical vocabulary

### Product nouns

These are the words Talkie should use in navigation, menus, help, status, and
product discussion.

| Term | Canonical meaning | Use it when | Do not use it as |
| --- | --- | --- | --- |
| **Memo** | A durable Talkie record centered on a thought, usually with audio and transcript, and optionally media, notes, and skill results. | The user chose to keep, review, organize, or build on the content. | A synonym for every audio file, dictation, or temporary transcript. |
| **Dictation** | A live voice-input session whose primary outcome is text inserted into another context. It may later be promoted to a memo. | Voice is being captured for immediate text input. | A synonym for memo, recording, transcript, or conversation. |
| **Note** | A durable, editable, text-first Talkie record. It may contain dictated segments and may be promoted to a memo. | The user is composing or preserving text as the primary material. | A generic label for annotations, drafts, transcripts, or every text field. |
| **Recording** | A time-bounded act of acquiring audio or video, and by context its resulting time-based media. Qualify the modality outside a context where it is unmistakable. | Saying **voice recording**, **memo recording**, or **screen recording**. | A synonym for memo, dictation, transcript, or every media item. |
| **Capture** | The act or session of acquiring visual context from a display, window, or region. | Naming an action such as “Capture region” or a state such as “Capturing.” | A generic name for the resulting media item, the tray, the capture source, or the destination. The persisted `TalkieObjectType.capture` case is an intentional storage-name exception documented below. |
| **Screenshot** | A still-image media item produced by a screen capture. | Referring to the resulting image or an image-specific action. | The umbrella term for clips, recordings, imported media, or capture UI. |
| **Screen recording** | A time-based visual media item, and by context the session that creates it. | Referring to recorded screen video. | Bare “recording” where it could be confused with voice recording. |
| **Tray** | A temporary holding state for captured or selected media before the user attaches, delivers, saves, copies, or clears it. | The user can inspect or manipulate held items. | A durable library, an automatic delivery queue, or a visual component. |
| **Shelf** | A compact visual presentation of tray contents. | Naming the overlay or strip that exposes tray items. | A persistence layer or a second collection beside the tray. |
| **Draft** | Editable user content that has not been committed to its durable final form. | A user can continue editing, save, or discard the content. | A captured file, pending delivery, transient overlay, or generic in-memory state. |
| **History** | A review surface over past records, versions, runs, or events. Qualify the domain when more than one kind is present. | Saying **capture history**, **edit history**, or **skill-run history**. | A primary record type, queue, tray, or undifferentiated event dump. |
| **Workflow** | The advanced/internal automation definition and execution graph beneath Talkie’s skill presentation. | Engineering, file formats, migration, or an explicitly advanced editor. | A new peer product concept beside Skill. |
| **Delivery target** | A remembered destination context into which Talkie intends to place content. It may include an app, window, and input element identity. | Saying where queued content should go. Short UI can say **Target** when the destination context is already clear. | The display/window/region being captured; call that the **capture source**. |
| **Queue** | An ordered set of payloads awaiting automatic delivery, with item-level state. | Talkie has accepted responsibility for attempting delivery later or in order. | A tray, a visual badge, or proof that the destination received an item. |
| **Delivery** | The lifecycle of moving one payload from the queue toward a delivery target and recording the outcome. | Describing automatic send/paste behavior and its result. | A synonym for capture, clipboard mutation, focus change, or an unverified input event. |

### Supporting terms

| Term | Meaning |
| --- | --- |
| **Media item** | A durable or temporary image, video, audio, or imported file. Screenshot and screen recording are specific media-item types. |
| **Capture source** | The display, window, or region from which visual context is acquired. |
| **Attachment** | A relationship that associates a media item or file with a memo or another durable record. It is not a media type. |
| **Library** | The durable, reviewable collection of Talkie records and saved media. |
| **Receipt** | Durable evidence of what a delivery attempted and what outcome Talkie can truthfully claim. |
| **Transcript** | Text derived from audio. A transcript can belong to a memo or dictation; it is not the session itself. |

### Storage vocabulary and product mapping

`TalkieObject` is the persisted content model shared by the macOS Talkie
targets. It is an engineering/storage name, not a label that should appear in
ordinary product copy. Its shipped `TalkieObjectType` cases map to product
language as follows:

| Storage case | Product meaning | Naming rule |
| --- | --- | --- |
| `memo` | Memo | The storage and product nouns align. |
| `dictation` | Dictation | The storage and product nouns align. |
| `note` | Note | The storage and product nouns align. |
| `segment` | A durable child of a note that is not shown as a top-level record. | Treat **segment** as an internal structural noun; say **note segment** only where the hierarchy matters to the user. |
| `selection` | Text captured through Quick Selection for local, time-limited processing. | Use **Quick Selection** for the feature and **selection** for the user-chosen text; do not present it as a durable library record. |
| `capture` | A local, durable record containing a screenshot plus optional OCR or user text. | Keep `capture` as the persisted case for compatibility. In product copy, name the resulting **screenshot**, **media item**, or **capture record** according to context rather than treating every result as the capture act. |

This mapping does not authorize renaming persisted enum cases, keys, routes,
Codable fields, or public API contracts.

### Required qualifiers

Some short words are useful in compact UI but ambiguous in docs and code review.
Use these rules:

- Prefer **voice recording** or **screen recording** over bare **recording**.
- Prefer **delivery target** over **capture target** when the destination receives
  content.
- Prefer **capture source** for the display, window, or region being acquired.
- Prefer **tray item** for user-held media and **queued item** for content Talkie
  has promised to deliver.
- Prefer **delivered**, **delivery failed**, or **delivery unconfirmed** only when
  the underlying evidence supports that exact claim.

## What remains from prior taxonomy work

**Observed:** Talkie already has substantial, dedicated research on
Workflow/Skill/Action naming:

- [TLK-011](tlk-011-skill-presentation.md)
- [TLK-012](tlk-012-ai-tools-taxonomy.md)
- [workflow/skill/action taxonomy](../planning/2026-05-20-workflows-skills-actions-taxonomy.md)
- [codebase-state survey](../planning/2026-05-20-taxonomy-codebase-state.md)
- [rename inventory](../planning/2026-05-20-rename-inventory.md)

This document does not reopen that decision. **Skill** remains the intended
user-facing automation concept; **workflow** remains valid for the underlying
definition, execution graph, file format, and advanced tooling. “Action” should
remain contextual rather than becoming another top-level peer.

## State relationships

### Capture is not storage

A capture ends by producing zero or more media items. What happens next is a
separate decision:

```text
capture
  ├─► tray         temporary, user-visible holding
  ├─► queue        automatic-delivery responsibility
  ├─► memo         attached to a durable record
  └─► library      saved for later review
```

One media item may be both visible in the tray and represented by a queued
delivery entry, but those states must not be collapsed. Clearing one must have
an explicit, tested effect on the other.

### Shelf is a view, not a state

Showing, hiding, moving, or restyling the shelf must not change whether an item
is held in the tray. Product copy should describe the shelf as a way to see the
tray, never as the owner of the media.

### Target is destination, not success

Remembering a target establishes intent. It does not prove that the app is
available, that the same input still exists, or that the destination accepted a
payload. A target can be remembered while unavailable. Delivery outcomes belong
to queue entries and receipts, not to the target badge.

### Delivery claims must match evidence

The strongest truthful state depends on what the destination can acknowledge:

| Evidence available | Strongest product claim |
| --- | --- |
| Payload is stored in Talkie’s queue | **Queued** |
| Talkie began an attempt | **Sending** / **Delivering** |
| Input event was dispatched but the destination cannot acknowledge receipt | **Sent — unconfirmed** or **Delivery unconfirmed** |
| Destination explicitly acknowledged the payload | **Delivered** |
| Attempt ended with a known error | **Delivery failed** |
| Outcome cannot be reconstructed after interruption | **Delivery status unknown** |

Do not convert an input event, focus change, clipboard write, or timeout into a
stronger claim than the evidence permits.

## Hardening principles

1. **Protect user data before polishing the path.** Loss, duplication, and false
   success outrank animation and surface consolidation.
2. **One authoritative writer per state domain.** Other processes observe with
   snapshots or request changes with commands.
3. **Persist promises, not incidental UI state.** If Talkie has accepted
   responsibility for later delivery, that responsibility must survive a view
   disappearing and must have an explicit lifecycle-boundary matrix covering
   Agent restart, Talkie restart, logout, update, and machine restart.
4. **Make each state inspectable.** A user or diagnostic tool should be able to
   answer what is held, queued, in flight, delivered, failed, or unknown.
5. **Separate source, payload, destination, and receipt.** These have different
   lifecycles and must not be represented by one overloaded object.
6. **Prefer recovery over silent clearing.** Target loss, process restart, and
   partial failure should produce recoverable state or an explicit user choice.
7. **No architectural migration without evidence.** Existing proposals inform
   the audit but do not substitute for tracing the running path.

## Roadmap

Priority describes user risk, not implementation order inside a pull request.
Each item must be narrowed by its audit or implementation brief before code
changes begin.

### P0 — Trust, ownership, and recovery

#### P0.1 — Capture-to-paste reliability

**Problem:** Once Talkie accepts media for automatic delivery, the user needs a
truthful, recoverable answer to “what happened to it?”

**Audit status:** Complete. Implementation has not started under this document.

**Required outcome:**

- every queued screenshot has stable identity and explicit lifecycle state
- concurrent triggers cannot silently duplicate an item
- target loss, interruption, and restart have defined recovery behavior
- partial success is represented per item
- paste confirmation and the strongest truthful delivery claim are explicit
- return-to-origin behavior is deliberate, configurable, and tested
- clearing a target, tray, or queue has explicit and separately tested semantics
- Talkie never claims destination receipt without adequate evidence

**Acceptance evidence:**

- a state-transition table reviewed alongside the implementation
- tests for duplicate trigger, process interruption, unavailable target, partial
  batch failure, retry, and explicit cancellation
- a diagnostic receipt that can explain the last attempt without private content
- a reviewed lifecycle-boundary matrix for Agent restart, Talkie restart, logout,
  update, and machine restart; each boundary must state whether queued work
  survives and how non-survival is surfaced
- runtime verification showing the queue is neither silently lost nor replayed
  twice across every boundary the matrix declares supported

**Dependency:** Uses the nouns and evidence levels in this document. The state
machine and failure semantics can be designed in parallel with P0.2, but durable
queue implementation must not choose its authoritative writer until P0.2 records
and accepts that ownership decision.

#### P0.2 — Agent ↔ Talkie ownership

**Problem:** Live desktop behavior becomes fragile when more than one process can
believe it owns the same state, surface, or lifecycle.

**Audit status:** Complete. Target-state ownership decisions remain for review.
[TLK-027](tlk-027-agent-owned-overlays-and-assistant-workflow.md) is prior
architecture direction, not proof of the current runtime boundary.

**Required outcome:**

- capture, overlays, history, settings, and tray each have one authoritative owner
- command, snapshot, durable-storage, and rendering responsibilities are distinct
- launch, relaunch, app quit, Agent restart, and version skew have defined behavior
- duplicate implementations are either justified or given a removal sequence
- settings ownership is separated from settings presentation

**Acceptance evidence:**

- a current-state ownership table grounded in code paths and runtime observation
- a target-state decision record with one writer per mutable state domain
- lifecycle tests covering each process starting first, stopping, and reconnecting
- no shared mutable state whose conflict resolution is “last writer wins” without
  an explicit protocol

**Dependency:** Must inform later surface and lifecycle consolidation. It should
not silently rewrite P0.1’s delivery semantics.

#### P0.3 — Engine and bridge completeness

Finish the intended Agent `/v1/talkie/*` surface, engine HTTP routes, and
transcription-model XPC bindings so a reachable route cannot terminate in an
unexplained placeholder or generic availability response.

**Evidence gate:** Inventory every declared route and binding against its actual
handler before classifying it as complete, placeholder, deprecated, or blocked.
Do not infer completeness from registration alone.

**Acceptance evidence:**

- a route/capability matrix with caller, owner, transport, auth, and error contract
- contract tests for success, unavailable dependency, invalid input, and version skew
- reachable unsupported paths return an intentional typed response
- diagnostics distinguish routing, process availability, and downstream engine failure

**Dependencies:** P0.2 decides ownership. P0.5 defines repair UX for unavailable
processes and permissions.

#### P0.4 — Sync consistency

Define one authoritative sync path for each record class and make conflict,
offline, and multi-device delivery state observable across CloudKit, TalkieSync
XPC, the bridge, and local providers.

**Evidence gate:** This is a consistency audit, not an instruction to merge all
transports. Record which path is authoritative, which is a mirror, and which is a
compatibility bridge before proposing removal.

**Acceptance evidence:**

- an authority table per data class and transport
- deterministic conflict and offline behavior with user-visible recovery
- correlation identifiers that trace one change across process boundaries
- tests for duplicate, reordered, delayed, and rejected updates
- no silent last-writer-wins behavior unless it is an explicit product policy

**Dependencies:** P0.2 for state ownership; P0.3 for truthful bridge/engine
contracts. This docs track does not authorize iOS changes.

#### P0.5 — Permissions and recovery

Provide coherent diagnostics and repair for microphone, Accessibility, Screen
Recording, Automation, and local-network access.

**Evidence gate:** Verify the responsible process and actual system status for
each permission. Do not derive permission truth solely from which UI is visible.

**Acceptance evidence:**

- one permission matrix naming requester, consumer, check, prompt, and repair path
- blocked actions explain the missing capability and preserve recoverable work
- revocation and re-grant are tested without requiring an unexplained full reset
- diagnostics separate denied, restricted, not determined, stale, and unavailable

**Dependencies:** P0.2 determines the responsible process; P0.3 ensures permission
failures cross bridges as typed errors.

### P1 — Contract convergence and product graduation

#### P1.6 — Workflow contract

Converge the in-app builder, WFKit canvas, and server-portable planner around an
explicit contract for steps, retries, errors, and side effects such as email
compose-versus-send. Preserve [TLK-011](tlk-011-skill-presentation.md)’s product
presentation while making advanced/internal workflow semantics unambiguous.

**Acceptance evidence:** round-trip fixtures across each representation, a
capability/portability matrix, explicit retry and idempotency policy, and tests
that distinguish preparing an external action from performing it.

#### P1.7 — Settings and connection control

Consolidate Agent/main-app settings responsibility and make Connection Center
report truthful runtime, transport, account, and permission state.

**Acceptance evidence:** one source of truth per setting, migration coverage for
duplicate paths identified by P0.2, and UI states that distinguish configured,
connected, degraded, unavailable, and permission-blocked.

**Dependencies:** P0.2, P0.3, and P0.5.

#### P1.8 — AI feature graduation

Inventory gated titles, summaries, tasks, keyboard transforms, and voice
foregrounding, first classifying each as shipped, gated, or speculative. Then
decide whether each candidate graduates, remains experimental, or is removed.
Each decision needs latency, privacy, fallback, and failure criteria.

**Acceptance evidence:** a feature card for each candidate naming value,
required context, model/provider, local/cloud boundary, latency budget, fallback,
failure UX, and graduation decision.

**Dependencies:** P1.10 for provider truth and P0.5 for capability recovery.

#### P1.9 — Cross-platform continuity — deferred

The atlas identified Deck mirror, workspaces, sync-conflict handling, Watch
assistance, `HomeNextStub`, and other partial or legacy cross-platform surfaces as
candidates to finish or remove.

**Decision for this track:** Deferred. The user explicitly asked to leave iOS
alone. Documentation may record an interface dependency needed by macOS, but no
iOS implementation, removal, or terminology migration belongs in this roadmap
slice.

#### P1.10 — LLM/provider consolidation

Reduce duplicated provider concepts across Talkie, TalkieKit, TalkieServer, and
future platform clients. Align authentication, model naming, cost/capability
metadata, selection, and failure semantics without forcing all execution into one
process.

**Acceptance evidence:** one provider capability schema, explicit ownership of
credentials and selection, compatibility fixtures across runtimes, and user-facing
errors that identify configuration versus provider versus network failure.

### P2 — Simplification and shared language

#### P2.11 — Legacy removal

Retire TalkieLive residue, the old notch composer, disabled macOS views, and
obsolete macOS navigation notifications only after ownership and caller evidence
establish that they are no longer serving a real path. Keep aliases only for
verified callers or bounded migration windows. iOS-only legacy candidates,
including `HomeNextStub`, remain deferred under P1.9.

**Acceptance evidence:** each deletion cites its replacement, caller search,
runtime verification, migration window, and rollback story. “Appears unused” is
insufficient.

**Dependency:** P0.2 and the relevant P0/P1 replacement.

#### P2.12 — Architecture documentation

Update the process model around TalkieEngineCore, EngineClient, TalkieAgent, and
TalkieServer after P0 decisions land. Diagrams should identify state owners,
process boundaries, durable stores, command direction, and recovery responsibility.

**Acceptance evidence:** a new contributor can trace capture-to-delivery,
memo/dictation, engine request, and sync lifecycles without reading view code
first; docs match the checked-in topology and supported launch modes.

#### P2.13 — Surface vocabulary

Adopt this document’s distinctions for memo, dictation, capture, note, selection,
segment, draft, history, shelf, tray, target, queue, and delivery, including the
explicit `TalkieObject` storage mappings above. Start with an inventory; change
copy in coherent slices and do not mechanically rename persisted keys, API fields,
routes, or internal types.

**Acceptance evidence:** a reviewed exception list for intentionally internal or
legacy names, search evidence for user-facing alignment, and lightweight review
guardrails where repeated drift would create false state claims.

## Cross-cutting evidence requirements

Every implementation item should contribute to the same inspectable model:

- state fixtures shared by unit tests, integration tests, and previews
- privacy-preserving receipts for queue, target, bridge, permission, and sync events
- explicit unknown/unconfirmed states instead of optimistic success
- owning process and version on cross-process diagnostics
- acceptance tests named after the user promise, not only the rendering surface

## Dependency map

```text
TLK-034 vocabulary
    ├──► P0.1 capture-to-paste contract
    └──► P2.13 surface vocabulary

P0.2 ownership
    ├──► P0.3 engine/bridge completeness
    ├──► P0.4 sync consistency
    ├──► P0.5 permissions/recovery
    ├──► P1.7 settings/connection control
    └──► P2.11 legacy removal

P0.3 + P0.5 ──► P1.7 settings/connection control
P0.4         ──► P1.9 cross-platform continuity (deferred)
P1.10        ──► P1.8 AI feature graduation

P0 + P1 verified decisions
    └──► P2.12 architecture documentation
```

P2.13 inventory can proceed independently, but broad renames should wait until P0
terminology is reflected in real state contracts. P2.11 deletion must wait for
P0.2 and the relevant replacement evidence.

## Acceptance criteria for this document

This vocabulary is ready to become canonical when:

- product and engineering agree on the product/storage distinction for every
  term in the canonical table, and every shipped `TalkieObjectType` case has an
  explicit product-language mapping
- P0.1 uses queue, delivery, target, and receipt consistently
- P0.2 uses owner, command, snapshot, and durable store consistently
- the Studio feature atlas links this document and presents the same priorities
- ambiguous bare “recording” and “capture target” uses have an explicit exception
  or migration plan
- no open audit result is represented here as a verified current-state claim

## Explicit non-goals

- No iOS work or cross-platform terminology migration in this track.
- No Swift, runtime, XPC, storage, schema, or database changes.
- No renaming of persisted keys, routes, Codable fields, or public API contracts.
- No reopening the Skill/Workflow/Action product decision.
- No decision here about whether Talkie or TalkieAgent owns a specific live
  surface; P0.2 owns that conclusion.
- No assertion that every tray item must be queued, saved, or attached.
- No promise of exactly-once delivery to a destination that cannot acknowledge
  receipt.
- No visual redesign of the tray, shelf, target badge, or notifications.
- No deletion of legacy code based only on a documentation inventory.

## Review questions

1. Is **delivery target** clear enough in user-facing copy, with **Target** as
   the compact form?
2. Should **queue** be visible to users, or should UI say “held for delivery”
   while engineering retains queue as the state-model term?
3. Is a screenshot captured for automatic delivery also placed in the tray, or
   are those independent policies with independent clear actions?
4. What evidence can each supported destination provide beyond input dispatch?
5. Which lifecycle promises must survive Agent restart, Talkie restart, logout,
   update, and machine restart?
6. Once the P0.2 target-state decision lands, which prior ownership statements
   in TLK-027 remain correct, and which should be marked superseded?

## Change discipline

When an audit or implementation changes this roadmap:

1. add the evidence source and date
2. change **Audit pending** to **Observed** only for facts the evidence proves
3. preserve unknown and unconfirmed states rather than forcing a binary success
4. update Studio and this document together when priority or terminology changes
5. keep implementation/storage names in migration tables instead of silently
   rewriting them as product nouns
