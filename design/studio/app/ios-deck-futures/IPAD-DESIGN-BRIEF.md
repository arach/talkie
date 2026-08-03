# Talkie iPad Codex surface design brief

**Status:** Draft for confirmation  
**Mode:** Operate  
**Target:** `CodexCommandDeckSurface` on iPadOS 26  
**Reference device:** iPad Air (5th generation), landscape  
**Studio:** `/ios-deck-futures`  
**Evidence:** physical-device capture, current Swift implementation, and the
Opus, Grok, and Kimi critiques in `IPAD-CRITIQUE.md`

## Decision

Replace the enlarged phone deck on iPad with a task-first conversation
instrument. The iPad surface must show named work, the latest Codex truth, and
the next voice action without asking the user to decode lane machinery or a
permanent key matrix.

The design promise is: **See the work. Hear what came back. Speak the next
move.**

This brief is ready for direction confirmation. It does not authorize Swift
implementation.

## Direction program

Use this document as the shared product and interaction contract for two design
tracks:

1. **Primary fusion:** combine 01 The Bridge, 04 Ops Ledger, and 05 Patch Bay.
   Use `IPAD-BRIEF-WORKBENCH.md`.
2. **Independent wildcard:** develop 03 Flight Recorder as a separate temporal
   thesis. Use `IPAD-BRIEF-FLIGHT-RECORDER.md`.

Each track must produce at least two structurally different designs. Color or
component restyling alone does not count as a second design.

## Job and audience

The primary user is near-technical. They understand projects, branches, tasks,
Macs, and agents. They do not want to operate a terminal or learn an internal
routing model before they can continue work.

The user opens Talkie on an iPad while one or more Codex tasks are running on a
Mac. They need to check the work, notice when Codex needs them, hear or read the
latest result, and speak a safe follow-up.

The surface is successful when the user can answer four questions in one
glance:

1. Which task and Mac am I addressing?
2. What is Codex doing, and does it need me?
3. What did Codex most recently produce?
4. What will happen if I speak now?

## Current behavior

The physical iPad capture verifies the following behavior:

- A six-position lane ribbon spans the screen.
- A large console shows task identity, repository provenance, a numbered Talk
  instruction, and `CODEX> READY`.
- The console does not show the latest exchange in the captured idle state.
- A permanent 4-by-4 keybed gives setup, navigation, playback, status, and Talk
  similar visual weight.
- Several keys remain visible while unavailable.
- An unmapped task displays `NO LANE`, although the task remains valid.

The current design has the correct instrument character. It gives the largest
area to the least useful information.

## Selected direction

### Product model

The task is the primary object. A lane is an optional address for fast voice
targeting. A Mac bridge is the place where the task runs.

The interface must lead with the task name. It may show a lane number as quiet
secondary metadata. An unmapped task must not appear broken.

The bridge must stay quiet while healthy. If the bridge fails, the bridge
failure becomes the primary state because the user can no longer act on the
task.

### Structural thesis

Use a two-pane landscape composition with a contextual action edge:

1. The leading pane shows available work.
2. The main pane shows the selected task and its latest exchange.
3. The bottom of the main pane holds the persistent voice action.
4. Secondary actions appear beside the content they affect.

This composition gives the user fleet awareness and task focus at the same
time. It must not become a grid of operational widgets.

### Visual authority

The first visual study must use the existing **Porcelain** treatment:

- a cool blue-white outer chassis;
- a deep navy work pane;
- cobalt as the single live, selected, and completion signal;
- thin low-contrast dividers;
- human-readable sans-serif text for tasks, state, and results;
- monospaced text only for branch, path, lane, and other provenance.

The design must preserve Talkie's restrained instrument quality. The design
must not depend on numbered keycaps, terminal prompts, fake hardware, or dense
microtype to feel technical.

Validate the composition in Mineral and system dark appearance after the
Porcelain direction is coherent. Do not redesign the theme system in this
slice.

### Focal moment

The main pane is the focal surface. It always contains one current truth:

- the latest exchange while the task is idle;
- live activity while Codex is working;
- the blocking question while Codex needs the user;
- the last-known exchange and connection failure while the Mac is unavailable.

Empty black space is not an idle state.

## Information model

Use these nouns consistently:

| Noun | Meaning | Presentation |
|---|---|---|
| **Task** | One named Codex work context | Primary identity and navigation item |
| **Mac** | The computer that runs the task | Secondary identity while healthy; primary problem when unavailable |
| **Lane** | An optional numbered address assigned to a task | Quiet metadata and mapping affordance |
| **Turn** | One user instruction and its Codex work | Current activity or completed exchange |
| **Result** | The response from a completed turn | Readable content with local actions |
| **Delivery mode** | The existing steer or queue choice for an active turn | Explicit helper text before voice dispatch |

Do not use `RDY`, `RUN`, `QUE`, `RX`, `VOX`, or `CODEX>` as the only expression
of a state. Decorative codes may reinforce plain language, but they must not
carry required meaning.

## Layout and hierarchy

### Leading pane: available work

The leading pane should occupy about one quarter of a landscape iPad. It must
contain:

- the selected Mac name and one health statement;
- a scrollable list of named tasks;
- one human state for each task;
- the project name as secondary context;
- an optional lane number as tertiary metadata;
- one deliberate entry to browse tasks or assign lanes.

The list must use one selection model. Do not retain separate lane ribbon,
previous-lane key, and next-lane key controls.

### Main pane: selected task

The main pane must contain:

- the task title;
- the canonical state in plain language;
- the Mac and project identity;
- quiet branch provenance;
- the user's latest instruction;
- Codex's latest result or current activity;
- contextual result actions;
- the persistent voice control.

The main pane must keep the latest useful content visible while the task is
idle. Full history may open in a secondary surface.

### Contextual actions

Attach actions to their objects:

- Put Hear and Copy on a result.
- Put Stop beside active work only when Stop is supported.
- Put History in the task header or result context.
- Put task details on task identity.
- Put output routing in voice settings.
- Put connection recovery on the bridge failure surface.

Mapper, Spaces, Details, Refresh, Read, Copy, Replay, Stop, Task, and Readout
must not remain as equal permanent keys.

## Voice interaction

The Talk control must remain in one predictable location at the bottom of the
main pane. Preserve the existing hold gesture, slide-to-cancel behavior,
capture perimeter, and haptic feedback.

The helper text must name the dispatch result before capture:

- If no turn is active, show `Hold to continue this task`.
- If a turn is active and delivery mode is Steer, show `Hold to steer this
  turn`.
- If a turn is active and delivery mode is Queue, show `Hold to queue a
  follow-up`.
- If Codex asks a question that voice can answer, show `Hold to answer`.
- If the Mac is unavailable, disable Talk and show `Talk unavailable while the
  Mac is offline`.

Talkie must send voice to the selected task only. Talkie must not infer an
approval, destructive action, or delivery-mode change from speech alone.

## State contract

### Idle

- Show the latest exchange.
- Show `Idle` as a quiet state label.
- Keep Talk available.
- Do not replace useful content with `Ready`.

### Working

- Show what Codex is doing in plain language when truthful activity exists.
- Show elapsed time when the start time is available.
- Keep the user's latest instruction visible.
- Keep Talk available with the current Steer or Queue consequence stated.
- Use one restrained motion signal. Respect Reduce Motion.

### Needs you

- Put the blocking question or approval request at the top of the main pane.
- Mark the task in the leading pane so attention survives task switching.
- Allow a voice answer when the task accepts ordinary text.
- Keep approve, deny, stop, and other consequential actions as explicit
  controls.
- Give this state more visual priority than Working.

### Mac unavailable

- State `Mac unavailable` and name the affected Mac.
- Show when Talkie last heard from the Mac.
- Preserve the last-known task and result as stale content.
- Disable Talk and explain why.
- Offer Reconnect, Review connection, and Choose another Mac when those actions
  are available.
- Do not present stale task state as current.

### Empty and loading states

- If the Mac has no tasks, explain that no Codex tasks are available and offer
  the existing task-browse or task-create path.
- While tasks load, preserve the selected Mac identity and avoid placeholder
  controls that imply availability.
- If refresh fails but cached tasks exist, keep the cached tasks, mark their
  age, and offer Retry.

## Content ranges

The design must remain usable with these ranges:

- zero tasks;
- one selected task;
- two to six active or recent tasks;
- more than six tasks in a scrollable or searchable list;
- one to three known Macs;
- a one-line task title or a title that wraps to two lines;
- short and long project or branch names;
- no previous result;
- a two-line result excerpt;
- a result long enough to require a full reading surface;
- simultaneous Working and Needs you states on different tasks.

Do not truncate the task title before project or branch metadata. Do not allow
long content to move the Talk control out of reach.

## Adaptation

Landscape is the reference composition.

In portrait, move the leading pane into a persistent compact task rail or a
single task-switcher control. Keep the main pane and Talk control primary. Do
not recreate the phone keybed to fill the narrower width.

In compact Stage Manager widths, preserve selected-task identity, current
state, latest result, and Talk. Collapse provenance and secondary actions
before removing task content.

## Accessibility and input

- State must remain understandable without color or motion.
- VoiceOver must announce the selected task, Mac, state, and Talk consequence
  as one coherent context.
- Dynamic Type must preserve the task title, state, latest result, and Talk.
- Pointer and keyboard users must receive visible focus treatment.
- The design must preserve standard iPad touch targets.
- Reduce Motion must replace animated activity with a static state signal.
- Increased Contrast must strengthen separators and state text without adding
  new colors.

## Scope

This brief includes:

- an iPad-specific composition for `CodexCommandDeckSurface`;
- task-first navigation;
- latest exchange and current-state presentation;
- contextual result actions;
- existing voice dispatch behavior;
- idle, working, needs-you, unavailable, loading, and empty states;
- landscape, portrait, and compact-width adaptation.

This brief excludes:

- changes to the bridge protocol or authentication;
- new Codex lifecycle or reasoning telemetry;
- a redesign of Connection Center;
- a redesign of the iPhone deck;
- changes to Steer, Queue, Stop, or task-creation semantics;
- automatic approval or destructive voice actions;
- a generic multi-agent dashboard;
- terminal emulation;
- a new theme system.

The existing task store, bridge store, voice capture, delivery mode, narration,
and sheet behavior remain authoritative until a separate product decision
changes them.

## Acceptance checks

1. On a physical landscape iPad, select an idle task with a previous result.
   The first viewport shows the task, Mac, Idle state, latest result, and Hold
   to continue without opening another surface.
2. Select an unmapped task. The task remains available, and the interface does
   not show an error or warning solely because no lane is assigned.
3. Start a Codex turn. The main pane shows Working and truthful activity. The
   Talk helper states the active Steer or Queue consequence.
4. Make a task require a question or approval. The question becomes the main
   focal content, the task list shows Needs you, and approval remains an
   explicit control.
5. Disconnect the selected Mac. The surface preserves stale task content,
   states when the Mac was last heard from, disables Talk with a reason, and
   offers a connection recovery path.
6. Load more than six tasks. The user can select any task through one task
   switcher without lane-step controls.
7. Load a long task title, long branch, and long result. The task title and Talk
   remain visible, while provenance and result detail disclose progressively.
8. Rotate the device to portrait and resize it with Stage Manager. The selected
   task, state, latest result, and Talk remain primary.
9. Enable VoiceOver, an accessibility text size, Increased Contrast, and Reduce
   Motion. Every required state and action remains legible and operable.
10. Test Porcelain in light appearance and Mineral in dark appearance on a
    physical iPad. State remains clear without relying on color alone.

## Open decisions for confirmation

1. Confirm that named tasks replace numbered lanes as the primary navigation
   model on iPad.
2. Confirm Porcelain as the first prototype treatment.
3. Confirm that iPad receives a distinct composition while the iPhone deck
   remains unchanged.
4. Confirm whether lane numbers remain visible in every task row or appear only
   in task details and mapping.
5. Verify which current bridge events can truthfully distinguish Working from
   Needs you before implementation. The design must not invent progress or
   attention states that the bridge cannot provide.
