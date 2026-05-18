# Talkie Icon System — Exploration Brief

**Status:** Draft — exploration phase
**Owner:** iconlab (new Hudson-side Scout card)
**Reviewers:** operator, narrative-studio
**Date:** 2026-05-12

---

## 1. Goal

Produce **8–12 distinct icon directions** for Talkie that work across the three destination contexts below. Each direction is a complete visual idea — composition + treatment + color — rendered at the platform-required sizes. The aim is a *system* (one icon, three contexts), not three unrelated icons.

This is exploration. No direction is locked in. Operator picks the survivors after seeing them side by side.

---

## 2. Three destinations

| Destination | Where it lives | Constraints |
|---|---|---|
| **Web** | `/Users/arach/dev/usetalkie.com` (favicon, PWA install, social card) | 32×32 + 16×16 ICO/PNG, 192×192 + 512×512 maskable PNG, 1200×630 OG card. Dark + light variants. SVG master. |
| **iOS + watchOS + Widget** | `/Users/arach/dev/talkie/apps/ios` (Talkie iOS, TalkieWatch, TalkieWidget) | 1024×1024 master, **no alpha**, **no transparency**, rounded square mask applied by system. Watch icons must read clearly at 24×24 + 40×40. Widget icon may differ slightly from app icon. |
| **macOS + tap switcher** | `/Users/arach/dev/talkie/apps/macos` (AppIcon.appiconset already structured) | Squircle (rounded with Big Sur+ corner-radius convention), **alpha allowed** (use it — the Dock + Mission Control cutout aesthetic depends on it). Sizes: 16/32/128/256/512 @1x + @2x. Recognizable at 16px in the Dock. |

The icon must **read at a glance** in every one of these placements. A direction that works at 1024 but mushes at 32px is failing the brief.

---

## 3. Source primitives (the locked stuff)

The Talkie brand has three signature forms. Every direction should build on at least one of these — do not invent a new mark from scratch.

### a. The wordmark — "talkie"

- Font: **Talkie Medium** — `/Users/arach/dev/hero/web/public/fonts/Talkie-Medium.ttf` (also available as path-built glyphs in Hero's `web/src/talkie/glyphOps.ts`)
- Six glyphs: `t a l k i e` — three families of form: vertical bars (`l`, `i`), forward-leaning hook (`t`), rounded body (`a`, `k`, `e`)
- Notable: tight letterfit (negative left-padding on most glyphs), the `i` is bar-only (no tittle), the `t` leans forward
- Use case: Watch complications, wide social cards, anywhere width is plentiful

### b. The landmark T

- Talkie's signature glyph. **Forward-leaning crossbar** (right side +20u from JBM baseline), **thinner crossbar than JBM**, **tighter descender hook**. The visual metaphor is an "instrument needle" — a measurement tool.
- This is the strongest single-letter mark in the wordmark. The natural choice for a monogram icon.
- Reference: Hero's `glyphOps.ts:buildT` for the canonical path
- Use case: square icons (favicon, app icon), Dock recognizability

### c. The Hot Mic dot

- Cassette orange `#E68A3C`, lives over the `i` in the wordmark
- Pulses at 1.0Hz when capturing audio (motion belongs in app, not in static icon — but the *shape* and *color* carry brand)
- Can be a standalone mark or paired with the T

### Brand colors (locked)

| Token | Hex | Use |
|---|---|---|
| Hot Mic orange | `#E68A3C` | accent, dot, "live" state |
| Tape tan | `#7A6E5C` | secondary, recessive |
| Canvas | `#0E0D0A` | dark background |
| Cream | `#F4EFE6` | light foreground |
| Hairline | `#16140e` (dark) / `#d4cfc5` (light) | borders, dividers |

You may introduce **one** accent metal/gradient (silver, brass, rosegold) per direction. No bright primaries outside the brand palette.

---

## 4. Existing exploration (look at these before starting)

There's prior icon work in `/Users/arach/dev/talkie/assets/icon-assets/` — composed variations like retro-rosegold-1024, talkie-tall-1024, eyes-variants. Review these for context but **do not** retread the same directions. The new explorations should push into territory those didn't cover.

Also look at `/Users/arach/dev/talkie/assets/brand/AppIcon.appiconset/` for the current shipped icon — that's the floor, not the ceiling.

---

## 5. Treatments to explore

Aim for ~10 directions across these treatments. Pick the ones most likely to be strong; you don't have to do all of them.

1. **Solid mark, flat** — landmark T or wordmark in single color, no decoration. The most restrained direction. Brutalist confidence.
2. **Gradient** — Hot Mic orange → deep cassette amber, or tape tan → canvas. Subtle, brand-warm. Not Instagram-style multi-stop.
3. **Glass / frosted** — modern Apple-Vision aesthetic. Translucent T over a tinted blur. Soft inner shadow.
4. **Debossed / paper** — the icon stamped into a textured surface. Tactile. Warm shadows. Works particularly well on macOS with alpha.
5. **Neon / glow** — outlined T or wordmark with soft luminous edge. Recording-studio "ON AIR" lamp feeling.
6. **Retro chrome / rosegold** — there's prior work here; push it further. Bevel + reflection + brand color. Walkie-talkie / radio-era nostalgia.
7. **Monoline** — single-stroke version of the T or wordmark. Pure geometry. Reads at small sizes.
8. **Tape / cassette** — the Talkie name implies voice/recording. A tape-spool or cassette-reel motif behind/within the T.
9. **LCD / segment readout** — pixel-grid or LED-segment rendering of the T. Hot Mic dot as a glowing indicator. Vintage device feel.
10. **Negative space mark** — the T or wordmark cut out of a solid shape (square, squircle, circle). Strong silhouette.

Bells and whistles allowed: subtle inner highlights, single-direction shadows, paper grain, vinyl scratches, brushed metal — *only* if they serve the direction. Decoration without intent makes the icon look like a stock template.

---

## 6. Output structure

For each direction, create:

```
/Users/arach/dev/talkie/assets/icon-explorations/2026-05-12-<short-name>/
├── README.md              # the treatment, what it evokes, what's locked vs loose, where it shines vs fails
├── master-1024.svg        # SVG source, 1024×1024 viewBox
├── ios-1024.png           # iOS app icon (no alpha, no rounded mask — system applies)
├── ios-watch-1024.png     # watchOS app icon (no alpha)
├── macos-squircle-1024.png # macOS app icon (squircle shape, alpha used for cutout)
├── favicon-32.png         # web favicon
├── favicon-512.png        # web maskable PWA
├── og-card-1200x630.png   # social card (optional but encouraged)
└── thumbs/                 # 16, 24, 32, 40, 64, 128 PNGs for legibility check
```

The README should be short — 3 short paragraphs:
- **What it is** — name + treatment in one sentence
- **What it evokes** — the feeling, the reference, the why
- **Where it shines / where it fails** — honest call. "Reads great at 1024 but mushes below 64." or "Works on macOS squircle, fights the iOS rounded mask."

Names: `flat-t`, `chrome-rosegold-mk2`, `glass-vision`, `tape-spool`, `lcd-readout`, `negative-square` — short, descriptive, hyphenated.

---

## 7. Constraints / no-go's

- **No transparency on iOS variants.** Render the iOS PNG on the icon's chosen background color, not on transparency.
- **Watch icons must survive at 24×24 and 40×40.** Show a 40px thumb in the README for self-audit. If the icon disappears, the direction needs a small-size variant.
- **macOS squircle should respect the macOS 11+ icon template.** That means the shape sits inside a roughly 824×824 area centered in 1024, with optional bleed (for shadows). Don't fill the full 1024 square.
- **No emoji-style faces.** No "eyes" direction — that's been tried (`/Users/arach/dev/talkie/assets/icon-assets/composed/var1-eyes-only.png`), retreading it isn't useful.
- **No multi-color spectacle.** Talkie's palette is warm, restrained. Three colors max per icon, brand palette + one metallic if used.
- **Recognizable from the wordmark or landmark T.** Someone who's seen the wordmark should be able to recognize the icon as Talkie.

---

## 8. Process notes

- This is **exploration**, not production. The deliverable is a set of evaluable directions, not finished assets.
- You may use any tooling you like (SVG by hand, Sharp/ImageMagick for resizing, Python+CairoSVG for batch, etc.). Hudson has tooling at `apps/logo-designer` and Plotter that may help — your call whether to use them.
- Build the SVG masters first, then batch-resize. Don't hand-edit each PNG size.
- When done, post in `channel.font-studio` (NOT `channel.shared`) with:
  - Path to the explorations directory
  - A short summary line per direction
  - Your top 3 picks and why
  - One "honorable mention" — something you tried that didn't work but is interesting

Operator (the human) and narrative-studio will review the explorations and pick survivors.

---

## 9. Open questions to flag (don't block on)

- Should the macOS Dock icon have a colored background, or rely on Dock recess shadow to define it? Answer: try both per direction if cheap.
- Watch face complication icon — separate from the app icon? Default answer: yes, but only if the standard icon doesn't read at 24×24. Otherwise reuse.
- Animated variants (Hot Mic pulse) — out of scope for this round. Static only.
