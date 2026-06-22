# Talkie icon — NIGHT variants (dark warm source)

Focus per user: make the **dark** source read as well-bounded under both the
macOS squircle/rectangle and the watchOS circle, JetBrains Mono Bold `t`, no
black-background rejection risk.

- Render: `python3 scripts/icon-explorations/render-night.py`
- Output: `scripts/icon-explorations/out/night/` — `master-*.png`, `contact-sheet.png`, `zoom-circle-on-black.png`
- The decisive test is **`zoom-circle-on-black.png`**: circle mask on pure black at 300/88/55/**48**px (actual watch sizes).

## Governing principle

A dark icon gets **no help from the background** on the black watch home screen
— that's the rejection. So the boundary must be carried by an **internal lit
rim/bevel** that follows `max(circle, square)` (one source → both masks inherit
the edge). The **rim, not the field**, is what guarantees the boundary. Verify
every candidate at 48px circle-on-black.

## Variants

| key | field | rim (color · width · strength) | glyph | 48px edge on black |
|-----|-------|--------------------------------|-------|--------------------|
| n1-cream-rim | flat `#2A2418` | `#EDE4D0` · 0.08 · 0.70 | cream `#F2EAD8` | ✅ strongest, crisp |
| n2-ember-rim | flat `#2A2418` | `#D29A4A` · 0.10 · 0.60 | cream `#F2EAD8` | ◐ dims small — bump |
| n3-top-lit | vgrad `#3A3220→#1C180F` | `#E7DCC4` · 0.07 · 0.55 | cream `#F2EAD8` | ✅ rim carries bottom |
| n4-bevel | flat `#2A2418` | `#F4ECDA` · 0.045 · 0.88 | cream `#F2EAD8` | ✅ hairline holds, cleanest |
| n5-amber-glyph | flat `#2A2418` | `#C9A86A` · 0.08 · 0.50 | **amber `#E3A53F`** | ⚠️ best identity, weakest edge |
| n6-lifted | flat `#34301F` | `#E7DCC4` · 0.06 · 0.40 | cream `#F2EAD8` | ◐ soft (field-led) |
| n7-hybrid | flat `#2A2418` | `#EDE4D0` · 0.08 · 0.70 | amber `#E3A53F` | ✅ best color + safe edge |

## Design-lead read + adjustments

- **Boundary-safe picks:** **n1 Cream Rim** (crispest) and **n4 Bevel** (cleanest,
  most product-like). Both hold to 48px with no rejection risk.
- **Brand pick → n7-hybrid (recommended):** keep n5's amber `t` `#E3A53F` but swap in
  n1's rim (`#EDE4D0` · 0.08 · 0.70). Amber glyph carries identity, cream rim
  carries the boundary. This is the strongest single candidate.
- **n2 Ember Rim:** if we want the *edge* to be the warm/brand element, tighten +
  brighten it: width `0.10→0.085`, strength `0.60→0.74`, so it survives 48px.
- **Field floor/ceiling:** keep the field warm and in the `#2A2418`–`#34301F`
  band. Below that it merges with black even with a rim; above it stops reading
  as "Night." Lifting the field (n6) is *not* a substitute for the rim.
- **Rim discipline:** stay warm (cream/amber), never cool white/blue (clashes with
  mag-tape). Keep the bevel tight (don't let it bleed inward into a sticker halo).

## Square vs watch — go PLATFORM-AWARE (decided)

The square preview of n7 reads as a "dark coin inside a pale rounded square."
Root cause (see `out/night/square-coin-diagnosis.png`): the cream rim `#EDE4D0`
is ~identical to the Icon Composer pale fill `#F4EFE6`, so on the square the rim
merges with the fill at the corners and the rim's circular component rounds the
dark mass into a coin. It stays coin-ish even on a dark fill — the lit ring
itself traces a circle.

The two masks have **opposite** edge needs, so one bitmap cannot serve both:
- watchOS circle on the black home screen has **no background contrast** → it
  needs an internal **light ring**.
- the iOS/macOS square already gets four crisp edges from the mask → it must
  have **no ring** (a ring = the coin).

**Decision: two platform-specific Icon Composer layers** (the project already
splits `circles:[watchOS]` / `squares:shared`). Not one shared bitmap.

- **watchOS (circle) layer** = n7-hybrid, unchanged: field `#2A2418`, circular
  rim `#EDE4D0` · 0.08 · 0.70, amber glyph `#E3A53F`.
- **iOS/macOS (square) layer** = `out/night/master-sq-square.png`: full-bleed,
  field vertical top-light `#322C1C`→`#201C12`, **square-only** inner edge sheen
  `#3C3422` (from `square` metric, last 10%, strength 0.30 — no radial/no ring),
  amber glyph `#E3A53F` Bold @0.62. Boundary = the squircle mask + faint square
  sheen; zero internal circle.
- **Composer fill for the square group:** change the pale cream
  `extended-srgb:0.957,0.937,0.902` to the dark field `#2A2418`
  (`extended-srgb:0.165,0.141,0.094`) so no pale ring can show at the corners.

Render the square master: it's emitted by the diagnosis cell; regen via the same
generator pattern (full-bleed dark + `square`-only sheen).

## FLAT Night (final direction — no gradients)

Solid dark field, no lighting gradients, no coin. Platform-aware stays.
Proof: `out/night/flat-night-check.png`; bitmaps `flat-square.png`, `flat-watch.png`.

- **Field (both):** flat `#2A2418` (warm-charcoal). No gradient.
- **Glyph (both):** amber `#E3A53F`, JetBrains Mono **Bold**, height 0.62.
  (Neutral alt: cream `#F2EAD8`.)
- **iOS/macOS square:** full-bleed flat, **no boundary element** — the squircle
  mask is the edge. Set the square-group Composer fill to `#2A2418`
  (`extended-srgb:0.165,0.141,0.094`), not pale cream, so no halo.
- **watchOS circle:** flat `#2A2418` + a thin crisp ring — cream `#EDE4D0`,
  stroke **3.2% of diameter**, outer edge ~1% inside the masked circle,
  hard-edged (no glow). Verified legible down to 48px on black. Bump to ~4% for
  a heavier read at the smallest sizes.
- Yes: **watchOS alone gets the ring; the square stays flat/full-bleed.** A flat
  dark field has no edge against the black watch home screen (the rejection); the
  square's mask already supplies its edge, so a ring there only reintroduces the coin.
  mag-tape). Keep the bevel tight (don't let it bleed inward into a sticker halo).
