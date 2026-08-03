## Current iPad critique — Kimi (independent review)

**Reviewer:** Kimi  
**Evidence:** landscape capture
`/Users/arach/.codex/visualizations/2026/08/01/019fbddf-37c3-7fd2-b108-961e0559c6bf/ipad-current-view.png`
and `apps/ios/Talkie iOS/Codex/CodexCommandDeckSurface.swift`  
**Mode:** Words only. No Swift or Studio changes.

### 1. First five seconds — what the user believes, and where it breaks

The first read is "a hardware control surface for something technical." The
dark console lid, the keycap indices (01–16), and the monospaced labels all
say *instrument*, which is on-brand for Talkie. But the belief that breaks
fastest is the most basic one: *this screen is about my work*. The console —
the largest element on the screen — spends most of its area on emptiness. The
task title "Improve iOS connection manager" is legible, but nothing in the
console shows what Codex last said, what it is doing now, or whether it is
waiting on me. The console is a label plate, not a window.

Meanwhile the keybed fills the lower half with sixteen positions, roughly
half of which (Read, Copy, Replay, Stop, Refresh, lane stepping) are
secondary acts dressed as primary ones. Within five seconds the user
concludes "this is a remote control for experts," and the one thing they came
for — the conversation with Codex — is nowhere visible.

The `CODEX> READY` footer is a terminal tell that contradicts the "no literal
terminal" constraint while still failing to be a real terminal. It sits in
the uncanny valley between the two: enough jargon to exclude the
near-technical user, not enough function to serve the expert.

### 2. Information hierarchy for iPad

- **Primary (always visible, always fresh):** the current task in plain
  language; Codex's live state as one of four human words (idle, working,
  needs you, unreachable); the latest thing Codex produced as a two-to-three
  line excerpt, not just the fact that one exists; and the talk affordance.
- **Secondary (one glance or one tap):** the task/lane switcher rendered as
  named work ("Improve iOS connection manager — working"), not numbered
  slots; narration controls while narration is actually playing; the bridge
  identity and health.
- **Progressively disclosed:** History, full response text, task details,
  changed files, Mapper, Spaces, output routing, refresh. These are sheets
  and panels, not permanent keycaps. The source already models all of them as
  sheets (`showingHistory`, `showingReadoutHistory`, `showingTaskDetails`,
  and so on) — the keybed is duplicating doors that only need one contextual
  handle each.

### 3. How landscape should change the composition

Landscape iPad is a two-column conversation, not a taller remote. The phone
deck's stack (console over keybed) should split:

- a **left column that is the task itself** — identity, live status, and the
  actual exchange with Codex (latest response, your last ask, streaming
  state);
- a **right rail that is the instrument** — a vertical lane strip showing
  named tasks with state dots, the talk control anchored at the bottom near
  the thumb, and at most a handful of contextual actions that change with
  state ("Hear it" appears only when there is something to hear).

The console's dead space is the single clearest signal that the phone layout
was scaled rather than rethought: on a 2746px canvas, the content the user
cares about would fit in a third of the lid. The same is true of the
six-position lane ribbon stretched across the full width — a phone component
pulled past its meaning. As a vertical named list it gains room for task
titles and per-task status, which is what lanes are actually for.

### 4. Clearest mental model

The model the current screen teaches is *switchboard*: numbered lanes,
keycap indices, `RDY/RUN/QUE/RX/VOX` signal codes, `CODEX> READY`. That is
an operator's model. The model a near-technical user already carries is
simpler: **"my Mac is working on several things; this iPad is how I check in
and talk to whichever one I mean."**

In that model:

- A *task* is a unit of work with a name — the hero object.
- A *lane* is just "which task I'm talking to right now" — a selection, not
  a destination system. Lane numbers are an implementation leak; the mapper
  already thinks in tasks, and the ribbon should too.
- The *bridge* is plumbing: invisible when healthy, loud when broken.
- *Live work* is a state of the task ("Codex is working on X"), not a meter.
- A *result* is the latest response, shown as content, first-class.
- *Voice follow-up* is "hold and talk to this task" — one gesture, always
  attached to the current task, never to an abstract destination.

### 5. Four states

- **Idle:** task name, a quiet "Idle" word, and the last response excerpt —
  idle is a reading state, so content leads. Talk key calm and available.
- **Codex working:** the status word changes to "Working" with subtle motion
  confined to one place (the existing status instrument is enough, elevated
  into the task header); the console shows the in-flight turn ("You asked…"
  plus elapsed feel); Talk stays live with its steer/queue behavior made
  visible as a plain-language hint ("Hold to add to this").
- **Needs attention:** this state currently has no representation — it is
  the biggest gap in the deck. A question or blocker from Codex should be
  the most saturated thing on the screen: the question itself quoted in the
  console, an explicit answer-by-voice affordance, and a badge on the task
  in the lane list so attention survives task switching. "Needs you" must
  outrank "working."
- **Bridge failure:** the whole deck is meaningless without the bridge, so
  the failure should own the header and tint the task area cold red (the
  codebase already reserves a single cold red for failures — use it at the
  frame level, not just a dot): "Mac mini unreachable — last seen 12:04."
  Talk and all task actions visibly disabled, one explicit Reconnect action,
  and the last known state preserved underneath so nothing feels lost.

### 6. Remain / move / merge / disappear

- **Remain:** the task identity header (title, project, branch — though the
  branch can quiet down); the status instrument as the single motion
  element; the push-to-talk capture key with its slide-to-cancel; the
  capture perimeter glow; the lane concept itself; the narration rail when
  active (it is already a well-scoped overlay).
- **Move:** narration transport (Replay/Stop/Read) out of the permanent
  keybed into the narration rail and the response view — they only mean
  something when audio or a response exists. History and Details into the
  task header as taps on the content they describe. The output-route dial
  into Settings or a long-press on the narration affordance — it is a
  set-and-forget preference, not a per-session instrument.
- **Merge:** the lane ribbon and the two lane-step keys into one task
  switcher (three ways to change lanes is two too many). Read, Copy, and
  Replay merge into one "latest response" surface with its own actions.
  Mapper and Spaces are both "go somewhere else" and can share one
  navigation entry. The `CODEX> READY` footer and the Details key's status
  readout merge into one status voice — the screen currently narrates state
  in three vocabularies (footer text, meter codes, lane rail signals).
- **Disappear:** the keycap index numbers (01–16) — they reference a
  hardware metaphor the user never benefits from; empty keycap sockets; the
  `NO LANE` badge as a persistent element (it is a one-time onboarding
  state); Refresh as a keycap (sync should be automatic with a quiet
  last-updated note); the terminal-flavored `CODEX>` prompt glyph.

### 7. Five principles for the next iPad study

1. **Content is the console.** The largest surface shows the exchange —
   latest response and live state — not a label plate. Empty console space
   is a bug, not breathing room.
2. **Name the work, not the wiring.** Tasks and state in human words
   ("Working on connection manager", "Needs you"); lanes, bridges, queues,
   and signal codes stay below the waterline unless they break.
3. **One voice for state.** Exactly one status vocabulary, one animated
   element, one failure color, one place each fact lives. If two elements
   say "ready," one of them goes.
4. **Actions follow context.** The persistent controls are Talk, switch
   task, and see more. Everything else appears with the content it acts on —
   audio controls with audio, response actions with a response.
5. **Landscape is a conversation, not a bigger remote.** Recompose into
   task-plus-instrument columns; never stretch a phone component wider as a
   substitute for using the space.
