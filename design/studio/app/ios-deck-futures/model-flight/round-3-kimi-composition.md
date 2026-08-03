# Round 3 synthesis: Kimi — composition, adaptation, accessibility

**Role:** Composition, adaptation, and accessibility editor
**Inputs:** the three briefs; all six Round 1–2 files. No code modified.

## 1. Field ranking

All three Round 2 reviews converge: the Fixed Command Desk is the only
structure that survives portrait, Stage Manager, Dynamic Type, and the verified
data boundary at once.

| Rank | Structure | Corrected scores | Verdict |
|---:|---|---|---|
| 1 | Fixed Command Desk | 8.5–8.6 (Kimi); 84.7 (Grok); Opus strongest-after-revision | Ship target, after §2 revisions |
| 2 | Selected-Task Tape | 8.4 (Kimi); 84.0 (Grok) | Conditional challenger; payload portable into rank 1 |
| 3 | Operational Folio | 8.5 (Kimi, pre-fix); 80.6 (Grok) | Viable only after Talk-invariance fix; differentiation dies in portrait |
| 4 | Cross-Task Chronicle | 7.3 (Kimi); 65.7 (Grok) | Do not advance as a surface; harvest components only |

Decisive lens findings:

- **Landscape.** Desk's 22/52/26 geometry keeps one dominant navy surface;
  Folio's 460/456 split and Chronicle's swimlanes trend dashboard. Tape's
  canvas wins only if the event census confirms ≥4 truthful event types.
- **Portrait / Stage Manager.** Desk loses nothing: rail → compact switcher,
  inspector → drawer, Talk invariant. Folio's portrait pager orphans Talk
  (flagged by two reviewers; violates the brief twice). Chronicle collapses
  into Tape — a landscape-only thesis on a device that rotates.
- **Accessibility.** Desk's 22% rail (≈260 pt) survives accessibility text
  sizes; Folio's 14% spine (≈165 pt) wraps titles to 4+ lines and fails the
  Dynamic Type floor. Chronicle's marker-scan attention is the worst
  VoiceOver and Reduce-Motion story.
- **First glance.** Desk answers all four questions in one viewport on
  verified data. Chronicle splits Q3 across lane and inspector. Tape answers
  Q3 best *when events exist* — a data condition, not a composition property.

## 2. Production composition: Fixed Command Desk, revised

Landscape reference: iPad Air 5, 1180 × 820 pt.

| Zone | Width | Content | Rules |
|---|---:|---|---|
| Task rail | 260–280 pt (≈22%) | Mac name + one health line; scrollable named tasks; one truthful state-or-recency line each; project secondary; lane tertiary | One selection model. State word only where this device has first-hand evidence; otherwise recency (`Codex last wrote 4m ago`). Unmapped task shows no error. |
| Live-work surface | remainder, navy | Task title; plain-language state; quiet branch provenance; latest instruction; latest result **or** truthful live activity; Hear/Copy on result | Never empty. Idle keeps the last exchange. Working shows verified progress strings + derived elapsed time. |
| Turn inspector | promoted, ≤ (live surface − 120 pt) | Bound to **one turn**: instruction, timestamped update stream, result, duration, provenance | Appears only when ≥2 evidence modules have real content (History + Details, or History + Readouts). Never reserves space empty. No task-level region — junk-drawer growth becomes a type error. |
| Needs-you strip | pinned atop live surface | Task name + waiting fact (`Waiting for approval in Codex Desktop since 12:04 PM`) | Pins any unresolved blocked job on the selected Mac, even while viewing another task. Labeled suspension; chronology visibly, honestly reordered. |
| Voice shelf | fixed bottom of live surface | Hold-to-talk, slide-to-cancel, capture perimeter, haptics; helper text per the brief's five-case contract; destination task name inside the control | Never moves, resizes, or paginates in any orientation or state. Disabled with stated reason when the Mac is offline. |

State geometry: one identical layout for Idle, Working, Needs you, and Mac
unavailable; only content and the strip change. `Mac unavailable` names the
Mac, shows `Last successful contact · …`, preserves stale content marked
stale, disables Talk with reason, offers Reconnect / Review connection /
Choose another Mac.

**Voice safety rules (binding):**

1. Selection locks from capture start until dispatch or cancel; a rail tap
   during capture queues and applies after.
2. A Needs-you pin is not inspectable without a selection decision: tapping
   it selects its task (Talk → `Hold to answer`) or opens with response
   controls inert until `Select this task to respond`.
3. A blocking question is never readable as primary content while Talk
   targets another task.

### Adaptation

| Form factor | Rail | Inspector | Live surface + Talk |
|---|---|---|---|
| Portrait | Compact top switcher, full names | Bottom drawer over persistent task page | Primary, unchanged |
| Compact Stage Manager | Switcher | Collapsed first | Task, state, latest result, Talk always survive |

Collapse order under pressure: provenance → inspector → rail. Never task
title, state, result, or Talk.

### Accessibility requirements (exact)

| Requirement | Specification |
|---|---|
| Dynamic Type | Task title, state, latest result, Talk helper preserved at all sizes; rail floor 260 pt so titles wrap to ≤2 lines; provenance truncates before title |
| Contrast | Cobalt is the only live/selected signal but never the only carrier — state always pairs color with a word; Increased Contrast strengthens separators and state text, adds no colors |
| Touch targets | ≥44 × 44 pt: rail rows, Hear, Copy, recovery actions, Talk |
| Reduce Motion | Working pulse replaced by a static state signal; no parallax on the pinned strip |
| VoiceOver | One coherent announcement per context: selected task, Mac, state, latest-result summary, Talk consequence — in that order |
| Focus | Visible focus ring on rail rows and all contextual actions for pointer/keyboard |

### First-glance hierarchy (reading order)

1. **Task** — title, largest type on the navy surface.
2. **State** — one plain word beside it; Needs you outranks Working via the
   pinned strip, not louder chrome.
3. **Result** — latest exchange or truthful activity; the visual anchor.
4. **Voice consequence** — helper text + destination name on the fixed shelf.

## 3. Features the Desk may adopt

| From | Feature | Condition |
|---|---|---|
| Tape | Pinned Needs-you event with explicit suspension label | Adopt as the §2 strip; an ordering rule, not a timeline property |
| Tape | In-turn timestamped update stream (Asked → Working steps → Result) | Adopt as live-work Working content; verified data (≤12 updates/turn) |
| Tape / Chronicle | Terminal failure honesty: time visibly stops, last event marked stale | Adopt in failure copy |
| Folio | Result rendered for reading as the inspector's default content | Adopt when the turn has a long result; History = dated turn selectors on its edge |
| Folio | Failure-as-page recovery reading surface | Adopt as the Mac-unavailable main-pane treatment |
| Chronicle | Rail-level Needs-you promotion group (attention tasks sort above recency) | Adopt inside the rail only |
| Chronicle | Multi-Mac freeze semantics | Adopt if >1 Mac is paired |

## 4. Combinations that must not ship

| Forbidden combination | Reason |
|---|---|
| Folio focus mode + any timeline canvas | Two navigation systems; both reviews: keep absolute |
| Portrait pager with Talk on only one page | Orphans voice during evidence reading; violates brief twice |
| Dual-tap canvas (event tap ≠ selection, empty-space tap = selection) | Dead canvas area doing consequential voice work; labels are not guards |
| Readable blocking question on a non-selected task + live Talk elsewhere | Misdirected voice at the highest-consequence moment |
| `[ Stop ]` on Working or Needs-you | **Rejected by code:** no bridge turn-cancel endpoint; deck Stop is narration-only — a dead consequential button |
| Approve / Deny for approval-required | **Rejected by code:** the bridge refuses approvals by design; copy must direct to Codex Desktop |
| Permanent third column with empty modules | Equal-weight panes become an admin dashboard with thin data |
| State words on every rail row | **Rejected by code:** catalog has no state field; asserting `Idle` for an untouched task is a false statement in a calm voice |

## 5. Data separation

| Data | Status |
|---|---|
| Task title, project, branch, cwd, Mac name, `updatedAt` recency | **Current** |
| Steer/Queue delivery mode + confirmed outcome | **Current** |
| Per-task turn history: instruction (≤4), updates (≤12, timestamped), response, duration | **Current** (per-task, on-demand fetch) |
| Working activity strings for turns this device dispatched; device-local working/accepted/receiving/failed | **Current, device-scoped only** |
| `blocked` job status on approval-required (task + time, no question text) | **Current, job-scoped** |
| `lastSuccessfulContactAt` | **Current** (iOS-side bookkeeping, not a heartbeat) |
| Durable per-task Needs-you badge surviving job resolution | **Proposed** — store work |
| Per-task state for tasks this device did not dispatch | **Proposed** — bridge cost (polling `readTurnActivity` per task) or stay recency-only |
| Live elapsed ticker | **Proposed** — derived from `sentAt` |
| Affirmative Mac-unavailable detection between polls | **Proposed** — inferred from failed requests today; copy must say so |
| Catalog refresh loop running from the deck | **Proposed** — today runs only in mapper/new-task views |
| Turn Stop, approval labels, question text, changed files, token counts | **Not available — do not design for** |

## 6. Five visual acceptance checks

1. **One-viewport truth.** Landscape, idle task with a prior result: task
   title, Mac, `Idle`, latest result with Hear/Copy, and `Hold to continue
   this task` with the destination named inside Talk — all visible, no sheet,
   no scroll.
2. **Pinned attention.** Task A blocked, user viewing task B: the strip names
   A and its waiting fact above B's content; B's Talk helper is unchanged;
   tapping the strip forces a selection decision before any response control
   is live.
3. **Rotation and compaction.** Portrait, then minimum Stage Manager width:
   task title, state, latest result, and Talk survive at full size in fixed
   position; inspector and rail collapse before any of the four shrink.
4. **Accessibility pass.** Largest accessibility text size + Increased
   Contrast + Reduce Motion: rail titles wrap to ≤2 lines untruncated; state
   legible as text without color; Working shows a static signal; every
   actionable element ≥44 pt with visible focus.
5. **Honest failure.** Disconnect the Mac: stale task and result remain,
   marked stale; `Mac unavailable` names the Mac with `Last successful
   contact · …`; Talk disabled with its reason; Reconnect / Review connection
   / Choose another Mac are the only primary actions — and no Stop control
   appears in any state.

*End of Round 3 synthesis — Kimi*
