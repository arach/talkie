# Round 2 — Claude Opus critiques Kimi

**Reviewer:** Claude Opus, acting as an adversarial but constructive iPad design
reviewer
**Date:** 2026-08-01
**Track:** Model flight, Round 2 (Cross-examine)
**Portfolio under review:** `model-flight/round-1-kimi.md`
**Contracts:** `IPAD-DESIGN-BRIEF.md`, `IPAD-BRIEF-WORKBENCH.md`,
`IPAD-BRIEF-FLIGHT-RECORDER.md`
**Mode:** Words only. No application code was modified.

---

## Evidence key

Every claim below is tagged.

- **Verified** — read directly from the current implementation at the cited
  `file:line`.
- **Inferred** — derived from verified code plus the brief's stated reference
  device. The arithmetic is mine.
- **Proposed** — my recommendation. Not present today.

---

## Verified data boundary

I tested Kimi's portfolio against the real bridge rather than against Kimi's
data inventory. The inventory is wrong in three places, and the errors do not
point the same direction.

| Kimi's claim | Verdict | Evidence |
|---|---|---|
| Per-task state "sufficient to express Idle, Working, Needs you" is current data | **Rejected** | No state field exists. `CodexTaskSummary` carries `id`, `title`, `preview`, `cwd`, `project`, `gitBranch`, `gitOriginURL`, `updatedAt` and nothing else — `Codex/CodexLane.swift:58`. Verified. |
| Per-event timestamps are *proposed* | **Under-claimed — they exist** | `CodexChannelHistory.Turn` has `startedAt`, `completedAt`, `durationMs`; `Update` has `timestamp` — `Codex/CodexChannelHistory.swift:16`, `:40`. Sourced from `readTurnActivity` — `codex-desktop-bridge.cjs:527`, reachable via `codexTaskHistory(taskId:)` — `Bridge/BridgeClient.swift:409`. Verified. |
| "Last heard from" is *proposed* | **Under-claimed — it exists** | `BridgeManager.lastSuccessfulContactAt` — `Bridge/BridgeManager.swift:155`. Cleared only on pending-pairing and unpair (`:545`, `:843`), so it survives an ordinary disconnect. Verified. |
| Needs you supports Approve / Deny on iPad | **Rejected** | The bridge *refuses* approval by design: it answers a Codex app-server request with `approval-required` and "Talkie cannot approve Codex server requests" — `codex-desktop-bridge.cjs:1083–1095`. The recovery hint is "Open this task in Codex Desktop to review the approval request" — `routes/codex.ts:134`. Verified. |

Two further constraints no design accounts for:

- **State is device-local and dispatch-scoped.** Task activity lives in
  `liveActivitiesByLane` and `liveActivitiesByDirectKey` —
  `Codex/CodexLaneStore.swift:57–61` — populated only when *this device*
  dispatches a turn. `CodexLaneActivityState` is `working` / `accepted` /
  `receiving` / `failed` — `Codex/CodexLaneActivity.swift:10–15`. There is no
  `needsYou` case anywhere in the model. Verified.
- **Content is capped.** The bridge truncates to `instructions.slice(-4)` and
  `updates.slice(-12)` — `codex-desktop-bridge.cjs`, `finishTurn`. iOS holds
  `historyLimit = 20` and `liveActivityLimit = 6` —
  `Codex/CodexLaneStore.swift:44–45`. Lanes are capped at six —
  `Codex/CodexLane.swift:220`. Verified.

In fairness to Kimi: dispatched turns *are* durable. `CodexPendingTurn.Store`
persists them across launches — `Codex/CodexLaneStore.swift`, `init`. The
device-local state is reliable. It is simply not fleet-wide.

---

## 1. The idea that must survive

**The pinned Needs-you event with a visible suspension label — Design 3.**

Kimi pins an unresolved Needs-you event above newer Working and Result events
and marks it "Pinned — waiting for you" so chronology is *visibly and honestly*
suspended.

This is the only element in the portfolio that resolves a genuine conflict
rather than decorating one. Both briefs require that Needs you outrank Working
and that new events not push an unresolved question out of awareness. Every
design that expresses attention through color alone loses that fight the moment
newer content arrives — the loud thing scrolls away and the quiet thing stays.
Reordering fixes it but lies about time. The label is what makes reordering
truthful.

It must survive for a second reason the other designs do not enjoy: **it is the
only Needs-you treatment that still works at the current data boundary.** Kimi's
Approve / Deny controls do not survive first contact with
`codex-desktop-bridge.cjs:1083` (Verified). The pin does. A blocked job carries
no question text, but it carries a task, a time, and a fact — and "This turn is
waiting for approval in Codex Desktop, since 12:04 PM" is a complete, honest,
pinnable event. The mechanism degrades; the buttons do not.

Port it into whichever structure wins. It is a rule about ordering, not a
property of a timeline.

---

## 2. The assumption that must be rejected

**That every task row can carry a truthful state word.**

All four designs put "one human state word" on every task in the rail, spine, or
column. Design 1's rail, Design 2's spine, Design 3's peripheral rail, and
Design 4's task column all assume it. It is the load-bearing assumption of the
portfolio and it is not supported.

The catalog has no state (Verified — `Codex/CodexLane.swift:58`). State exists
only where this iPad dispatched the turn (Verified —
`Codex/CodexLaneStore.swift:57–61`). So a task the user started by typing on the
Mac, or by speaking into the iPhone, renders on the iPad as **Idle while it is
actively working**. That is not a missing feature. It is the interface asserting
something false in its calmest voice, in six rows at once.

Kimi does flag open decision #5, but frames it as a *resolution* problem — "the
Working versus Needs-you distinction must be verified." The real problem is
*existence and scope*: there is no task state at all for any task this device did
not touch. That is a materially larger and more expensive finding, and the two
framings lead to different designs.

Note the asymmetry in Kimi's inventory. Timestamps and last-heard were marked
proposed when both are verified present; state was marked current when it is
absent. Kimi was conservative in the two places it cost them nothing and
optimistic in the one place that decides the field. The net effect is that the
Tape was scored *down* for a dependency it does not have, and the Chronicle was
scored *up* for a dependency it cannot satisfy.

**Proposed correction.** State words must be sourced, not asserted. Two honest
options:

1. Show a state word only where Talkie has first-hand evidence, and show
   **recency** everywhere else. `updatedAt` is already on every catalog row and
   already refreshes on a 15-second cadence (Verified —
   `Codex/CodexLaneStore.swift:41`, `refreshCatalog`). "Codex last wrote 4m ago"
   is truthful, useful, and free.
2. Poll per-task activity to synthesize real state — which is a bridge cost, not
   a label. See §5, Design 4.

Either way, the rail's vocabulary needs a third term the briefs do not yet
have: **Unknown**, or its honest cousin, plain recency. An interface that cannot
say "I do not know" cannot be trusted when it says "Idle."

One adjacent note: the catalog refresh loop runs only while a viewer is on
screen — `beginCatalogUpdates` is called from `CodexLaneMapperView` and
`CodexNewTaskView` only, never from the deck (Verified —
`Codex/CodexLaneMapperView.swift:43`, `Codex/CodexNewTaskView.swift:75`). Every
design in this portfolio shows a persistent task list on the primary surface. All
four therefore require a refresh loop the deck does not currently run. Small,
but it belongs in the required-data list and is in none of them.

---

## 3. Interaction and voice-targeting risk

**Design 4's most attention-grabbing element leads directly into its most
dangerous state.**

Kimi identifies the dual-highlight hazard and mitigates it with rail text —
"Inspecting: Fix watchOS handoff regression · Talk → Improve iOS connection
manager." Naming both facts is correct. It is not sufficient, and the reason is
structural rather than a matter of tuning.

Trace the intended path. The Needs-you treatment is deliberately the loudest
thing on the canvas: an extended-height marker breaking the lane grid, spanning
into the gutter, pinned at the Now edge, in a reserved attention color. Its
entire job is to recruit the eye and the finger. The user taps it — as designed.
The inspector opens with the full question and Approve / Deny. Talk is still
bound to whatever task was selected before.

So the loudest affordance on screen routes the user into the one state where
misdirected voice is most likely and most consequential, and the defense is a
two-line text label competing against a treatment engineered to overpower
everything around it. Kimi's "Select this task" control in the inspector is the
right instinct but is offered as an option. At that moment it should not be
optional.

**Proposed rule.** A Needs-you pin is not inspectable without a selection
decision. Tapping it either selects its task outright, or opens with the Approve
path visibly inert and one control — "Select this task to respond" — as the only
way forward. Attention and destination must move together, or the attention
model is a targeting hazard.

**Portfolio-wide corollary — absent from all four designs.** None of the four
states what happens when task selection changes *during* an open voice capture.
The machinery for this collision exists: `CodexLanePhase.isCapturing` and the
push-to-talk hold are both live (Verified — `Codex/CodexLane.swift:301–312`).
On a 1180-point landscape iPad the rail and the Talk control are comfortably a
two-handed reach apart (Inferred), which makes a thumb-on-Talk / finger-on-rail
collision reachable rather than theoretical. Design 3 makes it most likely by
promising the rail re-binds "instantly, its helper text updating in place" —
instant re-binding during capture is exactly the wrong behavior. The rule should
be stated once and shared: **selection locks from the moment capture begins
until dispatch or cancel.** A rail tap during capture queues the switch and
applies it after; it never redirects speech already in flight.

---

## 4. iPad composition and adaptation risk

**The Operational Folio's thesis exists only in landscape.**

Kimi's own portrait adaptation reads: "Focus mode disappears in portrait — the
drawer *is* the reading state." Combined with the spine collapsing to a top
switcher and the Evidence page becoming a paged drawer, the portrait Folio is
the portrait Desk. The two-page joinery, the shared baseline grid, the spine
metaphor, and the focus choreography — every element that distinguishes the
Folio — are gone.

That matters because the Folio also carries, by Kimi's own accounting, "the
highest layout-engineering cost of the four: two pages, one focus state, and
three adaptations per module." The design pays its full cost in every
orientation and delivers its differentiation in one. The shared brief treats
landscape as the *reference* composition, not the only one that has to carry the
design's value.

Two supporting defects:

**The spine is too narrow to survive Dynamic Type.** At 14% of an iPad Air 5
landscape width, the spine is about 165 points before padding (Inferred — iPad
Air 5 landscape is 1180 × 820 pt; 0.14 × 1180 ≈ 165). "Improve iOS connection
manager" plus a state word, at an accessibility text size, in ~145 points of
usable width, wraps to four or more lines per row. Six tasks becomes a wall of
wrapped text. The shared brief requires Dynamic Type to preserve the task title,
and the Folio's own adaptation section forbids reducing names. The spine cannot
satisfy both at 14%. Design 1's 22% rail (≈260 pt) can. Design 4's 18% column
(≈212 pt) is marginal.

**The image study has partially run and came back negative.** Kimi nominates the
Folio on the grounds that its joinery is the one genuinely undecidable question.
The reasoning is good — but `IPAD-MODEL-FLIGHT.md` already records Probe 2's
verdict: "The image does not yet prove the folio thesis because the result still
reads as a polished three-column application. The Talk control is also too large
for an idle state" (Verified — `IPAD-MODEL-FLIGHT.md:105–110`). Kimi wrote
independently and before the probes, so this is not an error on their part. It
is new evidence that arrived after their nomination and it points against the
folio reading. A second study should test the *revised* Folio in §5, not the
one nominated.

---

## 5. One concrete revision per design

### Design 1 — Fixed Command Desk → bind the third column to a turn, not a task

Kimi's named risk is that the inspector becomes a junk drawer, and their remedy
is that "evidence must stay attached to the selected task and collapse before it
competes — a rule the team has to keep enforcing, not a property the layout
guarantees." Correct diagnosis, and a critique should not leave it there. A rule
that depends on enforcement will be broken by the fourth feature that wants a
home.

**Revision (Proposed).** Rename it the **Turn inspector** and bind it to one
turn rather than to the task. It renders exactly what belongs to the exchange
currently visible in the live-work surface: that turn's instruction, its
timestamped update stream, its result, its duration, its provenance. It has no
task-level region at all.

This converts junk-drawer growth from a discipline problem into a type error.
Mapper, Spaces, Refresh, and settings are not properties of a turn, so there is
nowhere to put them. It also gives the third column an actual justification on a
1180-point screen: it stops being "more things" and becomes "the same exchange,
in depth," which is the only argument a persistent third zone has ever had.

The data supports it exactly. `CodexChannelHistory.Turn` already carries
`startedAt`, `completedAt`, `durationMs`, `instructions`, `updates`, `response`,
`error`, and `status` (Verified — `Codex/CodexChannelHistory.swift:13–33`). The
inspector is a rendering of a type that already exists.

### Design 2 — Operational Folio → delete focus mode, fix the reading column

Focus mode is (a) the most expensive element, (b) Kimi's own named strongest
risk, (c) the thing that vanishes in portrait, and (d) by Kimi's own framing a
second navigation system layered on top of task selection. Meanwhile every
advantage the Folio claims over the Desk comes from having a *permanent reading
surface*, not from the ability to expand modules.

**Revision (Proposed).** Remove focus mode entirely. Fix the right page as one
permanently expanded reading column: the full latest result, always rendered for
reading, with Hear and Copy. History becomes a slim dated spine of turn
selectors down its leading edge — selecting a turn changes what the column
reads, and nothing moves. Details becomes a footer strip. No expansion, no
return gesture, no compressed task strip, no choreography.

Widen the binding rail from 14% to at least 20% and state the Dynamic Type floor
explicitly.

This version survives portrait without losing its identity — the reading column
becomes the drawer's default page, the same thing in a different frame — and it
collapses cleanly under Stage Manager. It also keeps the one property that
genuinely distinguishes the Folio from the Desk: the latest result never
requires a sheet.

Note the consequence honestly: after this revision and the Design 1 revision,
the two Workbench designs differ in exactly one decision — whether the third
column shows *turn evidence* or *the result rendered for reading*. See §6.

### Design 3 — Selected-Task Tape → move the chronology inside the active turn

Kimi names the right risk: "if a user reads the top entry and gets exactly what
a conventional conversation view gives them, the tape is decoration." Their tape
is vulnerable to precisely that, because its chronology sits *between* turns —
Asked → Working → Result — which is the ordering a conversation view already
implies. Time between turns is not information a user lacks.

**Revision (Proposed).** Default the tape to one turn, expanded, with prior
turns collapsed into a compact dated ledger beneath. Put the bridge's real
update stream *inside* the current turn, timestamped:

```
12:09  Asked — "Make connection recovery clear on iPad."
12:09  Working                                       4 min 12 s
       12:09  Reviewing bridge discovery and saved ports
       12:11  Edited NearbyMacBrowser.swift
       12:12  Ran the iOS test target
```

That is where the tape beats every other structure, and it is where the data is
actually rich. The updates come from `agent_message` commentary,
`patch_apply_end`, and `mcp_tool_call_end` records in the rollout (Verified —
`codex-desktop-bridge.cjs:630–650`), each with a timestamp (Verified —
`Codex/CodexChannelHistory.swift:40`), capped by the bridge at twelve per turn.
Twelve timestamped, truthful steps is a real temporal object. No conversation
view shows it. It directly answers the brief's hardest question — "What is Codex
doing, and does it need me?" — with evidence rather than a spinner.

Design against the caps rather than around them: four instructions and twelve
updates per turn from the bridge; twenty turns and six live activities on the
device (Verified). The ledger below the active turn should show turn count and
age honestly rather than implying unbounded history.

### Design 4 — Cross-Task Chronicle → remove the time axis and the inspector

The Chronicle's unique contribution is a shared time axis across tasks. That
feature is simultaneously the most expensive, the least supported by data, and
the least necessary.

Cost, verified: a cross-task canvas needs per-task activity, and per-task
activity means `readTurnActivity` per task — each call opening the task's
rollout file and scanning up to 32 MB (`maximumScan = 32 * 1024 * 1024` —
`codex-desktop-bridge.cjs:529`). Six lanes on a polling cadence is six 32 MB
file scans per refresh on the Mac. Today that call is a one-shot, per-task,
sheet-triggered fetch (Verified — `Codex/CodexChannelHistorySheet.swift:318` is
its only caller). The Chronicle turns it into a continuous fleet-wide loop.

Necessity: the catalog already gives `updatedAt` per task, for free, on the
existing 15-second cadence (Verified). Recency ordering plus attention marks
answers "which task deserves me next" — the Chronicle's stated purpose — using
data Talkie already has. The time axis answers it no better.

**Revision (Proposed).** Demote the Chronicle from a surface to a component.
Replace the shared time axis with a fleet strip that has no time axis at all:
named tasks ordered by recency, attention marks for anything blocked, "last
heard" per Mac, and nothing else. Delete event inspection from the fleet view
entirely — tapping anything selects that task and takes the user to the primary
surface. One highlight, one gesture, one meaning, and the dual-highlight
targeting hazard in §3 disappears rather than being labeled around.

State the consequence plainly: this revision deletes the Chronicle's thesis.
That is the finding, not a side effect. If the panel wants to keep it as a
surface, the minimum safe version has no inspector and no per-lane event markers
— at which point it is a sorted list with a horizontal axis it does not use.

---

## 6. Strongest and weakest after revision

### Strongest — revised Design 1, the Fixed Command Desk with a Turn inspector

It wins the two heaviest rubric criteria outright — four first-glance answers at
25% and task-and-voice clarity at 20%, 45% combined — with the lowest cognitive
load and one selection model. It is the only structure whose *value*, not merely
its content, is unchanged in portrait and under Stage Manager. And its named
weakness is the only one in the portfolio that a structural rule can eliminate:
bind the third column to a turn and the junk drawer becomes impossible. The
other three designs' named weaknesses — focus mode as a second navigation
system, chronology as decoration, dashboard gravity — are properties of their
theses, not fixable details.

It should adopt two things it did not originate: the Tape's in-turn update
stream as its live-work content (§5, Design 3) and the Tape's pinned Needs-you
event as its attention rule (§1).

I am revising my own Round 1 position, which ranked the Selected-Task Tape
first. The verified finding that changed it: the Tape's real payload is the
in-turn timestamped update stream, and that payload is fully portable into the
Desk's live-work surface without the tape structure. Once the payload moves, the
tape's remaining contribution is the ordering of turns — which a conversation
view already gives. The panel should discount my agreement with Kimi's ranking
accordingly: we arrive at the same first place from opposite directions, and
that is weaker evidence than it looks.

### Weakest — Design 4, the Cross-Task Chronicle

It is weakest not because it scores lowest but because it does not survive
revision as a surface. The revision that makes it safe and affordable removes
the shared time axis and the event inspector, which is everything that made it a
chronicle. Kimi reaches a nearby conclusion — "it should survive as an attention
model, not as the primary surface" — and I would go one step further: the
attention pattern worth keeping is the *Tape's* pin, not the Chronicle's
lane-breaking marker. The Chronicle's own contributions are the shared time axis
and the dual-highlight model, and both are liabilities.

### The finding that matters most for Round 3

**This is not a field of four structures. It is a field of two, and the
remaining disagreement is about where the update stream lives.**

After the §5 revisions, Design 1 and Design 2 differ only in whether the third
column shows turn evidence or the result rendered for reading. Design 3 becomes
Design 1's live-work surface with a different scroll model. Design 4 becomes a
component of any of them. The genuine open questions Round 3 should decide are
narrower and more answerable than four compositions:

1. Does the third column read the *result* or inspect the *turn*? Both are
   supported by current data. Only one should be built first.
2. Does the update stream live inline in the live-work surface (Tape) or in the
   third column (Desk)? This is the actual structural disagreement in the
   portfolio.
3. What does a task row say when Talkie does not know the task's state? This is
   the unresolved question, it blocks all four designs equally, and no portfolio
   in Round 1 has answered it.

Question 3 should be settled before any prototype. Everything else in this
review is a composition preference. That one is a truthfulness requirement, and
the current bridge cannot satisfy it as any of the four designs assume.

---

*Reviewer's note: Kimi's portfolio is internally disciplined and its self-stated
risks are, in every case, the correct risks. Three of the four named risks are
things I would have raised had they not. The critique above is mostly about the
data boundary — where Kimi reasoned from the briefs, and the briefs are quieter
about the bridge than the bridge is.*
