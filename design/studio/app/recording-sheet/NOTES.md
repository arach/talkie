# Recording Sheet — Decisions Log

## What the study renders

The iPhone recording-sheet artifact that overlays Home when capture
begins: top strip (`ESC` · `· REC`) · waveform band · timer + level
readout · details hint · brass stop button. Per-card it's the SAME
sheet rendered against each material scheme, so the comparison is
about palette/accent legibility, not layout.

Source of truth in Swift (when it lands): the iOS recording sheet
view (currently lives in the iOS app's recording flow — see
`apps/ios/Talkie iOS/Models/AudioRecorderManager.swift` and its
presenting view).

## Anchor schemes

Reuses the 9-scheme picker established in `agent-bay/`. Each scheme
is one ruleset of CSS vars applied via `.scheme-X`. The two anchor
points stay the same:

- **AMBER** — `#14181A` gunmetal + `#E89A3C` phosphor. Dark
  instrument identity.
- **PAPER** — `#EEE7D6` cream + `#9A6A22` copper. Print-dashboard
  identity.

Both feel *designed*; both commit to a material. The recording sheet
needs to read as recording in both worlds.

## Treatments

Independent of the scheme. All toggle simultaneously across all bays.

- **Waveform** — five mutually-exclusive trace styles (radio-row):
  - `sparkle` — the shipping scattered-dot pattern (baseline).
  - `printout` — single solid trace at ink weight, no glow.
  - `brass` — single trace in the scheme accent, no glow.
  - `phosphor` — single trace in the scheme accent + halo glow.
  - `hybrid` — phosphor trace + graticule overlay.
- **Graticule** — faint cell grid behind the trace. Independent of
  waveform style (so `printout + graticule` reads as scope-paper).
- **Brackets** — viewfinder L-shapes at the four corners of the
  trace band. Borrowed from agent-bay; reads as instrument framing.
- **Glow** — adds an outer halo around the trace (only meaningful
  on dark schemes; light schemes ignore it per studio principle
  "glow lives on dark surfaces").
- **Compact** — phone aspect tightened; useful when comparing many
  schemes at once.

## Open questions

- Whether the sheet's *home backdrop* (faint Home content showing
  through behind the sheet) should be part of the artifact or
  abstracted away. Currently abstracted — the bay frame is just the
  sheet card itself.
- Whether `phosphor` should auto-disable on light schemes (PAPER /
  BONE / ALUMINUM / STEEL / CONCRETE) per the "glow lives on dark"
  rule, or stay enabled so the rule can be re-examined visually.
- Whether to add an `iOS theme` constraint layer — the iOS app ships
  Scope / Midnight / Tactical / Ghost as user-facing themes; these
  could map to a subset of the studio schemes (e.g. Scope ≈ PAPER,
  Midnight ≈ AMBER) or get their own per-theme card rows.

## Why these treatments and not others

- **No "scattered-dot animated" mode.** The sparkle baseline is
  here as a static reference. Re-implementing the animation in HTML
  doesn't change the design decision — the static version already
  shows why it reads as decorative noise.
- **No CRT inset / dark-window-on-light-sheet.** Tried in earlier
  HTML iterations. The dark inset reads as a foreign object inside
  the cream sheet — better reserved for a dedicated "scope bay"
  hero moment elsewhere. Dropped from the studio.
