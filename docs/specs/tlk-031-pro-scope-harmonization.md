# TLK-031: Pro / Scope Harmonization Fork Map

**Status**: Draft
**Date**: 2026-06-14
**Studio**: /eng/tlk-031

---

## Summary

Talkie currently has two visual directions that also behave like two structural
forks:

- **Pro**: the original theme path. It is simpler, denser, more direct, and has
  better performance characteristics in the June 14 trace.
- **Scope**: the newer design path. It carries the strongest current visual
  thinking, with a warmer writer/creative workspace voice, but several screens
  duplicate full data and layout structures.

The harmonization goal is not to pick one theme. The goal is to separate product
personality from structural work:

- Use **Pro** as the performance and interaction baseline for the shared app
  skeleton.
- Use **Scope** as the leading presentation system where its visual language is
  valuable.
- Keep genuine persona differences, but collapse duplicate loading, filtering,
  row construction, and large SwiftUI bodies into shared primitives.

This should make both themes faster and easier to evolve.

---

## Trace Signal

The June 14 Instruments trace compared Scope against the original theme path.

### Scope Run

- Main-thread hangs: 13 total, about 9463 ms.
- Max hang: about 1480 ms.
- Hitches: 136 rows, about 13903 ms total.
- Large SwiftUI body updates included:
  - `ScopeModelsView.body`: about 1246 ms and 1244 ms.
  - `ScopeOverviewSection.body`: about 563 ms.
- Many shared views were noisy during the same windows:
  - `Sidebar`
  - `PerfStatusReadout`
  - `HelpView`
  - `AppNavigation`
  - `RootView`
  - row-level views

### Original / Pro Run

- Main-thread hangs: 7 total, about 2171 ms.
- Max hang: about 394 ms.
- Hitches: 81 rows, about 5681 ms total.
- No hitches above 500 ms.

### Interpretation

The big signal is not that Scope uses the wrong colors. The signal is that Scope
often represents a whole-screen fork with more work inside larger bodies. Where
Scope looks like a full rewrite, it tends to be slower and harder to reason
about. Where Scope is a presentation layer over shared pieces, it is a better
candidate for long-term reuse.

---

## Product Roles

### Pro

Pro should be the simple, elegant, pure workspace. It should feel like a builder
tool:

- dense but calm
- fast to scan
- low ornament
- direct controls
- structured around repeated daily use

Pro should be allowed to stay plain where plainness is useful. Its value is the
feeling of speed, control, and legibility.

### Scope

Scope should be the writer/creative workspace. It should feel more editorial and
more expressive:

- richer hierarchy
- more composed surfaces
- more context around work
- warmer details
- stronger narrative grouping

Scope should keep its best visual ideas, but those ideas should usually live in
tokens, styles, section chrome, and composition rules rather than duplicated
screen implementations.

---

## Harmonization Rules

1. **Shared data first**

   Theme-specific screens should not own separate loading, filtering, sorting,
   status derivation, provider refresh, or row model construction when the
   product behavior is the same.

2. **Shared structure second**

   If two screens show the same object hierarchy, they should share the shell,
   sections, rows, empty states, and command wiring. The theme should provide a
   style or presentation variant.

3. **Theme forks only for real product differences**

   A full fork is acceptable when the theme changes the user's task model, not
   just the look. Example: a dense builder dashboard and a writer-focused home
   surface can remain different layouts, but they should still share data
   snapshots and small components.

4. **Small bodies over clever bodies**

   A large SwiftUI body that combines data derivation, branching, layout, and
   styling should be split. The target is small, named views with stable inputs.

5. **Presentation is a style boundary**

   Scope design language should move into reusable style boundaries where
   possible:

   - design tokens
   - row styles
   - section styles
   - screen chrome styles
   - inspector/detail styles
   - empty/loading/error state styles

6. **No new whole-screen forks without a ticketed reason**

   New `if settings.isScopeTheme` branches around entire screens should be
   treated as temporary unless the fork is explicitly justified by task model.

---

## Fork Labels

Use these labels while auditing screens.

| Label | Meaning | Action |
| --- | --- | --- |
| Keep Pro | Pro has the better structure or performance baseline. | Make Pro the shared skeleton, then style it. |
| Promote Scope | Scope has the better presentation idea. | Move the idea into tokens, styles, or small components. |
| Extract Shared | Both forks duplicate behavior. | Extract state, row models, sections, or commands. |
| Keep Fork | The screens support different task models. | Share data and leaf components only. |
| Retire | A fork is unused, redundant, or only preserves old visual churn. | Delete after replacement and verification. |

---

## Current Fork Map

### Models

**Files**

- `apps/macos/Talkie/Views/Models/ModelsContentView.swift`
- `apps/macos/Talkie/Views/Models/ScopeModelsView.swift` (retired June 14)

**Trace signal**

`ScopeModelsView.body` produced the largest observed SwiftUI body updates in the
trace, around 1.2 seconds.

**Classification**

- Structure: Keep Pro
- Presentation: Promote Scope
- Behavior: Extract Shared

**Recommendation**

Make Models the first harmonization slice.

Extract a shared models screen layer that owns provider refresh, model grouping,
availability state, empty/loading states, and row model construction. Keep the
Pro layout as the baseline structure because it already performs better. Move
Scope's better visual treatment into section and row styles.

Target shape:

- `ModelsScreenState`
- `ModelsSectionModel`
- `ModelsProviderRowModel`
- `ModelsScreenShell`
- `ProModelsStyle`
- `ScopeModelsStyle`

The first pass should avoid visual ambition. The goal is to remove duplicate
body work and make Scope render through smaller pieces.

### Settings Context Overview

**Files**

- `apps/macos/Talkie/Views/Settings/ScopeContextView.swift`

**Trace signal**

`ScopeOverviewSection.body` showed a large body update around 563 ms.

**Classification**

- Structure: Extract Shared
- Presentation: Promote Scope

**Recommendation**

Split the overview into stable inputs and leaf cards. Avoid recomputing derived
overview values during the full section body pass. If the Pro settings path has
similar overview data, route both through the same summary model.

### Sidebar And Navigation

**Files**

- `apps/macos/TalkieKit/Sources/TalkieKit/UI/Sidebar/Sidebar.swift`
- `apps/macos/Talkie/Views/AppNavigation.swift`

**Trace signal**

Sidebar geometry and hover/tooltip work showed up in both runs. The branch was
less catastrophic than the Scope screen bodies, but it is shared enough that
small inefficiencies are paid often.

**Classification**

- Structure: Extract Shared
- Presentation: Promote Scope

**Recommendation**

Keep Sidebar as one shared primitive. Scope should tune density, tint, selected
state, and compact affordances through style inputs rather than by forking the
navigation model. Any geometry readers should be compact-mode-only and tied to
clear interaction requirements.

### Library

**Files**

- `apps/macos/Talkie/Views/Library/ScopeLibraryView.swift`
- `apps/macos/TalkieKit/Sources/TalkieKit/UI/ScopeLibraryList.swift`

**Classification**

- Structure: Extract Shared
- Presentation: Promote Scope

**Recommendation**

`ScopeLibraryList` already looks like the right direction: a reusable library
primitive with a Scope presentation. The next step is to identify the reusable
row and bucket model underneath it, then let Pro and Scope choose density and
chrome through style.

The likely shared layer:

- date buckets
- memo row state
- thumbnail state
- selection state
- recording status
- command wiring

### Home

**Files**

- `apps/macos/Talkie/Views/HomeScreen.swift`
- `apps/macos/Talkie/Views/Home/ScopeHomeView.swift`

**Classification**

- Structure: Keep Fork
- Behavior: Extract Shared
- Presentation: Keep theme-specific

**Recommendation**

Home is allowed to remain more divergent because the persona split is real.

Pro should be the builder dashboard: simple, direct, fast, and dense. Scope can
remain more editorial and creative. Both should consume the same home data
snapshot rather than each owning separate observation and derivation.

Shared layer:

- memo stats
- recent captures
- recording status
- workflow summaries
- command availability
- tray state

Theme-specific layer:

- section order
- hero or top band treatment
- density
- copy tone
- visual grouping

### Workflows

**Files**

- `apps/macos/Talkie/Views/Workflows/WorkflowColumnViews.swift`
- `apps/macos/Talkie/Views/Workflows/ScopeWorkflowListColumn.swift`
- `apps/macos/Talkie/Views/Workflows/ScopeWorkflowStepCard.swift`
- `apps/macos/Talkie/Views/Workflows/WorkflowContentViews.swift`

**Classification**

- Structure: Extract Shared
- Presentation: Promote Scope selectively
- Some shells: Keep Fork until audited

**Recommendation**

The workflow area has a large mixed file with substantial Scope-specific detail
views. Split by responsibility before redesigning:

- workflow list model
- workflow detail model
- step row model
- run state model
- inspector model
- shell and style

Do not start by changing the visible design. Start by extracting models and
leaf views so body invalidation has smaller blast radius.

### Drafts, Notes, And Stats

**Files**

- `apps/macos/Talkie/Views/Drafts/DraftsScreen.swift`
- `apps/macos/Talkie/Views/Drafts/ScopeDraftsScreen.swift`
- `apps/macos/Talkie/Views/Stats/StatsScreen.swift`
- `apps/macos/Talkie/Views/Stats/ScopeStatsScreen.swift`

**Classification**

- Drafts: audit next
- Notes: audit next
- Stats: likely Retire or Extract Shared, depending on current routing

**Recommendation**

These should follow Models and Library. Before implementation, confirm which
Scope screens are actually mounted. Retire inactive forks rather than polishing
them.

---

## Execution Lanes

This section tracks the orchestrated refactor work. Each lane should have a
clear write scope so multiple agents can move without overwriting each other.

### Baseline Lane: Models Route

**Status**: Integrated and built

**Owner**: Orchestrator

**Scope**

- `apps/macos/Talkie/Views/Models/ModelsContentView.swift`
- `apps/macos/Talkie/Views/AppNavigation.swift`

**Current direction**

The active Models route should be provider-first:

- one local voice capability: Parakeet
- providers as the integration unit
- model pickers inside each provider row
- no active STT model card grid
- no Pro/Scope route fork for Models

This lane is intentionally narrower than a complete model-system cleanup. Old
card helpers can be retired later after Settings and onboarding references are
audited.

**June 14 execution**

- Removed the active Pro/Scope route fork for Models.
- Replaced the large model-card surface with a provider-first screen.
- Normalized speech recognition to one local voice capability: Parakeet
  (`TalkieDefaults.dictationModelId`).
- Kept provider model choice inside provider rows.
- Retired `ScopeModelsView.swift` after confirming active navigation renders
  `ModelsContentView()` for both Pro and Scope.
- Built successfully with `apps/macos/run.sh Talkie --no-launch`.

### Home Lane

**Status**: Standard Home slices integrated; Scope Home first slice integrated

**Owner**: Home worker, HomeGridCards worker, ScopeHome worker

**Scope**

- `apps/macos/Talkie/Views/HomeScreen.swift`
- new leaf files under `apps/macos/Talkie/Views/Home/`
- Xcode project membership only as required

**First slice**

Pure extraction from `HomeScreen.swift`:

- `CardStyle`
- recent activity rows
- activity heatmap views and models
- empty state view
- search trigger pill

This should not touch `ScopeHomeView.swift` yet. The first goal is to reduce the
root Home file without changing behavior.

**June 14 execution**

- Extracted `CardStyle`, recent activity rows, heatmap models/views, empty
  state, and search trigger pill out of `HomeScreen.swift`.
- Reduced `HomeScreen.swift` to 594 lines.
- Built successfully with `apps/macos/run.sh Talkie --no-launch`.

**Second slice**

- Extracted device and bridge cards into `HomeDeviceCards.swift`.
- Reduced `HomeGridCards.swift` from 2603 lines to 1887 lines.
- Fixed the two Swift 6 actor-isolation warnings on `HomeStatCard` and
  `HomeActionCard` by storing stable `id` values instead of deriving them from
  actor-isolated card type state.
- Kept this lane separate from `ScopeHomeView.swift`.
- Built successfully with `apps/macos/run.sh Talkie --no-launch`.

**Scope Home slice**

- Extracted `BayScheme` into `Views/Home/Scope/ScopeBayScheme.swift`.
- Extracted bay treatment helpers into
  `Views/Home/Scope/ScopeAgentBayTreatments.swift`.
- Extracted discovery widgets into `Views/Home/Scope/ScopeDiscoveryWidgets.swift`.
- Reduced `ScopeHomeView.swift` from 2702 lines to 1998 lines.
- Kept Pro/Scope Home behavior separate; this was a pure Scope leaf move.
- Flattened decorative hover state in Scope discovery cards, Scope capture
  rows, Scope signal rows, and standard Home shortcut rows after the second
  trace showed shared hover/update machinery as a top offender.
- Restored pointer hover polish with `HomeHoverChrome`, an AppKit-backed
  tracking/layer primitive that avoids row-local SwiftUI hover state.
- Built successfully with `apps/macos/run.sh Talkie --no-launch`.

**Hover polish restoration**

The first perf pass intentionally removed decorative hover work from repeated
rows/cards so the trace could isolate row invalidation costs. That was not a
final visual direction. The restoration path is a shared low-churn primitive:
`HomeHoverChrome` in `Views/Home/HomeCardStyle.swift`.

`HomeHoverChrome` uses an `NSTrackingArea` and direct `CALayer` updates for
fill, border, and optional leading accent. Pointer enter/exit no longer
publishes SwiftUI state through every repeated row body.

Restored surfaces:

- Scope discovery cards in `Views/Home/Scope/ScopeDiscoveryWidgets.swift`
- Scope capture mode cards and signal rows in `Views/Home/ScopeHomeView.swift`
- standard Home shortcut rows in `Views/Home/HomeShortcutsWidget.swift`
- standard Home recent activity rows, widgets, and grid cards touched by this
  pass
- Scope recent two-pane rows in `Views/Home/RecentTwoPane.swift`
- standard Home calendar day cells in `Views/Home/HomeCalendarWidget.swift`

Ongoing rule:

- Use shared, low-churn hover mechanisms rather than per-row `@State isHovered`
  for repeated Home/sidebar rows.
- Prefer AppKit-backed chrome, parent-level hover underlays, pressed/focus
  states, selected states, or styles driven from a single hovered item id.
- Do not re-add row-local hover state to repeated Home/sidebar rows unless a
  trace shows it is not a top contributor.

Acceptance:

- Visual review confirms Home and Scope Home recover the intended pointer
  affordance.
- A follow-up trace does not put hover, tooltip, geometry, or repeated row body
  updates back in the top offenders.

### Workflow Lane

**Status**: First, second, and third slices integrated and built

**Owner**: Workflow workers

**Scope**

- `apps/macos/Talkie/Views/Workflows/WorkflowContentViews.swift`
- narrowly scoped new files under `apps/macos/Talkie/Views/Workflows/`
- Xcode project membership only as required

**First slice**

Pure extraction from `WorkflowContentViews.swift`, preferably:

- `WorkflowTemplatePicker`
- `WorkflowMemoSelectorSheet`

Avoid the high-risk areas in the first pass:

- run execution and polling
- builder streaming
- dictation
- workflow input eligibility
- app-wide lightbox registration

**June 14 execution**

- Extracted `WorkflowTemplatePicker`.
- Extracted `WorkflowMemoSelectorSheet` and private `WorkflowMemoRow`.
- Kept `WorkflowCard`, `MemoSelectorSheet`, and run execution behavior in place.
- Reduced `WorkflowContentViews.swift` to 479 lines.
- Built successfully with `apps/macos/run.sh Talkie --no-launch`.

**Second slice**

- Extracted `WorkflowLibrarySelectorSheet` and private
  `WorkflowLibraryObjectRow` from `WorkflowColumnViews.swift` into
  `WorkflowLibrarySelectorSheet.swift`.
- Reduced `WorkflowColumnViews.swift` from 4776 lines to 4473 lines.
- Kept run execution, polling, builder streaming, dictation, and lightbox
  behavior in place.
- Built successfully with `apps/macos/run.sh Talkie --no-launch`.

**Third slice**

- Extracted the Scope workflow step outline cluster into
  `apps/macos/Talkie/Views/Workflows/ScopeWorkflowStepList.swift`.
- Moved display-only step list, row, binding line, token chip, type tag, and
  step-detail helpers.
- Reduced `WorkflowColumnViews.swift` from 4473 lines to 4162 lines.
- Left execution, polling, streaming, dictation, provider resolution, and
  lightbox behavior in place.
- Built successfully with `apps/macos/run.sh Talkie --no-launch`.

### Shared Hotspot Lane

**Status**: Integrated and built

**Scope**

- `apps/macos/Talkie/Debug/PerfHUD.swift`
- `apps/macos/TalkieKit/Sources/TalkieKit/UI/Sidebar/Sidebar.swift`
- `apps/macos/Talkie/Services/Agents/TabDefinitionRegistry.swift`

This lane already has targeted performance fixes. It should stay separate from
large view decomposition so trace changes remain attributable.

**June 14 execution**

- Slowed the debug perf HUD publish/log cadence to 1 Hz so profiling UI does
  less SwiftUI work while traces are running.
- Gated sidebar rail geometry measurement to compact mode and only shows rail
  tooltips when a measured row frame exists.
- Filtered `~/.talkierc` FSEvents before reparsing and avoided publishing
  unchanged global config.
- Built successfully with `apps/macos/run.sh Talkie --no-launch`.

### Settings Models Lane

**Status**: Integrated and built

**Owner**: Orchestrator

**Scope**

- `apps/macos/Talkie/Views/Settings/ModelsSettings.swift`

**June 14 execution**

- Removed the active Whisper/Parakeet STT model-card grid from Settings.
- Replaced it with one Parakeet voice-model row.
- Normalizes `liveTranscriptionModelId` to `TalkieDefaults.dictationModelId`.
- Built successfully with `apps/macos/run.sh Talkie --no-launch`.

### Waiting Lanes

These should not start until the current active project-file lane is integrated
and the app builds:

- further `WorkflowColumnViews.swift` split after auditing execution/state
  boundaries
- Library row/bucket sharing

### Current Line Counts

After the June 14 execution wave:

- `HomeScreen.swift`: 596 lines
- `HomeGridCards.swift`: 1847 lines
- `ScopeHomeView.swift`: 1984 lines
- `WorkflowContentViews.swift`: 479 lines
- `WorkflowColumnViews.swift`: 4162 lines
- `ModelsContentView.swift`: 598 lines
- `ModelsSettings.swift`: 313 lines

`WorkflowColumnViews.swift` remains the main oversized file. The next split
should be planned around state ownership, because the remaining large blocks
include execution, polling, streaming, dictation, provider resolution, and
lightbox wiring.

---

## Implementation Order

### Slice 1: Models Harmonization

Goal: make Scope Models fast without losing Scope's better presentation.

Work:

1. Keep `ModelsContentView` as the single active Models route.
2. Move any remaining provider grouping or availability derivation into small
   row/state models if the unified route regresses.
3. Retire unused card helpers only after Settings and onboarding references are
   audited.
4. Re-run the Models route trace against both themes.

Success:

- No inactive `ScopeModelsView` route or source file.
- No main-thread hitch over 500 ms on the Models route.
- Pro remains visually stable.
- Scope remains visually recognizable.

### Slice 2: Settings Overview And Shared Hotspots

Goal: remove the next known Scope body spike and reduce shared noise.

Work:

1. Split `ScopeOverviewSection` into stable cards.
2. Cache or precompute overview values in a small state model.
3. Keep Sidebar geometry and tooltip work gated to the states that need it.
4. Keep the perf HUD publish cadence coarse enough to avoid becoming a profiler
   participant.

Success:

- No settings overview body update over 100 ms.
- Sidebar does not show up as a top shared hotspot in normal navigation.
- Perf HUD does not materially affect the trace.

### Slice 3: Library Primitive

Goal: turn the Scope library row/bucket work into a shared primitive.

Work:

1. Extract library bucket and row models.
2. Keep thumbnail state separate from row layout.
3. Style Pro and Scope from the same row model.
4. Re-run theme comparison.

Success:

- Similar body counts across Pro and Scope for library navigation.
- Scope retains its richer presentation.
- Pro stays dense and direct.

### Slice 4: Home And Workflow Audit

Goal: classify the largest remaining forks before implementation.

Work:

1. Write a short per-screen audit for Home and Workflows.
2. Identify shared state snapshots.
3. Identify true product-mode differences.
4. Split large workflow files by responsibility before visual changes.

Success:

- Every remaining full-screen fork has one of:
  - a clear Keep Fork reason
  - a planned shared extraction
  - a retirement path

---

## Design Direction

### Pro Layout Direction

Pro should get a deliberately simpler layout version, not just the old theme by
default.

Principles:

- fewer decorative bands
- tighter section headers
- more table/list energy
- fast keyboard and pointer workflows
- direct status readouts
- minimal animation
- plain empty states
- strong alignment and predictable spacing

This is the dev/builder workspace.

### Scope Layout Direction

Scope should preserve the newer visual thinking while becoming structurally
lighter.

Principles:

- richer top bands where they carry context
- editorial grouping for creative review
- warm accents and paper-like hierarchy
- visual affordances for writing, clips, and memory
- calmer density than Pro
- no duplicated data loading just to achieve the style

This is the writer/creative workspace.

---

## Guardrails

- Do not add new full-screen theme forks without documenting the product reason.
- Do not copy provider refresh, memo filtering, workflow derivation, or tray
  state into theme-specific views.
- Do not optimize only by hiding expensive views after they already performed
  expensive derivation.
- Do not make Scope faster by making it visually indistinguishable from Pro.
- Do not make Pro richer by importing Scope's heaviest structural patterns.

---

## Measurement Plan

Run the same navigation trace for both themes after each slice.

Track:

- main-thread hangs
- hitch count and max hitch
- top SwiftUI body updates
- body counts for the changed route
- `Sidebar` and `PerfStatusReadout` presence in top offenders
- route-specific regressions from Pro baseline

Initial thresholds:

- No route-level body update above 100 ms during normal navigation.
- No main-thread hitch above 500 ms during theme comparison.
- Scope should move toward Pro's June 14 profile before adding new visual
  features.

---

## Open Questions

1. Should Pro and Scope become named workspace modes instead of only visual
   themes?
2. Should Home be the only long-term full-screen fork, or should Workflows also
   keep a persona-specific shell?
3. Which Scope-only screens are still mounted in current navigation?
4. Should Studio get a visual study route for the Pro builder layout before the
   Models slice, or should Models proceed code-first because the trace is clear?
