# iPad concept brief: Flight Recorder

**Status:** Draft for confirmation  
**Track:** Independent wildcard  
**Source:** 03 Flight Recorder  
**Shared contract:** `IPAD-DESIGN-BRIEF.md`  
**Required output:** Two structurally different landscape designs

## Purpose

Develop a credible opposing thesis to the Task Workbench.

The Flight Recorder treats time and activity as the main organizing surface.
It asks whether a near-technical user can understand several Codex tasks more
quickly by seeing what happened, what is happening, and what needs attention on
one temporal canvas.

This track may challenge the primary composition. It must preserve exact task
targeting, safe voice behavior, human-readable state, and truthful data.

## Core thesis

Work becomes understandable when events form a visible record. A task is not
only a destination. It is a sequence of instructions, state changes, results,
questions, and failures.

The timeline must read as work history, not system telemetry. The user should
see meaningful events such as `Asked`, `Working`, `Result`, `Needs you`, and
`Mac unavailable`. Internal logs and reasoning traces do not belong on the
primary canvas.

## Required first-glance answers

Every design must answer these questions without interaction:

1. Which task will receive voice?
2. Which tasks are active or need the user?
3. What happened most recently on the selected task?
4. What will happen if the person holds Talk now?

## Required anatomy

### Time canvas

Show events in a clear temporal order. Each event must belong to one named
task. Use readable content excerpts, not only dots or codes.

The canvas must distinguish a current event from a completed result and a stale
last-known event.

### Task identity

Keep task names visible on or beside the timeline. The selected task must be
unambiguous. Lane numbers may appear as secondary addresses.

### Event detail

Selecting an event must reveal its task, time, state, content, and relevant
actions. The detail surface must not hide which task will receive Talk.

### Master voice rail

Anchor Talk outside the scrolling time canvas. Bind Talk to the selected task.
State whether voice will continue, steer, queue, or answer before capture.

### Attention model

Needs you must outrank Working. A question or approval event must remain
visible until resolved, even when newer background events arrive elsewhere.

## Visual direction

Use Porcelain as the shared comparison treatment. The wildcard may use a darker
navy time canvas if contrast and event density require it.

Use cobalt for selection and live work. Reserve one distinct attention signal
for Needs you and one failure treatment for Mac unavailable. Do not create a
rainbow status system.

The design may borrow from a flight recorder, annotated tape, or technical
chronicle. It must not resemble a source-control graph, performance trace,
server log viewer, or Gantt chart.

## Design A: Selected-task tape

Create one dominant timeline for the selected task:

- the latest user instruction, live work, result, and question form a readable
  tape;
- other tasks appear in a compact peripheral rail with state and latest-event
  markers;
- selecting another task replaces the dominant tape without moving Talk;
- event detail opens beside the tape or inline.

This design favors comprehension of one task over simultaneous comparison.

This design succeeds if the latest exchange and current state are more legible
than in a conventional conversation view.

This design fails if the timeline adds chronology without improving the four
first-glance answers.

## Design B: Cross-task chronicle

Create aligned task swimlanes against one shared time axis:

- each named task owns one lane;
- meaningful events appear as readable markers or short excerpts;
- the selected event opens a persistent inspector;
- the selected task owns the master voice rail;
- Needs-you events remain prominent across the full canvas.

This design favors fleet awareness and comparison.

This design succeeds if a user can identify the next task that deserves
attention without reading every lane.

This design fails if the screen becomes an operations dashboard or requires
expert interpretation of timing marks.

## Required states

Show both designs with these event types:

1. **Idle result:** a completed turn with a readable result excerpt.
2. **Working:** an active turn with truthful activity or a plain Working event.
3. **Needs you:** a persistent question or approval event.
4. **Mac unavailable:** a connection event that freezes later task activity and
   marks following content as stale.

Do not fabricate granular progress, reasoning, token counts, or file events that
the current bridge does not provide. If a proposed event requires new data,
label that requirement in the rationale.

## Realistic content

Use the physical capture as the selected identity:

- Task: `Improve iOS connection manager`
- Project: `talkie`
- Branch: `codex/automatic-screen-preview`
- Mac: `Arachs-Mac-Mini.Local`

Use two to six additional named tasks so the cross-task design faces realistic
density. Keep task names concrete. Do not use `Task 1` or `Agent A`.

Use the same illustrative events as the Task Workbench brief so reviewers can
compare designs without content bias.

## Temporal behavior

- New events must not push an unresolved Needs-you event out of awareness.
- Scrolling into history must not change the selected voice destination.
- Selecting an event may select its task only when the change is explicit.
- Returning to Now must be one clear action.
- Time must remain understandable without relying on spatial precision alone.
- Bridge failure must stop the appearance of current events for the affected
  Mac and mark the last event as stale.

## Adaptation

For portrait, give the selected task the full timeline. Show other tasks in a
compact overview above or below it. Keep Talk anchored outside the scrolling
history.

For compact Stage Manager width, collapse the event inspector before reducing
event legibility. Do not reduce task names to lane numbers.

## Deliverables

Produce for each design:

1. One full landscape composition at the physical-capture aspect ratio.
2. One event-detail state.
3. One Needs-you state that includes activity on another task.
4. One Mac-unavailable state.
5. One portrait adaptation diagram or thumbnail.
6. A short rationale that explains time orientation, selection, and voice
   targeting.
7. A data inventory that separates current bridge data from proposed data.

Do not provide Swift in this phase.

## Review rubric

| Criterion | Weight |
|---|---:|
| Four first-glance answers | 25% |
| Temporal comprehension | 20% |
| Voice destination safety | 20% |
| Attention and failure behavior | 15% |
| Talkie instrument identity | 10% |
| Adaptation and accessibility | 10% |

Reject a design if it becomes a generic monitoring dashboard, hides the latest
result behind event markers, or implies live data that Talkie does not have.

## Decisions a designer must not invent

- Talk always targets one explicitly selected task.
- Needs you outranks Working.
- The current bridge contract remains the source of truth.
- Reasoning traces and internal logs remain unavailable.
- Consequential actions require explicit controls.
- The Task Workbench remains an independent comparison track.

