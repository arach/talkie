# Round 1 portfolio — Kimi

**Designer:** Kimi, acting as an independent iPad product designer
**Date:** 2026-08-01
**Track:** Model flight, Round 1 (Diverge)
**Sources:** `IPAD-DESIGN-BRIEF.md`, `IPAD-BRIEF-WORKBENCH.md`,
`IPAD-BRIEF-FLIGHT-RECORDER.md`, physical-device capture
`ipad-current-view.png`
**Mode:** Words and composition only. No Swift, no TypeScript, no application
code changes.

---

## Shared ground

All four designs use the same content so the panel compares structure, not
copy:

- **Selected task:** Improve iOS connection manager
- **Project:** talkie
- **Branch:** `codex/automatic-screen-preview` (monospaced, quiet)
- **Mac:** Arachs-Mac-Mini.Local
- **Latest user instruction:** "Make connection recovery clear on iPad."
- **Working activity:** "Reviewing bridge discovery and saved ports."
- **Result excerpt:** "The connection flow now separates retry, edit, and
  remove so a stale Mac does not block the rest of Talkie."
- **Needs-you prompt:** "The saved Mac answers on a different port. Update
  this connection?"

Additional named tasks for fleet and chronicle density (illustrative):

- Rebuild tray clip thumbnails — Working
- Draft App Store preview copy — Idle, has result
- Fix watchOS handoff regression — Needs you
- Add Whisper fallback for long memos — Idle
- Audit Liquid Glass adoption — Idle, no result yet
- Ship tmp-janitor launchd job — Working

All four designs use the Porcelain treatment: cool blue-white chassis, deep
navy work surface, cobalt as the single selected/live signal, one attention
treatment for Needs you, one cold failure treatment for Mac unavailable,
human-readable sans for task and result content, monospaced type only for
branch, path, lane, and time provenance.

All four designs hold one rule absolutely: **voice always goes to one
explicitly selected task, and the Talk helper names its consequence before
capture.** No design infers approvals, destructive actions, or delivery-mode
changes from speech.

The current capture's failure mode — the largest surface holding the least
useful information, and a permanent 4-by-4 keybed giving setup and playback
the same weight as Talk — is the anti-pattern all four designs are measured
against.

---

## Design 1 — Fixed Command Desk

*Track: Task Workbench, Design A*

### Landscape topology

Three fixed vertical zones with one horizontal shelf:

- **Task rail (leading, ~22% width):** porcelain. At top, the Mac identity
  "Arachs-Mac-Mini.Local" with one quiet health line ("Connected"). Below, a
  scrollable list of named tasks, each row showing the task name, one human
  state word, the project as secondary, and an optional lane number as
  tertiary monospaced metadata. A single "All tasks" entry at the rail's
  bottom opens the existing task browse/lane-mapping flow.
- **Live-work surface (center, ~52% width):** deep navy. Task header (title,
  state word, Mac + project identity, quiet branch), then the exchange area.
- **Evidence inspector (trailing, ~26% width):** porcelain, persistent. Its
  content is bound to the selected task and changes with selection; it never
  covers the live-work surface.
- **Voice shelf:** full width of the live-work surface only, anchored to its
  bottom edge. It visually belongs to the center zone, not to the whole
  screen — the shelf's cobalt capture key sits directly beneath the
  conversation it addresses.

Geometry is identical across Idle, Working, Needs you, and Mac unavailable.
Only content changes.

### Focal surface

The center live-work surface. In Idle it shows the user's latest instruction
("Make connection recovery clear on iPad.") above Codex's result excerpt, with
Hear and Copy attached to the result. The surface always contains one current
truth; there is no empty-plate state.

### Task selection

One selection model: tap a task in the rail. The selected row carries the
cobalt selection signal. No lane ribbon, no previous/next stepping keys. More
than six tasks scroll; a search field appears at the rail top only when the
list exceeds eight tasks.

### Voice destination

The Talk control lives only on the center shelf, bound to the selected task.
Helper text states the consequence before capture: "Hold to continue this
task" when idle, "Hold to steer this turn" or "Hold to queue a follow-up"
while working per the existing delivery mode, "Hold to answer" when Codex
asks something voice can answer. The existing hold gesture, slide-to-cancel,
capture perimeter, and haptics are preserved unchanged.

### Latest-result treatment

The result is the default idle content, rendered as readable prose with the
user's instruction above it for context. Hear and Copy sit on the result card.
"History" lives in the task header and opens the full reading surface. A long
result shows a two-to-four-line excerpt with "Read in full"; the excerpt never
pushes Talk out of reach because the exchange area scrolls independently of
the shelf.

### Needs you treatment

The question becomes the top of the live-work surface, set larger than result
prose, with the attention treatment reserved for this state: "The saved Mac
answers on a different port. Update this connection?" Below it, explicit
Approve and Deny controls (consequential actions are never voice-inferred),
plus the voice shelf reading "Hold to answer." The task rail row for that
task carries the attention mark so it survives task switching. Needs you is
visually louder than Working everywhere it appears.

### Mac failure treatment

The failure owns the task rail header and a banner across the top of the
live-work surface: "Mac unavailable — Arachs-Mac-Mini.Local. Last heard from
12:04 PM." The last-known exchange stays visible underneath, explicitly
marked "Last known, 14 minutes ago" so stale content is never presented as
current. Talk is disabled with "Talk unavailable while the Mac is offline."
Reconnect, Review connection, and Choose another Mac appear on the banner
itself. The inspector dims to its last-known content.

### Portrait adaptation

The task rail collapses to a compact vertical strip of named tasks (title +
state, no provenance) that can hide behind a single task-switcher button in
the header. The evidence inspector becomes a bottom drawer over the live-work
surface, summoned from the task header. The live-work surface and voice
shelf keep their relationship and dominate the layout. In compact Stage
Manager widths the inspector is the first thing to collapse; provenance
collapses before task content; task title, state, latest result, and Talk
remain.

### Strongest risk

**The inspector becomes a junk drawer.** A persistent third zone invites
every future feature to claim permanent residency, slowly reassembling the
keybed in a new shape. The discipline that saves this design — evidence must
stay attached to the selected task and collapse before it competes — is a
rule the team has to keep enforcing, not a property the layout guarantees.

---

## Design 2 — Operational Folio

*Track: Task Workbench, Design B*

### Landscape topology

Two "pages" joined as one open folio, bound by a compact task rail:

- **Binding rail (leading edge, ~14% width):** porcelain. A narrow column of
  named tasks — title and state word only, vertically stacked — plus the Mac
  identity at top. Narrower than the Desk's rail; it reads as the folio's
  spine, not a list pane. The same single selection model applies.
- **Left page — Task page (~46% width):** deep navy. The selected task's
  header, current state, latest instruction, and latest result or live
  activity. The voice shelf anchors this page's bottom.
- **Right page — Evidence page (~40% width):** porcelain with low-contrast
  folio rules. Three fixed modules stacked on a shared baseline grid:
  **History** (recent turns as dated rows), **Readout** (the latest result
  rendered for reading, with Hear and Copy), **Details** (branch, project,
  lane, changed-file count if the bridge reports it).

The two pages share a baseline grid and one gutter, so the composition reads
as a single open document, not a card collection. Any evidence module can
expand to a focused reading state that borrows the Task page's width; the
task header and voice shelf remain visible in a compressed strip at left, so
focus never costs the user their voice destination. One tap or an edge swipe
returns to the two-page spread. Modules are fixed in number and order —
there is no rearranging, no customization surface.

### Focal surface

The Task page. The Evidence page is deliberately quieter (porcelain, smaller
type) so the eye lands on navy first. In a focused reading state the focal
surface temporarily becomes the expanded module, with the compressed task
strip as a persistent reminder of where voice is bound.

### Task selection

Tap a task on the spine. Because the spine shows names and states at all
times on both pages and in focus mode, selection never becomes ambiguous.
Selection changes the content of both pages atomically — the folio always
shows exactly one task.

### Voice destination

Identical contract to the Desk: one shelf, bound to the selected task,
helper text naming continue / steer / queue / answer before capture. The
shelf survives module focus in compressed form. It never appears on the
Evidence page — evidence is read, not spoken to.

### Latest-result treatment

The result lives twice by design: as the working excerpt on the Task page
(the current truth), and as a fully readable document in the Readout module.
The excerpt is for glancing; the Readout is for reading. This is the Folio's
core claim — the Desk makes you open a sheet to read properly; the Folio
always has a reading surface open.

### Needs you treatment

The question takes over the Task page top with the attention treatment, and
the History module on the Evidence page pins the unresolved question event at
its top with the same treatment — the folio shows the question in both the
conversation and the record. Approve/Deny remain explicit controls beside the
question. The spine row carries the attention mark.

### Mac failure treatment

The spine header turns to the failure state ("Mac unavailable — last heard
12:04 PM"), a failure banner crosses the Task page, and the Evidence page
freezes: every module gets a "Last known" age stamp. Talk disabled with its
reason; recovery actions on the banner. Because the Evidence page is
porcelain and persistent, the frozen-record quality of a dead bridge reads
especially clearly here — the whole right page visibly stops being live.

### Portrait adaptation

The folio closes like a book: the Task page goes full width, the spine
becomes a compact switcher at top, and the Evidence page becomes a paged
lower drawer (History / Readout / Details as three swipeable pages of one
drawer). Focus mode disappears in portrait — the drawer *is* the reading
state. Voice shelf stays anchored to the Task page.

### Strongest risk

**Focus mode becomes a second navigation system.** The moment a module can
borrow width, the user must track "where am I in the folio" in addition to
"which task am I on." If focus entry, focus exit, and the compressed task
strip are not perfectly choreographed, this design fails its own brief —
module movement becoming work. It also has the highest layout-engineering
cost of the four: two pages, one focus state, and three adaptations per
module.

---

## Design 3 — Selected-Task Tape

*Track: Flight Recorder, Design A*

### Landscape topology

One dominant temporal tape for one task, with a peripheral task rail:

- **Peripheral rail (leading, ~20% width):** porcelain. Named tasks, each
  with a state word and a small latest-event marker (e.g., "Result 11:58 AM"
  or "Needs you"). This is awareness, not the main surface.
- **Time canvas (center and trailing, ~80% width):** deep navy, one vertical
  tape for the selected task, newest at top. Each entry is a readable event,
  not a dot:
  - **12:11 PM — Result** — "The connection flow now separates retry, edit,
    and remove so a stale Mac does not block the rest of Talkie." *(Hear,
    Copy)*
  - **12:09 PM — Working** — "Reviewing bridge discovery and saved ports."
    *(4 min)*
  - **12:09 PM — Asked** — "Make connection recovery clear on iPad."
  - Earlier turns recede below, dimmer with age.
- **Master voice rail:** a fixed band at the bottom of the time canvas,
  outside its scroll area, bound to the selected task with the standard
  helper text.

Only four event types exist: Asked, Working, Result, Needs you — plus the
Mac-unavailable connection event. No reasoning traces, no token counts, no
invented telemetry.

### Focal surface

The top of the tape — the most recent meaningful event. In Idle that is the
latest Result, shown in full readable form with its actions. The tape's
chronology is context; the present is the content.

### Task selection

Tap a task in the peripheral rail and the entire tape is replaced with that
task's tape. The voice rail does not move and re-binds instantly, its helper
text updating in place. Tapping an event inside the tape opens detail — it
does **not** change selection. The only way to change the voice destination
is the rail, so the mapping from intent to target is one gesture wide.

### Voice destination

One master voice rail, always at bottom, always bound to the rail-selected
task, helper text naming continue / steer / queue / answer. Scrolling deep
into the tape's history never affects it. A "Now" button appears the moment
the tape is scrolled away from its top; returning to Now is one tap and
never changes selection.

### Latest-result treatment

The latest result is the tape's top entry, rendered as full prose, not a
marker. This is the Tape's structural advantage over the Chronicle: there is
no event-icon layer to decode before you reach content. Older results remain
scrollable beneath, each with its own Hear and Copy.

### Needs you treatment

A Needs-you event **pins to the top of the tape until resolved**, above any
newer Working or Result events, with the attention treatment and a "Pinned —
waiting for you" note so chronology is visibly and honestly suspended. The
question shows in full with explicit Approve/Deny controls; the voice rail
reads "Hold to answer." The peripheral rail row carries the attention mark.
Newer background events stack beneath the pin, preserving true order without
displacing the question.

### Mac failure treatment

A connection event is inserted on the tape: "**12:04 PM — Mac unavailable —
Arachs-Mac-Mini.Local.** No new events since." Everything above the insertion
point (nothing, by construction) and the tape header switch to the failure
treatment; all prior entries get a collective "Last known before 12:04 PM"
stamp. The voice rail disables with its reason; recovery actions sit on the
connection event itself. Because the tape is a record, a dead bridge reads
naturally: the record simply stops.

### Portrait adaptation

The tape takes the full width. The peripheral rail compresses to a horizontal
strip of named task chips above the tape (names, never lane numbers), and the
voice rail stays fixed at bottom. In compact widths the event timestamps
collapse to relative ("4 min ago") before any content is cut.

### Strongest risk

**Chronology without comprehension payoff.** The tape must earn its time
axis: if a user reads the top entry and gets exactly what a conventional
conversation view gives them, the tape is decoration. The design succeeds
only if "what happened, in what order, on this task" is a question users
actually ask — the pinned Needs-you event and the natural Mac-failure record
are its best evidence that it is.

---

## Design 4 — Cross-Task Chronicle

*Track: Flight Recorder, Design B*

### Landscape topology

Aligned task swimlanes against one shared horizontal time axis:

- **Task column (leading, ~18% width):** porcelain. One named row per task —
  title and state word. This column is the lane header for each swimlane and
  the single selection surface.
- **Chronicle canvas (~82% width):** deep navy, time flowing left (past) to
  right (now), with a bold "Now" rule at the right edge. Each task's row is a
  swimlane carrying its meaningful events as short readable markers — e.g.,
  "Asked 12:09" → "Working" → "Result 12:11" — where tapping a marker
  reveals its excerpt. Dense stretches collapse to a count ("3 turns") that
  expands on tap.
- **Inspector (trailing overlay or push panel):** selecting any event opens a
  persistent inspector showing that event's task, time, state, full content,
  and its actions. The inspector always names its task, and the selected
  task's row stays highlighted in cobalt independently of which event is
  inspected.
- **Master voice rail:** fixed at the canvas bottom, bound to the selected
  **task row** — never to an inspected event on another task.

### Focal surface

Two-level focus: the Now column (the rightmost slice of every lane) for fleet
state, and the inspector for content. The design deliberately answers "which
task deserves me next" before "what did this task say."

### Task selection

Tap a task row in the leading column. Row selection (cobalt) and event
inspection are two separate, always-visible highlights — this is the
Chronicle's core safety mechanism and its biggest teaching burden. Inspecting
an event on another task never re-binds voice; a "Select this task" control
in the inspector makes cross-task selection explicit when wanted.

### Voice destination

The master voice rail names its bound task in text at all times: "Talk →
Improve iOS connection manager." Helper text then states the consequence
("Hold to continue this task"). When the inspected event belongs to a
different task than the selected one, the rail shows both facts ("Inspecting:
Fix watchOS handoff regression · Talk → Improve iOS connection manager").

### Latest-result treatment

Each lane's most recent Result marker carries a one-line excerpt inline on
the canvas where width allows; the full result opens in the inspector with
Hear and Copy. This is the Chronicle's acknowledged weakness: the latest
result is one tap further away than in the other three designs, so the
inline excerpt must be honest content, not a label.

### Needs you treatment

A Needs-you event breaks the lane grid: it renders as an extended-height
marker spanning into the gutter above its lane, in the attention treatment,
and **stays pinned at the Now edge** regardless of newer events until
resolved. A summary chip in the Now column header counts unresolved Needs-you
events ("2 need you"). Selecting the pinned event opens the inspector with
the full question and explicit Approve/Deny controls. Voice can answer only
after that task is explicitly selected.

### Mac failure treatment

The affected Mac's tasks get a failure-tinted vertical freeze rule at the
last-heard time; every event left of the rule in those lanes is stamped
stale, and no events can appear right of it. The lane headers for those tasks
show "Mac unavailable — last heard 12:04 PM." The voice rail disables with
its reason when the selected task is on the dead Mac; recovery actions live
in the lane header. Tasks on other, healthy Macs continue flowing — the
chronicle makes per-Mac failure scope visible at a glance.

### Portrait adaptation

Swimlanes rotate 90 degrees: lanes become horizontal bands stacked vertically,
time flows downward, Now at top. Only the selected task's lane is expanded;
other lanes collapse to one-line summaries. The inspector becomes a bottom
sheet; the voice rail stays fixed. In compact widths the inspector collapses
before event markers lose legibility, and task names are never reduced to
lane numbers.

### Strongest risk

**It becomes the operations dashboard the brief forbids.** Six lanes times a
shared time axis times two highlight systems (selection vs. inspection) is
the highest cognitive load of the four designs. A near-technical user may
read the canvas as telemetry to decode rather than work to direct —
precisely the failure the current keybed commits. The dual-highlight model
also carries a real, if mitigated, voice-destination confusion risk that the
other three designs do not have at all.

---

## Data inventory

**Current bridge / task store data used by all four designs:**

- Task name, project, branch, Mac identity, optional lane number
- Task state sufficient to express Idle, Working, Needs you *(pending open
  decision #5 in the shared brief — the Working vs. Needs-you distinction
  must be verified against real bridge events before implementation)*
- Latest user instruction and latest result text per task
- Delivery mode (Steer / Queue) for Talk helper text
- Existing actions: Hear, Copy, History, Stop, Reconnect, task browse/mapping

**Proposed data, labeled as required, not assumed:**

- Per-event timestamps for Tape and Chronicle entries (Asked / Working /
  Result times). If the bridge cannot supply them, both Flight Recorder
  designs degrade to undated sequences — survivable for the Tape, damaging
  for the Chronicle.
- "Last heard from" timestamp for the Mac-unavailable state (all four
  designs).
- Elapsed time on an active turn (all four; omit if start time is
  unavailable, per the shared brief).
- Changed-file count in the Folio's Details module (optional; the module
  works without it).

No design uses reasoning traces, token counts, granular progress, or file
events.

---

## Weighted scores

Scores are 0–10 per criterion, weighted per the track rubrics. Workbench
rubric applies to Designs 1–2; Flight Recorder rubric applies to Designs 3–4.
Cross-track totals are indicative, not decisive — the selection rule in
`IPAD-MODEL-FLIGHT.md` governs.

### Task Workbench rubric

| Criterion | Weight | 1. Command Desk | 2. Operational Folio |
|---|---:|---:|---:|
| Four first-glance answers | 25% | 9 | 8 |
| Task and voice clarity | 20% | 9 | 8 |
| iPad-specific composition | 20% | 8 | 9 |
| State and failure behavior | 15% | 9 | 8 |
| Talkie instrument identity | 10% | 8 | 8 |
| Adaptation and accessibility | 10% | 8 | 7 |
| **Weighted total** | | **8.60** | **8.10** |

### Flight Recorder rubric

| Criterion | Weight | 3. Selected-Task Tape | 4. Cross-Task Chronicle |
|---|---:|---:|---:|
| Four first-glance answers | 25% | 8 | 7 |
| Temporal comprehension | 20% | 8 | 8 |
| Voice destination safety | 20% | 9 | 7 |
| Attention and failure behavior | 15% | 8 | 7 |
| Talkie instrument identity | 10% | 8 | 7 |
| Adaptation and accessibility | 10% | 8 | 6 |
| **Weighted total** | | **8.20** | **7.10** |

### Reading the scores

- **Fixed Command Desk (8.60)** is the strongest baseline: highest
  first-glance and voice clarity, lowest cognitive load, cheapest adaptation
  story. Its ceiling is also the lowest — it is the most conventional
  composition.
- **Selected-Task Tape (8.20)** is the strongest wildcard. It keeps
  single-task focus (no dual-highlight hazard), and its pinned Needs-you
  event and natural failure record give the time axis real work to do. Its
  score depends on per-event timestamps existing.
- **Operational Folio (8.10)** has the highest composition ceiling and the
  widest risk spread. If focus mode is choreographed well it beats the Desk
  on composition and readability; if not, it fails its own brief.
- **Cross-Task Chronicle (7.10)** answers "which task deserves me next"
  better than anything else here, but it pays for it: dual-highlight voice
  risk, dashboard gravity, weakest adaptation, and a hard dependency on
  timestamp data. It should survive as an attention model (the pinned,
  lane-breaking Needs-you treatment is worth stealing), not as the primary
  surface.

---

## Image study nomination

**The Operational Folio deserves the image study.**

The Fixed Command Desk can be judged from words — its risks are editorial
(what goes in the inspector), not visual. The Tape and Chronicle hinge on
data questions (timestamps) that pixels cannot answer. The Folio is the only
design whose success or failure is genuinely undecidable in text:

- Its core claim — that two pages joined by shared baselines read as *one
  folio* rather than a card collection — is a purely visual property. If the
  joinery fails in pixels, the concept fails; if it holds, the Folio is the
  only design that gives the latest result a permanent, first-class *reading*
  surface, which is the current capture's single biggest deficit.
- Its widest-spread risk (focus mode) is spatial: whether the compressed
  task strip keeps voice destination legible during module focus can only be
  evaluated at the physical-capture aspect ratio with real content and real
  type sizes.
- It carries the highest composition score in the portfolio (9 on
  iPad-specific composition), so it is the design where an image study has
  the most to confirm and the most to falsify.

One image, Porcelain, landscape, physical-capture aspect ratio: the Folio in
the Needs-you state with the History module entering focus — that single
frame exercises the spine binding, the two-page joinery, the pinned
attention treatment, and the compressed voice strip all at once. If that
frame reads as one calm instrument, the Folio earns a prototype; if it reads
as four panels negotiating, the Desk becomes the default and the Folio's
Readout module is absorbed into it as a persistent reading column.

---

*Independence note: this portfolio was written from the three briefs and the
physical capture only, before reading any peer Round 1 output. Scores use
the briefs' rubrics; final comparison follows the selection rule in
`IPAD-MODEL-FLIGHT.md`.*
