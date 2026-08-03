# iPad concept brief: Task Workbench

**Status:** Draft for confirmation  
**Track:** Primary fusion  
**Sources:** 01 The Bridge, 04 Ops Ledger, 05 Patch Bay  
**Shared contract:** `IPAD-DESIGN-BRIEF.md`  
**Required output:** Two structurally different landscape designs

## Purpose

Create the primary iPad direction for a near-technical person who uses Talkie
to check and direct Codex work on a Mac.

Combine the strongest parts of three existing concepts:

- **The Bridge:** a stable task rail, dominant live surface, persistent
  inspector, and voice shelf;
- **Ops Ledger:** current work and durable evidence remain visible together;
- **Patch Bay:** information surfaces can focus, expand, or recede without
  forcing every capability into a modal sheet.

The result must feel like one coherent instrument. Do not place all three
concepts beside each other as independent zones.

## Core thesis

The iPad is a workbench for one selected task. The person can see other tasks,
understand the selected task, inspect evidence, and speak the next instruction
without losing context.

The task conversation is always dominant. Evidence and controls support the
conversation. They do not compete with it.

## Required first-glance answers

Every design must answer these questions without interaction:

1. Which task and Mac are selected?
2. Is the task Idle, Working, Needs you, or unavailable?
3. What did Codex most recently say or produce?
4. What will happen if the person holds Talk now?

## Required anatomy

### Work rail

Show named tasks with one state each. Show the selected Mac as quiet context.
Show a lane number only as secondary metadata.

The rail must support more than six tasks. It must not reproduce the numbered
lane ribbon or add separate previous and next controls.

### Live work surface

Show the selected task title, current state, latest user instruction, and latest
Codex result or truthful live activity.

This surface is the visual anchor. It must never become an empty label plate.

### Evidence surface

Provide direct access to useful task evidence such as History, Readouts,
changed files, and task details.

Evidence must remain attached to the selected task. It may stay visible,
collapse, or enter focus mode. It must not become a generic analytics panel.

### Voice shelf

Anchor Hold to talk at the bottom of the selected task. Preserve the existing
hold and slide-to-cancel gesture.

Before capture, state whether the message will continue, steer, queue, or answer
the selected task.

### Contextual actions

Put Hear and Copy on a result. Put Stop on active work only. Put recovery on a
Mac failure. Do not recreate the permanent 4-by-4 keybed.

## Visual direction

Use Porcelain as the reference treatment:

- cool blue-white chassis;
- deep navy live-work surface;
- cobalt as the single live and selected signal;
- low-contrast rules that evoke a technical folio;
- human-readable type for task and result content;
- monospaced provenance in a subordinate role.

The design may borrow the precision of a control desk, a field notebook, or a
modular work surface. It must not imitate a terminal, mixing desk, server
dashboard, or toy hardware panel.

## Design A: Fixed command desk

Create a stable three-zone composition:

- a narrow task rail;
- a dominant live-work surface;
- a persistent evidence inspector;
- a voice shelf that belongs to the live-work surface.

The inspector changes content with selection but does not cover the live work.
The geometry stays stable across Idle, Working, and Needs you.

This design succeeds if the user can build muscle memory and scan all important
state without opening a sheet.

This design fails if the three zones receive equal visual weight or resemble an
admin dashboard.

## Design B: Operational folio

Create a two-page composition with focusable modules:

- one page holds the selected task and voice interaction;
- one page holds evidence, history, and changed files;
- a compact task rail binds the pages to one exact task;
- evidence modules can expand into a focused reading state and return without
  losing the task or Talk control.

The composition should feel like an open technical folio, not a collection of
cards. Use hierarchy and shared baselines to join the pages.

This design succeeds if evidence feels more readable and deliberate than the
fixed inspector while the live task remains continuously available.

This design fails if module movement becomes customization work or if the user
must arrange their own dashboard.

## Required states

Show both designs in these states:

1. **Idle:** latest exchange visible, Talk ready to continue.
2. **Working:** truthful activity visible, Talk consequence names Steer or
   Queue.
3. **Needs you:** Codex's question owns the live surface, and the task rail
   carries an attention signal.
4. **Mac unavailable:** last-known content remains visible and stale, Talk is
   unavailable with a reason, and connection recovery is explicit.

The full-size composition may use Idle or Working. Show the other states as
focused state studies that preserve the same layout.

## Realistic content

Use the physical capture as the identity source:

- Task: `Improve iOS connection manager`
- Project: `talkie`
- Branch: `codex/automatic-screen-preview`
- Mac: `Arachs-Mac-Mini.Local`

Use clearly illustrative task content:

- User instruction: `Make connection recovery clear on iPad.`
- Working activity: `Reviewing bridge discovery and saved ports.`
- Result excerpt: `The connection flow now separates retry, edit, and remove so
  a stale Mac does not block the rest of Talkie.`
- Needs-you prompt: `The saved Mac answers on a different port. Update this
  connection?`

Do not imply that illustrative copy describes shipped behavior.

## Adaptation

For portrait, preserve the live-work surface and voice shelf. Convert the task
rail to a compact rail or task switcher. Convert the inspector or evidence page
to a lower drawer or pager.

For compact Stage Manager width, collapse evidence before task content. Keep
the selected task, state, latest result, and Talk visible.

## Deliverables

Produce for each design:

1. One full landscape composition at the physical-capture aspect ratio.
2. One focused Needs-you state.
3. One focused Mac-unavailable state.
4. One portrait adaptation diagram or thumbnail.
5. A short rationale that names the hierarchy, voice behavior, and evidence
   model.
6. A short list of implementation risks and required data.

Do not provide Swift in this phase.

## Review rubric

Score each design against the same criteria:

| Criterion | Weight |
|---|---:|
| Four first-glance answers | 25% |
| Task and voice clarity | 20% |
| iPad-specific composition | 20% |
| State and failure behavior | 15% |
| Talkie instrument identity | 10% |
| Adaptation and accessibility | 10% |

Reject a design if it depends on invented telemetry, hides the latest result,
or makes consequential actions implicit.

## Decisions a designer must not invent

- The task remains the primary object.
- Lane numbers remain optional metadata.
- The existing delivery mode controls Steer versus Queue.
- The bridge and task stores remain authoritative.
- Voice does not approve consequential actions.
- The iPhone deck remains outside this design track.

