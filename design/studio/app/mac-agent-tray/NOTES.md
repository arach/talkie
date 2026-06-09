# Mac Agent Tray — decisions log

Studio rework of the TalkieAgent menu-bar pop-out
(`apps/macos/TalkieAgent/TalkieAgent/Views/Components/AgentMenuPopoverView.swift`).

## Problem

The shipping panel stacks four labelled sections before Tools: **NOW**
(record action), **INPUT** (mic picker), **RECENT**, **TOOLS**. NOW and INPUT
each cost an eyebrow + a full row to say one thing: "record, from this mic."
And the material is a generic near-black menu wired to ad-hoc hex values
(`panelBackground #040405`, local `talkieAmber` / `hotMic`) — not the app's
design tokens, so it doesn't read as Talkie.

## Moves

### 1. Consolidate NOW + INPUT → one capture composer, split 50/50

Record action on the **left**, mic picker on the **right**, one rounded unit
with a hairline divider. No INPUT eyebrow, no shortcut keycaps — the chord
already lives in the header (`Ready for ⌃⌥⇧⌘D`).

- Label is the verb only: **Record** / **Stop** (not "Start Recording"). The
  red disc carries the "recording" meaning; the short verb keeps a true
  50/50 from ever truncating. (User call, 2026-06-07.)
- While recording: left flips to red `Stop`; right half drops the picker for a
  live level meter + `0:08` timer. Header pill → REC, subtitle → "Listening…".
- Layouts under study:
  - **Split** *(default)* — clean 50/50, `Record | 🎙 Yeti Stereo Mic… ⌄`.
  - **Labeled** — same split + RECORD / INPUT micro-eyebrows + `48 kHz · stereo`.
  - **Stacked** — record hero full-width, mic as an attached footer strip.

**SHIPPED (2026-06-07)** in `AgentMenuPopoverView.swift`: the **Split** 50/50.
We briefly shipped **Stacked + "Start Talking"** (looked great in Carbon) then
reverted to Split for compactness. Label is the compact **Record / Stop**
("Start Talking" truncates in the narrow half). Recording swaps the right half
to the live meter (no `0:08` timer in-app — no elapsed-time source exposed yet).

### 2. Scope-dress RECENT + TOOLS

- Channel eyebrows: accent tick + faint mono caps (was plain white-40 caps).
- Recent rows: accent trace dot, hairline rules, faint mono timestamps, hover.
- Tools: warm two-stop tile fill + scheme edge; icon tint accent for
  primary/restart, rec-red for Quit; badge fills with the accent.

### 3. Coordinate with the app theme

The studio **AMBER** scheme is a direct port of `ScopePanel.*`:
`bg #14181A`, `inkFaint #7A8B85`, `trace/accent #E89A3C`, and the same
`stripTop` / `stripBottom` gradients. **One divergence:** `ScopePanel.ink` is
near-white `#E8ECEA` (amber is *only* the accent), whereas the studio AMBER
scheme sets `--scheme-ink` to amber — which tints the title/labels amber. So
for the dark panel, **CARBON** (near-white ink `#F0EDE6` + orange accent) is
the truer match to the shipping panel's intent.

The panel follows the active app appearance:

| Mode            | Scheme  | Reads as                                   |
|-----------------|---------|--------------------------------------------|
| **Dark**        | CARBON  | near-black + near-white ink + orange accent |
| **Light·modern**| FROST   | barely-there cool sheen + graphite ink      |
| **Warm**        | PAPER   | cream + warm-graphite ink + brass amber     |

`Strip header` toggle — `ScopePanel.stripTop` gradient behind the header.
`Graticule` — instrument grid wash; too busy for a panel this small, default off.

## Out

- Recovery/queue row — unchanged, conditional, lives below Tools in Swift.
- Permissions command row — still surfaces in NOW when permissions are missing;
  not modelled here (happy-path study).

## Port targets

`AgentMenuPopoverView.swift`:

- `nowSection` + `inputSection` → one 50/50 composer view (Record half + mic
  picker half) with the live-meter recording state.
- `AgentMenuSection` eyebrow, `AgentMenuRecentRow`, `AgentMenuToolTile` →
  scope tints.
- **Re-ground the palette on tokens, not local hex.** Map:
  `panelBackground → ScopePanel.bg`, `talkieAmber → ScopePanel.trace`
  (or `ScopePalette.amber` in light), `hotMic → ScopePanel`-family rec red,
  ink → `ScopePanel.ink/.inkFaint/.inkSubtle`. Drive light/warm variants from
  `ScopePalette.*` so the panel tracks whatever appearance the app is in.
