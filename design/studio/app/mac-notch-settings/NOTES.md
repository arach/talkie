# Mac Notch Settings — Decisions Log

## What this study renders

A **live, interactive** prototype of the simplified notch settings
surface, proposed to replace the ~40-control sprawl in the shipping
`SurfaceSettingsView.swift`. Every toggle, picker, and slider is
wired to React state and drives a live notch preview to the right.

## The consolidation

| Tab | Today | Proposed |
|---|---|---|
| **Notch** (was "Overlay") | Enable / Always Visible / Shape + 7 geometry steppers | Enable / Always Visible / Shape + Advanced disclosure (4 knobs) |
| **Tray** | Dot Strip + Placement + Standalone Badge + ~13 tuning steppers + Shelf | Tray Indicator + Placement + Show preview while recording + Advanced disclosure (3 knobs) |
| **Hover Zone** | Width/Height/PadX/PadY steppers (global + per-monitor) | Sensitivity preset picker (Subtle / Normal / Aggressive) + Per-display custom disclosure (2 knobs) |

**Main-surface visible: 7 controls.** Advanced disclosures, when
expanded, expose another 9 tuning knobs — for a total worst-case
of 16 controls when every disclosure is open. Compared to the legacy
surface's ~40, that's a ~60% reduction in default-state surface
area and a ~60% reduction even when every advanced is open.

## Why interactive (not static frames)

The user asked: "make the UI tool interactive." Static frames hide
two things that matter for this surface:

1. **State interactions.** "Show tray preview while recording" only
   matters during recording. "Always visible" is only meaningful
   when the notch is enabled. Disabled-state UI reads correctly
   only when you can actually click around.

2. **Live preview is the explanation.** The Notch tab's `Shape`
   picker means nothing without seeing the shape change. The
   Hover sensitivity preset is just a word until you see the
   dashed zone widen.

The preview pane on the right shows the notch at the top of a
simulated screen, with a faint amber-dashed hover-zone outline
always visible (studio affordance, not shipping chrome). Hover the
notch → it expands. Click "record" in the preview controls bar →
the notch tints red and shows `REC 0:14`. Drag the "tray items"
slider → dots appear/disappear in the indicator at the chosen
placement.

## Key consolidation decisions

### Tray Indicator collapse
The biggest user-visible win. Today's surface has two parallel
indicators (Overlay Dot Strip + Standalone Badge) with suppression
logic between them, two sets of tuning knobs, and confusing dual
visibility. The proposal collapses them into **one** indicator with
a Placement picker (Auto / Inside / Below). "Auto" picks based on
context: inside the notch on built-in displays, floating below on
external. One concept, one decision.

### Hover sensitivity preset
Today's surface has four steppers (Width / Height / PadX / PadY) at
the top level, plus per-monitor overrides, plus Reset Zone vs Reset
All. The proposal: **one picker** with three named presets that map
to sensible width/height combinations. The four steppers move into
"Per-display custom" disclosure for users who genuinely need
per-monitor tuning.

### Advanced disclosure as the home for "shipped by accident"
Opacity, Corner Radius, Hover Expansion, Active Expansion, Indicator
Width, Dot Size, Max Dots — all of these were main-surface controls
in the legacy view. They're tuning knobs that read like developer
sliders. Moving them behind a per-section "Advanced" disclosure
(amber chevron + section label + knob count) preserves them for
designers and power users without forcing every user past them.

## Open questions

- **Should "Always Visible" stay?** It's a real preference (some
  users want the notch present even when idle) but it competes
  conceptually with "Enable Notch" — feels redundant. Could fold
  into a 3-state picker (Off / On-demand / Always) to make the
  three real states explicit.
- **Tray placement "Auto" needs explanation.** The hint copy says
  "Inside the notch on built-in displays, floating below on external"
  but that asymmetry might surprise users with mixed setups. Could
  preview both placements side-by-side when "Auto" is selected.
- **Hover sensitivity preset values.** Subtle = 120pt zone, Normal =
  180pt (current default), Aggressive = 260pt. These need real-world
  testing to validate. Subtle in particular might be too narrow on
  built-in notch Macs where the physical notch is already ~180pt.
- **Recording state interaction.** Currently in the preview, hitting
  "Record" expands the notch via `activeExpansion`. The real Swift
  also drives the notch via `NotchComposer.resolve()` from the
  `recording` intent — so the legacy `hoverExpansion` / `activeExpansion`
  steppers are still meaningful but they're geometry tuning, not
  primary behavior controls. Position is correct (Advanced).

## What this study does NOT do yet

- **Doesn't propose Swift code.** The next step (when you approve
  the consolidation) is a port pass against `SurfaceSettingsView.swift`.
- **Doesn't address the `NotchTuning` shared instance.** Today's
  geometry tuning persists across all the controls; the proposal
  preserves the underlying keys (they're harmless) but hides them
  behind disclosure. Migration is trivial.
- **Doesn't model multi-display setups in the preview.** Single
  simulated display, no external-display swap yet. That's a worthy
  follow-up iteration.

## Component map

- `app/mac-notch-settings/page.tsx` — route wrapper, uses StudioPage.
- `components/studies/MacNotchSettings.tsx` — composition root, all
  state lives here.
- Sub-components inline:
  `Disclaimer`, `SettingsPanel`, `TabBar`, `NotchTab`, `TrayTab`,
  `HoverTab`, `ToggleRow`, `PickerRow`, `SliderRow`, `AdvancedDisclosure`,
  `PreviewPanel`, `NotchScreen`, `HoverZoneOutline`, `NotchShape`,
  `TrayIndicator`, `PreviewControls`, `CountReadout`.

Promotion candidates if a second settings-style study needs them:
- `<ToggleRow>` / `<PickerRow>` / `<SliderRow>` / `<AdvancedDisclosure>`
  — generic settings primitives. Likely belong in
  `primitives/SettingsRows.tsx` once a second caller appears.
