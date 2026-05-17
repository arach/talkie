# Agent Bay — Decisions Log

## What the study renders

The dark "instrument bay" panel that sits on Home, between Capture
Modes and the Captures table. Top control rail · 4 stat tiles
(memos/dictations/streak/words) · bottom rail. Optional treatments:
sparkline under each stat, 24h timeline strip, 7-day heatmap,
viewfinder corner brackets, inset bezel.

Source of truth in Swift: `apps/macos/Talkie/Views/Home/ScopeHomeView.swift`.

## Anchor schemes

Two reference points the study orbits around:

- **AMBER** — `#14181A` gunmetal + `#E89A3C` phosphor. The original
  CRT/instrument identity. Warm dark, amber halo, reads as
  illuminated electronics.
- **PAPER** — `#EEE7D6` cream + `#9A6A22` copper. The flipped
  counterpart. Warm light, copper ink, reads as printed
  dashboard / typewriter sheet.

Both feel *designed*. Both committed to a material identity
(electronics; paper) with strong contrast and saturated accents. They
share an amber-family accent — that consistency is what ties the
picker together.

## Schemes that did NOT survive

- **GREEN / CYAN / MONO / CREAM** (first pass) — phosphor color
  swaps on the same gunmetal floor. Quick to ship, low-effort, didn't
  feel like distinct designs. Dropped 2026-05-17.
- **LINEN / FROST** (second pass, light) — light surfaces with
  alternative accents. Felt like generic "light mode" treatments.
  Dropped 2026-05-17.
- **GRAPHITE / PEWTER / ASH / STONE** (third pass, gray gradient) —
  lightness interpolations between AMBER and PAPER with graphite ink
  tuned for the mid-tones. Read as filters applied to AMBER, not
  designed materials. Dropped 2026-05-17 — *the lesson: muddy
  mid-tones lose intent. Commit to a real material identity with
  strong contrast or don't ship the scheme.*

## Current scheme lineup (9, ordered dark → light)

| Scheme | Surface | Accent | Identity |
|---|---|---|---|
| **AMBER** | `#14181A` gunmetal | `#E89A3C` amber | Lit electronics bay (anchor) |
| **CARBON** | `#0E0F10` true black | `#FF9D33` electric amber | Max-contrast dark, cooler sibling to AMBER |
| **SLATE** | `#363D45` cool slate | `#E5B040` golden amber | Real slate stone. Golden accent because warm orange clashed with cool dark. |
| **OXIDE** | `#22344A` patinated blue-steel | `#D69862` patina copper | Weathered industrial. Warm-white ink, not crisp — feels aged. |
| **CONCRETE** | `#B0ADA6` warm industrial gray | `#9A6A22` deep copper | Bridges STEEL→BONE warmly. Espresso ink. |
| **STEEL** | `#BCC3C9` cool industrial | `#E89A3C` saturated amber | Industrial signage. Sharp gunmetal ink. |
| **ALUMINUM** | `#D6DBE0` light brushed cool | `#D49236` cool amber | Cleaner, cooler counterpart to STEEL. Charcoal ink. |
| **BONE** | `#E8E2D2` warm off-white | `#9A6A22` copper | Typewriter sheet — drier counterpart to PAPER. |
| **PAPER** | `#EEE7D6` cream | `#9A6A22` copper | Printed dashboard (anchor). |

## Design principles surfaced by the study

1. **Same accent family throughout.** AMBER and PAPER both use
   amber-family accents — that consistency is what makes them feel
   like the same product. Mid-tone schemes that drift to blue or
   green accents lose the through-line. Stay within amber/copper.

2. **Saturation per surface.** Deep amber `#B86810` reads as muddy
   brown on cool gray. Saturated `#E89A3C` reads as committed copper
   on the same surface. Surface lightness changes the *saturation*
   the accent needs, not just the hue.

3. **Glow lives on dark surfaces.** Light schemes get no glow halo —
   printed paper doesn't emit. The glow is the "lit" cue.

4. **Stat ink committed to a side.** Either phosphor (= accent, on
   dark) or deep neutral (= graphite/espresso, on light). The
   tuned-graphite-for-mid-gray approach reads as a filtered
   compromise. Pick a side.

5. **The picker should be a gradient.** Ordering schemes by surface
   lightness — darkest → lightest — turns the picker itself into an
   evaluation tool. Adjacent schemes should read as siblings; jumps
   in lightness signal a missing intermediate.

## Treatments

Independent of the scheme. All toggle simultaneously across all bays.

- **Sparkline** — 7-day mini-trace under each stat label. Default on.
- **Compact** — height 220 → 158, stat font 34 → 26. Default on.
- **Heatmap** — 7×5 phosphor cell grid, top-right of body area.
- **Timeline** — 24h tick strip at bottom of body.
- **Brackets** — viewfinder corner crops, inset from the panel border.
- **Bezel** — inner highlight + shadow ring for "sunk into desk" depth.

## Open questions

- Whether ALUMINUM and STEEL are differentiated enough or whether one
  should absorb the other.
- Whether OXIDE needs to lean further into the patina (more green-blue
  oxidation) or stay restrained.
- Whether CARBON is meaningfully distinct from AMBER or is just AMBER
  with the warmth removed — might be the next drop candidate.
