# Talkie — Logo Animations (Round 1)

**Status:** Draft — exploration round
**Owner:** preframe
**Reviewers:** operator, narrative-studio
**Date:** 2026-05-13

---

## What to produce

**Two animations, both anchored on the locked Talkie brand primitives:**

### Animation 1 — State transitions for the `t` mark

The lowercase `t` (JBM → Talkie modified) cycling through four canonical states:

| State | Indicator | Color | Notes |
|---|---|---|---|
| IDLE | small dot, off | Tape Tan `#7A6E5C` | dot is recessive, the mark is "at rest" |
| LISTENING | dot, pulsing | Hot Mic Red `#FF5346` | **1.0Hz pulse — brand's canonical motion** |
| PROCESSING | "reels rolling" — cassette spool motif | Cassette Orange `#E68A3C` | 2.4s loop; two reels alternately rolling. Per slide 8: "one becomes two becomes one." |
| ERROR | yellow square (NOT a dot) | Caution Yellow `#E5C547` | snaps in, doesn't pulse. Never Hot Mic. |

**Choreography:**
- Each state shown for 1.5–2s
- Transitions between states are 200–400ms eases
- Loop infinitely: IDLE → LISTENING → PROCESSING → ERROR → IDLE
- The `t` glyph itself is **static** through all four states — only the indicator above the stem changes

**Reference for static states:** slide 8 of the deck at `/Users/arach/dev/narrative-studio/src/app/deck/talkie/page.tsx` ("One letter. Four states. No microphone."). Look at it to see exactly how the four states are visualized statically.

### Animation 2 — Wordmark entrance

The "talkie" wordmark assembling for app launch / splash:

- 6 glyphs (`t a l k i e`) appear sequentially, left to right
- Each letter fades in (no slide, no bounce — restraint is the brand)
- Hot Mic dot arrives **last**, settles above the `i` stem, and begins its 1.0Hz pulse
- Total duration ~1.4s — fast enough not to make people wait, slow enough to feel deliberate
- Once assembled, hold for ~1.2s, then can fade out or loop

**Reference for the static wordmark:** slide 1 of the deck (`SlideCover` in `narrative-studio/src/app/deck/talkie/page.tsx`) and the Frames page (`narrative-studio/src/app/deck/talkie/frames/page.tsx`).

---

## Source primitives (locked)

### Lowercase `t` geometry

Calibrated against JBM Medium at `fontSize = size × 0.78`, baseline `size × 0.86`:

```
T_CELL_CENTER              = 0.31
T_STEM_OFFSET_FROM_ANCHOR  = -0.034
T_STEM_WIDTH               = 0.08
T_CROSS_Y                  = 0.469
T_CROSSBAR_LEFT            = 0.115
T_CROSSBAR_RIGHT           = 0.4825
```

The `TGlyph` SVG renderer pattern is in `narrative-studio/src/app/deck/talkie/marks/page.tsx` — lift the math/component shape from there.

### Talkie Medium font

`/Users/arach/dev/hero/web/public/fonts/Talkie-Medium.ttf` — the wordmark font. Dotless `i`, forward-leaning `t` crossbar. Use this for the wordmark entrance animation.

### Brand palette (locked)

```
INK / Studio Cream     #F4EFE6   the glyph / wordmark ink on dark
CANVAS                  #0E0D0A   dark background
TAPE_TAN                #7A6E5C   IDLE indicator
HOT_MIC (red)           #FF5346   LISTENING — the only red
CASSETTE (orange)       #E68A3C   PROCESSING
CAUTION (yellow)        #E5C547   ERROR
```

No primaries outside this palette.

### Canonical motion: 1.0Hz Hot Mic pulse

```
frequencyHz: 1.0
periodMs:    1000
opacityRange: [0.55, 1.0]
easing:      ease-in-out
```

This is the brand's *one* canonical motion. Already defined in `narrative-studio/src/app/deck/talkie/_brand/tokens.ts` as `PULSE`. Honor it in the LISTENING state.

---

## Output

### Viewable surface

Render both animations inside **Hudson's app workspace** at `http://localhost:3500/app#focus=image-process-lab` (or wherever the canonical motion-review surface lives — check with the iconlab work that already ships there). Side-by-side, autoplaying on loop, captioned. Same caption restraint as the existing Marks page.

If `image-process-lab` isn't the right surface, propose the right one and confirm with the operator before building.

### Final asset files

For each animation, drop in `/Users/arach/dev/talkie/assets/animations/2026-05-13-<animation-name>/`:

```
├── README.md              # what it is, what it evokes, duration, loop behavior
├── source.tsx             # Remotion source (you have Remotion in the repo)
├── render.mp4             # 1080×1080 (square), 60fps, H.264, transparent if possible
├── render.webm            # WebM with alpha — for web overlays
├── render.gif             # 480×480 fallback for places that need GIF
└── lottie.json            # Lottie JSON — for iOS/Android/Lottie-web playback
```

The Lottie export is the most portable for product use (iOS app launch screens, Android, web). MP4/WebM for marketing. GIF for fallbacks.

---

## Don't

- **No motion outside the brand's vocabulary.** No bouncing, no elastic eases, no 3D rotations, no particles. Talkie's motion is restrained — 1.0Hz pulse is the brand's loud move; everything else should be quieter.
- **No microphone glyph.** Slide 8 explicitly excludes it. "Voice apps that show microphones are still confused about who they are."
- **No emoji-face stuff.**
- **Don't redraw the `t`.** Use the locked geometry. The brief is about choreographing existing primitives, not new glyph design.
- **Don't invent new colors.** Brand palette only.

---

## Reference materials

- **Slide 1 cover** — `narrative-studio/src/app/deck/talkie/page.tsx` (`SlideCover`)
- **Slide 8 four states** — same file, search for "One letter. Four states."
- **Marks page (T-cross studies)** — `narrative-studio/src/app/deck/talkie/marks/page.tsx`
- **iconlab t-treatments** — `talkie/assets/icon-explorations/2026-05-12-t-treatments/` (decoration studies on the same locked `t`)
- **Brand tokens** — `narrative-studio/src/app/deck/talkie/_brand/tokens.ts` (palette, geometry, pulse constants)
- **Wordmark component** — `narrative-studio/src/app/deck/talkie/_brand/wordmark.tsx`

---

## Reply expectation

When the viewable surface is live and the asset files are dropped, post in `channel.font-studio` with:

- The URL on :3500 to open
- Paths to the two animation asset directories
- Total render duration for each (so the operator knows what they're looking at)
- One thing that surprised you in the process (a constraint that bit, a motion choice that landed better than expected, anything)

Operator + narrative-studio will review and decide whether to lock these as the canonical animations or commission revisions.
