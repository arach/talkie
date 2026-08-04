# Round 1 portfolio: Grok — four iPad compositions

**Role:** Independent iPad product designer  
**Mode:** Words only. No Swift, no TypeScript, no app code edits.  
**Shared contract:** `IPAD-DESIGN-BRIEF.md`  
**Tracks:** Task Workbench (`IPAD-BRIEF-WORKBENCH.md`), Flight Recorder (`IPAD-BRIEF-FLIGHT-RECORDER.md`)  
**Physical reference:**  
`/Users/arach/.codex/visualizations/2026/08/01/019fbddf-37c3-7fd2-b108-961e0559c6bf/ipad-current-view.png`  
**Reference device:** iPad Air (5th gen), landscape capture of SpeakEasy Deck / Codex  
**Treatment:** Porcelain first (cool blue-white chassis, deep navy work surface, cobalt live/selected)

---

## Capture diagnosis (what the portfolio must fix)

The physical capture shows a handsome instrument that fails as a conversation surface:

| Capture fact | Product cost |
|---|---|
| Full-width dark console with title, monospaced path, and empty body | Largest surface answers nothing about latest work |
| Six-slot lane ribbon (`01`…`06`) with no occupancy | No fleet awareness |
| `NO LANE` badge on a valid named task | Unmapped work looks broken |
| `CODEX> READY` as status language | Expert code, not plain state |
| Permanent 4×4 keybed with many disabled peers | Talk competes with setup furniture |
| Hold instruction references keys `14–15` | Hardware map language on a touch primary surface |

**Promise this portfolio keeps:** See the work. Hear what came back. Speak the next move.

**Identity content used throughout (from capture + briefs):**

| Field | Value |
|---|---|
| Selected task | Improve iOS connection manager |
| Project | talkie |
| Branch | `codex/automatic-screen-preview` |
| Mac | Arachs-Mac-Mini.Local |
| User instruction | Make connection recovery clear on iPad. |
| Working activity | Reviewing bridge discovery and saved ports. |
| Result excerpt | The connection flow now separates retry, edit, and remove so a stale Mac does not block the rest of Talkie. |
| Needs-you prompt | The saved Mac answers on a different port. Update this connection? |

**Fleet tasks for multi-task designs (illustrative, concrete names):**

1. Improve iOS connection manager — Idle or Needs you (selected)
2. Fix CloudKit memo conflict merge — Working
3. Polish tray clip contact sheets — Idle
4. Harden TalkieServer bridge reconnect — Idle
5. Clarify workflow step validation copy — Needs you
6. Ship Mineral dark deck tokens — Idle
7. Document Stage Manager compact rules — Idle (scroll overflow for Design A/B rails)

Illustrative copy does not describe shipped behavior. No invented bridge telemetry (no token counts, reasoning traces, file-level progress, or fake latency graphs).

---

## Design 1: Fixed Command Desk

**Track:** Task Workbench · Design A  
**Thesis:** A stable three-zone desk the user can learn once. Geometry does not reflow across Idle, Working, and Needs you. Content changes; frames stay.

### Landscape topology

```
┌─ chassis (Porcelain cool blue-white) ──────────────────────────────────────┐
│ Talkie · Codex          Arachs-Mac-Mini.Local · Connected · quiet health   │
├─────────────┬──────────────────────────────────────────┬───────────────────┤
│ WORK RAIL   │ LIVE WORK SURFACE (navy)                 │ EVIDENCE          │
│ ~22–25%     │ ~50–55%                                  │ INSPECTOR ~22–25% │
│             │                                          │                   │
│ Mac chip    │ Task title                               │ Context for       │
│ quiet       │ State: Idle · cobalt pip                 │ selected task     │
│             │ talkie · monospaced branch               │                   │
│ Tasks       │                                          │ History turns     │
│ · selected  │ You: Make connection recovery…           │ Readouts          │
│ · Working   │ Codex: The connection flow now…          │ Details           │
│ · Needs you │ [ Hear ] [ Copy ]                        │ (no generic       │
│ · …scroll   │                                          │  analytics)       │
│             │                                          │                   │
│ Browse /    ├──────────────────────────────────────────┤                   │
│ lanes…      │ VOICE SHELF (belongs to live surface)    │                   │
│             │ Hold to continue this task               │                   │
│             │ [ ● Hold Talk ]                          │                   │
└─────────────┴──────────────────────────────────────────┴───────────────────┘
```

Zones are unequal by design: the live surface owns visual mass. The rail is a quiet list. The inspector is subordinate evidence, never a peer dashboard tile.

### Focal surface

The **live work surface** (center navy pane). It always holds one current truth:

- Idle → latest exchange (instruction + result)
- Working → activity line with elapsed time when available
- Needs you → blocking question first
- Mac unavailable → last-known exchange marked stale + failure banner

Empty black is never an idle state.

### Task selection

One selection model: the work rail. Named task rows carry:

1. Task title (primary)
2. Human state: Idle / Working / Needs you / Unavailable
3. Project name (secondary)
4. Optional lane number as tertiary monospaced metadata only

Selecting a row updates the live surface and inspector together. No lane ribbon. No previous/next lane keys. Unmapped tasks show no error; omit lane or show a quiet “—” in details only.

### Voice destination

Always the **selected task** in the rail. Talk lives only on the voice shelf at the bottom of the live work surface (same horizontal band as the shelf, never floating over the rail or inspector).

Helper text before capture:

| Condition | Helper |
|---|---|
| Idle, no active turn | Hold to continue this task |
| Active turn, Steer | Hold to steer this turn |
| Active turn, Queue | Hold to queue a follow-up |
| Needs you, text answer accepted | Hold to answer |
| Mac unavailable | Talk unavailable while the Mac is offline |

Preserve hold, slide-to-cancel, capture perimeter, haptics. Voice never approves, denies, stops, or changes delivery mode.

### Latest-result treatment

Idle composition (primary full landscape):

```
Improve iOS connection manager
Idle
talkie · codex/automatic-screen-preview

You
Make connection recovery clear on iPad.

Codex
The connection flow now separates retry, edit, and remove so a
stale Mac does not block the rest of Talkie.

[ Hear ]  [ Copy ]                    History → (also in inspector)
```

Result text uses human sans. Provenance stays monospaced and quiet. Long results clip with progressive disclosure into the inspector History / full reading surface; Talk shelf never leaves the viewport.

### Needs you treatment

**Live surface:** Question owns the top of the navy pane with higher priority than Working.

```
Needs you
The saved Mac answers on a different port. Update this connection?

[ Update connection ]  [ Keep current ]  [ Stop ]   ← explicit only
Hold to answer · when ordinary text is accepted
```

**Work rail:** Selected or non-selected Needs-you rows carry a durable attention mark (shape + text, not color alone) so attention survives task switching. Needs you outranks Working in rail sort or badge weight when both exist.

Geometry of the three zones does not change.

### Mac failure treatment

```
Mac unavailable · Arachs-Mac-Mini.Local
Last heard from · 2 minutes ago   (use real last-heard when available)

[ Reconnect ]  [ Review connection ]  [ Choose another Mac ]

— Stale content below —
Improve iOS connection manager
Last known: The connection flow now separates retry…
```

Talk disabled with reason. Stale content never presents as live Idle. Inspector may show connection-oriented recovery links but does not invent diagnostics beyond what the bridge store already exposes.

### Portrait adaptation

```
┌─ compact task switcher or slim horizontal rail ─┐
│ Improve iOS connection manager · Idle · ▾        │
├──────────────────────────────────────────────────┤
│ LIVE WORK (full width)                           │
│ … exchange / state …                             │
│ VOICE SHELF                                      │
├──────────────────────────────────────────────────┤
│ Evidence → bottom drawer / page peeks            │
└──────────────────────────────────────────────────┘
```

Keep live work + Talk primary. Collapse inspector into a lower drawer or pager. Do not restore the phone keybed.

Compact Stage Manager: collapse evidence first; keep task, state, latest result, Talk.

### Strongest risk

**Equal visual weight.** If the inspector grows into a permanent multi-widget ops column, the desk becomes an admin dashboard and the conversation loses authority. Mitigation: hard content budget on the inspector (History list + one detail block), cobalt only on selection/live/Needs-you, no charts.

### Rationale (hierarchy, voice, evidence)

Hierarchy: rail (fleet) → live (conversation) → inspector (support) → voice shelf (action). Muscle memory is the product bet. Evidence stays attached to the selected task without covering the exchange. Voice is a fixed shelf, not a key among peers.

### Implementation risks and required data

| Need | Source |
|---|---|
| Named tasks + selection | Existing task store |
| Plain states Idle / Working / Needs you | Must map only from truthful bridge events; open decision #5 in shared brief |
| Latest instruction + result text | Existing turn / narration surfaces |
| Steer vs Queue delivery mode | Existing delivery mode |
| Last heard from Mac | Bridge store health |
| Stop only when supported | Existing stop semantics |

Do not invent progress percentages or reasoning streams for Working.

### Review scores (Workbench rubric)

| Criterion | Weight | Score (0–10) | Weighted |
|---|---:|---:|---:|
| Four first-glance answers | 25% | 9.0 | 2.25 |
| Task and voice clarity | 20% | 9.0 | 1.80 |
| iPad-specific composition | 20% | 8.5 | 1.70 |
| State and failure behavior | 15% | 9.0 | 1.35 |
| Talkie instrument identity | 10% | 8.5 | 0.85 |
| Adaptation and accessibility | 10% | 8.0 | 0.80 |
| **Total** | | | **8.75** |

Reject checks: no invented telemetry; latest result visible in Idle; consequential actions explicit. **Pass.**

---

## Design 2: Operational Folio

**Track:** Task Workbench · Design B  
**Thesis:** An open technical folio: left page = task conversation and voice; right page = evidence modules that can expand into focus reading and return. Shared baselines and hierarchy join the pages. Not a card wall the user must arrange.

### Landscape topology

```
┌─ chassis ──────────────────────────────────────────────────────────────┐
│ Talkie · Codex     Arachs-Mac-Mini.Local · Connected                     │
├──┬──────────────────────────────────┬────────────────────────────────────┤
│R │ LEFT PAGE · TASK                 │ RIGHT PAGE · EVIDENCE              │
│A │ (dominant conversation)          │ (readable modules, not cards)      │
│I │                                  │                                    │
│L │ Title · state · provenance       │ History                            │
│  │                                  │  · turn excerpts, times            │
│c │ You / Codex exchange             │ Changed files (if available)       │
│o │ or live activity                 │ Task details                       │
│m │                                  │                                    │
│p │ [ Hear ] [ Copy ]                │ [ Expand module → focus reading ]  │
│a │                                  │                                    │
│c │ ───────────────────────────────  │ Focus mode: module fills right     │
│t │ VOICE SHELF                      │ page; left page + Talk stay        │
│  │ Hold to continue this task       │                                    │
│  │ [ Hold Talk ]                    │                                    │
└──┴──────────────────────────────────┴────────────────────────────────────┘
```

Compact vertical task rail (narrower than Design 1’s rail) binds both pages to one exact task. Selecting a task refreshes both pages; Talk does not move.

### Focal surface

The **left page** (task conversation). Evidence on the right may become more legible and deliberate than a fixed inspector, but must never outrank the left page for first-glance answers.

### Task selection

Compact rail with the same row model as Design 1 (title, state, project, optional lane). One selection model. Browse / assign lanes as a deliberate entry at the rail foot.

### Voice destination

Selected task only. Voice shelf is fixed to the bottom of the **left page**. Focus expansion of evidence never covers Talk. Helper text contract identical to Design 1.

### Latest-result treatment

Left page Idle:

```
Improve iOS connection manager · Idle
talkie · codex/automatic-screen-preview

You · Make connection recovery clear on iPad.

Codex · The connection flow now separates retry, edit, and remove
so a stale Mac does not block the rest of Talkie.

[ Hear ] [ Copy ]
```

Right page History shows the same turn as a durable row so Ops Ledger’s “evidence remains visible with current work” is true without duplicating bulk on the left.

### Needs you treatment

Left page:

```
Needs you
The saved Mac answers on a different port. Update this connection?

[ Update connection ]  [ Keep current ]  [ Stop ]
Hold to answer
```

Rail attention mark persists. Right page may surface the same question as the top History event, but the live answer lives on the left so the user does not hunt for controls.

### Mac failure treatment

Left page gains a failure band above the stale exchange:

```
Mac unavailable · Arachs-Mac-Mini.Local
Last heard from · 2 minutes ago
[ Reconnect ] [ Review connection ] [ Choose another Mac ]
Talk unavailable while the Mac is offline
```

Right page modules freeze as last-known; no “live” labels. Focus reading of history remains allowed so the user can re-read stale results while reconnecting.

### Portrait adaptation

```
┌─ task switcher chip ─────────────────┐
│ Improve iOS connection manager · ▾   │
├──────────────────────────────────────┤
│ TASK PAGE (default)                  │
│ exchange + VOICE SHELF               │
├──────────────────────────────────────┤
│ ‹ Evidence page ›  (pager / swipe)   │
└──────────────────────────────────────┘
```

Pager between task page and evidence page; Talk only on the task page. Compact width collapses evidence before task content.

### Strongest risk

**Customization drift.** If modules invite rearrange, hide, or “build your desk,” the folio becomes dashboard DIY and loses instrument calm. Mitigation: fixed module set and order; only expand/collapse/focus, never free layout.

### Rationale

Hierarchy uses shared baselines across two pages of one folio rather than three equal columns. Evidence is more readable for long History and details than a narrow inspector. Voice stays anchored to the conversation page so focus reading cannot orphan the next action.

### Implementation risks and required data

Same as Design 1, plus:

| Need | Note |
|---|---|
| Focus reading without modal death of Talk | Sheet or in-pane expansion must keep left page identity and Talk visible |
| Changed files | Only if already available; otherwise omit module rather than invent |

### Review scores (Workbench rubric)

| Criterion | Weight | Score (0–10) | Weighted |
|---|---:|---:|---:|
| Four first-glance answers | 25% | 8.5 | 2.13 |
| Task and voice clarity | 20% | 9.0 | 1.80 |
| iPad-specific composition | 20% | 9.0 | 1.80 |
| State and failure behavior | 15% | 8.5 | 1.28 |
| Talkie instrument identity | 10% | 9.0 | 0.90 |
| Adaptation and accessibility | 10% | 7.5 | 0.75 |
| **Total** | | | **8.66** |

Reject checks: **Pass.** Slight adaptation risk: pager in portrait can hide evidence; acceptable if task page remains default.

---

## Design 3: Selected-Task Tape

**Track:** Flight Recorder · Design A  
**Thesis:** One dominant temporal tape for the selected task. Other tasks live in a compact peripheral rail with state and latest-event markers. Comprehension of one task’s sequence beats simultaneous comparison.

### Landscape topology

```
┌─ chassis ──────────────────────────────────────────────────────────────┐
│ Talkie · Codex     Arachs-Mac-Mini.Local · Connected                     │
├────────────┬───────────────────────────────────────────────────────────┤
│ TASK RAIL  │ TIME CANVAS · selected-task tape (navy, darker ok)        │
│ peripheral │                                                           │
│            │  Now ─────────────────────────────────────────────► past  │
│ · selected │  or past ◄─────────────────────────────────── Now (pick   │
│ · markers  │  one orientation and keep it)                             │
│ · Needs you│                                                           │
│   badge    │  [Result] excerpt…                                        │
│            │  [Working] Reviewing bridge discovery…                    │
│            │  [Asked] Make connection recovery clear on iPad.          │
│            │                                                           │
│            │  Event detail: inline expand or side slip                 │
│            │  (must still show which task owns Talk)                   │
├────────────┴───────────────────────────────────────────────────────────┤
│ MASTER VOICE RAIL (outside scroll)                                     │
│ Destination: Improve iOS connection manager                            │
│ Hold to continue this task · [ Hold Talk ]                             │
└────────────────────────────────────────────────────────────────────────┘
```

Time orientation: prefer **Now at the leading edge of the tape, history extends opposite the primary reading direction**, with a single **Now** jump control. Do not require spatial precision alone to read time; each event carries a human relative time when available.

### Focal surface

The **selected-task tape**. Latest exchange and current state must be more legible than a conventional chat bubble stack: larger type for the current event, quieter type for older events, clear event kind labels (`Asked`, `Working`, `Result`, `Needs you`, `Mac unavailable`).

### Task selection

Peripheral rail. Selecting another task **replaces** the dominant tape; Talk stays put and rebinds to the new selection. Selecting an **event** may open detail without changing voice destination unless the user explicitly selects that event’s task (if different). Scrolling history never changes voice destination.

### Voice destination

Master voice rail, fixed outside the scrolling canvas, always bound to the selected task (named in the rail). Helper text contract identical to Workbench. Talk never “follows” a scrolled historical event.

### Latest-result treatment

Current (top of tape / Now region) when Idle:

```
Result · just now
The connection flow now separates retry, edit, and remove so a
stale Mac does not block the rest of Talkie.
[ Hear ] [ Copy ]

Asked · earlier
Make connection recovery clear on iPad.
```

Do not reduce results to dots or codes. Excerpts are readable; full text opens event detail.

### Needs you treatment

```
Needs you · persistent until resolved
The saved Mac answers on a different port. Update this connection?
[ Update connection ] [ Keep current ] [ Stop ]
```

Needs-you events stay pinned in the Now region (or pinned strip above the scroll) even when newer Working events arrive on **other** tasks. Rail shows attention on any Needs-you task. Needs you outranks Working visually on both tape and rail.

### Mac failure treatment

A `Mac unavailable` event freezes the tape’s “current” edge:

```
Mac unavailable · Arachs-Mac-Mini.Local
Last heard from · 2 minutes ago
[ Reconnect ] [ Review connection ] [ Choose another Mac ]

— Following content marked stale —
Result (stale) · …
```

No new current events appear for the affected Mac. Talk disabled with reason on the master voice rail.

### Portrait adaptation

```
┌─ other tasks overview (compact strip) ─┐
│ badges · Needs you · Working           │
├────────────────────────────────────────┤
│ FULL-WIDTH SELECTED TAPE               │
│                                        │
├────────────────────────────────────────┤
│ MASTER VOICE RAIL                      │
└────────────────────────────────────────┘
```

Other tasks above or below as compact overview; selected task owns the timeline. Talk outside scroll.

### Strongest risk

**Chronology without first-glance gain.** If the tape is only a prettier history log, it fails Design A’s success test. Mitigation: force the current event to dominate type size and position; put Idle result + Talk consequence in the first viewport without scrolling.

### Rationale

Time orientation makes “what happened, then what” legible for one task. Selection is explicit via the rail. Voice targeting is safer than a pure timeline because Talk is outside the canvas and always labeled with the task name.

### Data inventory

| Event / field | Current bridge / stores | Proposed (label only) |
|---|---|---|
| Task name, project, branch | Available | — |
| Mac identity and health | Available | — |
| User instruction text | Available | — |
| Result / narration text | Available | — |
| Working plain activity string | Only if bridge already provides truthful activity | Do not invent granular steps |
| Needs you question text | Only if bridge distinguishes attention | Shared brief open decision #5 |
| Relative timestamps | If turn times exist | — |
| Reasoning / token / file diffs on tape | Not available | Out of scope |

### Review scores (Flight Recorder rubric)

| Criterion | Weight | Score (0–10) | Weighted |
|---|---:|---:|---:|
| Four first-glance answers | 25% | 8.0 | 2.00 |
| Temporal comprehension | 20% | 9.0 | 1.80 |
| Voice destination safety | 20% | 9.0 | 1.80 |
| Attention and failure behavior | 15% | 8.5 | 1.28 |
| Talkie instrument identity | 10% | 8.0 | 0.80 |
| Adaptation and accessibility | 10% | 8.0 | 0.80 |
| **Total** | | | **8.48** |

Reject checks: **Pass** if current event is excerpt-first; **Reject** if reduced to marker dots.

---

## Design 4: Cross-Task Chronicle

**Track:** Flight Recorder · Design B  
**Thesis:** Named-task swimlanes against one shared time axis. Fleet awareness and comparison first. Selected event opens a persistent inspector; selected task owns the master voice rail. Must not become an ops dashboard or Gantt chart.

### Landscape topology

```
┌─ chassis ──────────────────────────────────────────────────────────────┐
│ Talkie · Codex     Arachs-Mac-Mini.Local · Connected     [ Jump to Now ]│
├────────────────────────────────────────────────────┬───────────────────┤
│ SHARED TIME AXIS                                   │ EVENT INSPECTOR   │
│ past ─────────────────────────────── Now           │                   │
│                                                    │ Selected event:   │
│ Improve iOS connection manager ════ ●Result ●Asked │ task, time, state │
│ Fix CloudKit memo conflict merge ══ ●Working       │ content, actions  │
│ Polish tray clip contact sheets ═══ ●Result        │                   │
│ Harden TalkieServer bridge recon… ═ ·              │ Destination for   │
│ Clarify workflow step validation ═ ●Needs you      │ Talk remains       │
│ Ship Mineral dark deck tokens ════ ·               │ named here too    │
│                                                    │                   │
│ (readable short excerpts on markers when space)    │                   │
├────────────────────────────────────────────────────┴───────────────────┤
│ MASTER VOICE RAIL                                                      │
│ Voice goes to: Improve iOS connection manager                          │
│ Hold to continue this task · [ Hold Talk ]                             │
└────────────────────────────────────────────────────────────────────────┘
```

Each lane is a **named task**, never a numbered agent. Markers show event kind + short excerpt when width allows; do not rely on color alone. Cobalt for selection/live; one distinct attention treatment for Needs you; one failure treatment for Mac unavailable.

### Focal surface

The **chronicle canvas** for fleet scan, with the **inspector** holding full content for the selected event. First-glance answer “what happened most recently on the selected task” requires either a highlighted selected-lane Now excerpt or the inspector defaulting to that task’s latest event. Prefer both: selected lane emphasized + inspector seeded to latest.

### Task selection

- Tapping a lane header or empty lane space selects that task for Talk.
- Tapping an event selects the event for the inspector; task selection changes only when explicit (lane select or explicit “Talk to this task”).
- Voice destination label always shows the Talk target task name, even when the inspector shows another task’s historical event.

### Voice destination

Master voice rail outside the scroll. Bound only to the selected task. Scrolling time or inspecting another task’s event does not silently retarget Talk.

### Latest-result treatment

On the selected lane, the rightmost (Now) event shows a readable excerpt, not a lone pip:

```
Improve iOS connection manager
● Result  The connection flow now separates retry, edit, and remove…
```

Inspector expands Hear / Copy / full text. Unselected lanes may show shorter markers; selected lane gets excerpt priority.

### Needs you treatment

Needs-you markers remain prominent across the full canvas (larger mark, attention strip, or pinned annotation). Example concurrent state:

- Selected: Improve iOS connection manager · Result / Idle
- Other lane: Clarify workflow step validation · Needs you (visible without scrolling away)
- Other lane: Fix CloudKit memo conflict merge · Working

Unresolved Needs-you cannot be pushed out of awareness by newer background Working events. Inspector opened on Needs you offers explicit approve/deny-style controls; Talk helper becomes Hold to answer when text answers are accepted.

### Mac failure treatment

A Mac-level connection event spans or stamps all tasks on that Mac:

```
Mac unavailable · Arachs-Mac-Mini.Local · last heard …
[ Reconnect ] [ Review connection ] [ Choose another Mac ]
```

Later task activity freezes; markers after the failure are marked stale. Talk disabled for tasks on that Mac.

### Portrait adaptation

```
┌─ fleet overview (compact multi-task strip) ─┐
│ Needs you · Working badges across tasks     │
├─────────────────────────────────────────────┤
│ SELECTED TASK FULL TIMELINE                 │
│ (other lanes collapse to overview)          │
├─────────────────────────────────────────────┤
│ Inspector peeks / drawer                    │
├─────────────────────────────────────────────┤
│ MASTER VOICE RAIL                           │
└─────────────────────────────────────────────┘
```

Do not reduce task names to lane numbers. Collapse inspector before event legibility.

### Strongest risk

**Ops dashboard failure mode.** Swimlanes invite expert reading of timing marks, density overload at 6+ tasks, and false precision. Mitigation: human event labels only; max short excerpts; no Gantt bars for duration unless truthful duration exists; Prefer “what needs me” scanning over micro-timing; reject rainbow status.

### Rationale

Time orientation is comparative: who needs me across the fleet. Selection and voice safety require a louder destination label than Design 3 because the canvas shows many tasks. Attention model is the product bet: Needs you across lanes without opening each task.

### Data inventory

Same as Design 3, with higher density pressure:

| Need | Constraint |
|---|---|
| 2–6+ concurrent task rows | Task store |
| Event timestamps for alignment | Only if real; otherwise order by known sequence without fake precision |
| Cross-task Needs you visibility | Requires truthful attention state per task |
| No performance traces / SCR graphs | Out of scope |

### Review scores (Flight Recorder rubric)

| Criterion | Weight | Score (0–10) | Weighted |
|---|---:|---:|---:|
| Four first-glance answers | 25% | 7.0 | 1.75 |
| Temporal comprehension | 20% | 8.0 | 1.60 |
| Voice destination safety | 20% | 7.5 | 1.50 |
| Attention and failure behavior | 15% | 9.0 | 1.35 |
| Talkie instrument identity | 10% | 6.5 | 0.65 |
| Adaptation and accessibility | 10% | 7.0 | 0.70 |
| **Total** | | | **7.55** |

Reject risk: dashboard feel at high density. Acceptable as wildcard for fleet attention if excerpts stay human and Talk destination stays loud. Closest to a reject on instrument identity.

---

## Comparative scoring summary

Workbench and Flight Recorder use different rubrics. For portfolio ranking, report both **native weighted totals** and a **normalized comparison** that keeps each track’s criteria.

### Native totals

| Design | Track | Native total | Rubric |
|---|---|---:|---|
| 1 Fixed Command Desk | Workbench | **8.75** | Workbench |
| 2 Operational Folio | Workbench | **8.66** | Workbench |
| 3 Selected-Task Tape | Flight Recorder | **8.48** | Flight Recorder |
| 4 Cross-Task Chronicle | Flight Recorder | **7.55** | Flight Recorder |

### Shared product questions (unweighted check)

| Question | Desk | Folio | Tape | Chronicle |
|---|---|---|---|---|
| Which task and Mac? | Strong | Strong | Strong | Medium (Mac clear; task easy to lose among lanes) |
| State / needs me? | Strong | Strong | Strong | Strong (fleet) |
| Latest produce? | Strong | Strong | Strong if Now dominant | Medium (marker density) |
| Speak consequence? | Strong | Strong | Strong | Strong if destination label stays loud |

### Decision matrix (designer recommendation)

| Priority | Winner | Why |
|---|---|---|
| Primary iPad direction | **Fixed Command Desk** | Highest first-glance reliability, safest voice story, stable muscle memory, least dashboard risk |
| Best evidence reading | Operational Folio | Right page and focus reading beat a narrow inspector for History |
| Best single-task temporal clarity | Selected-Task Tape | Sequence of Asked → Working → Result without chat chrome |
| Best fleet attention scan | Cross-Task Chronicle | Needs you across tasks; highest dashboard risk |

**Rank order for next investment:**  
1 → Fixed Command Desk  
2 → Operational Folio (close second; better long-form evidence)  
3 → Selected-Task Tape (credible opposing thesis)  
4 → Cross-Task Chronicle (wildcard only; needs severe density discipline)

---

## Image study nomination

### Nominate: **Fixed Command Desk** (Design 1) in Idle with a secondary Needs-you rail signal

**Why this composition deserves the first visual study**

1. **It is the primary fusion candidate.** The shared brief’s structural thesis is two-pane landscape with a contextual edge; Design 1 is the most direct, stable reading of that thesis with a third evidence zone that stays subordinate.

2. **It directly reverses the capture’s failure.** The physical reference wastes the largest surface on empty navy and elevates a 4×4 keybed. The Desk study should prove that the same Porcelain chassis can put latest exchange + Hold Talk in the first viewport while demoting setup actions to the inspector.

3. **State geometry is constant.** One Idle master frame plus small Needs-you and Mac-unavailable patches is cheaper to study than Folio focus modes or Chronicle swimlane density, and still covers the acceptance checks.

4. **Scoring.** Highest native total (8.75) with no reject conditions. Folio is close on craft but introduces pager/focus complexity before the base hierarchy is proven.

5. **What the image study must show (acceptance-aligned):**
   - Landscape iPad Air aspect matching the physical capture
   - Work rail with `Improve iOS connection manager` selected; at least one other task showing Working and one showing Needs you
   - Live surface with You / Codex exchange using the brief’s illustrative copy
   - Quiet monospaced branch; no `CODEX>`; no `NO LANE` error
   - Voice shelf: `Hold to continue this task`
   - Inspector with History, not equal-weight widgets
   - Porcelain treatment: cool chassis, navy live surface, cobalt selection

**Secondary study (only after Desk holds):** Operational Folio focus-reading of a long result, to test whether evidence page beats fixed inspector without stealing Talk.

**Do not spend the first image study on Cross-Task Chronicle.** It is the highest risk of looking like a monitoring dashboard and the weakest on Talkie instrument identity.

---

## Open decisions this portfolio does not invent

1. Named tasks replace numbered lanes as primary navigation — assumed per brief for design; product confirmation still open.
2. Porcelain first prototype treatment — used throughout.
3. iPad-distinct composition; iPhone deck unchanged.
4. Lane numbers: tertiary only; may hide entirely when unmapped (no error).
5. Working vs Needs you must map from real bridge events before implementation; designs use plain language only when truthful.

Voice never performs consequential approval. Steer vs Queue remain existing delivery mode. Bridge protocol and Connection Center redesign are out of scope.

---

## Deliverable checklist

| Required by briefs | Desk | Folio | Tape | Chronicle |
|---|---|---|---|---|
| Landscape topology | Yes | Yes | Yes | Yes |
| Focal surface | Yes | Yes | Yes | Yes |
| Task selection | Yes | Yes | Yes | Yes |
| Voice destination | Yes | Yes | Yes | Yes |
| Latest-result treatment | Yes | Yes | Yes | Yes |
| Needs you treatment | Yes | Yes | Yes | Yes |
| Mac failure treatment | Yes | Yes | Yes | Yes |
| Portrait adaptation | Yes | Yes | Yes | Yes |
| Strongest risk | Yes | Yes | Yes | Yes |
| Rationale | Yes | Yes | Yes | Yes |
| Data / implementation notes | Yes | Yes | Yes | Yes |
| Weighted scores | Yes | Yes | Yes | Yes |
| Image study nomination | Fixed Command Desk | | | |

No Swift. No TypeScript. No invented bridge telemetry.

---

*End of Round 1 portfolio — Grok*
