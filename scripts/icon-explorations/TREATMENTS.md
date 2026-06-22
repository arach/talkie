# Talkie icon — treatment explorations

Design-lead scratch. Does **not** touch production assets. One shared idea
(JetBrains Mono **Bold** lowercase `t`); only **field / boundary / glyph color**
varies. Goal: a single source artwork that reads as a crisply *bounded* shape
under **both** the macOS squircle mask and the watchOS circle mask, on **both**
black (watch home screen) and white (App Store / Settings) backgrounds.

- Render: `python3 scripts/icon-explorations/render-treatments.py`
- Output: `scripts/icon-explorations/out/` — `master-*.png` (1024) + `contact-sheet.png`
- Contact sheet columns: squircle/black · squircle/white · circle/black · circle/white · 48px/black · 48px/white

Glyph weight is JetBrains Mono **Bold** throughout; height = fraction of the
1024 canvas. Field is flat unless noted. Rim follows `max(circle, square)` edge
distance so both masks inherit the same edge — it is an edge treatment, not an
internal button.

| # | Name | Field | Boundary | Glyph | Bounded on black | Bounded on white |
|---|------|-------|----------|-------|------------------|------------------|
| 1 | Paper | flat `#EFE7D6` | mask only | `#16140E` @0.62 | ✅ | ⚠️ weak |
| 2 | **Tape-Tan** | flat `#D9C49B` | mask only (saturated mid-tone) | `#1A160E` @0.62 | ✅ | ✅ |
| 3 | **Amber** | vgrad `#E9B45A→#D6902C` | mask only (saturated) | `#1C160C` @0.60 | ✅ | ✅ |
| 4 | Reel | vgrad `#F1E7D3→#C9B488` | darker base anchors lower edge | `#16140E` @0.62 | ✅ | ◐ top softens |
| 5 | Night | flat `#2A2418` (warm charcoal) | mask only | `#F2EAD8` @0.62 | ⚠️ vs black home | ✅ |
| 6 | Rim-Tan | flat `#DECBA4` | tonal rim `#8A7752`, width 0.07, strength 0.55 | `#16140E` @0.62 | ✅ | ✅ (rim softens <64px) |

## Rationale per treatment

1. **Paper** — refined current direction: warmer, flatter cream, vignette and
   corner-browning removed (that browning is the "bad colors"). Cleanest/brand-
   true, but a near-white field is the *cause* of the weak watch boundary on
   white. Keep only if we accept light-on-light.
2. **Tape-Tan** — the safest single answer. A saturated mid-tone is the only
   field color that separates from *both* black and white with zero edge tricks.
   Neutral "paper-tape" feel.
3. **Amber** — leans into Talkie's mag-tape / VU amber identity. Most ownable
   color, highest contrast on every background. Gentle vertical gradient for life.
4. **Reel** — directional tape-reel light (bright top → warm bottom). Adds depth
   without the 3D-sphere look the radial vignette caused; darker base anchors the
   lower circle edge. Upper edge is the soft spot on white.
5. **Night** — warm-charcoal inverse (deliberately *not* pure black so it can
   separate from a black home screen). Bold on white; the edge against the black
   watch home screen is marginal — this is the original rejection risk, evaluate
   carefully before choosing.
6. **Rim-Tan** — flat tan plus a tonal rim that follows `max(circle, square)`, so
   both masks get a defined edge from one source. Most literal solution to "well
   bounded from same artwork," but the rim washes out below ~64px and can read as
   a soft inner shadow.

## Design-lead recommendation

Lead candidates: **#2 Tape-Tan** and **#3 Amber** — both stay bounded everywhere,
both masks, to 48px. Pick by identity: Amber = warm/branded, Tape-Tan = neutral
paper. **#4 Reel** is the depth option if flat feels too plain. Retire the
near-white **#1 Paper** as a primary (it reproduces the white-background
weakness) and treat **#5 Night** as experimental (watch-home edge risk).

In all cases drop the production radial vignette + corner-brown — that muddiness
is the "bad colors," and a flat saturated field bounds better than a vignette.
