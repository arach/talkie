# iOS Home — visual design review (2026-07-01)

Reviewed screenshot: dark theme, home at rest (1 memo · 1 dictation · 0 items, RECENT · 40).
Requested critique to honor: stats row overflows; UI feels flat (no texture/structure/color);
direction = a little metallic, a little liquid-glass, more material depth, not noisy.

Review only — no implementation in this pass.

## Confirmed problems

1. **Stats row truncates.** Middle cell renders `1 DICTATION T…`. Root cause in
   `HomeNextView.swift` `HomeTodayStrip` (~line 442): three equal-width cells
   (`.frame(maxWidth: .infinity)`), each rendering `"\(count) \(noun) today"` in tracked
   uppercase `.channelLabelTiny` plus an icon. "1 DICTATION TODAY" is ~17 tracked caps in a
   ~120pt third — it cannot fit. `minimumScaleFactor(0.78)` both fails to save it and makes
   the three cells render at visibly different sizes (ransom-note effect). The word TODAY is
   repeated three times — pure redundancy eating the width that's missing.

2. **Flatness is structural, not tonal.** Every container on the screen is the same recipe:
   `.background(cardBackground)` + `.clipShape` + `.overlay(hairline stroke)` — see
   HomeTodayStrip (~473), HomeFrequentActionsStrip (~548), RecentSection (~826). Meanwhile
   `DesignSystem.swift` already ships the depth vocabulary and Home never adopted it:
   - `bezelChassis()` (line ~1178): 1px plusLighter inner top highlight + dual drop shadow
   - `screenRecess()` (line ~1216): recessed-glass vignette + dark stroke
   Only `DeckMirrorNext.swift` uses these today.

3. **Equal-weight slabs → flat AND busy.** Header, stats card, QUICK card, RECENT card,
   EXPLORE chips = five horizontal bands at identical elevation with three eyebrow labels.
   No tier reads as "the point of the screen."

## Direction: three material tiers

Raised metal vs recessed glass is the whole depth story. One opposition, no noise.

| Tier | Elements | Treatment |
|---|---|---|
| Chrome (raised metal) | Deck/gear circles, QUICK deck, mic FAB | `bezelChassis` + metal gradient fill + specular rim |
| Screen (recessed glass) | RECENT list | `screenRecess` — content behind glass |
| Ambient (no container) | Today ticker, EXPLORE rail | de-carded / glass chips |

Names for shared vocabulary: **Today ticker · Quick deck · Recent screen · Explore rail**.

## Recommendations

### 1. Today ticker — restructure, don't shrink
- Say TODAY once, in the eyebrow (`· TODAY`), never per-cell.
- Go numeral-forward per cell: count in a tabular/mono instrument readout (~17–20pt,
  `textPrimary`), unit label below in `channelLabelTiny` (`textTertiary`). "DICTATIONS"
  (10 chars) fits a third-width cell; "1 DICTATION TODAY" (17) never will.
- Drop `minimumScaleFactor` entirely; tabular numerals prevent jitter as counts change.
- Zero-count cells dim both numeral and label to tertiary — state without reading.
- Keep the per-cell taps → `openLibrary(tab:)`.
- Cheaper alternative if vertical budget matters: kill the card, render one centered line
  under the wordmark — `1 MEMO · 1 DICTATION · 0 ITEMS` — no container at all.

### 2. Containment swap (one-line changes)
- QUICK deck: replace raw background/stroke recipe with `.bezelChassis(...)`.
- RECENT screen: replace with `.screenRecess(...)`.
- Stats/EXPLORE: no chassis — ambient tier.
- Rows inside the Recent screen stay flat ink; depth belongs to containers only.

### 3. Metal fill token
- Flat `cardBackground` → subtle vertical gradient: ~white 3–4% at top → black 8–10% at
  bottom over the card color. Add as a `ChromeTokens` member (e.g. `metalFill`) so each
  theme tunes it — do not inline per-view. Keep deltas ≤10%: machined, not glossy.

### 4. Specular rim on circular chrome
- Deck complication, gear, mic FAB: replace flat `strokeBorder(edgeFaint)` with an
  `AngularGradient` stroke — white ~20% at 10–11 o'clock fading to clear by 4–5 o'clock.
  Reads as light on a machined rim. Preserve the status-colored border states on the Deck
  complication (error/connected tints) — the specular rim is the neutral state only.

### 5. Ambient canvas light — highest-leverage single change
- Gradients, hairlines, and materials all read as flat when the backdrop is uniform.
  Paint a faint radial gradient into the canvas (white 4–6% centered near the wordmark,
  falling off by mid-screen) where `colors.background` is applied — `AppShellNext.swift`.
  Every shadow and highlight then has something to be relative to.

### 6. Liquid glass — sparingly
- Deployment target is iOS 26 and `BottomTrayBackground.swift` already uses the glass
  APIs — reference implementation exists. Apply `glassEffect` to the EXPLORE chips and/or
  the bottom tray only. Not the big containers: glass on every card is noise, and glass
  needs the ambient gradient behind it to have anything to refract.

### 7. Color discipline
- Don't fix flatness with more accent — ChromeTokens marks accent as RARE (live/status
  only), and that discipline is right. Fix it with lighting (items 3–5).
- Do nudge temperature: pure-neutral dark grays read dead. Shift panel fills 1–2% toward
  the theme hue (warm for scope, cool indigo for midnight) inside ChromeTokens per theme.
- Existing chromatic anchors are enough: `· RECENT · 40` accent count, Deck status bead,
  record FAB.

### 8. Overload guard (subtraction pass)
- End state: header → ticker (no card) → Quick deck (raised) → Recent screen (recessed) →
  Explore rail (glass chips). Three material moments, one per tier.
- Max two depth cues per element (highlight + shadow, or gradient + stroke). Anything
  carrying four is noise — remove until two remain.

## Files to touch

- `apps/ios/Talkie iOS/Views/Next/HomeNextView.swift` — HomeTodayStrip (~442),
  HomeFrequentActionsStrip (~518), RecentSection container (~826), HomeHeader circles (~281)
- `apps/ios/Talkie iOS/Resources/DesignSystem.swift` — ChromeTokens (~420, add `metalFill`
  + temperature nudge), bezelChassis (~1073/1178), screenRecess (~1085/1216)
- `apps/ios/Talkie iOS/Views/Next/AppShellNext.swift` — canvas ambient gradient
- `apps/ios/Talkie iOS/Views/BottomTrayBackground.swift` — existing glass reference
- `apps/ios/Talkie iOS/Views/Next/HomeFeed.swift` — TodayStats if ticker copy changes
- `design/studio/app/home/page.tsx` + `SWIFT_PORT.md` — studio spec is canonical; mirror
  the direction there to keep parity
