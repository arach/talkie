## Current iPad critique — near-technical Codex operator

**Status:** Three reviews complete; synthesis ready  
**Captured:** 2026-08-01, physical iPad Air (5th generation), landscape  
**Review mode:** Words only. No Swift or Studio implementation changes by reviewers.

### The person we are designing for

The user is near-technical: comfortable with projects, tasks, Macs, agents, and
the idea that work can be running remotely, but they should not have to reason
like a terminal operator. They use Talkie to manage Codex by voice while moving
between an iPad and one or more Mac bridges.

They need to answer four questions without decoding the machinery:

1. What am I currently talking to?
2. What is Codex doing, and does it need me?
3. What did it most recently produce?
4. What can I safely say or do next?

### Current physical-device evidence

The captured landscape screen has:

- a thin Talkie/Codex header with the selected Mac bridge on the right;
- a six-position lane ribbon across the top;
- one very large dark console showing the selected task, repository, branch,
  a short voice hint, and a quiet `CODEX> READY` footer;
- a dense 4-by-4 command bed below, including Mapper, Spaces, Details, History,
  Refresh, lane navigation, Task, Readout, and a two-column Talk control;
- substantial unused console space and many controls whose relationship to the
  selected task is not immediately legible.

The source implementation is
`apps/ios/Talkie iOS/Codex/CodexCommandDeckSurface.swift`. The current capture
is available locally at
`/Users/arach/.codex/visualizations/2026/08/01/019fbddf-37c3-7fd2-b108-961e0559c6bf/ipad-current-view.png`.

### Shared review questions

Each reviewer is answering these independently:

1. What does a near-technical user believe this screen is for in the first five
   seconds, and where does that belief break?
2. What information and actions should be primary, secondary, or progressively
   disclosed on iPad?
3. How should landscape iPad space change the composition instead of merely
   enlarging the phone deck?
4. What is the clearest mental model for tasks, lanes, Mac bridges, live work,
   results, and voice follow-up?
5. What should the screen show in four states: idle, Codex working, needs
   attention, and bridge failure?
6. Which current elements should remain, move, merge, or disappear?
7. What five design principles should govern the next iPad study?

Constraints: keep voice as the front door; preserve Talkie's calm technical
instrument character; avoid a generic admin dashboard, a literal terminal, and
expert-only agent jargon; keep consequential actions explicit and human-owned.

### Recommendation at a glance

Design the iPad surface as **a named-task switcher beside the selected task's
conversation**. Keep the last Codex exchange or live activity in the largest
pane, anchor Hold to talk to that pane, and reveal only the actions that apply
to its current state. Treat lane numbers as optional speed-dial metadata and
bridge health as quiet plumbing until the connection fails.

The permanent 4-by-4 keybed should not define the landscape layout. Talkie's
instrument character can survive through precise state, stable geometry,
tactile voice control, restrained motion, and the existing visual language.

---

### Opus

#### 1. The first five seconds

A near-technical user reads this screen as **an equipment panel that is currently
switched off**. That reading is produced by real evidence, not by inattention:

- Four of the sixteen keys (`06 READ`, `07 COPY`, `10 REPLAY`, `11 STOP`) are
  ghosted. A whole middle column is dim.
- The one console on screen — the largest element by far — is empty below three
  lines of header.
- The footer reads `CODEX> READY`, which is a machine saying it is *not doing
  anything*.
- Roughly a third of the display, everything below the key bed, is blank.

The belief breaks at the moment they want to act, because the screen has told
them the truth about the system's plumbing and nothing about their work. The
specific failures, in the order a user hits them:

**The lane ribbon contradicts the task.** Six numbered slots span the top, and
the selected task carries a `NO LANE` chip (`CodexCommandDeckSurface.swift:1545`).
The user sees six containers and is told their task is in none of them. Nothing
on screen explains whether that is a problem, and the chip is a button, so it
reads as an error to be fixed. It is not — an unmapped task is perfectly valid.
This single contradiction does more damage than any other element.

**The lane keys point the wrong way.** Keys `09` and `12` read `LANE 06` and
`LANE 01`. That is the wrap-around at line 1100 labelling its endpoints when no
lane is active. Left-chevron-to-06 and right-chevron-to-01 reads as inverted, and
these are two of the largest controls in the bed advertising a destination the
user has no reason to want.

**Status hides in the smallest element on screen.** The only live indicator is a
37×24pt LED reading `RDY`, inside keycap `04`, captioned `DETAILS`
(`statusReadoutKey`, line ~613). Above it sits a ~400pt console with nothing in
it. The most important question — *what is Codex doing* — is answered by the
smallest pixel area on the display, while the largest is idle. This inversion is
the core defect; most other problems are downstream of it.

**The voice hint is written in hardware.** "Hold the 14–15 key to talk directly
to this task." There is no keyboard. `14` and `15` are 7pt corner indices on a
touch target. This is exactly the expert-only jargon the constraints rule out,
and it is the one line of plain-language instruction on the screen.

**The primary slot is unlabelled.** Key `01` is the output-route dial — silent /
Watch / iPhone. Every other key carries a monospace caption; this one carries
none. The most prominent position holds the only anonymous control, and it
governs audio routing, which is not a deck action at all.

Minor but additive: two `×` buttons (header right, console bottom-right); repo,
path, and branch rendered as three coequal 9pt crumbs when only one of them is
usually the answer to "where am I."

#### 2. Primary, secondary, progressive

**Primary — always visible, never earned:**
- What I am talking to: Mac bridge *and* task, as one joined statement, not two
  widgets at opposite corners.
- What Codex is doing right now, in words, with elapsed time.
- The most recent thing it produced.
- Push-to-talk.

**Secondary — visible, subordinate:**
- Branch and working directory (provenance for the above, not peers of it).
- Switch task / switch Mac.
- Stop, when and only when something is running.

**Progressive:**
- History, changed files, full activity log, per-result copy/read/replay,
  lane mapping, output routing, the mapper, spaces.

Everything in that third list currently occupies a permanent key. That is the
trade to unwind: the deck spends all sixteen positions on capabilities and none
on the four questions the brief opens with.

#### 3. What landscape should change

The current screen is the phone deck stretched horizontally and *not* vertically
— hence the dead band at the bottom. Widening a vertical stack does not produce
an iPad layout; it produces a phone layout with margins.

Landscape should change the composition from **stack** to **three columns**,
because the user's three questions are genuinely independent and can be held
simultaneously on this much glass:

- **Left rail (~22%) — what I am talking to.** Mac bridge at the top with
  reachability. Below it, the task list: the handful of real tasks, each showing
  its own state. Lanes live here as optional speed-dial numbers *on* tasks, not
  as a separate six-slot bank.
- **Center (~55%) — what it is doing and what it produced.** The console,
  finally with content: a running conversation between the user and Codex, newest
  at the bottom, each entry stamped and attributable. Idle does not mean empty —
  idle means the last exchange is still on screen.
- **Right (~23%) — what I can say next.** Push-to-talk anchored at the bottom
  where a thumb rests in landscape, with the two or three verbs that actually
  apply to the current state directly above it.

The discipline that keeps this from becoming the admin dashboard the constraints
forbid: **the center column is a conversation, not a widget grid.** No tiles, no
sparklines, no counts. It reads as a transcript with provenance, and voice
composes into the bottom of it. That keeps the object a radio to a workshop
rather than a monitoring console.

The 4×4 bed does not survive this. It becomes a contextual action strip of two to
four named verbs.

#### 4. The mental model

Propose: **Talkie is a radio to a workshop.**

| Concept | What it is to the user | What it must never be |
|---|---|---|
| Mac bridge | The workshop — the place where work physically happens | A connection setting |
| Task | The bench you are standing at: repo + branch + intent | A row in a queue |
| Lane | A speed-dial number *on* a task, for fast voice targeting | A container tasks live in |
| Live work | The workshop is busy; you can hear it | A progress bar |
| Result | What came back and is waiting to be read | A notification |
| Voice | The radio; press to talk | A command palette |

The one change that matters most: **demote lanes from an organizing axis to an
addressing convenience.** Today lane-as-slot and task-as-thing are conflated,
which is why a valid task gets stamped `NO LANE` and why six empty numbered boxes
head the screen. Users think in *my tasks*; lanes exist because a hardware deck
metaphor wanted six numbered positions. Tasks become the noun, lanes become an
optional number you can assign to one for hands-free targeting. `NO LANE`
disappears as a concept — a task without a speed-dial is simply a task you
address by name.

#### 5. The four states

**Idle.** The console shows the *last exchange*, not `READY`. "Ready" is not
information; the thing Codex last produced is. The screen at rest should be a
record of what happened, with the talk key inviting the next turn.

**Working.** The console shows what step Codex is on, how long it has been going,
and what it is touching. `RUN` in a keycap LED is not this. The talk key changes
meaning to *steer* — the user can interject mid-run, and the label should say so.
Motion stays minimal and must survive reduce-motion, since `statusInstrument`
currently animates as a primary state channel.

**Needs attention.** The current design has no vocabulary for this state at all,
and it is the most important one — it is the entire reason to look at the iPad
rather than let it run. When Codex asks a question or awaits approval, that
question dominates the center column, and the talk key becomes *answer*. This is
the one state permitted to break calm, and it should do so with a single accent
and a plain sentence, not with alarm styling.

**Bridge failure.** Critically: the task is fine, the *radio* is down. Do not
blank or gray the task — gray the link. Show last-known state with an explicit
age ("last heard 4m ago") and one recovery action. The current design cannot
express the difference between *Codex stopped* and *I cannot hear Codex*, and
those demand opposite responses from the user. Making that distinction legible is
the single highest-value state fix on the screen.

#### 6. Remain, move, merge, disappear

**Remain (promoted):** bridge picker — becomes a named, permanent statement of
what you are talking to. Push-to-talk — becomes persistent and thumb-anchored.
Task identity — becomes the console's header rather than a crumb.

**Move:** the status LED out of keycap `04` and into the console header, at
console scale. Output routing next to voice, where it belongs, with a label.

**Merge:** `DETAILS` + `HISTORY` + `READOUT` collapse into the console — the
console *is* the detail view. `READ` / `COPY` / `REPLAY` become row-level actions
on an individual result, appearing on the thing they act on rather than as global
keys that are dim most of the time.

**Disappear:** the persistent six-slot lane ribbon; the 4×4 key bed; the lane
prev/next keys; the "14–15 key" hint; the numbered key indices; the second `×`;
the `NO LANE` chip; ghosted-but-present keys as a pattern.

**Keep, unchanged:** the typographic voice, the restraint of the palette, the
monospace provenance line. The instrument character is right — it is currently
applied to the wrong information.

#### 7. Five principles for the next study

1. **The largest surface carries the most recent truth.** No arrangement in which
   a keycap LED is better informed than the console.
2. **Name things the way the user names them.** Task, Mac, branch, result. Never
   key positions, never lane indices as identity, never phase enums.
3. **Controls appear when they apply.** A dim control is a control that should
   not be there yet. Absence is calmer than disablement.
4. **State is legible without color and without motion.** Words first; the LED,
   the accent, and any animation are reinforcement. This is also what makes it
   survive reduce-motion and glare on a physical iPad.
5. **Consequential actions stay explicit and human-pressed.** Stop, dispatch,
   approve are always named targets the user commits to — never a dial detent,
   never a swipe, never inferred from voice alone.

#### Smallest change with the largest effect

If only one thing ships from this review: **fill the console at rest.** Put the
last exchange and a plain-language status where the emptiness currently is, and
move the `RDY` LED up beside it. That single move answers three of the brief's
four questions, removes the "switched off" reading, and makes the dead space at
the bottom of the screen a layout problem rather than an evidence-of-brokenness
problem.

### Grok

Grok's full independent review is rendered below this synthesis. Its central
proposal is a named lane: a stable destination that binds one Codex task to one
Mac. It keeps the lane model more visible than Opus or Kimi, but agrees that the
current numbered ribbon and permanent 4-by-4 keybed do not explain the work.

### Kimi

Kimi's full independent review is rendered below Grok's. It treats the task as
the hero object, the lane as selection rather than identity, and the bridge as
plumbing that should become prominent only when it fails.

### Synthesis

#### The shared diagnosis

The present deck has the right character and the wrong information hierarchy.
It looks calm, deliberate, and instrument-like, but asks the person to decode
controls before it shows the conversation they came to manage. All three
reviewers identified the same inversion:

- the largest surface is an almost-empty console;
- the most useful state is compressed into small codes or a terminal-like
  footer;
- the latest Codex result is hidden behind controls;
- Talk is surrounded by setup, navigation, and playback actions that do not
  apply most of the time;
- landscape width stretches the phone deck instead of changing the composition.

The design should keep Talkie's visual restraint, typography, and sense of a
dedicated instrument. It should stop treating the permanent key matrix as the
source of that identity. The instrument quality can come from precise state,
stable geometry, tactile voice control, and restrained motion.

#### Editorial judgment: manage named work, not lane machinery

The reviewers disagree on whether a lane is the user's primary destination.
Grok says a named lane should be the stable binding between a task and a Mac.
Opus and Kimi say the user thinks in tasks, while lanes are speed-dial or
selection machinery.

For the near-technical audience, the next study should make **the named task the
primary object**. Preserve lane assignment as an optional address for muscle
memory and voice targeting, but render it as secondary metadata: “Lane 3,” not
the title of the thing. A task without a lane is simply an available task, not a
task in an error state. This preserves the current framework without asking the
person to learn it before they can understand their work.

The bridge follows the same rule. When healthy, it completes one plain statement
of identity: “Connection manager on Arach's Mac mini.” When it fails, the bridge
becomes the primary problem and must not be confused with Codex stopping.

#### Recommended landscape composition

Use a **two-pane task conversation with a contextual action edge**, rather than
a full admin dashboard or three equal columns.

**Leading pane — work switcher, roughly one quarter of the width**

- a compact bridge identity and health control;
- a list of named tasks with one human state each: Idle, Working, Needs you, or
  Unreachable;
- optional lane numbers as quiet secondary labels;
- one deliberate way to browse or map more tasks.

**Main pane — selected task, the rest of the width**

- one joined identity line: task, Mac, project, and quiet branch provenance;
- the latest exchange as the default resting content;
- live activity in plain language when Codex is working;
- Codex's actual question when it needs the person;
- the latest result excerpt, with Read, Hear, Copy, and History attached to the
  result rather than occupying global keys.

**Voice and contextual actions**

- anchor Hold to talk at the bottom of the main pane, near the landscape thumb;
- keep Talk in the same place through every healthy state, changing its helper
  language from Continue to Steer to Answer;
- show only the two or three actions that apply to the current state;
- place setup and diagnostics behind a clearly named More or task-details
  surface.

This uses iPad width for simultaneous fleet awareness and focused conversation,
without turning Talkie into an operations dashboard.

#### State contract

| State | Main pane | Primary voice/action | Peripheral signal |
|---|---|---|---|
| **Idle** | Last exchange and latest result remain visible | “Hold to continue this task” | Quiet Idle label |
| **Working** | Plain-language current activity and elapsed time | “Hold to steer” or “add a follow-up” | Subtle activity signal on the task |
| **Needs you** | The blocking question or approval request owns the pane | “Hold to answer”; approvals remain explicit buttons | One unmistakable attention accent in the task list |
| **Bridge failure** | Last-known task state remains visible but clearly stale | Reconnect, edit connection, or choose another Mac | “Mac unreachable · last heard 4m ago”; Talk disabled with a reason |

The four state names should be the canonical user vocabulary. Codes such as
`RDY`, `RUN`, `QUE`, `RX`, `VOX`, and `CODEX>` may remain implementation or
decorative details only where they do not carry meaning by themselves.

#### Disposition of the current deck

**Keep:** the calm dark palette, typographic restraint, selected task identity,
push-to-talk gesture, capture perimeter, one status instrument, and optional
lane assignment.

**Move:** bridge selection into the leading pane; latest output into the main
pane; output routing into voice settings; Mapper, Spaces, Details, Refresh, and
History into named secondary surfaces.

**Merge:** lane ribbon plus previous/next into the named task switcher; Read,
Copy, Replay, and Readout into actions on a result; the footer and status LED
into one human-readable state.

**Remove from the primary surface:** numbered key indices, persistent disabled
keys, the `NO LANE` warning treatment, the “14–15 key” instruction, terminal
prompt language, and the permanent 4-by-4 grid.

#### Smallest credible first slice

Before a full iPad recomposition, one bounded change can test the central thesis:

1. Fill the console at rest with the last exchange or an honest empty state.
2. Put one human status sentence beside the task identity.
3. Replace the numbered Talk instruction with “Hold to talk to this task.”
4. Hide response actions until a response exists.

If that makes the current physical iPad feel alive and self-explanatory, proceed
to the two-pane landscape study. If it does not, the problem is deeper than
layout and the task/result model needs another pass before Swift polish.

#### Five governing principles

1. **The largest surface carries the latest truth.**
2. **Name the work; reveal the wiring only when it matters.**
3. **Voice is persistent, while other actions follow context.**
4. **State is written in human language and remains legible without motion or
   color.**
5. **Landscape holds task awareness and conversation at the same time; it does
   not merely enlarge the phone deck.**

### Scout provenance

- **Opus:** completed with Claude Opus 5, high effort — `ref:5-lnv5cy`,
  flight `flt-msaln3r5-lnv5cy`, conversation
  `chn-82e27904b5094c79851a326ef9a47816`.
- **Grok:** completed through Grok ACP — `ref:3-d97283`, flight
  `flt-msaln3l3-d97283`, conversation
  `chn-2f629f1fa4aa4fc28582fddf1973c739`.
- **Kimi:** initial review completed through Kimi ACP — `ref:k-48iddc`, flight
  `flt-msaln3mk-48iddc`; the truncated reply was recovered in the same
  conversation through `ref:d-4tg6rz`, flight `flt-msaltpzd-4tg6rz`;
  conversation `chn-3eb9d530b9294dc387d020d15a61e919`.
