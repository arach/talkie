# Mac Talkie Button — Decisions Log

## What this study renders

A single button — the Talkie Button — proposed to replace three
distinct affordances on the macOS app today:

1. The **global sidebar** (`AppNavigation.swift`, Hidden / Icon-rail /
   Expanded triplet, `Cmd+Ctrl+S` toggle).
2. The **Command Palette** (`CommandPaletteView.swift`, Raycast-style
   560×420 sheet, `Cmd+K`).
3. The **Voice Command Overlay** (`VoiceCommandOverlay.swift`,
   particle-blob capture UI, `Cmd+Shift+V`).

The button fuses them into one anchor with three gestures:

| Gesture            | Action                                            |
|--------------------|---------------------------------------------------|
| Tap                | Open palette (text search, fuzzy nav)             |
| Hold (≥250ms)      | Start voice capture (released → recognize intent) |
| Right-click        | Sectioned nav popover (Primary / Activity / Tools / Settings) |

The button is the **same surface** as the recording indicator in
NotchComposer — when a memo is recording, the button hosts the
elapsed timer + red pulse. No second floating element needed.

## The study has three sections

### 1. Button states gallery

Eight states in a 4×2 grid: `idle`, `hover`, `paletteOpen`, `navOpen`,
`listening`, `processing`, `recording`, `error`. The shape (notch-pill)
is constant; what changes is the pill's width, the mark/glow, and the
inline content (search hint vs. listening text vs. REC + 0:24 vs. !).

### 2. Summoned overlays

Two anchored compositions side-by-side:

- **Palette** — the existing CommandPaletteView shape, but explicitly
  anchored to the button (via the connecting-bracket lead-line) rather
  than centered on screen. Reuses the same row taxonomy as
  `PaletteCommand.registry()`: Go-to / Action / Workflows.
- **Nav popover** — a 260pt sectioned list mirroring `sidebarEntries`
  (Primary / Activity / Tools / Settings). Same icons, badges where
  the live app shows them (`436` for Library count, `3` for Pending).

The connecting bracket is studio-only — it visualizes the anchor
point. The shipping UI just opens flush below the button.

### 3. Variants A & B in context

Two reframings of the existing `MacHome` composition at 820 / 1180 /
1440 widths:

**Variant A — Floating.** Sidebar gone entirely. The Talkie button
lives in the window-chrome center (where a window title would be).
Canvas is fully reclaimed. This is the maximalist read.

**Variant B — Icon-rail.** A 52pt-wide rail anchored by the Talkie
button at top, with 7 icon-only nav buttons stacked below and a
Settings cog at the bottom. The rail preserves the spatial "I know
where each section lives" affordance that the sidebar gives today,
while still demoting it from a 220pt panel to a 52pt strip. This is
the safer read — Library and Compose users who rely on nav context
don't lose it.

Both variants share the same MacHome content. The body composition
reflows naturally because MacHome already accepts a `width` prop
(introduced in iteration 1 of the mac responsive studies).

## Why three gestures (tap / hold / right-click)

Tap and hold are the iOS-native idioms; right-click is the Mac-native
idiom for "give me more options." Together they cover the three
interaction registers without inventing a new pattern:

- **Tap** is the everyday — search, navigate, do anything.
- **Hold** is the talkie idiom — speak, the brand is the verb.
- **Right-click** is the discovery — see all destinations laid out.

Power users still get `Cmd+K` (palette) and `Cmd+Shift+V` (voice)
unchanged. The button adds a discoverable mouse path to flows that
were keyboard-only.

## What replaces the sidebar (precisely)

- Variant A: **nothing**. The sidebar is fully deleted from the
  default surface. `Cmd+Ctrl+S` still summons it for power users who
  want it (no regression).
- Variant B: a **52pt icon-rail** with the Talkie button anchoring
  the top. The rail is the new default. The expanded sidebar is
  still summonable via `Cmd+Ctrl+S` for users who want labels.

In both variants, the existing **`NavigationState.shared`** machinery
keeps working. The sidebar isn't deleted from the codebase — it's
demoted to "summonable when needed."

## Shipped analogs

- **Raycast** — `Option+Space` summons one window that's both search
  and command surface. Validates that consolidating into a single
  anchor works at consumer scale.
- **Arc's command bar (`Cmd+T`)** — search + navigation + new-tab in
  a single floating input. Validates text-first nav once shortcuts
  are taught.
- **Apple Spotlight** — voice (via Siri) and text invoked from one
  menubar anchor. Closest precedent for the voice+text duality.

## Open questions

- **Anchor location at runtime.** The notch is the natural anchor on
  M-series Macs with a display notch, but it's invisible on external
  monitors or older Macs. The composer's `isVirtual` branch already
  handles this — the question is whether the button lives in
  window-chrome (Variant A) or in the icon-rail's top slot
  (Variant B) when there's no notch.
- **Hold gesture vs. accidental long-tap.** Today `Cmd+Shift+V`
  triggers voice command from any focus context. Hold-to-speak only
  works when the button is hovered. Need a fallback affordance
  (right-click menu has "Voice Command" item?) so the muscle memory
  doesn't break.
- **Library's filter pills.** Library's current header has its own
  filter pill row. In Variant B with the icon-rail, the Library
  filter row works as-is. In Variant A with no rail, Library's
  filters become the only persistent navigation on that surface —
  worth a study iteration to see if it reads.
- **Recording state takeover.** When recording, the Talkie button
  becomes a `REC · 0:24` pill. That means it temporarily isn't a
  search/nav button. Is the loss acceptable? Probably yes — during
  a recording the user's intent is already focused.
- **Multi-window.** If two Talkie windows are open, do they both
  show the button, or does the button live in the menubar and serve
  both? Current notch is global. Open.

## Component map

- `app/mac-talkie-button/page.tsx` — route wrapper.
- `components/studies/MacTalkieButton.tsx` — composition root.
- Sub-components inline:
  `StatesGallery`, `StateCell`, `TalkieButton`, `ButtonInner`,
  `TalkieMark`, `RedPulse`, `Spinner`, `ParticleBlob`, `Caret`,
  `SummonedOverlays`, `PaletteAnchored`, `PaletteSheet`, `KeyCap`,
  `NavPopoverAnchored`, `NavPopover`, `ConnectingBracket`,
  `VariantA`, `VariantB`, `ReframedHomeFrame`, `WindowChrome`,
  `FloatingLayout`, `RailLayout`, `IconRail`, `RailTalkieButton`,
  `RailButton`.

Promotion candidates if a second mac study adopts the button:
- `<TalkieButton state={...}>` — promote to
  `primitives/TalkieButton.tsx` once Library / Compose pages start
  rendering it.
- `<IconRail>` — promote to `primitives/IconRail.tsx`.
