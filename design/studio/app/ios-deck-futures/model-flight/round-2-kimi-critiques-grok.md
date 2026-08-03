# Round 2 critique: Kimi reviews Grok

**Role:** Adversarial but constructive iPad design reviewer
**Portfolio under review:** `round-1-grok.md` (Fixed Command Desk, Operational Folio, Selected-Task Tape, Cross-Task Chronicle)
**Rubrics applied:** Workbench and Flight Recorder weighted rubrics, plus the shared contract in `IPAD-DESIGN-BRIEF.md`
**Data boundary applied:** current bridge protocol and iOS stores, verified in code (see Evidence ledger)

Grok's portfolio is disciplined: it reads the briefs closely, keeps the helper-text contract verbatim, labels its data inventory, and ranks itself with plausible scores. The critique below is therefore narrow. It concentrates on the places where the portfolio contradicts the verified bridge boundary or its own data tables, and on two interaction risks the scores underweight.

## Evidence ledger

Used throughout this review. Status values: **verified** (found in current code), **inferred** (derivable but not present as stated), **rejected** (contradicted by current code).

| Data claim | Status | Evidence |
|---|---|---|
| Task title, project, branch, Mac identity | verified | `apps/ios/Talkie iOS/Codex/CodexLane.swift` `CodexTaskSummary`; `BridgeManager.pairedMacName` |
| Working state with plain activity string | verified | `CodexProgressUpdate` (`commentary`/`tool` text) in `apps/macos/TalkieServer/src/bridge/routes/codex.ts:98-103`; rendered in `CodexCommandDeckSurface.swift` |
| Needs you state | verified, per submitted job only | job status `"blocked"` on `approval-required` (`codex.ts:568-574`, `codex.ts:831`) |
| Needs you as a passive, durable per-task list attribute | inferred | the `blocked` status lives on a turn job; retaining it per task for rail badges after the job resolves is store behavior that must be built, not a bridge attribute |
| Latest instruction + result text, per-task history | verified | `CodexTurnRecord`, `GET /codex/tasks/:id/history` (`src/bridge/index.ts:510`) |
| Turn timestamps; elapsed time | verified / inferred | `startedAt`/`completedAt`/`durationMs` exist; a live elapsed ticker is derived from `sentAt`, not provided |
| Steer vs Queue delivery mode with confirmed outcome | verified | `CodexMessageMode`, `CodexTurnDelivery` (`CodexLane.swift:43-55`, `193-213`) |
| `Last heard from` Mac | verified with caveat | `BridgeManager.lastSuccessfulContactAt` is last-successful-request bookkeeping on the iOS side, not a Mac-pushed heartbeat |
| `Mac unavailable` as an affirmative state | inferred | the deck can only observe failed requests plus last successful contact; between polls it cannot distinguish an idle Mac from an unreachable one |
| Stop control on active work | **rejected** | the deck Stop key calls `interruptNarration` (TTS only); the bridge route list (`src/bridge/index.ts:489-520`) has no turn-stop or cancel endpoint. The Mac detects externally interrupted turns (`turn-interrupted`) but iOS cannot initiate one |

## 1. The idea that must survive

**The pinned, persistent Needs-you event that outranks Working and survives task switching** — Designs 3 and 4, and the rail attention marks in Designs 1 and 2.

This is Grok's genuine contribution beyond the briefs. The briefs require "Needs you outranks Working"; Grok turns that into a concrete retention rule: an unresolved question stays pinned in the Now region (or a pinned strip) even when newer Working events arrive on other tasks, and the rail mark persists across selection changes. That rule is:

- supported by real data: `approval-required` → `blocked` is a verified bridge state, so pinning is truthful, not decorative;
- the differentiating failure of the current capture, which buries attention behind a `CODEX> READY` console;
- portable: it can be adopted by the Fixed Command Desk without adopting the timeline, which is exactly what a Round 3 synthesis should do.

The probe review in `IPAD-MODEL-FLIGHT.md` independently reached the same conclusion ("The Flight Recorder contains the strongest attention pattern"). Two independent reads make this the portfolio's load-bearing idea.

## 2. The assumption that must be rejected

**`[ Stop ]` as an explicit control on active work and Needs-you states.**

Grok draws `[ Stop ]` in the Needs-you treatments of Designs 1, 2, and 3, and "approve/deny-style controls" in Design 4, while its own data table hedges with "Stop only when supported — Existing stop semantics." The hedge is wrong as written: Stop is **not supported** for turns. The verified boundary gives the deck exactly one stop — `interruptNarration`, which silences TTS playback. There is no bridge endpoint to cancel or interrupt an in-flight Codex turn; interruptions on the Mac are only detected after the fact (`turn-interrupted`).

This is not a nitpick. The shared brief's rule is "Put Stop beside active work **only when Stop is supported**," and both rubrics reject designs that make consequential actions implicit or invent capability. A drawn Stop button is worse than an implicit action: it promises a consequential control that will dead-end or, worse, get wired to narration-stop and silently do nothing to the turn. That is a safety defect wearing a safety costume.

What survives the rejection: approve/deny controls for `approval-required` are legitimate in principle (the bridge emits the code), but the labels must follow whatever the approval payload actually carries, not Grok's illustrative `[ Update connection ] / [ Keep current ]`. Mark those labels **proposed** until the approval payload shape is confirmed. Stop must come out of all four designs now.

Secondary rejection, smaller: `Last heard from · 2 minutes ago` must be presented as *last successful contact*, and the Mac-unavailable state must acknowledge it is inferred from failed requests, not observed. The copy Grok uses is close to honest; the state trigger is not as solid as the confidence of the layout suggests.

## 3. Interaction / voice-targeting risk

**The dual-tap selection model in Design 4 (Cross-Task Chronicle) — and its quieter cousin in Design 3.**

Grok specifies: tapping a lane header or *empty lane space* retargets Talk; tapping an event opens the inspector without retargeting. Two tap targets with different voice consequences share one canvas, separated only by whether the finger lands on a marker or beside it. For the near-technical user the brief defines, the mental model will be "I tapped that task's event, so I'm talking to that task." The design says the opposite.

The mitigations Grok lists — a destination label in the inspector and the named master voice rail — are labels, not guards. They tell the user where voice goes; they do nothing about the mis-tap that changed it. The Flight Recorder brief's rule ("selecting an event may select its task only when the change is explicit") is satisfied on paper by the word "explicit," but empty-lane-space-as-selection is not an explicit gesture; it is the canvas's dead area doing consequential work.

Design 3 has the same shape in milder form: event tap opens detail, rail tap retargets. There the targets are at least in separate zones, so the risk is lower — but the event-detail surface still needs an affirmative, unambiguous path when the user *does* want to retarget from an event.

## 4. iPad composition / adaptation risk

**Design 2 (Operational Folio) orphans Talk in portrait.**

Grok's portrait adaptation is a pager between a task page and an evidence page, with "Talk only on the task page." That violates the shared brief twice over: portrait must "keep the main pane and Talk control primary," and "do not allow long content to move the Talk control out of reach." A pager that puts Talk on one of two pages means that half the user's reading time — long History, changed files, details, the exact content the folio exists to make readable — happens with the voice control absent. The user reads a long result on the evidence page, wants to speak the follow-up, and must swipe back first. The folio's core win (serious evidence reading) is precisely where Talk disappears.

Grok scored Folio's adaptation 7.5 and flagged the pager as a "slight" risk. It is not slight; it inverts the brief's portability rule for the one control that must never move. Landscape focus mode keeps Talk ("left page + Talk stay"), which makes the portrait regression look unexamined rather than deliberate.

Runner-up risk, noted but not the pick: Design 1's three-zone geometry at compact Stage Manager width. Grok says "collapse evidence first," but the rail plus live surface plus inspector at ~22/53/25 proportions has no stated breakpoint behavior, and the brief demands task, state, result, and Talk survive compaction. This is unspecified rather than wrong, so it stays a revision item, not the headline risk.

## 5. One concrete revision per structure

### Design 1 — Fixed Command Desk

Remove `[ Stop ]` from the Needs-you and Working treatments, and adopt the Flight Recorder's pinned Needs-you strip at the top of the live surface: when any task on the selected Mac has an unresolved `blocked` job, a pinned banner names that task and its question until resolved, even while the user views another task. The desk's weakness is that its attention model lives only in the rail; a rail badge is easy to miss once the user is reading the live surface. The pinned strip fixes that with verified data and no new zones. Also relabel the failure copy to "Last successful contact · …" to match what the store actually knows.

### Design 2 — Operational Folio

Anchor the voice shelf **below the pager, not inside the task page**, in portrait and compact widths: the pager swaps task page and evidence page above a fixed shelf that never paginates. Talk then survives evidence reading, which is the folio's reason to exist. Remove Stop. If the shelf cannot be made page-independent, the portrait pager must be replaced by a bottom drawer over a persistent task page — pick one; "Talk only on the task page" is not an acceptable third option.

### Design 3 — Selected-Task Tape

Make event selection mechanically incapable of retargeting voice: event tap opens detail only, task change happens only in the rail, and event detail for another task's event gets one explicit "Talk to this task" action that visibly rebinds the master rail. Then put the verified `commentary`/`tool` progress strings to work as the live Working event text (Grok gestures at this but doesn't commit; the data is real and already rendered in the current console, so the tape should own it). Remove Stop.

### Design 4 — Cross-Task Chronicle

Remove empty-lane-space as a selection gesture; lane selection happens only on the lane header (name row), event tap opens the inspector only, and retargeting from the inspector requires the same explicit "Talk to this task" action as Design 3. Replace the spatial time axis with an **ordinal** axis: verified timestamps exist per turn, but cross-task alignment precision invites Gantt-reading the brief forbids, and ordering by known sequence with human relative times ("just now", "earlier") carries the same comprehension at lower density risk. Move Needs-you out of the lanes into a persistent pinned strip above the canvas, so the one thing this design is for — fleet attention — does not depend on marker scanning. Remove Stop.

## 6. Strongest and weakest structure after revision

**Strongest: Design 1, Fixed Command Desk — with conditions.**

Grok's ranking holds, but for a sharper reason than its 8.75 self-score suggests. The desk is the only structure whose entire data diet is verified: task identity, latest exchange, Working activity strings, Steer/Queue consequence, last-contact time. Every one of its first-glance answers maps to a field that exists today. Its geometry is the most direct reading of the shared brief's two-pane-plus-contextual-edge thesis, and its failure mode (inspector bloat) is a discipline problem, not a data problem. With Stop removed and the pinned Needs-you strip adopted from the Flight Recorder, it also covers the attention model that was the recorder's edge. Grok's 9.0 on state and failure behavior is inflated — the Stop invention sits inside that criterion — but the structure absorbs the correction without redesign, which is exactly what "strongest" should mean.

**Weakest: Design 4, Cross-Task Chronicle — and it should not advance.**

Also agreeing with Grok's ranking, but the verdict should be firmer than "wildcard only." After revision its differentiating value collapses: the fleet attention scan, once moved to a pinned strip, is no longer a swimlane property — Designs 1 and 3 carry it equally well with a single selection model. What remains uniquely Chronicle's is the comparative time axis, which is the part with the highest dashboard risk, the weakest instrument identity (Grok's own 6.5), the dual-tap voice hazard, and the least verified payoff. A structure whose best idea survives transplantation and whose remainder is its risk has done its job as a wildcard: it contributed the attention model and the rejection case. Keep it in the record; do not invest a visual study in it. Grok's image-study nomination logic already concludes this; this review makes it explicit.

Middle order after revision: Design 3 edges Design 2 if — and only if — the folio's Talk-orphaning pager is fixed, because the tape's voice safety story is verified-data-clean while the folio's evidence-reading advantage is real but its portrait story is currently broken. If the folio revision lands, the order flips back to Grok's 2-over-3.

## Scoring adjustments

Grok's self-scores, corrected for the verified boundary:

| Design | Criterion corrected | Grok | Kimi | Reason |
|---|---|---:|---:|---|
| 1 Desk | State and failure behavior (15%) | 9.0 | 7.5 | Stop drawn but unsupported; failure trigger is inferred, presented as observed |
| 2 Folio | Adaptation and accessibility (10%) | 7.5 | 6.0 | Portrait pager orphans Talk; violates two explicit brief rules |
| 3 Tape | Temporal comprehension (20%) | 9.0 | 8.5 | Sound; Working event should commit to verified progress strings |
| 4 Chronicle | Voice destination safety (20%) | 7.5 | 6.0 | Dual-tap retargeting; labels are not guards |

Corrected native totals: Desk ≈ 8.53, Folio ≈ 8.51, Tape ≈ 8.38, Chronicle ≈ 7.25. The ranking is unchanged; the margins are thinner than Grok reports, and the top two are effectively tied until the Folio Talk revision is tested.

## What this review does not claim

- No Swift or implementation guidance; probes remain composition tests only.
- Approval-control labels (`Update connection`, `Keep current`) are **proposed** pending confirmation of the `approval-required` payload shape; the approval mechanism itself is verified to exist.
- The inferred items (passive per-task Needs-you, affirmative Mac-unavailable, elapsed ticker) are buildable and worth building; they are flagged so Round 3 does not treat them as free.

*End of Round 2 review — Kimi on Grok*
