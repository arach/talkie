# Capture Target Confirmation

## Product job

Confirm that Talkie has remembered the destination for future captures without
turning the moment into a warning, targeting operation, or second persistent
control.

The transient confirmation and the persistent locked-mode badge are siblings,
not one object travelling between two places:

- The transient confirmation appears immediately above the chosen input.
- The persistent badge stays in Talkie's overlay stack and quietly preserves
  state after the confirmation is gone.
- Captures accumulate against that target until the user sends or clears them.

## Visual direction

_Fourth aesthetic pass — "Destination Token". A small Talkie routing
instrument rather than a generic notification card._

- Civilian, editorial, and calm. No reticles, radar rings, crosshairs, giant
  locks, arrows, neon, or police/military visual language.
- The app name remains the only visible copy. The window title and status
  sentence stay out of the layout.
- Talkie's white T tile is fused into the component; a canonical amber trace
  travels toward the app name and resolves into the mint locked-state color.
- A three-sided receiving bracket marks the app name as the destination, while
  the lower point physically attaches the token to the selected input below.
- Seven-point corners, a 0.75pt perimeter, and the custom pointed silhouette
  make the object recognizable without a decorative top strip.
- No target-app icon, checkmark, lock glyph, badge, reticle, or military target
  illustration. The Talkie mark is authorship, not decoration.
- Screen-aware material: graphite over light content, pearl over dark content,
  and a sampled neutral over mixed content (Studio illustration; the Swift
  toast folds mixed into the system fallback tone).
- Keep the material quiet enough that the destination, not the container, is
  what the eye reads. The persistent badge is the sibling that *keeps* chrome
  (glyph, mint count chip) so the two never read as the same object.

The generated art-direction board lives at
`/studies/capture-target-confirmation/art-direction.png`. It is a reference,
not a pixel contract; the interactive Studio study is the source of truth.

## Geometry

| Token | Value |
| --- | --- |
| Height | 40 pt total (36 pt body + 4 pt input pointer) |
| Width | 140 pt min → 260 pt max (hug route furniture + app name) |
| Corner radius | 7 pt |
| Internal padding | 10 pt horizontal |
| Talkie mark | 20 pt fused white T tile |
| Route | 18 pt amber → mint trace |
| Destination receiver | 7 × 17 pt three-sided bracket |
| Gap from input | 7 pt |
| Edge | 0.75 pt inside, plus restrained top light |

## Motion

_Slightly tighter for a thinner object (~1.32 s total)._

1. Enter over 150 ms: opacity 0 to 1, y 2 pt to 0, ease out.
2. During the first 460 ms, one signal travels from Talkie to the destination;
   the receiver bracket and input point resolve once, then remain still.
3. Dwell for the remainder of about 1.0 s without pulsing or drifting.
4. Exit over 170 ms: fade in place, ease in.

The motion must not imply that a screenshot has been sent. It only confirms
the target lock.

## Typography

- Title: SF Pro Text Semibold 13.5 / leading 17 / tracking −0.18.
  Copy: `{AppName}`.
  Copy: window title, or `Ready for screenshots` when none.
- Color: `primaryText` at 0.94 (title), `secondaryText` at 0.88 (subtitle).
- Truncate each to one line with ellipsis; never wrap (height is fixed).
- App name stays at semibold. Amber and mint are reserved for the route and
  receiver rather than used as text color.

## Material / edge (little chrome)

Reuse `LiveGlassTone` graphite/pearl only — no new shared tone API for this
pass. Quieter plate than the full `liveGlassSurface` hero:

1. ultraThinMaterial.
2. `tone.surface` at 0.55 graphite / 0.64 pearl (down from 0.62 / 0.72).
3. Single inset 0.5 pt stroke: `tone.edge` (graphite white/13 %, pearl
   black/14 %).
4. Contact shadow only: black 0.18, blur 8, y 3. Drop the large ambient glow
   and the top sheen gradient.
5. No outer black ring, no specular top stroke, no mint accent on the toast.

## Accessibility

- One coherent announcement: `Capture target locked, ChatGPT, Work with ChatGPT`.
  (The visible copy reads `Capturing to ChatGPT`; the *announcement* keeps the
  explicit "locked" language — the toast confirms a lock, not a send.)
- Do not rely on mint or a checkmark alone to convey success — the toast has
  neither; the label carries the meaning.
- Respect Reduce Motion by using opacity only (no y translation).
- Preserve legibility over both light and dark sampled backgrounds.

## Swift port

- `apps/macos/TalkieAgent/TalkieAgent/Views/Overlay/CaptureTargetLockOverlay.swift`
- `apps/macos/TalkieAgent/TalkieAgent/Views/Overlay/ScreenAwareOverlayAppearance.swift`

## Studio implementation (page.tsx)

Interactive route `/mac-capture-target-confirmation`, registered in
`lib/studio-pages.ts` under Surfaces · Mac · `capture` (status `concept`).
Self-contained page; no new shared component files.

> Superseded in visual detail by the **Quiet Caption** pass below; kept for
> the sibling-architecture rationale, which still holds.

Design decisions:

- **Two siblings, drawn separately.** `ConfirmationCard` (transient) and
  `PersistentBadge` (persistent) are distinct components — nothing animates
  between them. The badge is shorter (34pt) and carries a mint capture-count
  chip because captures accumulate against the target until sent or cleared.
  (As of Quiet Caption the transient is text-only and the badge is the one that
  keeps ornament.)
- **Tone tokens track `LiveGlassTone`.** `GRAPHITE` and `PEARL` are the Swift
  RGBs converted to CSS. `SAMPLED` is a new mid-neutral for the mixed case —
  what `ScreenAwareOverlayAppearance` settles on when the content beneath is
  neither light nor dark. Pairing: light content → graphite, dark → pearl,
  mixed → sampled.
- **Glass is CSS-reproduced from `liveGlassSurface`:** backdrop blur+saturate,
  `surface` at `surfaceOpacity`, a top sheen gradient, inner 0.5pt edge + inner
  top highlight + outer edge stacked as box-shadows, plus drop shadow.
- **Motion is a single keyframe cycle** (`enter 180 / dwell 1150 / exit 180`,
  y 4→0, opacity fade). Replay button re-keys the animation. A Reduce Motion
  toggle swaps to opacity-only, matching the accessibility note. Exit fades in
  place — never a translate that could read as "sent to the dock."
- **Geometry** comes straight from the table above (52h, 248→276w, r14, 28pt
  icon, 10pt gap). Placement section floats the card 10pt above a fake
  composer input.
- **Accessibility:** the card exposes one coherent `aria-label`
  (`Capture target locked, ChatGPT, Work with ChatGPT`); success is not carried
  by the mint checkmark alone.

No reticles, radar, crosshairs, giant locks, arrows, neon, or fly-to-dock
motion. Deps are not installed in `design/studio`; validated by review against
the existing `mac-capture-hud` study conventions (Bun validation owned by the
requesting agent).

### Review reconciliation (Grok pass)

- Subtitle bumped 10 → 11pt; geometry otherwise already matches Swift
  (248×52 target, 28pt icon, 12pt horizontal padding).
- One motion timeline only: 180ms in / 1.15s full dwell / 180ms fade out. The
  studied plateau is exactly 1150ms (11.9%→88.1% of the 1510ms cycle).
- Reduce Motion removes translation *and* the decorative checkmark draw.
- The transient toast is drawn with a single stable tone per context — it does
  not animate a tone flip during its ~1.5s life. Hysteresis / multi-sample
  settling belongs to the *persistent* badge's long life, not the toast.

### For the Swift porter (P0 carried from review)

- Size the `NSPanel` content to the real card + preserve the exact 10pt gap
  above the input (avoid the current 260×64 vs 252×52 slack).
- Sample tone from pixels under the *toast's own* frame, and pick once (hold
  it) for the toast's lifetime — do not run the 3-sample 0.35s flip inside a
  ~1.5s toast. Keep the settling behavior on the persistent badge.

### Second aesthetic pass — "Quiet Caption" (this pass)

Direction from Grok; Studio owned by Opus. Sharper/crisper/more beautiful via
reduction. Only `page.tsx` + this file changed; no Swift, no shared Studio
infra.

- **Transient is text-only.** Deleted the app-icon well and the decorative
  checkmark. `ConfirmationCard` is now a two-line `flex-col` caption
  (`Capturing to {app}` / window title), left-aligned, sized once to hug text
  (168–240 pt).
- **Stronger corners, less chrome.** New `quietPlate()` for the toast: single
  crisp inset hairline + one contact shadow (black 0.18 / blur 8 / y 3), r8,
  reduced surface opacity (0.55 graphite / 0.64 pearl / 0.58 sampled). No
  sheen, no outer ring, no specular highlight, no mint.
- **Full `glassStyle()` retained for the persistent badge only.** The badge
  keeps its glyph + mint count chip on purpose — the extra chrome is now the
  clearest signal that it is the *other*, longer-lived object. Section 04/05
  copy and eyebrows updated to name the caption-vs-badge contrast.
- **Motion tightened** to 160 / 1000 / 160 ms, rise y 2→0 (~1.32 s cycle).
  Reduce Motion stays opacity-only; the checkmark keyframe (`cttick`) was
  removed with the checkmark.
- **Accessibility unchanged in intent:** the announcement still says
  `Capture target locked, {app}, {title}` even though the visible title reads
  `Capturing to {app}` — the announcement carries the explicit lock semantics.

Validated with `bun run build` in `design/studio` (route compiles clean).

### For the Swift porter (Quiet Caption — next, not now)

- `CaptureTargetLockView`: drop the `appIcon` UI and the checkmark; make it a
  two-line VStack (title 13 semibold / subtitle 11 regular), leading-aligned.
- `CaptureTargetLockMetrics`: height 40, radius 8, pad 8/14, min/max width
  168/240; keep `gapFromInput` 10 and the single-sample tone pick.
- Prefer a quieter toast-only surface over the full `liveGlassSurface` hero:
  one hairline stroke + a small contact shadow; no sheen / outer ring / mint.
  Keep the NSAccessibility announcement exactly as-is.

### Final lock-plate reduction

- Visible copy is the app name only. The status label and window subtitle are
  removed; the full target description remains available to accessibility.
- Removed the top registration strip. Lock meaning comes from placement and
  motion rather than decorative chrome.
- The plate is 32 pt tall, 112–220 pt wide, with 4 pt corners and 12/7 pt
  horizontal/vertical padding. The screen-aware graphite, pearl, and sampled
  materials remain.
- Studio and native SwiftUI now use the same geometry and content hierarchy.

### Agent taste passes — Destination Seal vs Struck Plate

Two repo-scoped Scout agents were given the same constraints: app name only,
no subtitle, top strip, icon, or target/reticle styling.

- **Grok · Destination Seal:** 36 pt high, 5 pt corners, centered 14 pt type,
  and a dual full-perimeter definition. Presence comes entirely from proportion
  and optical type centering.
- **Opus · Struck Plate (selected):** 32 pt high, 4 pt corners, centered 13.5 pt
  type, a milled bright/dark double bezel, faint convex illumination, and one
  520 ms diagonal reflection when the lock engages. The dwell is motionless.
- The Studio study retains both candidates for comparison. The active examples
  and SwiftUI implementation use Struck Plate.
- Reduce Motion removes the glint and positional entrance; the accessibility
  announcement still includes the app and window target context.
