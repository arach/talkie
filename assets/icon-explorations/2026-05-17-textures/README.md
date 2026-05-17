# Round 3 — Texture / Effects / Lighting Studies

Date: 2026-05-17
Builds on: round 2 decoration studies (2026-05-12)

Eight surface treatment directions applied to the locked `t` glyph and `talkie` wordmark.
All effects are pure SVG (filters, patterns, masks, clipPaths) — no raster dependencies.

## Directions

| # | Direction     | Palette                      | Technique                                          |
|---|---------------|------------------------------|----------------------------------------------------|
| 1 | Phosphor CRT  | Amber LED on Ribbon Black    | feGaussianBlur bloom ×3 + scanline pattern         |
| 2 | Dot-matrix    | Amber LED / Cassette Orange  | Circle-pattern mask + composited unlit grid         |
| 3 | Pixel / Bitmap| Studio Cream on Ribbon Black | Rect-pattern mask with 2–4px cell gap               |
| 4 | Halftone      | Hot Mic + Tape Tan on Cream  | Dual circle-pattern layers + xy misregistration     |
| 5 | Letterpress   | Ribbon Black on Studio Cream | feTurbulence grain + feMorphology dilate + shadow   |
| 6 | Etched        | Tape Tan on Ribbon Black     | Dual-angle line-pattern fill + text clipPath        |
| 7 | Warm Brass    | 7-stop brass gradient        | linearGradient + feSpecularLighting + fePointLight  |
| 8 | Particle      | Cassette Orange on Black     | feTurbulence threshold + dilate mask region          |

## Asset types per direction

- `{direction}-t-1024.svg` — single-letter hero (1024×1024)
- `{direction}-wordmark.svg` — full "talkie" wordmark
- `{direction}-dot-playful.svg` — indicator dot, expressive variant
- `{direction}-dot-restrained.svg` — indicator dot, system-quiet variant

## Gallery

Live gallery: `http://localhost:3500/talkie-textures`
Source: `/Users/arach/dev/hudson/app/talkie-textures/page.tsx`

## Top picks for Phase B

1. **Phosphor CRT** — letter + wordmark. The bloom reads at every size and the scanline texture is distinctive without competing with the mark. The restrained dot is a natural system indicator.
2. **Etched / Engraved** — letter + wordmark. The crosshatch gives the mark a premium, institutional quality. Scales down cleanly because the hatching pattern is resolution-independent.
3. **Letterpress** — wordmark especially. The grain + ink bleed is the most tactile treatment; the wordmark version looks like a real press proof. Dark-mode variant (on cassette brown) would be worth exploring.
4. **Halftone** — letter. The misregistration effect is strongest at icon scale. The wordmark version works but is harder to control at small sizes.
5. **Dot-matrix** — letter. Airport-sign energy is immediately recognizable. The 3×3 playful dot is a keeper.

## Surprise

The **etched** direction landed better than expected. Cross-hatching inside a monospace letterform creates a banknote-engraving quality that feels premium and distinctly non-digital — the exact opposite energy from phosphor/dot-matrix, but equally compelling. The wordmark version holds together because the hatching density adapts naturally to varying stroke widths across the six glyphs.

## Next round

Push **letterpress** further: dark-mode variant (Ribbon Black ink debossed into deep cassette-brown), and a distressed/worn variant where the ink coverage is incomplete (partial printing). Also worth exploring: combining phosphor with dot-matrix as a "LED terminal" hybrid — lit dots with bloom halos.
