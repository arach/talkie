# Overlay Visual-Design Review — One Coherent Family

Reviewer: Claude Opus 4.8 (visual-design pass only, no code edits).
Scope: `Views/Overlay/FloatingPill.swift`, `Views/Overlay/CaptureTargetLockOverlay.swift`,
shared `TalkieKit/UI/LivePill.swift` (`LiveGlassSurfaceModifier`, `.liveGlassSurface`).

## Root cause of the pale / light-gray look

Every floating surface is built on `.ultraThinMaterial` topped with **white** gradient
fills and **white** strokes:

- `LiveGlassSurfaceModifier` (LivePill.swift:75–135): `.ultraThinMaterial` + a radial white
  0.08 highlight + a linear white 0.12→0.02 fill + a white 0.4→0.15 specular stroke.
- Capture-target badge (FloatingPill.swift:1010–1013): `.ultraThinMaterial` + `mint 0.08` +
  `mint 0.24 / 0.5pt` stroke.
- Collapsed sliver (LivePill.swift:358–362): a bare `textMuted` bar at 0.6 opacity with **no
  chrome at all**.

`.ultraThinMaterial` is *adaptive*: over a light wallpaper it resolves to near-white. White
highlights on a near-white plate = no internal contrast, and white hairlines over a bright
desktop = invisible edge. The chip reads as a floating gray smudge. There is also **no dark
outer stroke**, so nothing separates the plate from a bright background.

The one surface that already reads correctly is the lock **toast** (CaptureTargetLockOverlay
.swift:275–279): it lays `Color.black.opacity(0.5)` *over* the material. That is the pattern
to generalize into a single family.

## The family: "Obsidian Glass" — one fixed dark plate for all three surfaces

Floating overlays sit over arbitrary, unknown content. They must not inherit appearance the
way in-window chrome does. Adopt one wallpaper-independent dark plate (Spotlight / Raycast /
Dynamic-Island idiom) and differentiate the three surfaces by **accent and size**, not by
base material.

### Shared plate token (replace the guts of `LiveGlassSurfaceModifier`)

Layer order, bottom → top:

1. `.ultraThinMaterial` — keep, for the frosted refraction of what's behind.
2. Tint scrim (this is the fix): `Color(white: 0.06).opacity(0.62)` fill. Guarantees a dark
   chip in light *and* dark mode while still letting material texture show through. (The
   toast's `black 0.5` is the same idea; 0.06/0.62 is a touch cooler and more consistent.)
3. Top specular sheen (very restrained): `LinearGradient([white 0.10, clear], top→center)`.
   Drop the radial white 0.08 and the white 0.12→0.02 body fill entirely — on a dark plate
   they add nothing and on a light plate they cause the wash.
4. Inner rim (top-lit): `LinearGradient([white 0.22, white 0.06], top→bottom)`, **0.75pt**.
   A specular top edge, not a full-perimeter white outline.
5. **Outer definition stroke (currently missing, most important for light mode):**
   `Color.black.opacity(0.35)`, **0.5pt**, inset by 0.5pt so it sits just outside the rim.
   This is what anchors the chip on a bright desktop.
6. Shadows: ambient `Color.black.opacity(0.30), radius 10, x 0, y 5` +
   contact `Color.black.opacity(0.22), radius 2, x 0, y 1`.
   Drop the `white 0.05` up-shadow — it does nothing over a dark plate.

Corner radius stays capsule/continuous per surface (below). Accent color enters only via the
state dot, the badge ring, and the toast, never via the plate.

---

## 1. Microphone overlay — normal + hover (esp. light mode)

Plate: shared Obsidian Glass, `Capsule()` (height 20 → radius 10).

Collapsed / normal (the current bare sliver is the worst offender in light mode — a 0.6
gray bar with no plate):

- Give the collapsed state a **mini plate**: same Obsidian Glass, height 14, horizontal
  padding 6 (it already reserves this frame). The bar now rides on a dark chip and reads on
  any wallpaper.
- Idle bar color: raise from `textMuted @ 0.6` to `Color.white.opacity(0.55)` — a defined
  light-on-dark value, not an adaptive muted gray. Width/height unchanged (20×2).
- Recording bar: keep the red pulse (LivePill.swift:348–357). Red on the dark plate is the
  strongest state signal and is fine.

Expanded (hover):

- Same plate, contents unchanged in layout. Text values move off adaptive theme grays to
  fixed light-on-dark: primary `white 0.92`, secondary `white 0.62`, tertiary `white 0.45`.
  (Currently `TalkieTheme.text*` — verify those resolve light over the dark plate; if they're
  appearance-adaptive they'll invert to dark-on-dark in light mode. Pin them.)
- Hover deltas (subtle lift, not a size jump):
  - scale `1.0 → 1.03`
  - tint scrim `0.62 → 0.56` (plate brightens slightly)
  - ambient shadow `radius 10 → 14`, `y 5 → 7`
- State dot stays the single accent: idle `white 0.55`, listening `.red` (pulsing),
  transcribing `warning`, routing `success`, refining `.purple`. Keep the border-color-per-
  state (LivePill.swift:48–55) but recolor the "default" case from `white 0.1` to the shared
  rim so it matches the family.

Animation: content swap `.spring(response: 0.28, dampingFraction: 0.82)` (the current
`.snappy(0.08)` is abrupt); hover in/out `.easeInOut(duration: 0.14)`.

Typography: labels stay SF 8–9; promote the recording timer and the mic-name to
`design: .rounded` for a friendlier numeral and to match the badge/toast. Weight `.medium`
for values, `.semibold` for state words.

---

## 2. Locked-target badge

This is the quiet, persistent sibling of the mic pill — same plate, mint identity, one notch
smaller in emphasis.

- Plate: shared Obsidian Glass, `Capsule()`. Drop the standalone `mint 0.08` background layer
  — instead tint the scrim itself very slightly mint: replace tint step 2 with
  `Color(red: 0.03, green: 0.09, blue: 0.08).opacity(0.62)` so the mint reads as *identity*,
  not as a pale wash on white.
- Size: height **18**, min width ~34, horizontal padding 3 (keeps it visually lighter than
  the 20-tall pill).
- Ring: `Circle().stroke(Color.mint.opacity(0.80), lineWidth: 1)`, 16×16 (was 0.72 / 17). On
  the dark plate you can afford the higher opacity — it's the badge's signature.
- Icon: app icon 12×12, or `scope` `mint @ 0.95` size 9 semibold.
- Count: `size 8 bold rounded`, `white 0.90`, `.numericText()` transition — keep.
- Rim/outer-stroke/shadow inherited from the plate (drops the current lone `mint 0.24 / 0.5`
  stroke and `black 0.28 / r3 / y1` shadow in favor of the family values).
- Appear/disappear: `.scale(0.72).combined(with: .opacity)` +
  `.spring(response: 0.32, dampingFraction: 0.74)` — already correct, keep.

Why it now reads: dark mint-tinted plate + 1pt mint ring at 0.8 gives a saturated, legible
token instead of an 8%-mint ghost over white.

---

## 3. Stacked relationship — 2pt gap, no overlap

Currently `captureTargetGap = 5`, `captureTargetHeight = 19` (FloatingPill.swift:16–18) and
the offset is centered off pill center (FloatingPill.swift:728–733). To hit the 2pt spec:

- `captureTargetGap = 2`, `captureTargetHeight = 18` (matches the badge height above).
- Center-to-center offset then becomes
  `pillHeight/2 (10) + gap (2) + badgeHeight/2 (9) = 21pt`, sign per `captureTargetIsAbove`.
  The two capsules share a 2pt air gap with zero overlap; the lane math already guarantees
  separate hit lanes, so nothing reflows.
- Horizontal alignment: align the badge to the **same edge as the pill** rather than
  centering both independently — leading for `.bottomLeft`, trailing for `.bottomRight`,
  centered for `.bottomCenter/.topCenter`. This makes the pair read as one stacked unit and
  keeps the 2pt gap visually crisp (misaligned centers make a 2pt gap look like a mistake).
- Concentric radii: both are capsules, so nested-radius rules are satisfied automatically.
  Keep the badge slightly narrower than the pill so the stack has a clear primary (pill) and
  secondary (badge) silhouette.

## 4. Target-locked toast / animation

The toast (`CaptureTargetLockView`) is the loud, transient confirmation. It's already the
best-looking surface; bring it *into* the family and let it visibly hand off to the badge.

- Plate: it already does material + `black 0.5` — swap to the shared tokens for consistency
  (tint `white 0.06 @ 0.62`, outer black 0.35 / 0.5pt, family shadows) but keep its richer
  mint treatment:
  - Perimeter gradient stroke `[mint 0.58, white 0.08]` topLeading→bottomTrailing, 0.75pt —
    keep (this is the toast's "hero" edge; the pill/badge use the plainer rim).
  - Mint glow `shadow(color: mint.opacity(0.14), radius 18, y 7)` — keep.
- Corner radius: bring `19 → 18` continuous so the whole family shares one large-surface
  radius vocabulary (pill/badge capsule, toast 18).
- Motion: entrance `.spring(response: 0.34, dampingFraction: 0.72)`, scale `0.94 → 1`,
  viewfinder settle `1.24 → 0.82` + opacity `0.35 → 1`, dashed orbit ring
  `linear 1.4s repeatForever` — all good, keep.
- **Hand-off (new):** the toast flies to the dock anchor over `0.42s easeInEaseOut` while
  fading (CaptureTargetLockOverlay.swift:87–91). Time the **badge's** spring-in to begin at
  ~`0.28s` into that flight so the small mint badge "catches" the identity the toast drops.
  Result: one continuous gesture — loud acquire → quiet persistent lock — instead of two
  unrelated animations.

---

## Hierarchy summary

- **Toast** = highest emphasis, transient: largest plate, hero mint gradient edge + glow,
  viewfinder animation. Says "acquired."
- **Mic pill** = primary persistent control: neutral dark plate, accent only via state dot.
- **Badge** = secondary persistent token: same plate, mint-tinted, one size down, 2pt below.
  Says "still locked."

They cohere because they share one plate recipe (material + dark tint + top rim + dark outer
stroke + family shadow) and differ only in size and accent. Nothing is white-on-white, so
nothing goes pale in light mode.

## Accessibility / contrast risks

1. **Idle collapsed bar** (`textMuted @ 0.6`) is the biggest current failure — invisible on
   light wallpapers. Fixed by the mini-plate + `white 0.55` bar above.
2. **Adaptive `TalkieTheme.text*` over a fixed dark plate** — if those tokens are
   appearance-adaptive they'll render dark-on-dark in light mode. Pin overlay text to fixed
   `white 0.92 / 0.62 / 0.45` values.
3. **8pt mint text** ("CAPTURE TARGET LOCKED", "AUTO") — mint at ~0.9 on the dark plate clears
   ~4:1, acceptable, but it's near the small-text floor. Don't shrink further; the icon +
   text label already back up the color, which also covers color-blind users (don't let mint
   be the *only* state signal).
4. **Reduce Transparency / Increase Contrast**: `.ultraThinMaterial` can go opaque under these
   settings. Because the dark tint scrim sits on top, the chip stays dark and legible — good.
   Verify the outer black 0.35 stroke still renders (it should; it's a solid stroke).
5. **Reduce Motion**: gate the orbit ring, the pulse, and the toast fly-to-dock behind
   `accessibilityReduceMotion` — fall back to a simple fade + static badge.

---

## 5. Screen-aware light-mode treatment (content-sampled, not system-appearance-only)

Goal: in light contexts give a genuinely *beautiful light* overlay (not a forced-dark chip),
and choose surface/text/accent from the pixels **immediately behind** the overlay, falling
back to system appearance only when sampling isn't available. All three components stay
coherent because they consume one resolved palette.

### Two plate variants (the family gains a light sibling)

- **Obsidian** (the dark plate from §"The family") — used over dark/busy backdrops.
- **Frost** (new light plate) — used over bright, relatively flat backdrops:
  - `.ultraThinMaterial` -> tint scrim `Color.white.opacity(0.72)` (bright frosted plate)
  - top sheen `LinearGradient([white 0.55, clear], top->center)`
  - inner rim `LinearGradient([white 0.95, white 0.45], top->bottom)` 0.75pt
  - **outer definition stroke `Color.black.opacity(0.12)` 0.5pt** (lighter than Obsidian's
    0.35 — a light plate needs a soft dark edge, not a hard one)
  - shadow ambient `black 0.16 r10 y5` + contact `black 0.12 r2 y1` (softer than Obsidian)
  - ink text: primary `black 0.85`, secondary `black 0.55`, tertiary `black 0.40`
  - accent: **deep mint** `Color(red: 0.02, green: 0.50, blue: 0.36)` (the bright brand mint
    ~`(0.24,0.86,0.63)` drops below 3:1 on white; the deep mint clears it). Used for the
    badge ring, toast hero edge, and LOCKED/AUTO labels in the Frost variant.

Same geometry (radii, sizes, 2pt stack) for both variants — only the plate/ink/accent tokens
swap, so the layout never moves when the palette changes.

### Sampling strategy

- **Region:** the overlay's frame on its screen, expanded outward ~8pt, so we read what backs
  and surrounds it. For the mic pill + badge (shared location) sample **once** for the pair.
- **Capture:** `CGDisplayCreateImageForRect(displayID, rect)` (synchronous, uses the screen-
  recording TCC the app already holds) or an `SCContentFilter` limited to that rect. Downscale
  to 16×16 with CILanczos, then `CIAreaAverage` -> 1×1 RGBA for the mean; keep the 16×16 to
  get min/max luminance (backdrop "busyness").
- **Derive:** relative luminance `L = 0.2126·R + 0.7152·G + 0.0722·B` on linearized sRGB;
  contrast/variance `ΔL = Lmax − Lmin`.
- **Cost control:** never block render on a sample — draw with last-known/fallback palette
  immediately, update async. Cache per `(displayID, anchor)`.

### Selection thresholds

Variant, with a hysteresis dead-band so it can't flip-flop near mid-gray:

- switch to **Frost** only when `L_backdrop ≥ 0.62`
- switch to **Obsidian** only when `L_backdrop ≤ 0.45`
- inside `0.45–0.62`: **hold current variant** (first-ever resolve tie-breaks to Obsidian —
  safer, and matches the red recording accent)
- **busy backdrop** (`ΔL > 0.5`, e.g. a photo): bias to Obsidian and bump the outer stroke to
  `black 0.45`, because a light plate loses its edges over a high-contrast image.

Text/accent, chosen against the *committed* plate's effective luminance (Obsidian ≈ 0.10,
Frost ≈ 0.90) using WCAG `(L1+0.05)/(L2+0.05)`:

- primary text: first ramp value that clears **≥ 4.5:1**
- secondary: **≥ 3:1**
- tertiary/decorative: **≥ 2:1**
- accent (mint) must clear **≥ 3:1** vs the plate; if bright mint fails (Frost case), step to
  deep mint. Compute, don't hardcode per-wallpaper.

**Recommended restraint:** drive the palette by *luminance only*. Do **not** re-hue the plate
to match the wallpaper's dominant color — it churns and looks garish. Keep the neutral plate +
brand mint; screen-awareness = light/dark + contrast, not hue-matching. (If a subtle
warm/cool nudge is ever wanted, cap it at ±6% on the accent only, never the plate.)

### Hysteresis / debounce (anti-churn)

- **Dual-threshold hysteresis** (the 0.17-wide dead band above) is the primary guard.
- **Temporal debounce:** commit a new variant only after it's stable across **3 consecutive
  samples (~1.2s)**.
- **Rate limit:** ≤ 1 sample / 500ms; back off to every ~2s while idle and static. Force an
  immediate sample on: overlay appear, `didChangeScreenParameters`,
  `NSWorkspace.activeSpaceDidChange`, and transition to `.listening`.
- **Smoothing:** when the palette actually changes, cross-fade tokens over **0.35s ease-in-out**
  so it never pops.

### Coherence across the three

- One resolver produces a single `OverlayPalette` struct
  `{variant, plateTint, rimGradient, outerStroke, textPrimary/Secondary/Tertiary, accent,
  shadow}`; mic pill, badge, and toast all render from it -> guaranteed coherence.
- The mic pill + badge share one sample (same location). The **toast** spawns at the input
  point and flies to the dock anchor: have it **inherit the mic-cluster's current variant** if
  it's on the same screen, and only re-resolve if it spawns somewhere whose backdrop differs
  beyond threshold. During the fly-to-dock it keeps its spawn palette (don't re-sample mid-
  flight).

### Graceful fallback

- No screen-recording TCC, capture failure, or perf/battery pressure -> resolve variant from
  `NSApp.effectiveAppearance` (system light/dark) with the fixed Obsidian/Frost palettes.
  Rendering never waits on a sample.
- **Reduce Transparency / Increase Contrast** -> force the higher-contrast palette (Obsidian
  with a more opaque tint, or Frost with darker ink) and **disable sampling churn** entirely.
- **Reduce Motion** -> keep the palette cross-fade (it's a fade, allowed) but drop orbit/pulse/
  fly-to-dock per §4.

### A11y note specific to Frost

The Frost variant must still clear the same ratios — verify deep-mint LOCKED/AUTO labels at
8–9pt reach ≥ 4.5:1 on the frosted white (deep mint above is ~5:1 on `white 0.90`, good). Don't
let the light plate drop the state signal to color alone; the icon + label still carry it.

## Next owner

This is a spec, not a change. Implementation (editing `LiveGlassSurfaceModifier`, the badge,
the layout constants, and the toast) is a separate task for whoever picks up the overlay work
— no code was modified in this review.
