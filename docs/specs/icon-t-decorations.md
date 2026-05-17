# Talkie — `t` Decoration Studies

**Status:** Draft — exploration round 2
**Owner:** iconlab
**Reviewers:** operator, narrative-studio
**Date:** 2026-05-12
**Supersedes:** the previous `icon-system-explorations.md` round (compositions). This round is *decoration on a locked glyph*.

---

## What changed from round 1

iconlab's previous batch invented compositions (T inside a circle, T cut out of a rounded rect, etc.). That's not what's needed. The brand kit already has:

- A locked single-glyph mark: lowercase **t** from the JBM → Talkie modified font (forward-leaning crossbar, "instrument needle" feel)
- A four-state dot system (IDLE / LISTENING / PROCESSING / ERROR)
- An existing **Marks** page with six quiet treatments at the T-cross

This round: same locked `t`, **explore the catalog of decoration treatments** that could sit on/around it. The shape doesn't change. Only what's *on* it changes.

---

## Locked geometry — the `t` glyph

Geometry is calibrated for JetBrains Mono Medium rendered as SVG `<text>` at `fontSize = size × 0.78`, `baseline = size × 0.86`. Use these exact constants — they're the same ones the existing Marks page uses, lifted from `narrative-studio/src/app/deck/talkie/marks/page.tsx`.

```
T_CELL_CENTER              = 0.31
T_STEM_OFFSET_FROM_ANCHOR  = -0.034
T_STEM_WIDTH               = 0.08
T_CROSS_Y                  = 0.469    // crossbar vertical center
T_CROSSBAR_LEFT            = 0.115    // crossbar leftmost x
T_CROSSBAR_RIGHT           = 0.4825   // crossbar rightmost x
```

The stem visible center is at `(size × T_CELL_CENTER) + (size × T_STEM_OFFSET_FROM_ANCHOR)`. The crossbar runs from `T_CROSSBAR_LEFT` to `T_CROSSBAR_RIGHT` horizontally at `T_CROSS_Y` vertically. Use these to anchor decorations precisely.

Eventually the deck will load `Talkie-Medium.ttf` (at `/Users/arach/dev/hero/web/public/fonts/Talkie-Medium.ttf`) and recalibrate. For this round, keep using the JBM-Medium calibration so studies match the existing Marks page exactly.

---

## Brand palette (locked)

```
INK / Studio Cream    #F4EFE6   the t itself, on dark canvas
CANVAS                 #0E0D0A   dark background
TAPE_TAN               #7A6E5C   recessive secondary
CASSETTE (dark)        #E68A3C   warm accent, Hot Mic when used as dot
HOT_MIC (red)          #FF5346   the listening state — use sparingly
CAUTION                #E5C547   error state — use even more sparingly
HAIRLINE (dark)        #16140e   borders, registration marks
```

May introduce **one** metallic per LOUD study (silver / brushed gold / rosegold / copper). No primaries outside this palette.

---

## Format reference — existing Marks page

`narrative-studio/src/app/deck/talkie/marks/page.tsx` already does six studies:

A. **Inset Chip** — Cassette Orange square inside the T-cross
B. **Knockout** — square of canvas cut from the glyph at the cross
C. **Annotation** — small Cassette Orange square offset above-right
D. **Crossbar Caps** — Tape Tan squares at the ends of the crossbar
E. **Stem-flush Cap** — Tape Tan square at stem width, flush at T-cross
F. **Registration Outline** — hairline Tape Tan square outlining the T-cross

Caption voice is restrained ("the smallest deliberate accent", "the letter holds its breath"). Match that register.

**Do not retread A–F.** Extend the catalog.

---

## What to produce — array of decoration studies

Aim for **12–16 studies**, blending two veins.

### Quiet (same restraint as existing 6; brand colors only; subtle moves)

- Stem dot — small mark at top / mid / base of stem (3 variants ok)
- Crossbar slot — narrow rectangle inside the crossbar
- Stem foot — short horizontal tick at the descender end
- Cross hairline — single hairline crossing the T-cross diagonally
- Ascender notch — small canvas square cut from the top of the stem
- Stem rule — vertical hairline parallel to the stem, just outside it
- Crossbar pin — single dot at left or right crossbar terminal
- Descender hook accent — Cassette Orange chip on the hook's inside curve

### Loud (treatments the marks page hasn't touched)

- **Gradient fill** — Cassette Orange → deep amber on the t itself
- **Glow halo** — neon "ON AIR" outline glow on the t
- **Glass overlay** — frosted translucent t over warm dark, soft inner shadow
- **Debossed** — t stamped into a kraft / paper surface, warm shadow
- **Chrome** — brushed metal fill on the t (silver / brass / rosegold)
- **Tape spool background** — faint cassette reels behind the t (subtle, must not compete)
- **LCD / segment** — t rendered as LED-segment pixels, possibly with Hot Mic dot lit
- **Letterpress** — slightly imprecise edges, soft ink bleed
- **Etched** — fine scratched / engraved texture inside the t
- **Lamp** — small lit lamp at the top of the stem replacing the dot, with halo

Pick the most likely-to-survive 12–16 across these. Don't pad.

---

## Output — Hudson app workspace at :3500

Render the studies as a viewable surface inside **Hudson's app workspace**, served at `http://localhost:3500`. The operator will open that URL to review.

- Add a new route / view in the Hudson app workspace (whatever the canonical path is — `/talkie-marks`, `/iconlab`, or wherever fits the workspace's routing). Find the workspace project under `/Users/arach/dev/hudson/` and follow its existing conventions for adding a page.
- Render the studies as a **grid of cards** in the same visual rhythm as `narrative-studio/src/app/deck/talkie/marks/page.tsx`: each card holds the t glyph at consistent size, decoration applied, and a short caption (eyebrow letter ID + name + 1–2 sentence body).
- Use the existing `TGlyph` SVG component pattern from the Marks page as the renderer — same `viewBox`, same `<text>` rendering, same `before`/`after` slot pattern. Lift it into the Hudson workspace.
- The page should work in dark mode by default (the canvas matches the brand). Add a light toggle if it's cheap; skip if not.
- Footer should show the geometry calibration line, matching the existing Marks page footer.

Also drop SVG masters for each study at:

```
/Users/arach/dev/talkie/assets/icon-explorations/2026-05-12-t-treatments/
├── README.md                        # overview + caption list
├── <study-name>-1024.svg            # one SVG per study, 1024×1024 viewBox
└── thumbs/<study-name>-{40,128}.png # legibility check
```

The SVGs become the source of truth for Phase B production.

---

## Phase B — production assets (after operator picks survivors)

This is a follow-up round. Don't do it yet. Just mentioned so you know where this is heading.

Once the operator picks 1–3 survivors:

- **macOS** — produce `.icns` bundle with the standard size set (16/32/128/256/512 @1x and @2x), squircle shape with alpha allowed. Drop in `talkie/apps/macos/Talkie/Resources/AppIcon.icns` (or wherever the macOS app expects it).
- **iOS / iPadOS** — produce PNG ladder per iOS AppIcon spec (1024 master + all required sizes), no alpha, no rounded mask (system applies). Drop in `talkie/apps/ios/.../Assets.xcassets/AppIcon.appiconset/`.
- **watchOS** — produce Watch icon PNG set, no alpha, must read at 24×24 and 40×40.
- **Web** — favicon set (16/32 ICO, 192/512 PNG, 1200×630 OG card). Drop in `usetalkie.com/public/` (or wherever the site expects).

The .icns bundle generation uses `iconutil` on macOS — straightforward once the PNG ladder is in place.

---

## Constraints

- The `t` is **locked**. Same shape, same geometry, every study. Decoration only.
- Brand palette only, one metallic per LOUD study if used.
- No motion. No emoji-faces. No reinventing the composition.
- Caption voice: restrained. Read the existing Marks page captions and match the register.
- If a study can't survive at 40px (the Watch test), it's a deck-only study — note it in the caption.

---

## Reply expectation

When the array is up and viewable on `localhost:3500`, post in `channel.font-studio` with:

- The URL path on :3500 to open
- A one-line summary per study (just the name, you can drop the lengthy assessment this round)
- Your top picks (3–5) for survival into Phase B
- Anything that surprised you (study that worked better than expected, or worse)

Operator + narrative-studio will pick survivors then trigger Phase B.
