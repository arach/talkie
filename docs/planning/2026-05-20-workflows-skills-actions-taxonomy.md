# Workflows · Skills · Actions — Taxonomy

**Status:** open thinking · pre-decision · 2026-05-20
**Author:** arach + claude
**Adjacent work:** studio framing study at `design/studio/app/mac-skill-forge/`

## One-line ask

We have three candidate terms — *workflow*, *skill*, *action* — and a single
WFKit engine underneath. Decide whether Talkie surfaces one user-facing
concept, two, or three, and what each one means.

## How this came up

The macOS app already ships a Workflows section: list + 3-column editor,
backed by `WorkflowDefinition` + `WorkflowStep`, ~2,400 lines of Swift in
`apps/macos/Talkie/Views/Workflows/`. Mature engine, ~21 step types, real
trigger + autoRun semantics.

Separately, exploring an authoring surface this week, we landed on a
*lighter* shape: voice-triggered "skills" with a four-keyword syntax
(`WHEN / WITH / DO / THEN`). The studio mock lives at
`/mac-skill-forge` — starters gallery (3 cards) over a chat-driven
editor (chat | markup) framing.

That surfaces the question this doc is trying to answer: are skills
*the same thing as* workflows under a different name and a constrained
authoring shell, or are they a different primitive that coexists?

## What exists today (grounded)

### `WorkflowDefinition`

`apps/macos/Talkie/Workflow/WorkflowDefinition.swift`

```swift
struct WorkflowDefinition: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var description: String
    var steps: [WorkflowStep]
    var isEnabled: Bool
    var isPinned: Bool
    var autoRun: Bool        // run automatically on sync
    var autoRunOrder: Int
    var source: WorkflowSource
    // ...
}
```

A workflow is a *linear-ish* sequence of steps. Branching exists
via the `.conditional` step type. Triggers are themselves a step type
(`.trigger`) — the first step in any auto-run workflow.

### `WorkflowStep.StepType`

Twenty-one step types, grouped into categories:

| Category | Step types |
|---|---|
| **trigger** | trigger, intentExtract, executeWorkflows |
| **ai** | llm, transcribe |
| **integration** | shell, webhook, cloudUpload |
| **communication** | email, notification, iOSPush, speak |
| **apple** | appleNotes, appleReminders, appleCalendar |
| **output** | clipboard, saveFile |
| **logic** | conditional, transform |

Every step has `id`, `type`, `config: StepConfig` (variant-keyed),
input/output keys for inter-step data flow, and notes.

### What "actions" means today

There is no `Action` type in the codebase. The word "action" appears
in two informal places:

1. **Compose smart actions** — `actionRegistry` exposes things like
   "Refine", "Simplify", "Summarize" as chips on the editor surface.
   These are essentially pre-configured `.llm` steps with a prompt
   template. Single-shot, transform-the-selection. They share the
   word "action" with the Pending Actions screen and the AI Results
   activity log.
2. **Pending actions / AI Results** — runtime events emitted while
   workflows execute (LLM responses, etc.). Different sense again.

So *action* is overloaded. No formal user-authored type, but the word
shows up in three different runtime contexts.

## The three candidate terms

### Action

- **Definition (proposed):** an atomic verb the engine knows how to do.
  Maps to `WorkflowStep.StepType`. Not user-authored — chosen from a
  catalog and configured.
- **Where it surfaces today:** smart-action chips in Compose. The
  catalog is implicit (registered step types).
- **User mental model:** "the thing that happens" — a press, a send,
  a save, a tag.

### Skill

- **Definition (proposed):** a *constrained, single-trigger composition
  of actions* expressed as `WHEN / WITH / DO / THEN`. Voice-first by
  default. User-authored. Stored as a `WorkflowDefinition` underneath.
- **Where it surfaces today:** doesn't yet. Studio mock at
  `/mac-skill-forge` proposes the authoring surface.
- **User mental model:** "the thing I taught Talkie to do when I
  say X" — a declared intent with a trigger.

### Workflow

- **Definition (today):** the full `WorkflowDefinition` graph —
  multi-step, possibly branching, possibly auto-running. The internal
  data model.
- **Where it surfaces today:** Workflows section, 3-column editor,
  template picker.
- **User mental model (today):** ambiguous. The sidebar says
  "Workflows" but the existing entries vary wildly in shape — some are
  one-trigger-one-step (essentially skills), some are multi-stage
  pipelines.

## The fork

Three structurally distinct options.

### Option 1 — One concept ("Skills")

Workflows are renamed to Skills end-to-end. The Workflows sidebar
becomes "Skills". `WorkflowDefinition` is kept internally as the data
model (no migration) but no user ever sees "workflow".

- **Pro:** simplest mental model. One word, one surface, one engine.
  Skill Forge becomes the only authoring path; the existing full editor
  becomes "advanced view of a skill" — same data, more knobs.
- **Pro:** matches the user's instinct ("skill" is what they actually
  said when sketching).
- **Con:** users with complex existing workflows (multi-step branching
  pipelines) may not recognize them as "skills" anymore.
- **Con:** Forge's WHEN/WITH/DO/THEN shape doesn't fit every existing
  workflow cleanly. The advanced editor has to accommodate the gap.

### Option 2 — Two concepts ("Skills" + "Workflows")

Skill is the constrained, single-trigger consumer surface.
Workflow is the multi-step, branching, possibly autorun power-user
surface. Same data model underneath; the *authoring affordance* is the
difference.

- **Pro:** matches the lived complexity. A Slack-on-standup is a
  skill. A multi-step daily review with conditionals is a workflow.
- **Pro:** Forge has clear scope (single trigger, linear-ish), full
  editor has clear scope (everything else).
- **Con:** two sidebar entries or one section with two modes — either
  way it's two surfaces to maintain.
- **Con:** the line between them is fuzzy. When does a skill "graduate"
  to a workflow? Does Talkie auto-promote?

### Option 3 — Three concepts (Action / Skill / Workflow)

All three surface to the user as distinct ideas.

- Action: chip on selected content. Right-now transformation.
- Skill: voice-triggered intent. Declared once, fires on command.
- Workflow: scheduled/automated multi-step. Runs in the background.

- **Pro:** most honest about what users actually experience — three
  different patterns of "when something happens."
- **Con:** three terms to learn. Talkie's design language is restrained;
  three names for adjacent concepts may feel bloated.
- **Con:** "Action" is already overloaded in the codebase (Pending
  Actions, AI Results, smart actions, action chips) — adopting it as
  a user-facing first-class term needs a cleanup pass.

## Where claude's head is

Lean toward **Option 1**, with these qualifiers:

- "Skill" becomes the user-facing word. Sidebar says Skills.
- `WorkflowDefinition` stays as the internal data model — no migration,
  no data-class rename. The PR is sidebar copy + a new authoring
  surface (Forge) that produces `WorkflowDefinition`s.
- The full editor stays available as an "Open in editor →" escape
  hatch for skills that need conditional / branching / multi-step.
- "Action" is *not* a user-facing term. The current smart-action chips
  in Compose stay called "smart actions" or get a re-name (TBD), but
  they're framed as *what skills do*, not as a peer concept.
- Triggers and confirmations are first-class structural elements of a
  skill (WHEN / THEN). Inputs and the action body are the middle
  (WITH / DO).

The reason for leaning to Option 1 over Option 2: **the line between
skill and workflow is fuzzy, and we don't have evidence that users
distinguish them**. Until we see a real example of someone wanting a
"workflow that isn't a skill", the simpler taxonomy wins.

## Research questions (for codex)

Codex isn't going to make this call — taxonomy is a UX judgment. But
prior art across automation tools is worth surveying. Concrete
questions:

1. **What does each tool surface?** Apple Shortcuts, Raycast,
   Alfred, Zapier, Make (Integromat), n8n, IFTTT, Tasker. For each,
   what is the user-facing top-level concept? (Shortcut? Workflow?
   Zap? Automation? Recipe?)
2. **One concept or multiple?** Do any of them surface
   action/skill/workflow as three distinct things to users? Most seem
   to collapse to one. Confirm or contradict.
3. **What's the vocabulary for the "atomic verb" tier?** Action,
   step, block, node, module, ingredient, command? Is there a
   convention?
4. **Triggered vs manual.** How do tools that have both surface the
   distinction? Shortcuts has both "Run from Shortcuts app" and
   "Automation" as separate tabs — does that pattern hold elsewhere?
5. **Authoring escape hatch.** Do constrained authoring tools (e.g.
   Zapier's UI vs Make's node graph) coexist with an advanced editor
   for power users? Where's the seam?

What I want back from Codex: **a short brief** — 1-2 paragraphs per
tool, then a synthesis paragraph naming the *pattern* (or the lack of
one). Not a recommendation for Talkie. Just the prior-art landscape.

## Open questions for arach

1. **One concept or two?** Above leans toward one; Option 2 is the
   real alternative. Decide before we wire Forge to data.
2. **Sidebar copy.** If we go with one concept, is the user-facing
   word "Skills" or "Skill"? Plural-as-section-name vs singular.
3. **Naming the catalog.** Today's `WorkflowStep.StepType` is the
   atomic verb tier. User-facing name? Internal name? Visible at all?
4. **What about "Pending Actions" and "AI Results"?** Those screens
   use "action" in a runtime/event sense. If "action" becomes (or
   doesn't become) a user-facing term, those names need a sanity check.
5. **Migration.** Existing workflow files keep working as-is. But do
   we want a one-time pass to re-shape simple ones into the
   WHEN/WITH/DO/THEN form, or let them sit as "advanced" until
   re-edited?

## Out of scope

- Forge UI implementation (that's the next doc, after this is decided).
- The actual grammar of the skill syntax — WHEN/WITH/DO/THEN is a
  wireframe, not a committed token list.
- Voice authoring (dictating a skill end-to-end) — separate research
  thread.
