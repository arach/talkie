# Mac Compose — Decisions Log

## What this study renders

The full macOS Compose composition. Source of truth in Swift:
`apps/macos/Talkie/Views/Drafts/ScopeDraftsScreen.swift`. Internally
called "Drafts" but surfaced as "Compose" in the sidebar.

Compose is **not** a list. It's a single focused editor with a
pipeline metaphor running across the top, plus a library of smart
actions below the fold.

The study stamps the same composition at three widths:

| Stamp | Width | Format  | What it surfaces |
|---|---|---|---|
| 1 | 820  | Compact | Pipeline pins drop their full labels (S1·S2·S3·S4 only). Action chip row truncates to 2 + overflow. Action grid drops 4→2 columns. |
| 2 | 1180 | Default | Studio standard. Everything fits cleanly. |
| 3 | 1440 | Wide    | Editor surface gets airy. Question is whether textarea should grow or stay at a content measure. |

## Composition

Top to bottom:

1. **Signal monitor** — dark instrument panel (`#0E1518` floor with
   teal phosphor `#5FE3C9`). Header row + 4-stage pipeline (CAPTURE →
   TRANSCRIPT → REVISE → SHIP) with active stages glowing amber.
   This is the Compose identity — every other Talkie surface is
   cream; the signal panel is the one moment of dark instrument
   register.
2. **Editor bay** — cream paper rectangle with chrome bar at the top
   (CH-IN label, model picker, word count, REVISING flag, NEW button)
   and a textarea below. A floating amber-haloed dictation pill sits
   bottom-center so it reads as "press here to speak" not as a
   permanent control.
3. **Action bar** — COMMAND voice-prompt button (amber border, used
   to issue free-form instructions like "make this more formal"),
   three smart-action chips, COPY and SAVE buttons on the right.
4. **Action grid** — below the fold, a 4-col (compact: 2-col) grid
   of all smart actions, each with name + one-line hint + "APPLY →"
   affordance. This is the "kitchen sink" for batch operations.
5. **Ownership strip** — P1 (Input device) → P2 (Model) → P3 (Output
   destination). Closes the page with the data-ownership story.

## Open questions

- **Pipeline pin compact mode.** At 820 the long stage labels
  ("CAPTURE", "TRANSCRIPT", "REVISE", "SHIP") are hidden, leaving
  just the short codes (S1 / S2 / S3 / S4) and connectors. Is the
  short code legible enough, or should the connector shorten and the
  full label survive? Currently the connector also halves (56→28).
- **Editor measure at 1440.** The textarea expands to the bay width.
  At 1440 the content measure becomes uncomfortably wide for prose
  (>120 char). Should the textarea cap at ~80ch and center, with the
  bay still spanning full width? Swift currently grows to fill.
- **Dictation pill placement.** Currently absolute-positioned at
  bottom-center of the editor surface. At narrow widths it can
  collide with text. Consider a sticky position outside the
  scrolling text area, or move to the action bar entirely.
- **Action grid below the fold.** Renders all 8 actions inline.
  In Swift, this is wrapped in a ScrollView capped at maxHeight 320.
  The study renders it un-scrolled for full visibility, but the real
  experience is scrollable. Worth labeling the boundary?
- **COMMAND button vs chips.** Both invoke smart actions — COMMAND
  via voice, chips via click. Visually they sit on the same bar; the
  user might not register that COMMAND is "the open one" and chips
  are "the preset ones." Consider a separator or different chrome
  ladder.
- **Signal monitor at 1440.** The header row's right-side cluster
  (model + word count + dictation duration) gets a lot of negative
  space. Consider adding a third element (last-saved timestamp?) or
  letting the trio breathe.

## Why these decisions

- **No SchemeCard wrapper.** Compose is Scope-first like the other
  mac studies; the signal monitor's dark register is hand-tuned to
  the cream canvas, not driven by `--theme-*` vars. A scheme-aware
  variant is a separate study if/when we ship Modern/Technical.
- **No Review-mode diff panes.** The Swift source has a side-by-side
  A/B diff when `editorState.isReviewing`. Out of scope for the
  composition study — that's a state study (4–6 modes of the same
  surface).
- **Smart action labels are hand-authored.** The Swift uses
  `actionRegistry`; this study writes them inline as `SMART_ACTIONS`.
  Promoting to a shared file is a port-time concern.

## Component map

- `app/mac-compose/page.tsx` — route wrapper, uses MacWindowGrid.
- `components/studies/MacCompose.tsx` — composition root, accepts
  `width` prop and branches at 880 for compact mode.
- Sub-components inline:
  `SignalMonitor`, `PipelinePin`, `PipelineConnector`, `EditorBay`,
  `EditorChromeBar`, `EditorSurface`, `GraticuleBackground`,
  `DictationPill`, `ActionBar`, `ActionGrid`, `ActionCell`,
  `OwnershipStrip`, `OwnershipCol`.

Promotion candidates if a second mac study needs them:
- `<SignalMonitor>` — the dark-on-cream identity strip. Likely
  reusable as a Notch / Agent rail in other studies.
- `<GraticuleBackground>` — instrument-paper underlay. Already
  conceptually shared with Compose's Swift `GraticuleBackground`.
- `<OwnershipStrip>` — already conceptually shared with MacHome's
  closing footer. Worth unifying.
