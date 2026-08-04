# Round 1 portfolio: Claude Opus

**Round:** 1, Diverge
**Model:** Claude Opus
**Role:** Independent iPad product designer
**Contract:** `IPAD-DESIGN-BRIEF.md`
**Tracks:** `IPAD-BRIEF-WORKBENCH.md`, `IPAD-BRIEF-FLIGHT-RECORDER.md`
**Reference device:** iPad Air (5th generation), landscape, 1180 by 820 points
**Evidence:** `ipad-current-view.png`, `probes/ipad-probe-command-desk.png`

This document proposes composition only. It contains no Swift, no TypeScript,
and no application edits.

---

## 1. What the physical capture actually proves

The capture is worth stating precisely, because three of the four designs below
exist to correct one measured defect.

Measured from `ipad-current-view.png`:

- The console occupies roughly 400 of 820 vertical points, about 49 percent of
  the screen height.
- Inside that console, content occupies the top 80 points. The remaining 320
  points are empty.
- The keybed occupies roughly 420 points across 16 positions. Five of the 16 are
  visibly unavailable but retain full footprint.
- The lane ribbon occupies 70 points to express six integers.
- The only Codex state on screen is `CODEX> READY`.
- The task carries the badge `NO LANE`, which reads as a defect rather than as
  an absent optional address.

So the surface spends about 40 percent of its area on an empty region, about 35
percent on a control matrix where a third of the controls do nothing, and zero
percent on the latest result. The four first-glance questions score one out of
four in the captured state. Question 1 is answered. Questions 2, 3, and 4 are
not.

Every design below is judged first on whether it moves area toward the latest
truth.

### A caution about the existing probe

`probes/ipad-probe-command-desk.png` is a strong composition, but its Evidence
column shows a `Changed files` list naming `ConnectionCenterView.swift`,
`BridgeConnectionStore.swift`, and `SavedMacEditor.swift`, plus a
`Latest checkpoint` timestamp. Neither is confirmed bridge data. The probe is a
composition test and is allowed to be illustrative, but no design in this
portfolio may depend on that content. Section 7 separates confirmed data from
proposed data for exactly this reason, and the Fixed Command Desk below is
specified so that its inspector survives with History and Details alone.

---

## 2. Constants shared by all four designs

### 2.1 Content

Selected identity, from the physical capture:

- Task: `Improve iOS connection manager`
- Project: `talkie`
- Path: `~/dev/talkie`
- Branch: `codex/automatic-screen-preview`
- Mac: `Arachs-Mac-Mini.Local`
- Lane: unassigned

Illustrative turn content, shared across both track briefs so reviewers compare
composition rather than copy:

- User instruction: `Make connection recovery clear on iPad.`
- Working activity: `Reviewing bridge discovery and saved ports.`
- Result excerpt: `The connection flow now separates retry, edit, and remove so
  a stale Mac does not block the rest of Talkie.`
- Needs-you prompt: `The saved Mac answers on a different port. Update this
  connection?`

Additional named tasks, used to give the cross-task designs realistic density.
All five sit on `Arachs-Mac-Mini.Local`.

| Task | Project | State | Lane |
|---|---|---|---:|
| `Improve iOS connection manager` | `talkie` | Working | none |
| `Connection diagnostics` | `talkie` | Needs you | 01 |
| `iPad deck study` | `talkie` | Idle | 02 |
| `Tighten memo list scrolling` | `talkie` | Idle | 04 |
| `Refine voice prompts` | `talkie` | Complete | 03 |
| `Simplify permissions flow` | `talkie` | Complete | none |

Two tasks carry no lane. That is deliberate. In every design an unmapped task
renders identically to a mapped one except that the lane slot is simply absent.
No design shows `NO LANE`.

### 2.2 Porcelain, expressed as tokens

| Token | Use | Value character |
|---|---|---|
| Chassis | Outer frame, rails, evidence pages | Cool blue-white, near `#F4F6FA` |
| Work pane | The focal surface only | Deep navy, near `#0E1726` |
| Cobalt | Live, selected, completion, Talk | Single saturated blue |
| Attention | `Needs you` only | One amber, used nowhere else |
| Failure | `Mac unavailable` only | One desaturated red-gray, used nowhere else |
| Rule | Dividers, tape ruling, folio gutter | Hairline, low contrast |
| Stale | Last-known content after failure | Reduced opacity plus an explicit caption |

Three signal colors total. Cobalt, amber, failure. Everything else is chassis,
navy, rule, and text. Each of the three always ships with a text label, so no
state depends on color.

Type roles are fixed across all four designs:

- Task titles and results: human sans, large, generous measure.
- State: human sans, small, always a word, never a code.
- Provenance only: monospace. Branch, path, lane, port, timestamp.

The navy work pane is the scarcest resource in the system. In every design,
navy marks the focal surface and nothing else. A reviewer can identify the focal
surface in any of these four compositions by asking which region is dark.

### 2.3 Voice contract

Identical in all four designs, taken from the shared brief without change.

| Condition | Helper text | Talk |
|---|---|---|
| No active turn | `Hold to continue this task` | Enabled |
| Active turn, Steer | `Hold to steer this turn` | Enabled |
| Active turn, Queue | `Hold to queue a follow-up` | Enabled |
| Codex asked a question voice can answer | `Hold to answer` | Enabled |
| Mac unavailable | `Talk unavailable while the Mac is offline` | Disabled |

In all four designs the Talk control prints the destination task name inside
itself, not only above itself. The reason is that three of these compositions
allow the eye to be somewhere other than the selected task when the hand reaches
for Talk. The destination must be readable at the point of contact.

Voice never approves, never denies, never stops, and never changes delivery
mode. Those remain explicit controls in every design and in every state.

### 2.4 Geometry budget

All landscape figures are stated in points against 1180 by 820. Subtract 24
points of status bar and 52 points of application chrome, leaving 744 points of
content height. Percentages below are of the 1180 point width.

---

## 3. Design 1: Fixed Command Desk

**Track:** Workbench, Design A
**Thesis:** The geometry never moves. State is expressed by content and by one
signal, never by layout. The user builds muscle memory in a week and stops
looking for things.

### 3.1 Landscape topology

Three fixed columns, full content height, separated by hairlines.

```
+--------------------------------------------------------------+
| Talkie  Codex            Arachs-Mac-Mini.Local  Connected  ...|  52
+-------------+------------------------------------+-----------+
| TASKS  (+)  | Improve iOS connection manager      | EVIDENCE  |
| 300 pt      | Working                             | 300 pt    |
| chassis     | talkie · codex/automatic-screen-... | chassis   |
|             |                                     |           |
| [selected]  |   You                               | History   |
| Improve iOS |   Make connection recovery clear    | Details   |
| connection  |   on iPad.                          |           |
| manager     |                                     | 12:07 PM  |
| talkie      |   Codex                             | Asked     |
| Working  —  |   Reviewing bridge discovery and    | Make conn |
|             |   saved ports.                      | ...       |
| Connection  |                                     |           |
| diagnostics |   The connection flow now           | 11:52 AM  |
| talkie      |   separates retry, edit, and        | Result    |
| Needs you 01|   remove so a stale Mac does not    | The conn  |
|             |   block the rest of Talkie.         | ...       |
| iPad deck   |                                     |           |
| study       |   Hear   Copy                       | Open full |
| talkie      |                                     | history   |
| Idle     02 | +---------------------------------+ |           |
|   ...       | | (o)  Hold to steer this turn    | |           |
|             | |      Improve iOS connection mgr | |           |
| Browse tasks| |      Release to send · Slide to | |           |
|             | |      cancel        [Steer  v]   | |           |
|             | +---------------------------------+ |           |
+-------------+------------------------------------+-----------+
   300 pt                 580 pt                      300 pt
```

- Rail: 300 points, chassis. Header holds the Mac name and one health
  statement. Body is a scrolling list of named tasks. Footer holds a single
  `Browse tasks` entry that also reaches lane assignment.
- Work surface: 580 points, navy, the only dark region on screen. Header,
  exchange, result actions, voice shelf.
- Inspector: 300 points, chassis. A segmented Evidence column bound to the
  selected task.

The three column widths never change. Not on state change, not on selection
change, not on failure. The inspector swaps content, never width.

### 3.2 Focal surface

The 580 point navy column. It is 49 percent of the width and the only dark
region, so it wins by both area and value contrast. Within it the vertical order
is fixed: title, state, provenance, your instruction, Codex activity or result,
result actions, voice shelf.

The voice shelf is pinned to the bottom of the navy column at 96 points and is
never displaced by content length. The exchange region scrolls beneath it.

The `NO LANE` failure of the current build is corrected here by omission. Lane
appears in the rail row as a right-aligned monospace numeral or as nothing.

### 3.3 Task selection

One model, one gesture. Tap a row in the rail. The selected row carries a 3
point cobalt left bar, a chassis-tinted fill, and its state chip. There is no
lane ribbon, no previous-lane control, and no next-lane control. Above six
tasks the rail scrolls; above roughly twelve, the rail header gains a filter
field. `Browse tasks` opens the existing task browse and lane assignment path.

### 3.4 Voice destination

Bottom of the navy column, 580 points wide, always in the same 96 points. The
capsule prints the helper line, the destination task name, the release and
cancel instruction, and the delivery mode control. Delivery mode is a visible
control inside the shelf, so Steer and Queue remain explicit and changeable by
hand rather than by speech. Hold, slide-to-cancel, capture perimeter, and
haptics are unchanged.

### 3.5 Latest result

The result is the tallest content block in the navy column and uses the largest
body size in the system. In Idle it is what the user sees first below the
header, because there is no activity line above it. `Hear` and `Copy` sit
directly beneath the result text as text-plus-icon controls, attached to the
object they act on. They are not keys.

A long result scrolls within the exchange region and gains an `Open full
result` control at its foot. The header and the voice shelf do not move. The
brief's prohibition on empty black space is satisfied structurally: the region
that was empty in the capture is now the only region that carries the result.

### 3.6 `Needs you`

Three simultaneous, redundant signals. Color is never the only one.

1. Work surface. A bordered question block opens above the exchange with an
   amber left rule, the label `Needs you`, the question `The saved Mac answers
   on a different port. Update this connection?`, and three explicit controls:
   `Update connection`, `Keep current`, `Not now`. The block does not scroll
   away. The prior exchange remains readable below it.
2. Rail. The task row gains an amber left bar and the chip text `Needs you`.
   The row sorts to the top of the rail under a `Needs you` group header, so
   attention survives selecting a different task.
3. Voice shelf. Helper text becomes `Hold to answer`. Talk carries the answer,
   never the approval. Speaking cannot press `Update connection`.

`Needs you` outranks `Working` in the rail sort order and in the work surface
stacking order. If both exist on one task, the question is on top.

### 3.7 Mac failure

Failure is chassis-level, because the failure invalidates all three columns at
once.

- The top chrome expands into a 64 point failure band spanning the full 1180
  points: `Mac unavailable` in text, `Arachs-Mac-Mini.Local`, `Last heard 14
  minutes ago`, then `Reconnect`, `Review connection`, `Choose another Mac`.
- The navy column keeps its last-known content at stale opacity, with a caption
  above the exchange reading `Last known · 12:11 PM`. No state chip claims to
  be current. `Working` becomes `Working when last heard`.
- The voice shelf renders disabled with the reason printed:
  `Talk unavailable while the Mac is offline`.
- The rail stays readable at stale opacity. State chips gain the same
  `when last heard` qualifier.
- The inspector keeps History, which is genuinely historical and therefore not
  stale.

The three column widths are unchanged. Only the chrome grew.

### 3.8 Portrait

820 by 1180.

- Rail collapses to a 64 point task switcher strip directly under the chrome.
  It shows the selected task name, its state, and a disclosure control that
  opens the full task list as a sheet. Task names are never reduced to lane
  numbers.
- Navy work surface takes the full width and roughly 70 percent of the height.
- Inspector becomes a bottom drawer with a grabber, resting at 56 points and
  expanding to half height. Its segmented control is preserved.
- Voice shelf stays at the bottom of the navy surface, above the drawer rest
  state.

Compact Stage Manager width drops the inspector entirely, then the rail, then
provenance, in that order. Task title, state, latest result, and Talk survive to
the narrowest supported width.

### 3.9 Strongest risk

**The inspector is a 300 point bet on data that may not exist.** It is 25
percent of the screen. If the bridge provides only History and Details, the
column becomes a thin strip of metadata beside a conversation, and the
composition reads as an admin dashboard, which is the explicit failure condition
in the Workbench brief. The existing probe fills this column with changed files
and a checkpoint timestamp, neither of which is confirmed.

Mitigation, and it should be treated as a requirement rather than a note: the
inspector must be specified to be worth 300 points using History and Details
alone. If it is not, the correct move is to delete the third column, widen the
navy surface to 880 points, and attach History to the task header. That change
makes this design converge on the Operational Folio, which is a real finding
about the two Workbench designs and not a hedge.

Second risk: fixed geometry is a promise about long results. A result long
enough to need a full reading surface must open elsewhere without moving the
columns, or the promise breaks on its first hard case.

---

## 4. Design 2: Operational Folio

**Track:** Workbench, Design B
**Thesis:** An open technical folio, not a dashboard. Two pages share one
baseline grid across a gutter. Either page can take the spread and give it back,
and Talk never leaves the lower left.

### 4.1 Landscape topology

A compact rail plus a two-page spread joined by a gutter rather than divided by
a border.

```
+--------------------------------------------------------------+
| Talkie  Codex            Arachs-Mac-Mini.Local  Connected  ...|  52
+---------+----------------------------+-----------------------+
| Arachs- | Improve iOS connection     |  RECORD               |
| Mac-Mini| manager                    |                       |
| Connect | Working · 4m                |  Exchanges            |
|         | talkie · codex/automatic-  |  12:07  Asked         |
| Improve | screen-preview             |  Make connection      |
| iOS ... |                            |  recovery clear on    |
| Working | You                        |  iPad.                |
|         | Make connection recovery   |  ------------------   |
| Connect | clear on iPad.             |  11:52  Result        |
| diagnos |                            |  The connection flow  |
| Needs u | Codex                      |  now separates ...    |
|         | Reviewing bridge discovery |  ------------------   |
| iPad    | and saved ports.           |                       |
| deck    |                            |  Readouts             |
| Idle    | The connection flow now    |  Two available        |
|         | separates retry, edit, and |                       |
| Tighten | remove so a stale Mac does |  Task details         |
| memo... | not block the rest of      |  ~/dev/talkie         |
| Idle    | Talkie.                    |  Lane unassigned      |
|         |                            |                       |
| Refine  | Hear   Copy                |                       |
| voice   |                            |                       |
| Complete| +------------------------+ |                       |
|         | | (o) Hold to steer this | |                       |
| Browse  | |     turn               | |                       |
| tasks   | |     Improve iOS conn.  | |                       |
|         | |     [Steer v]          | |                       |
|         | +------------------------+ |                       |
+---------+----------------------------+-----------------------+
  232 pt          460 pt          16 gutter      456 pt
```

- Rail: 232 points. Task name and state chip only. Project, path, and lane move
  to the Record page, because the rail's job here is switching, not describing.
  Header carries the Mac and health. Footer carries `Browse tasks`.
- Task page: 460 points, navy. Title, state, provenance, exchange, result
  actions, voice shelf.
- Gutter: 16 points of chassis with a single hairline centered in it. Not a
  border. The two pages align to one shared baseline grid so the eye reads a
  spread rather than two cards.
- Record page: 456 points, chassis. Stacked modules with a shared left margin
  and rules between them: `Exchanges`, `Readouts`, `Task details`.

The difference from Design 1 is not the column count. It is that the evidence is
set as a page with a text measure and a baseline, rather than as an inspector
with widgets, and that the spread can reallocate itself.

### 4.2 Focal surface

The navy Task page at 460 points, 39 percent of the width. It is narrower than
the Command Desk's work surface, and it wins focus by being the only dark region
rather than by area. This is the design's central bet and its central weakness.
See 4.9.

### 4.3 Task selection

Same single model as Design 1. Tap a rail row. Cobalt left bar plus fill on the
selected row. The rail is narrower, so rows carry two lines instead of three and
lane numbers move off the rail into `Task details`. This directly addresses open
decision 4 in the shared brief: in the Folio, lane appears only in details and
mapping, never in the row.

### 4.4 Voice destination

Bottom of the navy Task page, 460 points wide, 96 points tall. The destination
name is printed inside the capsule.

**Focus mode.** Tapping a Record module heading expands it. The Record page
grows to 700 points and the Task page collapses to a 216 point spine that keeps
the task title, the state, the last line of the latest result, and a full-height
Talk column with the same helper text. Talk stays in the lower left of the
content area in both geometries. It changes width. It does not change corner,
gesture, helper vocabulary, or destination. `Close` returns the spread in one
action.

This is the rule that keeps focus mode from becoming window management: exactly
one module can be open, there is exactly one control to open and one to close,
and nothing is draggable, resizable, or reorderable. The user never arranges a
dashboard because there is nothing to arrange.

### 4.5 Latest result

The result is the largest block on the Task page and holds the full 460 point
measure, which is close to a comfortable 60 to 70 character line at the system
body size. `Hear` and `Copy` sit under it.

The Record page's `Exchanges` module carries the same result in short form with
its timestamp, so the latest truth appears once at reading weight and once at
index weight. A long result opens `Exchanges` into focus mode, where it gets 700
points of measure and the Task page holds the spine. This is the Folio's real
advantage over the fixed desk: it has a genuine reading state for long output
that costs nothing when unused, and it never opens a modal sheet to get there.

### 4.6 `Needs you`

- Task page. The question is set as a full-measure block at the top of the page
  with a rule above and below and an amber left rule. Label `Needs you`, then
  `The saved Mac answers on a different port. Update this connection?`, then
  `Update connection`, `Keep current`, `Not now`. It sits above the exchange and
  does not scroll away.
- Rail. Amber left bar, `Needs you` chip, sorted to the top under a group
  header.
- Record page. The `Exchanges` module shows the question as its newest entry,
  marked open rather than resolved.
- Voice shelf. `Hold to answer`.

If focus mode is open when a question arrives, the spread does not snap closed.
The spine shows an amber marker and the label `Needs you`, and tapping it closes
focus mode. Layout never changes without a user action.

### 4.7 Mac failure

Failure takes a page instead of a band. This is the Folio's most distinctive
state behavior.

The Record page is replaced by a `Connection` page occupying the same 456
points:

- `Mac unavailable` as a heading in failure color plus text.
- `Arachs-Mac-Mini.Local` and `Last heard 14 minutes ago`.
- Saved address and port as monospace provenance.
- `Reconnect` as the primary control, then `Review connection`, then
  `Choose another Mac`, stacked with generous targets.
- A quiet line naming the other known Macs when more than one is known.

The Task page keeps last-known content at stale opacity with the caption
`Last known · 12:11 PM` above the exchange, and its state reads
`Working when last heard`. The voice shelf renders disabled with its reason. The
rail dims and its chips gain the same qualifier.

Recovery gets a reading surface rather than a strip of buttons, which suits a
near-technical user who may need to compare a saved port against a current one.
Nothing about the failure is hidden behind a sheet.

### 4.8 Portrait

820 by 1180.

- Rail becomes a 64 point switcher strip under the chrome, same as Design 1.
- The spread becomes a two-page pager. Page 1 is the Task page at full width,
  and it is the default. Page 2 is the Record page. A two-dot page indicator
  sits in the gutter position at the bottom, and a segmented control in the task
  header offers `Task` and `Record` for users who do not discover the swipe.
- Talk is anchored to the bottom of the screen on both pages, and on the Record
  page it renders as a collapsed 64 point bar that still names the destination
  and still holds to talk. Talk is never a page away.
- Focus mode in portrait is simply page 2 at full width. The mechanic collapses
  cleanly because it was never a window manager.

Compact Stage Manager width drops the Record page to a pager, then drops the
rail to a switcher, then drops provenance.

### 4.9 Strongest risk

**Two near-equal pages compete to be the focal surface.** At 460 against 456
points, the Task page wins only because it is dark. On a physical iPad in a
bright room, at an angle, with a long Record page, that margin may not hold, and
the design then fails first-glance question 3. The Command Desk wins the same
question by 120 points of extra width and never has to rely on value contrast
alone.

The honest test is not a mockup. It is the physical device, in daylight, held at
arm's length, timed. If the Task page does not win in under a second, the fix is
to move to 520 by 396 and accept a narrower Record measure.

Second risk: focus mode is the whole idea and also the whole exposure. One
additional affordance, one draggable edge, one remembered layout, and it becomes
customization work, which the brief names as this design's failure condition.
The single-open, single-control rule must be treated as load-bearing.

---

## 5. Design 3: Selected-Task Tape

**Track:** Flight Recorder, Design A
**Thesis:** The selected task is a record, not a chat. One dominant tape reads
top to bottom with `Now` pinned at the bottom, the newest truth is
typographically the largest object on screen, and time stops visibly when the
Mac goes away.

### 5.1 Landscape topology

A peripheral task rail, one dominant tape, and an event detail panel that is
absent until asked for.

```
+--------------------------------------------------------------+
| Talkie  Codex            Arachs-Mac-Mini.Local  Connected  ...|  52
+----------+---------------------------------------------------+
| TASKS    | Improve iOS connection manager    Working · 4m    |
| 260 pt   | talkie · codex/automatic-screen-preview           |
|          +---------------------------------------------------+
| Improve  |        |                                          |
| iOS conn | 11:48  | Asked                                     |
| Working  |        | Review how saved Macs are stored.         |
| * live   |        |                                           |
|          | 11:49  | Working                                   |
| Connect  |        | (collapsed, one line)                     |
| diagnost |        |                                           |
| Needs u  | 11:52  | Result                                    |
| ! open   |        | The connection flow now separates retry,  |
|          |        | edit, and remove so a stale Mac does not   |
| iPad     |        | block the rest of Talkie.                 |
| deck     |        |                                           |
| Idle     |        | Hear   Copy                               |
| Result   |        |                                           |
|          | 12:07  | Asked                                     |
| Tighten  |        | Make connection recovery clear on iPad.   |
| memo     |        |                                           |
| Idle     | 12:11  | Working                            NOW    |
|          |        | Reviewing bridge discovery and saved      |
| Refine   |        | ports.                                    |
| voice    +---------------------------------------------------+
| Complete | (o)  Hold to steer this turn                      |
|          |      Improve iOS connection manager               |
| Browse   |      Release to send · Slide to cancel  [Steer v] |
+----------+---------------------------------------------------+
   260 pt    72 gutter          848 pt tape             96 tall
```

- Rail: 260 points, chassis. Task name, state, and one latest-event marker per
  row. The marker is a word, not a glyph alone: `live`, `open`, `Result`.
- Tape header: 72 points, navy. Task title, state, elapsed, provenance. Fixed.
- Tape: 848 points wide, navy, scrolling. A 72 point time gutter on its left
  edge carries monospace timestamps and a hairline spine. Entries sit to the
  right of the spine at a comfortable 700 point measure.
- Voice rail: 96 points, full tape width, outside the scroll.

Entries are labeled with the brief's vocabulary in plain language: `Asked`,
`Working`, `Result`, `Needs you`, `Mac unavailable`. There are no dots-only
markers and no codes.

### 5.2 Focal surface

The tape. It is 848 points wide and roughly 576 points tall, about 72 percent of
the width and the entire navy region. It is the largest focal surface in the
portfolio, and unlike the current build's console, it is structurally incapable
of being empty while the task has any history.

The typographic rule is the design's core claim: **weight decays with age.** The
newest entry renders at full size, full measure, with actions attached. Entries
older than the newest two collapse to a single line of label plus first clause,
and expand on tap. So the largest thing on screen is always the most recent
truth, which is the exact inversion of the captured build, where the largest
thing on screen was empty.

### 5.3 Task selection

Tap a rail row. The tape header and tape content are replaced. The voice rail
does not move, does not resize, and does not animate. Its printed destination
name changes.

Scrolling the tape never changes selection. Opening event detail never changes
selection. Selection changes on one gesture in one place.

A `Return to now` pill appears floating 16 points above the voice rail as soon
as the tape is scrolled away from the bottom, and disappears when it is at the
bottom. That is the one clear action back to the present that the Flight
Recorder brief requires.

### 5.4 Voice destination

The voice rail is anchored below the tape, outside the scrolling canvas, at 848
points wide. It prints the helper line, the destination task name, and the
delivery mode control.

The rail is the only element that is guaranteed not to move when the user
scrolls into history. That is what makes scrolling safe: a person can read a
result from an hour ago and the answer to "what happens if I speak now" is still
in the same place saying the same thing.

### 5.5 Latest result

Best-in-portfolio by construction. The newest `Result` entry is the bottom-most
full-weight block, sits directly above the voice rail, and carries `Hear` and
`Copy` inline beneath its text. In Idle, the tape's last entry is the result, so
the largest and lowest thing on screen is the answer.

A result too long for the viewport truncates at roughly twelve lines with a
`Read full result` control. That opens the event detail panel at 340 points on
the right, narrowing the tape to 508 points and keeping the voice rail at 508
points. This is the only geometry change in the design, it is user-initiated,
and it is reversible with one control.

### 5.6 `Needs you`

The tape's distinctive move. A `Needs you` entry is **sticky to the top of the
tape viewport**. When the user scrolls, it detaches from its chronological
position and pins under the tape header as a band with an amber left rule, the
question text, and the three explicit controls. It unpins only when resolved.

The chronological slot it came from keeps a one-line placeholder reading
`Needs you · pinned above`, so the record stays honest about when the question
arrived. New events arriving below cannot push it out of awareness, which is the
brief's explicit temporal requirement.

In the rail, `Connection diagnostics` carries an amber bar, the chip `Needs
you`, the marker `open`, and sorts to the top. If the user is on `Improve iOS
connection manager` while `Connection diagnostics` needs them, the rail is the
only signal, and it is persistent. The tape does not interrupt with another
task's question, because interrupting would put a question above a Talk control
aimed at a different task. That would be a voice-destination safety failure, so
the design refuses it.

### 5.7 Mac failure

The most literal treatment in the portfolio, and the most honest.

The tape gets a **terminal rule**. A full-width band crosses the tape at the
failure moment:

```
| 12:14  | ==== Mac unavailable ==========================
|        | Arachs-Mac-Mini.Local · last heard 14 min ago
|        | Reconnect   Review connection   Choose another Mac
```

Nothing renders below that band. The tape's bottom edge is the failure. All
entries above it take stale opacity, and the tape header caption changes to
`Last known · 12:11 PM` with the state reading `Working when last heard`.

This is what the temporal thesis buys that no pane-based design gets for free:
the user sees that the record stopped, at a specific time, rather than inferring
staleness from a banner. Recovery controls live inside the terminal band, at the
place where the record broke.

The voice rail renders disabled with `Talk unavailable while the Mac is
offline`. `Return to now` is suppressed, because there is no now.

### 5.8 Portrait

820 by 1180. The tape's natural orientation, and the only design in the
portfolio that arguably improves in portrait.

- The rail becomes a horizontal strip of task chips under the chrome, 72 points
  tall, scrolling sideways. Each chip carries the full task name and state chip.
  Names are never reduced to lane numbers.
- The tape takes the full 820 point width and roughly 820 points of height, so
  it shows more record than landscape does.
- The voice rail stays anchored at the bottom, outside the scroll, full width.
- Event detail becomes a sheet rather than a side panel, because there is no
  width to give it.

Compact Stage Manager width keeps the tape and the voice rail, drops the event
detail panel first, then converts the rail to a single switcher control, then
collapses the time gutter from timestamps to relative markers. Event legibility
is the last thing to degrade, per the brief.

### 5.9 Strongest risk

**Chronology may be ceremony.** If the bridge emits only `Asked` and `Result`,
then a tape is a conversation view carrying a time gutter, a spine, entry
labels, and decay rules that buy nothing. The design's whole advantage, that the
record shows shape, requires at least `Asked`, `Working`, `Result`, and
`Needs you` as distinguishable events with timestamps. Open decision 5 in the
shared brief says exactly this is unverified.

This risk is testable before any implementation. Count the distinguishable event
types the current bridge emits for one real task. At two, build the Command
Desk. At four, the tape is the stronger instrument. The design should not be
scored as if that question were already answered, and it is not scored that way
in section 8.

Second risk: sticky `Needs you` plus a bottom-pinned newest result means a long
question and a long result can squeeze the readable tape to almost nothing.
There must be a floor, roughly 200 points of scrollable record, below which the
question collapses to a summary line with a `Show question` control.

---

## 6. Design 4: Cross-Task Chronicle

**Track:** Flight Recorder, Design B
**Thesis:** Aligned task lanes against one shared time axis. Fleet awareness
first, task depth second. Included because the brief requires an opposing
thesis, and specified honestly enough that its weaknesses are visible.

### 6.1 Landscape topology

A fixed task-name column, a lane stack against a shared ordinal time axis, and a
persistent event inspector.

```
+--------------------------------------------------------------+
| Talkie  Codex            Arachs-Mac-Mini.Local  Connected  ...|
+----------+-----------------------------------------+---------+
|          | Earlier      11 AM      12 PM      Now  | EVENT   |
+----------+-----------------------------------------+---------+
| NEEDS YOU                                          |         |
| Connect  |          [Asked]      [!Needs you      ] | Needs   |
| diagnost |                       The saved Mac ... | you     |
| talkie   |                                         |         |
+----------+-----------------------------------------+ Connect |
| Improve  | [Asked]  [Result: The connection flow  ] | diagnos |
| iOS conn |          now separates retry, edit, and | 12:09PM |
| SELECTED |          remove so a stale Mac does not | talkie  |
| talkie   |          block the rest of Talkie.    ] |         |
| Working  |          [Asked] [Working: Reviewing   ] | The     |
|          |                  bridge discovery ...  ] | saved   |
+----------+-----------------------------------------+ Mac     |
| iPad     |  [Result]                               | answers |
| deck     |                                         | on a    |
+----------+-----------------------------------------+ differ- |
| Tighten  |          [Result]                       | ent     |
| memo     |                                         | port.   |
+----------+-----------------------------------------+         |
| Refine   | [Result]                                | Update  |
| voice    |                                         | Keep    |
+----------+-----------------------------------------+ Not now |
| (o) Hold to steer this turn · Improve iOS connection manager  |
|     Release to send · Slide to cancel               [Steer v] |
+--------------------------------------------------------------+
   240 pt              600 pt lanes                    340 pt
```

- Task column: 240 points, chassis, fixed. One row per task with name, project,
  and state. Never scrolls horizontally.
- Lane canvas: 600 points, navy. One lane per task against a shared axis.
- Inspector: 340 points, chassis, persistent. Shows the selected event.
- Master voice rail: 96 points, full 1180 width, bottom, bound to the selected
  task.

Two rules keep this from becoming a Gantt chart or a trace viewer, and both are
non-negotiable:

1. **Time is ordinal, not proportional.** Events lay out in reading order within
   a lane, under coarse shared bands: `Earlier`, `11 AM`, `12 PM`, `Now`. No
   duration is encoded as width. Nothing is measured by pixel distance.
2. **The selected lane is double height and shows full excerpts.** It is 168
   points. Unselected lanes are 72 points with one-line markers. So the latest
   result of the selected task is never hidden behind a marker, which is the
   brief's stated rejection condition.

The `Now` edge is fixed at the right. History scrolls to the left.

### 6.2 Focal surface

Divided, and this is the design's structural problem. The 600 point navy lane
canvas holds the selection, but the selected lane inside it is only 168 points
tall. The inspector at 340 points often holds the content the user actually
wants to read. First-glance question 3 is answered by two regions cooperating
rather than by one region owning it.

### 6.3 Task selection

Tap a task name in the fixed left column, or tap any event in a lane and then
confirm with an explicit `Select this task` control in the inspector. Selection
never changes as a side effect of inspecting an event. That is a hard rule from
the Flight Recorder brief, and it costs this design a tap on its most natural
gesture.

The selected lane is double height, carries a cobalt left bar in the name
column, and prints `SELECTED` as a word in the name cell. Height, color, and
text all encode it.

### 6.4 Voice destination

The master voice rail spans the full 1180 points at the bottom and prints the
destination task name in the same size as the helper text, not smaller. This
matters more here than anywhere else in the portfolio: the eye may be in a lane
four rows away from the selected task when the hand reaches for Talk.

When the inspector shows an event belonging to a task other than the selected
one, the inspector prints a persistent line at its foot: `Talk goes to Improve
iOS connection manager`, with `Select this task` beside it. The mismatch is
stated, never implied.

### 6.5 Latest result

The selected lane's rightmost entry is a full excerpt at body size across up to
three lines, with `Hear` and `Copy` beneath. Unselected lanes show the label
only, such as `[Result]`, with no excerpt.

This is the compromise that keeps the design inside its rubric, and it is also
the compromise that undermines its thesis. If only one lane shows readable
content, the other lanes are a status board, and a status board of five rows is
information the 260 point rail in Design 3 delivers in less space with less
machinery.

### 6.6 `Needs you`

The strongest part of this design.

A `Needs you` event lifts its whole lane out of chronological stacking into a
`NEEDS YOU` group at the top of the canvas, above a rule, with an amber lane
tint and an amber marker. It stays until resolved regardless of what arrives in
other lanes. Multiple questions stack in that group.

The inspector opens to the question with `Update connection`, `Keep current`,
and `Not now` as explicit controls. If the question belongs to a non-selected
task, the inspector still shows the controls, and the answer-by-voice path is
not offered. The helper text stays bound to the selected task. To answer by
voice, the user selects the task first, one explicit tap, and the helper becomes
`Hold to answer`.

Cross-task attention without cross-task voice ambiguity is the one thing this
composition does better than the other three.

### 6.7 Mac failure

All lanes belonging to the failed Mac get a vertical failure rule at the failure
position on the shared axis, and everything to the right of it is empty. The
lanes stop. Above the canvas, a 64 point band states `Mac unavailable`,
`Arachs-Mac-Mini.Local`, `Last heard 14 minutes ago`, and offers `Reconnect`,
`Review connection`, `Choose another Mac`.

All content left of the rule takes stale opacity. The `Now` band label changes
to `Last heard 12:11 PM`. The voice rail disables with its reason.

When a second Mac is known and healthy, only the affected lanes freeze, and the
healthy Mac's lanes continue past the rule. That is the one failure case this
design reads better than any other in the portfolio, and it is worth noting that
it requires a fleet the primary user may not have.

### 6.8 Portrait

The chronicle does not survive portrait, and the honest specification says so
rather than inventing a rotation.

In portrait the design degrades deliberately into Design 3. The selected task
takes the full-width tape. Above it sits a 96 point overview strip with one
compact row per task carrying the full name, a state chip, and a single
latest-event word. Talk anchors at the bottom outside the scroll. The inspector
becomes a sheet.

That is a defensible adaptation, but it also means the composition only exists
in landscape, and a user who rotates loses the entire thesis. Designs 1, 2, and 3
each keep their structure in portrait in recognizable form.

### 6.9 Strongest risk

**It solves a problem the primary user may not have.** The shared brief
describes one near-technical person with one to three known Macs and two to six
tasks. Simultaneous comparison across five lanes is a fleet-operations problem.
For six tasks on one Mac, a 260 point rail with a state chip and a latest-event
word delivers the same awareness, keeps 588 more points for the task itself, and
adds no horizontal time axis to interpret.

The chronicle also carries the heaviest data requirement in the portfolio. It
needs a per-task ordered event stream with timestamps for every task at once,
not just the selected one. If the bridge provides events only for the foreground
task, this design cannot be built at all, while the other three degrade
gracefully.

Second risk: it sits closest to the rejection line in its own rubric. A stack of
lanes against a time axis with a status column reads as an operations dashboard
unless the ordinal-time and double-height-selected-lane rules are held
absolutely. Those rules are easy to lose in implementation, and losing either
one turns the design into the thing the brief forbids.

---

## 7. Data inventory

Separated per the Flight Recorder brief, and applied to all four designs so the
comparison is fair.

### 7.1 Confirmed by the physical capture

| Data | Evidence |
|---|---|
| Task name | `Improve iOS connection manager` on screen |
| Project | `talkie` on screen |
| Path | `~/dev/talkie` on screen |
| Branch | `codex/automatic-screen-preview` on screen |
| Lane mapping, including absent | `NO LANE` badge and 01 to 06 ribbon |
| Selected Mac identity | `ARACHS-MAC-MINI.LOCAL` in chrome |
| A ready state exists | `CODEX> READY` |
| History exists as a destination | `HISTORY` key enabled |
| Readout exists as a destination | `READOUT` key enabled |
| Stop, Read, Copy, Replay exist and can be unavailable | four keys rendered disabled |
| Task details exists | `DETAILS` key enabled |

### 7.2 Required by these designs and not yet verified

Listed with which designs need it. Open decision 5 in the shared brief already
flags the first two.

| Proposed data | Needed by | Consequence if absent |
|---|---|---|
| Truthful `Working` activity text | 1, 2, 3, 4 | Show plain `Working` with no activity line. All four degrade cleanly. |
| A `Needs you` state distinguishable from `Working` | 1, 2, 3, 4 | The attention model collapses in all four. This is the single highest-value verification in the flight. |
| The blocking question text | 1, 2, 3, 4 | Questions must be answered on the Mac. All four lose a required state. |
| Turn start time for elapsed display | 1, 2, 3, 4 | Drop `· 4m`. Cosmetic loss only. |
| Last-heard-from-Mac timestamp | 1, 2, 3, 4 | Failure states cannot say when. Weakens all four equally. |
| Ordered event stream with timestamps, selected task | 3 | The tape cannot be built. |
| Ordered event stream with timestamps, all tasks | 4 | The chronicle cannot be built. |
| Per-task state for unselected tasks | 1, 2, 3, 4 | Rails show names without states. Costs first-glance question 2. |
| Changed-file lists | none of these designs | Explicitly excluded. Used in the existing probe. Not depended on here. |
| Checkpoint timestamps | none of these designs | Explicitly excluded. Used in the existing probe. Not depended on here. |
| Token counts, reasoning traces, granular progress | none | Forbidden by both briefs. |

Designs 1 and 2 need six proposed items and degrade to a usable surface without
any of them. Design 3 needs seven and loses its thesis without the seventh.
Design 4 needs eight and cannot exist without the eighth. That difference is
priced into the scores below.

---

## 8. Weighted scores

### 8.1 Method

The two track rubrics are structurally identical. Same six slots, same weights.
Criteria 2 and 3 differ only in name, and the names map cleanly:

| Slot | Weight | Workbench name | Flight Recorder name |
|---|---:|---|---|
| 1 | 25% | Four first-glance answers | Four first-glance answers |
| 2 | 20% | Task and voice clarity | Temporal comprehension |
| 3 | 20% | iPad-specific composition | Voice destination safety |
| 4 | 15% | State and failure behavior | Attention and failure behavior |
| 5 | 10% | Talkie instrument identity | Talkie instrument identity |
| 6 | 10% | Adaptation and accessibility | Adaptation and accessibility |

Each design is scored against its own track's rubric, 0 to 100 per criterion.
Because the weights are identical, the weighted totals are comparable across
tracks, with the caveat that slots 2 and 3 measure different things. That caveat
is stated again under the cross-track board.

No design is rejected outright. All four keep voice bound to one explicitly
selected task, none hides the latest result, and none depends on forbidden
telemetry, so none trips a rejection condition in either rubric.

### 8.2 Workbench track

**Design 1: Fixed Command Desk**

| Criterion | Weight | Score | Weighted | Note |
|---|---:|---:|---:|---|
| Four first-glance answers | 25% | 92 | 23.0 | 580 pt navy surface, all four answers in one viewport, no sheet |
| Task and voice clarity | 20% | 90 | 18.0 | One selection model, one fixed Talk position, destination printed in the capsule |
| iPad-specific composition | 20% | 84 | 16.8 | Genuinely iPad, but the three-column form is the most conventional in the portfolio |
| State and failure behavior | 15% | 86 | 12.9 | Correct and complete. A chrome band is the least expressive failure treatment here |
| Talkie instrument identity | 10% | 82 | 8.2 | Restrained and correct. Closest of the four to a generic productivity layout |
| Adaptation and accessibility | 10% | 80 | 8.0 | Portrait works. The inspector drawer is the weakest part of the adaptation |
| **Total** | | | **86.9** | |

**Design 2: Operational Folio**

| Criterion | Weight | Score | Weighted | Note |
|---|---:|---:|---:|---|
| Four first-glance answers | 25% | 84 | 21.0 | All four answered, but question 3 rests on a 4 pt width margin plus value contrast |
| Task and voice clarity | 20% | 82 | 16.4 | Talk resizes in focus mode. Same corner and same vocabulary, still a variable |
| iPad-specific composition | 20% | 90 | 18.0 | The spread and gutter are the most iPad-native idea in the Workbench track |
| State and failure behavior | 15% | 90 | 13.5 | Giving failure a full page is the best recovery surface in the portfolio |
| Talkie instrument identity | 10% | 88 | 8.8 | Folio reads as a technical instrument without imitating hardware |
| Adaptation and accessibility | 10% | 76 | 7.6 | The pager is fine. Collapsed Talk on page 2 is the weakest element in the portfolio |
| **Total** | | | **85.3** | |

### 8.3 Flight Recorder track

**Design 3: Selected-Task Tape**

| Criterion | Weight | Score | Weighted | Note |
|---|---:|---:|---:|---|
| Four first-glance answers | 25% | 88 | 22.0 | Best latest-result answer in the portfolio. Mac identity sits in chrome, one step further from the eye |
| Temporal comprehension | 20% | 86 | 17.2 | Weight-decays-with-age is a real comprehension mechanism. Scored down for depending on event variety |
| Voice destination safety | 20% | 92 | 18.4 | Voice rail never moves during scroll. Refuses to surface another task's question above it |
| Attention and failure behavior | 15% | 94 | 14.1 | Sticky question plus terminal rule. The most legible failure treatment produced |
| Talkie instrument identity | 10% | 86 | 8.6 | Tape and time gutter are distinctly Talkie. Slight risk of reading as a log |
| Adaptation and accessibility | 10% | 84 | 8.4 | The only design that improves in portrait. Time gutter needs a VoiceOver rotor plan |
| **Total** | | | **88.7** | |

**Design 4: Cross-Task Chronicle**

| Criterion | Weight | Score | Weighted | Note |
|---|---:|---:|---:|---|
| Four first-glance answers | 25% | 74 | 18.5 | Question 3 is split between a 168 pt lane and a 340 pt inspector |
| Temporal comprehension | 20% | 78 | 15.6 | Shared axis is genuinely comparative. Ordinal time is a compromise that blunts it |
| Voice destination safety | 20% | 70 | 14.0 | Safe by explicit rules, but the eye is routinely far from the destination |
| Attention and failure behavior | 15% | 84 | 12.6 | Lane promotion is excellent. Multi-Mac freeze is the best in the portfolio |
| Talkie instrument identity | 10% | 66 | 6.6 | Closest to the ops-dashboard rejection line. Only two hard rules hold it back |
| Adaptation and accessibility | 10% | 62 | 6.2 | Does not survive portrait. Degrades into Design 3 rather than adapting |
| **Total** | | | **73.5** | |

### 8.4 Cross-track board

| Rank | Design | Track | Total |
|---:|---|---|---:|
| 1 | Selected-Task Tape | Flight Recorder | **88.7** |
| 2 | Fixed Command Desk | Workbench | **86.9** |
| 3 | Operational Folio | Workbench | **85.3** |
| 4 | Cross-Task Chronicle | Flight Recorder | **73.5** |

Read the top three as a cluster, not a ranking. The 3.4 point spread between
first and third is inside the noise of a prose evaluation, and slots 2 and 3
measure different properties across the two tracks. The defensible conclusions
are only these two:

1. The top three are all viable, and each wins a different slot. The Tape wins
   attention and failure. The Command Desk wins first-glance. The Folio wins
   composition.
2. The Cross-Task Chronicle is separated from the field by 11.8 points, which is
   outside the noise. It is the one design that should not advance in its current
   form. Its best idea, promoting a `Needs you` lane above chronology, should be
   preserved and transplanted into whichever composition advances.

---

## 9. The composition that deserves an image study

**Selected-Task Tape.**

Four reasons, in order of weight.

**It targets the measured defect directly.** Section 1 established that the
current build gives 40 percent of the screen to an empty region and 0 percent to
the latest result. The tape's central rule, that typographic weight decays with
age and the newest entry is the largest object on screen, is the exact inversion
of that defect. The other three designs correct it by allocating a region. The
tape corrects it by making the correction structural, so it cannot regress.

**Its central claim is a pixel question, not a prose question.** Everything in
sections 5.1 through 5.5 can be specified in words and still fail on a device.
Whether a tape with a time gutter, entry labels, a hairline spine, and decaying
weight reads as a *record* rather than as a chat log with decoration, or worse
as a server log, is decided entirely by type sizes, gutter width, rule contrast,
and the collapse threshold. No amount of further specification resolves it.
Rendering does. The other three designs can be argued to a conclusion on paper.
This one cannot.

**Marginal information is highest here.** A Command Desk probe already exists at
`probes/ipad-probe-command-desk.png` and answers most of what a second Command
Desk image would answer. The Folio's open question is narrow and physical, a 460
against 456 point contest in daylight, better settled on a device than in an
image. The Chronicle scored itself out. The Tape is the only composition in the
portfolio with a large unresolved visual question and no existing probe.

**It carries the portfolio's two best state treatments, and both are visual.**
The sticky `Needs you` band that detaches from chronology and leaves a
placeholder, and the terminal rule where the record visibly stops at a
timestamp, are the two strongest state ideas produced in this round. Both are
compositional. Both should be tested as images before either is argued about
further, and both are transplantable into the Command Desk if the tape itself
does not survive.

**Probe scope, if commissioned.** One landscape frame at the physical-capture
aspect ratio, Porcelain, Working state, `Improve iOS connection manager`
selected, five events on the tape with the newest at full weight and the two
oldest collapsed, the peripheral rail showing `Connection diagnostics` marked
`Needs you`, and the voice rail printing `Hold to steer this turn` with the
destination name. Composition only. No Swift, no traced implementation.

---

## 10. Carried into Round 2

Five items for the cross-examination round, stated as questions rather than
positions.

1. **Verify the `Needs you` event before anything else.** All four designs place
   their attention model on a state the bridge may not distinguish from
   `Working`. This is the highest-value verification in the flight, and it is
   cheaper than any of the four designs.
2. **Count the distinguishable event types on one real task.** At two, the
   Command Desk is correct and the tape is ceremony. At four, the tape is the
   stronger instrument. This single count settles the track question.
3. **Justify or delete the Command Desk's third column.** 300 points, 25 percent
   of the screen, for evidence that may reduce to History and Details. If it
   cannot be justified without changed files and checkpoints, delete it and
   widen the work surface to 880 points.
4. **The three best ideas are separable from their compositions.** The terminal
   rule at the failure timestamp, the sticky `Needs you` that leaves a
   chronological placeholder, and the promotion of a `Needs you` lane above
   chronology can each be transplanted into any of the four. Round 3 should treat
   them as components.
5. **Do not combine the Folio's focus mode with the Chronicle's lane canvas.**
   Two independent geometry-changing mechanisms on one surface produce window
   management, which both briefs reject. If a synthesis wants both evidence
   focus and cross-task lanes, one of them must be a sheet.
