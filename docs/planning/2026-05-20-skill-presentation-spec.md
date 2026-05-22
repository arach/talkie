# Skill — presentation & data model spec

**Status:** spec · pre-implementation · 2026-05-20
**Author:** arach + claude
**Predecessors:**
- Taxonomy thinking → `2026-05-20-workflows-skills-actions-taxonomy.md`
- Classical prior art → `2026-05-20-taxonomy-prior-art.md`
- AI/agentic prior art → `2026-05-20-taxonomy-ai-tools.md`
- Codebase-state survey → `2026-05-20-taxonomy-codebase-state.md`
- Studio committed surface → `design/studio/app/mac-skills/`
- Studio framing archive → `design/studio/app/mac-skill-forge/`

## Pinned decision

**Talkie surfaces one user-facing automation concept: the Skill.** Backed by:

- Classical prior art: container-noun-plus-building-blocks is the *rule* across 11 surveyed tools (Shortcut, Workflow, Zap, Scenario, Applet, Macro, Flow…). Three peer concepts has zero prior art.
- Agentic prior art: "Skill" is the *convergent cross-vendor name* — Anthropic SKILL.md is adopted unchanged by Cursor and Windsurf as an open standard.
- Internal: the WHEN/WITH/DO/THEN syntax we sketched maps 1:1 onto SKILL.md frontmatter, opening a potential interop path.

The fork has been collapsed. The remaining work is *how to present and persist*.

## User-facing model

A **Skill** is a single-trigger, single-outcome packaged capability. Four structural elements:

| Element | Keyword | Meaning |
|---|---|---|
| **Trigger** | `WHEN` | What fires the skill (voice phrase, hotkey, schedule, event) |
| **Inputs** | `WITH` | What the skill captures or pulls in (region, selection, last paragraph, dictation) |
| **Action** | `DO` | What the skill does (github.issue, slack.post, library.note, …) |
| **Confirmation** | `THEN` | How the skill closes (voice ack, banner, log entry) |

WHEN and DO are required. WITH and THEN are optional. A skill with multiple WITH lines reads as ordered input collection; a skill with multiple DO lines reads as a small linear sequence (no branching at this layer — see "Escape hatch" below).

Reading register: telegram-like. Mono. Each keyword on its own line, uppercase, amber. Sub-fields indent with `↳`.

### How skills compose — polymorphic DO

`DO` is polymorphic. Three modes:

- **Single action** (`DO github.issue`) — atomic skill. One catalog step.
- **Sequence** (`DO sequence`) — chain of skills run in order. Each sub-field references another skill: `↳ skill.pull-calendar`, `↳ skill.daily-standup`, `↳ skill.weekly-digest`.
- **Route** (`DO route via intent`) — branch to a child skill based on intent extraction. The Hey Talkie pattern: `↳ "log bug" → skill.log-bug`, `↳ "standup" → skill.daily-standup`, `↳ fallback → skill.capture-thought`.

Composition stays in the same four-keyword grammar — sequence and route are just shapes `DO` can take. Mechanically they map to existing engine steps: `DO sequence` is `executeWorkflows` with an ordered list; `DO route` is `intentExtract` + `executeWorkflows`. The Hey Talkie auto-run seed (`apps/macos/Talkie/Workflow/WorkflowDefinition.swift:220-252`) is literally this shape.

This is what lets the single user-facing concept ("Skill") hold even though Talkie's engine has real orchestration. Composed skills are still skills; their pipeline preview reads `DO sequence(3)` or `DO route(4)` in the gallery card and the chain is visible in the markup.

### Skill modes (gallery card variants)

| Mode | Status chip | DO shape | Editor surface |
|---|---|---|---|
| **Atomic** | `READY` / `DRAFT` / `EDITING` | single catalog step | editor bay (WHEN/WITH/DO/THEN) |
| **Composed** | `READY` / `DRAFT` / `EDITING` (same chip — no badge change) | `sequence` or `route` over child skills | editor bay (same surface, DO renders its sub-skills inline) |
| **Workflow** | **`WORKFLOW`** badge | branching / conditionals / multi-output chaining that exceeds WHEN/WITH/DO/THEN even with sequence/route | legacy 3-column "Workflow Editor" (escape hatch) |

Atomic and composed both fit `.skill.md`. Only the Workflow mode requires the graph editor.

**Where "Workflow" surfaces to the user:**

1. **Gallery card chip** — the `WORKFLOW` badge replaces `READY`/`DRAFT` on the right side of the card.
2. **Editor surface title** — clicking "Open in editor →" on a graduated skill opens the existing legacy editor with the title bar reading **"Workflow Editor"**. The user knows they're in a different authoring mode.

Sidebar stays "Skills." iOS surfaces stay "Skills." Workflow is never a section name; it's a mode label that appears at the moment of relevance.

## Data model

Skills are a **constrained, opinionated *view* over the existing `WorkflowDefinition`**. No new data class is introduced. No migration.

Mapping:

| Skill element | WorkflowDefinition shape |
|---|---|
| `WHEN` | A `WorkflowStep` of `.trigger` type as the first step |
| `WITH` | Zero or more input steps (`.transcribe`, `.transform`, screenshot-capture variant, …) chained via `inputKey`/`outputKey` |
| `DO` | One action step (`.llm`, `.webhook`, `.slack`-via-webhook, `.appleNotes`, `.saveFile`, …) — the work the skill exists to perform |
| `THEN` | Zero or one confirmation step (`.notification`, `.speak`, `.clipboard`, …) |

Skill metadata maps directly:

| Skill | WorkflowDefinition field |
|---|---|
| display name | `name` |
| description | `description` |
| icon | `icon` |
| status (READY/DRAFT) | derived from `isEnabled` |
| pinned in gallery | `isPinned` |
| auto-fires on event | `autoRun` |
| trigger order (if multiple) | `autoRunOrder` |
| origin | `source` |

**Skills never need fields `WorkflowDefinition` doesn't already have.** This is the load-bearing claim of this spec. If we discover a skill concept that needs a new field, that's a signal we're stretching the constrained shape too far — open the full editor instead (see "Escape hatch").

## File format

Skills persist as **`.skill.md`** files — Anthropic SKILL.md-compatible with a Talkie extension. Living format on disk, parsed into `WorkflowDefinition` at load.

```markdown
---
name: Log Bug
description: Capture a region + last paragraph and open a GitHub issue.
trigger:
  type: voice
  phrase: "log bug"
inputs:
  - capture.region
  - editor.last_paragraph
action:
  type: github.issue
  title: derive_from_selection
  body: "{{ inputs.0 }}\n\n---\n\n{{ inputs.1 }}"
confirm:
  type: voice.ack
icon: ant
isEnabled: true
isPinned: false
---

# Log Bug

When I say "log bug," capture a region screenshot and grab my last
paragraph. Open a GitHub issue with the screenshot as the body and the
paragraph as context. Confirm with a voice acknowledgment.
```

YAML frontmatter is the *machine* representation (loads into a `WorkflowDefinition`). The markdown body is the *human* representation — natural-language statement of intent, dictatable, useful for the chat editor to round-trip. Both stay in sync via the Forge.

**Interop path:** the frontmatter `name` / `description` / `when-to-use`-equivalent fields are deliberately a superset of Anthropic's SKILL.md schema. A Talkie skill should be openable in Claude Code (the action just won't execute outside Talkie's runtime). A Claude Code skill could potentially be imported as a starting point.

Storage location: `~/Library/Application Support/Talkie/Skills/` (parallel to existing `Workflow/` dir which keeps holding `.workflow.json` files for any pre-Skill workflows). One file per skill. Atomic writes.

## Step / Tool tier (the catalog)

The existing `WorkflowStep.StepType` (**19 variants** — confirmed by codebase audit: llm, shell, webhook, email, notification, iOSPush, appleNotes, appleReminders, appleCalendar, clipboard, saveFile, conditional, transform, transcribe, speak, trigger, intentExtract, executeWorkflows, cloudUpload) is **the catalog of things a Skill's DO can call**. This tier is not user-facing as a peer concept — users see "DO github.issue", not "DO step.type=.webhook with config…". The editor bay's DO field exposes the catalog as a typeahead-able list, but the underlying name is the engine's name.

When a future Skill needs something the catalog doesn't have, we add a `WorkflowStep.StepType` case. Catalog growth is the engineering work; the Skill surface stays stable.

## What about "Action"?

**Decision: "Action" stays narrow. Intentional overload. No renames.**

The codebase-state brief (`2026-05-20-taxonomy-codebase-state.md` §3) found "Action" already overloaded across ~10 user-facing surfaces: SmartAction chips in Compose, ActionEditorSheet in Settings, Context-Aware Quick Actions, PendingActions, Mac Actions (iOS), ComposeWorkflowAction (iOS), Quick Actions, plus WFKit's `NodeType.action`. This was a real ambiguity that could have argued for a rename.

The decision is to keep it. The reasoning: **Skill and Action live at different abstraction tiers.** Skill = the definition (you author a Skill, save it, the gallery lists it). Action = the manifestation (a chip in Compose, a button in Quick Actions, a row in Pending). Users don't see them collide because they never appear at the same tier in the same surface. This matches the prior-art convention — Shortcut+Action, Flow+Action, Scenario+Module/Action — every surveyed tool keeps "Action" as the secondary tier under a top-level container.

What this means concretely:

- **No renames anywhere.** SmartAction chips stay "Smart Actions." ActionEditorSheet stays. PendingActions / "Recent actions" stay. Mac Actions on iOS stays in concept (label changes — see iOS section below). WFKit's `NodeType.action` stays. The "Quick Actions" settings label stays.
- **A skill manifests as an action where the surface calls for it.** A skill named "Daily Standup" appears in Compose's Smart Actions row as a chip labeled "Daily Standup." Same skill, two tiers of naming.

## Presentation surfaces

### Sidebar

- **"Skills"** replaces **"Workflows"** in the sidebar. Same icon (`wand.and.stars`). Internal `NavigationSection.workflows` enum case keeps its name — wire stays untouched.
- The existing Workflows feature continues to render under this entry. Existing `.workflow.json` files keep working; they just appear under the new label.

### Surface map (within the Skills section)

```
Skills (single page — everything lives here)
├─ Editor bay        — chat ↔ markup of the active skill
├─ Console strip     — last run output
├─ Starters row      — 3-up cards, Talkie-shipped templates
├─ Your skills row   — cards for user-authored skills (empty on day one)
└─ Where it fires    — invocation-surface previews (Compose / Voice / Library)

Escape hatch: existing 3-column WorkflowDefinition editor, reached
via "Open in editor →" for advanced skills that outgrow WHEN/WITH/DO/THEN.
```

The committed shape is **one tab, one page, top-to-bottom journey** — wireframed at `design/studio/app/mac-skills/`. The earlier `mac-skill-forge` study is kept as an archive of the framing comparison that led here; the editor / list / detail are no longer separate tabs. "Forge" was a working name during exploration and is dropped — the editor bay isn't named at the product level.

Routing:

- Sidebar → Skills → land on the **Skills page** (the editor bay is empty + inviting on day one).
- Starter card click → starter loads into the **editor bay** above; card shows EDITING badge + `OPEN ABOVE ↑`.
- "+ New Skill" → editor bay clears to an empty `.skill.md` template.
- Save → skill lands in the **your skills** row, can be edited again by clicking its card.
- "Open in editor →" on a saved skill → existing `WorkflowDetailColumn` (3-column legacy editor).

### Gallery anatomy

(Already wireframed at `design/studio/app/mac-skills/`.) Card columns:

- Category eyebrow (Productivity / Comms / Personal / …)
- S-NNNN code
- Display name (font-display, 20pt)
- Italic byline (one line, voice-y)
- Hairline rule
- Compact pipeline preview: `WHEN voice · WITH region · DO github · THEN ack`
- Footer: status chip (READY/DRAFT amber/ink) + `USE →` or `OPEN →`

### Editor bay anatomy

Sits at the top of the Skills page. Two side-by-side panes + a console strip below:

- **Chat (left)**: conversation with the agent. Voice or typed. Agent composes the skill in response to intent ("make a skill that logs bugs").
- **Markup (right)**: `.skill.md` rendered as syntax-highlighted code (CodeMirror in WKWebView). Updated by the agent and editable by the user.
- **Console strip (below)**: run output from the last dry-run / live run.

Header: status chip (DRAFT/READY/EDITING), RUN / SAVE affordances, OPEN IN EDITOR escape hatch.

### Where it fires

The Skills page closes with a 3-up preview row showing where saved skills manifest in the rest of Talkie:

- **Compose · action chip** — skill appears in the smart-action row of the Compose editor.
- **Voice · trigger anywhere** — the WHEN line registers; saying the phrase fires the skill headless from any app.
- **Library · apply to memo** — apply a skill post-hoc to an existing recording via a dropdown in the memo row.

This row is the "promise of reach" — it tells users what they're getting beyond just the editor view. Each preview is a slice of a real Talkie surface with the active skill highlighted (see `feedback_where_it_fires.md` memory).

### iOS surface — same vocabulary, abbreviated where the phone needs it

**Principle: macOS coins the term, iOS echoes it.** Same word everywhere; iOS gets label-length latitude on the phone.

Concrete renames on the iOS side:

| Today (iOS) | New |
|---|---|
| "Mac Actions" section in memo detail | **"Skills"** (the qualifier "Mac" was redundant — context tells the user these run on their Mac) |
| `ComposeWorkflowAction` chip group label | **"Smart Actions"** (matches macOS Compose) |
| Storage key `pinnedMacActions` | **`pinnedSkills`** |
| Struct `PinnedWorkflow` | **`PinnedSkill`** |

The narrow "Action" senses (SmartAction chip, PendingActions, etc.) stay narrow on iOS too — same policy as macOS.

## Escape hatch — when a skill outgrows WHEN/WITH/DO/THEN

If a user wants conditionals, multiple parallel actions, branching, or anything else the constrained shape can't express, **"Open in editor →"** drops them into the existing `WorkflowDetailColumn` with the same underlying `WorkflowDefinition`. From that point the skill is an "advanced skill" — still a Skill in the sidebar, but no longer renderable as `.skill.md` with the four keywords. The card in the gallery shows an `ADVANCED` badge instead of the WHEN/WITH/DO/THEN preview.

This means the editor / list view stay unchanged for existing workflow files. They get re-labeled "advanced" in the gallery if they don't fit the constrained shape.

**Day-one density.** Per the codebase-state brief (§1), of 31 surveyed existing workflows: ~42% are single-trigger / simple linear (fit WHEN/WITH/DO/THEN atomic), ~16% are multi-step linear, ~32% are branching/conditional, ~10% are auto-run automation. With the polymorphic-DO refinement, many of the multi-step linear and routing seeds (Hey Talkie, etc.) absorb into the **composed** mode without graduating to `WORKFLOW`. Estimated split on day one:

- **Atomic** (single-step skills): ~42%
- **Composed** (sequence/route fits cleanly): ~30%
- **Workflow** (true branching, conditionals, multi-output chaining — needs the graph editor): ~15-18%
- **Auto-run automations**: ~10% (orthogonal — these are skills with a schedule trigger, can be any of the three modes above)

So roughly **1 in 6 existing workflows carries the `WORKFLOW` badge on day one**, not 1 in 2. The polymorphic DO does most of the work.

## Migration

Zero-touch on the data side. Copy and a couple of iOS-side renames.

**macOS:**
- Existing `.workflow.json` files: keep loading via existing `WorkflowFileRepository`.
- New skills authored in the editor bay: persist as `.skill.md`. The loader recognizes both extensions and produces `WorkflowDefinition` either way.
- Gallery surfaces both: skills authored fresh get a WHEN/WITH/DO/THEN card; legacy workflows get an ADVANCED-badged card.
- Sidebar copy change ("Workflows" → "Skills"). One-line PR for that.

**iOS:**
- Section label "Mac Actions" → "Skills" in memo detail view.
- Compose chip group label → "Smart Actions".
- Storage key `pinnedMacActions` → `pinnedSkills` (one-time rewrite of the `NSUbiquitousKeyValueStore` mirror; no historical data lost).
- Struct `PinnedWorkflow` → `PinnedSkill`.

A future *opt-in* migration tool could let users re-shape simple legacy workflows into the WHEN/WITH/DO/THEN form. Out of scope for this spec.

## Known adjacent bugs (flagged separately, not in scope)

From the codebase-state brief (§2):

- **`thenSteps` / `elseSteps` routing is not implemented in current code state.** Both Swift and TypeScript executors evaluate `conditional` steps to a boolean output but the execution loop remains linear — `thenSteps` and `elseSteps` UUID lists are never routed. Seeds that declare them (brain-dump-processor, learning-capture, feature-ideation) effectively run as linear pipelines today.
- **Flat JSON conditional index references only resolve to UUIDs generated so far.** Forward references in templates that point to later steps are dropped.
- **Scheduled automations without a memo context** log completion but don't execute against actual input.

None of these are taxonomy concerns; flagging here so they don't get conflated with the Skills work.

## Build order (implied, for planning)

This spec doesn't commit to a build order, but the data-model design above implies:

1. Sidebar copy: "Workflows" → "Skills" (one line).
2. `.skill.md` parser → `WorkflowDefinition`. Load + save round-trip.
3. Skills page surface — replace current Workflows section landing. Editor bay + starters row + your-skills row + where-it-fires row.
4. Editor bay — chat-driven authoring (UI shell first, Anthropic wiring later).
5. "Open in editor →" — wire from editor bay to existing `WorkflowDetailColumn`.
6. Starter skills shipped: Log Bug, Daily Standup, Capture Thought as `.skill.md` in app bundle.
7. iOS-side renames: "Mac Actions" → "Skills", `pinnedMacActions` → `pinnedSkills`, `PinnedWorkflow` → `PinnedSkill`, Compose chip group label.

## Open questions for arach

1. **Sidebar copy: "Skills" or "Skill"?** Plural-as-section-name (matches "Notes", "Memos", "Dictations") vs singular. Lean plural.
2. **File extension: `.skill.md` or `.skill`?** Lean `.skill.md` for SKILL.md interop, but it's two-token and unusual.
3. **Starter set: just three, or more out of the gate?** Studio shows three. Bigger set risks an app-store feel.
4. **Voice authoring of WHEN/WITH/DO/THEN.** Dictate the keywords vs let the agent infer from prose? Separate doc.
5. **Power-user view of `WorkflowStep.StepType`.** Does the catalog ever surface to users (autocomplete in DO), or stay internal? Spec assumes "autocomplete in Forge yes, no separate browse surface."
6. **Skill sharing.** Are `.skill.md` files shareable as gists / cross-app / via a marketplace? Out of scope here, but the format choice enables it.

## Out of scope

- The concrete grammar of YAML frontmatter (field names, allowed values, validation).
- Anthropic SKILL.md interop details (which fields are aliased, how Claude Code would actually invoke a Talkie skill).
- Voice authoring flow (dictation → keyword extraction).
- Chat pane runtime (which model, prompt template, function calls).
- Marketplace / sharing of `.skill.md` files.
- The broken `thenSteps`/`elseSteps` routing (separate bug, see "Known adjacent bugs").

## Refinements from the codebase-state brief (landed 2026-05-20)

The brief at `2026-05-20-taxonomy-codebase-state.md` confirmed the spec's shape and refined three things:

- **Step-type count.** 19 variants, not 21 (corrected in §"Step / Tool tier").
- **Bucket density.** ~48% of existing workflows would carry ADVANCED on day one (added to §"Escape hatch").
- **"Action" overload.** Confirmed as broader than the spec initially claimed (~10 user-facing surfaces). The decision to keep Action narrow is intentional and documented in §"What about 'Action'?".
- **iOS surface.** No `WorkflowDefinition` model exists on iOS — just a pinned-skill mirror. The macOS-coined vocab is echoed via copy + storage-key renames (§"iOS surface").
- **Adjacent bugs.** `thenSteps`/`elseSteps` routing isn't implemented; flagged separately to avoid conflation.
