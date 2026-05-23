# TLK-019 — iOS Shared Components

**Status**: Draft
**Owner**: TBD
**Branch context**: `feat/ios-shell-phase-0`

## Summary

A small primitive library for `apps/ios/Talkie iOS/Views/Next/` to replace ad-hoc surface scaffolding with shared components. Two payoffs:

1. **Fix a user-visible bug** — 14 modal/drill-down surfaces handcode their headers without yielding to `ShellChrome.occupiedZones`, so the chrome's Settings/Home pills overlap the surface's title or xmark. Fix: model header corner occupancy in a `ChromeAwareHeaderBar` that scopes yields per-slot (leading / trailing), so chrome can pre-empt corner content without hiding the center title.
2. **Stop the hygiene drift** — corner radii (6/8/10/12), capsule pill opacity (0.14 → 0.55, fill vs stroke), padding (12/14/16) all vary across 60+ instances. A token layer + a small set of primitives + a hairline-divider helper consume those tokens. Components without tokens just relocate the drift.

This spec is paint + token contract — not infrastructure. Codex builds whatever needs `@StateObject`, gesture wiring, or PreferenceKey plumbing. The `ChromeAwareHeaderBar` API is designed so its internal yield mechanism can be swapped from the existing `.yieldsToChromeZone()` modifier to a PreferenceKey-driven negotiation later without changing call sites.

Non-goal: rewriting the surfaces themselves. Each migration is HStack-for-component, no behavior change.

## What exists today

Three sources of prior art. None alone is sufficient; together they're the foundation.

**macOS — full precedent.** `apps/macos/Talkie/Components/TalkiePage.swift`:
- `TalkiePage<Header, Content>` scaffold with `PageStyle` (`.page` / `.fixed` / `.full` / `.pageOnly`)
- `PageHeaderBar` generic HStack
- `PageHeader` convenience for titled headers
- `ContentSection` + `SectionTitle` + `SectionStyle` (`.compact` / `.standard` / `.prominent`)
- `PageLayout` constants — header height, padding, spacing
- `SplitColumnWidth` for split layouts

**OG iOS — philosophy + seed primitives.** Walked 17 legacy files in `apps/ios/Talkie iOS/Views/`:
- `TalkieNavigationHeader` (wordmark + subtitle, "calm anchor" — no accent, no glow)
- `BottomTrayBackground` (glass tray surface)
- `TalkieStatusDot(diameter:, pulses:)` — exists in `SplashView.swift`
- `TalkieEyebrow(text:)` — exists in `SplashView.swift`
- `ConfiguratorDesign` enum in `SlotButtonPreview.swift` — proto-token system (colors, spacing, corner radius, button heights). **This is the layer-zero we generalize.**
- Phase-driven `@ViewBuilder` switches in `KeyboardActivationView`, `MinimalDictationOverlay`, `RecordingView` — standard pattern for state-machine UI worth codifying.

**Next surfaces — what we're collapsing.** Inventory across 42 files in `Views/Next/`:

| Pattern | Files | Notes |
|---|---|---|
| Page header (`TALKIE · X` wordmark + xmark/back) | 14 | Mix of modal and drill-down. None yield to chrome. **The collision bug.** |
| Sheet/drill-down ZStack scaffold | 44 | Same `background.ignoresSafeArea() → VStack { header / Divider / content }` template. |
| ALL-CAPS section label | 35+ | Tokenized via `.channelLabelTiny`; spacing varies. |
| List row (label + chevron / toggle / value) | 9 | Wide variation in padding + divider. |
| Centered `ProgressView` | 28 | Near-identical. |
| Rounded-rect card | 17+ | **Radius drift: 6/8/10/12.** |
| Capsule pill button | 60+ | **Worst drift surface. Opacity 0.14→0.55. Fill vs stroke vs ghost inconsistent.** |
| Capsule status chip (non-button) | ~12 | Mixed in with the 60+ above — should be a separate primitive (no tap target). |
| Empty state (icon + headline + caption) | 5+ | Each one custom-built. |
| Hairline divider under header | 9 | Same edgeFaint call. |
| Hairline divider between rows | 20+ | Same. |
| Icon tile (rounded square with accent fill) | ~10 | Workflows uses 30×30 with accent opacity — not catalogued in v1 of this spec; deferred. |

## Design principles

Three principles, lifted from the legacy iOS code and stated explicitly so they survive future contributors.

**1. Calm anchor by default.** Restraint over flare. Reference: `MinimalDictationOverlay.swift` — black.opacity(0.85) background, monospaced timer, minimal badge indicators, zero accent flare. Contrast with `SplashView`'s `talkieAccentGlow()`. Every primitive defaults to subtle; accent is reserved for critical moments (active recording, error states, FAB).

**2. Tokens precede components.** Hardcoded magic numbers (76, 64, 6/8/10/12 pt radii) are the dominant pitfall in the legacy code. Token layer is layer-zero. Rule: **no reusable design decisions as literals.** Per-primitive geometry implementation details (e.g. internal stack spacing chosen for one specific glyph alignment) are allowed; values that would drift if scattered are not.

**3. Phase-driven `@ViewBuilder` for state UI.** When a primitive needs to express different content per state (`LoadingView` showing spinner vs label vs error, `EmptyState` with/without action), use an enum-keyed `@ViewBuilder` switch — established pattern in `KeyboardActivationView`, `MinimalDictationOverlay`, `RecordingView`. No protocol-based polymorphism.

## Token foundation

Layer-zero. Single source of truth; primitives consume; reusable design decisions never inlined.

Two categories. Static layout invariants are geometry that defines hit targets, scaffold heights, and structural spacing — never expected to vary by theme. Appearance metrics are values a theme could plausibly want to override later (radii curves, fill opacities, motion durations); for v1 we keep them flat and add a `// theme-overridable` comment on the group so the swap is mechanical when a theme actually needs it.

```swift
enum TalkieToken {
    // MARK: - Static layout invariants

    enum Sizing {
        static let pageHeaderHeight: CGFloat = 56
        static let rowMinHeight: CGFloat = 44
        static let pillMinHeight: CGFloat = 32
        static let closeButtonSlot: CGFloat = 48
        static let closeButtonHit: CGFloat = 28
        static let iconCell: CGFloat = 30          // for icon tiles
    }

    enum Padding {
        static let pageHorizontal: CGFloat = 20
        static let cardStandard: CGFloat = 16
        static let cardTight: CGFloat = 10
        static let rowHorizontal: CGFloat = 16
        static let rowVertical: CGFloat = 12
        static let sectionLabelTop: CGFloat = 12
        static let sectionLabelBottom: CGFloat = 8
    }

    enum Stroke {
        static let hairlineWidth: CGFloat = 1.0    // moved from Opacity.hairline (was miscategorized)
    }

    // MARK: - Appearance metrics (theme-overridable later)

    enum Radii {                                    // theme-overridable
        static let card: CGFloat = 10
        static let pill: CGFloat = 999             // capsule via cornerRadius
        static let inputField: CGFloat = 8
        static let iconTile: CGFloat = 6
    }

    enum Opacity {                                  // theme-overridable
        static let pillFill: CGFloat = 0.20
        static let pillStroke: CGFloat = 0.55
        static let surfaceVeil: CGFloat = 0.85
    }

    enum Motion {                                   // theme-overridable
        static let chromeYield = Animation.easeOut(duration: 0.20)
        static let pillPress = Animation.easeOut(duration: 0.12)
    }
}
```

**Open: color tokens.** Color drift (accent opacity in pills, raw `Color.red` in destructive actions) stays in `ThemeManager.colors` for v1. `TalkieToken` is numeric only.

## Primitive set

Two tiers based on confidence. Tier 1 ships in the migration. Tier 2 lands during sweep work. Modifiers (formerly Tier 3) are sprinkled throughout — they don't deserve their own tier.

### Tier 1 — ships in the migration

#### `TalkiePage`

Scaffold. Owns background, safe-area, header slot, content wrapper. Does **not** own the `ScrollView` — surfaces pass scroll, primitive provides padding + background. (Compose has nested-scroll cases that would conflict with primitive-owned scroll.)

```swift
TalkiePage("settings", style: .scroll) {
    ModalHeader("Settings", onClose: { router.openHome() })
} content: {
    // …
}
```

- `style: PageStyle` — `.scroll`, `.fixed`, `.full`
- Header slot is generic — non-standard headers (Settings rail toggle) still fit
- `name:` arg sets `instrumentationSection` env, mirrors macOS

Replaces: 44 sheet scaffolds.

#### `HeaderBar` + three public wrappers

The chrome-aware header is the heart of the bug fix. Yields are scoped per-slot (leading / trailing) — never to the center title. Same API across today (uses `.yieldsToChromeZone()` internally) and tomorrow (emits PreferenceKey for chrome to read).

```swift
// Low-level — explicit slots, escape hatch
HeaderBar(
    leading:  { BackChevron("Memos", onTap: ...) },
    title:    { WordmarkTitle("DETAIL") },
    trailing: { Image(systemName: "ellipsis") }
)

// Public wrappers — cover the 14 collision-bug surfaces
ModalHeader("Settings", onClose: { … })                          // wordmark center + xmark trailing
DrillDownHeader(back: "Memos", title: "Detail",
                trailing: { Image(systemName: "ellipsis") })     // back chevron + plain title + optional trailing
WordmarkHeader(subtitle: "Memos")                                // OG calm-anchor, no actions
```

- **No magic wordmark prepend.** `ModalHeader` composes `WordmarkTitle("Settings")` internally; `DrillDownHeader` composes a plain `Text` title. The caller sees what's rendered.
- `WordmarkTitle(prefix:suffix:)` — explicit composition: `WordmarkTitle("Settings")` → `TALKIE · SETTINGS`. Custom prefix when needed: `WordmarkTitle(prefix: "TLK", suffix: "Logs")`.
- Close/back: 28pt hit target inside 48pt slot, faint circle background (`SettingsNext` pattern).

Replaces: 14 wordmark+xmark headers. Fixes the collision bug.

#### `TalkiePill` + `.pillSurface()`

Two flavors, one shape system. Action pills get a struct (enforces icon-and-label layout). Passive status chips get a modifier (so callers don't misuse Button for labels).

```swift
// Action button
TalkiePill("Open", icon: "arrow.up.right", style: .filled)
TalkiePill("Cancel", style: .stroked)
TalkiePill("Skip", style: .ghost)

// Passive status chip
Label("Synced", systemImage: "checkmark.circle")
    .pillSurface(style: .stroked)
```

Both consume the same `PillStyle` enum (`.filled` / `.stroked` / `.ghost`) and the same Radii/Opacity tokens. One opacity, one corner curve, one font weight per style.

Replaces: 60+ capsule instances. Splits the ~12 passive chips into their own non-button path.

#### `PageSection`

Caps label + spacing wrapper owns vertical rhythm so 35+ surfaces stop guessing. Without this, migrated screens still carry ad-hoc spacing — incomplete grammar.

```swift
PageSection("Voice") { rows }
PageSection("Connect", subtitle: "Bridge status") { rows }
```

- Label uses `.channelLabelTiny`
- Vertical rhythm: `Padding.sectionLabelTop` above, `Padding.sectionLabelBottom` below

Replaces: 35+ ad-hoc caps labels.

#### `HairlineDivider`

```swift
HairlineDivider()                    // full width
HairlineDivider(inset: .row)         // matches row left inset
HairlineDivider(inset: .header)      // matches page-header left inset
```

- Uses `theme.currentTheme.chrome.edgeFaint` and `TalkieToken.Stroke.hairlineWidth`
- Inset enum names known divider treatments — extends without scattering offset literals

Replaces: 9 header dividers + 20+ row dividers.

### Tier 2 — lands during sweep work

#### `EmptyState`

```swift
EmptyState(icon: "mic.slash", title: "No memos yet",
           caption: "Tap the mic to start your first.",
           action: .init(label: "Record", onTap: { … }))
```

#### `LoadingView`

```swift
LoadingView()
LoadingView(label: "Connecting to Mac…")
```

Centered `ProgressView` + optional caption. Reduce-motion handling stays standard via `ProgressView` honoring system preferences.

### Modifiers — no tier, used throughout

These are decoration, not structure. They apply to any content view.

```swift
content.talkieCardSurface(.standard)                  // padding + bg + radius
content.talkieCardSurface(.tight, bordered: true)     // tight padding + hairline border

content.rowStyle(.chevron(onTap: { … }))              // 44pt min height, hairline bottom
content.rowStyle(.toggle)
content.rowStyle(.value)
content.rowStyle(.destructive(onTap: { … }))

content.pillSurface(style: .stroked)                  // passive chip — covered above
```

`.talkieCardSurface` owns padding/background/border, not just cosmetics. `style` would undersell the structural ownership.

Replaces: 17+ cards + 9 explicit rows + many ad-hoc tap targets.

## Architectural decisions

### Chrome yield: per-slot, future-compatible

**Current state** (`ScreenZones.swift:55-74`): `.yieldsToChromeZone(zone)` modifier reads `ShellChrome.occupiedZones` and fades content to 0 when chrome occupies the same corner. Every view that has top-corner content must call it manually. Of the 14 surfaces that should yield, 0 actually do — hence the collision bug.

**Decision**: scope yields to the corner-occupant *slots* of `HeaderBar`, not to the whole `TalkiePage` header. A generic header that fades whenever any corner is occupied hides title/rail content unnecessarily.

```swift
struct HeaderBar<Leading, Title, Trailing>: View {
    // Internally:
    //   leading.yieldsToChromeZone(.topLeading)
    //   title  (no yield — never collides with corner pills)
    //   trailing.yieldsToChromeZone(.topTrailing)
}
```

**Future swap**: when chrome moves to PreferenceKey-driven negotiation, the same `HeaderBar` API stays. Internals switch from `.yieldsToChromeZone(...)` to declaring slot occupancy via PreferenceKey. Call sites don't change. No second migration.

### File location

**`Talkie iOS/UI/Shared/`** — app-target, not `TalkieMobileKit`. Primitives need `ThemeManager`, `AppShellRouter`, `ShellChrome` — all app-internal. `TalkieMobileKit` stays keyboard-runtime-focused.

Cross-platform sharing with macOS deferred. macOS precedent is vocabulary, not proof of shared implementation. Promote only tokens that survive both platforms.

### Migration order (revised v0.2)

Codex pushed this — architectural bug before drift hygiene. The collision-bug fix is independently shippable.

1. **Build `HeaderBar` + three wrappers + minimum tokens.** Per-slot yields work via existing `.yieldsToChromeZone()`.
2. **Sweep 14 collision-bug headers.** Replace handcoded HStacks with `ModalHeader` / `DrillDownHeader` / `WordmarkHeader`. **Ships the bug fix.** Each surface drops ~25 lines.
3. **Build `TalkieToken` (full) + `TalkiePage` scaffold.** Migrate one simple surface end-to-end (likely `FeedbackNext`) to validate API.
4. **Sweep remaining sheet scaffolds with `TalkiePage`.**
5. **`TalkiePill` + `.pillSurface` + sweep capsule sites.** Mechanical. Biggest drift kill.
6. **`PageSection` + `HairlineDivider` + sweep.** Cheap, low-risk; gives migrated pages complete grammar.
7. **`.talkieCardSurface` + `.rowStyle` + final sweep.** Touches the most code; do last.
8. **`EmptyState` + `LoadingView`.** Smallest count; stops new drift.

After each sweep: snapshot screenshots before/after. Use existing per-surface launch args (e.g. `--inspectorTab=`) where they exist.

## Open questions

Numbered for reviewer reference.

1. **Color tokens scope.** `TalkieToken` is numeric-only in v0.2; color drift stays in `ThemeManager.colors`. Reasonable for v1; revisit if pill-fill-opacity-per-theme becomes a need.
2. **Drill-down chevron.** System `chevron.backward` or custom? Existing iOS surfaces inconsistent. Pick one in first build.
3. **OG primitive seeds** — `TalkieStatusDot` and `TalkieEyebrow` live in `SplashView.swift`. Migrate into `UI/Shared/` or leave where they are? Lean: leave until a second consumer emerges, then migrate.
4. **Icon tile pattern** (cataloged in v0.2 but not specced) — Workflows uses 30×30 rounded squares with accent opacity, ~10 instances. Tier 3 or skip for v1? Lean: skip; revisit if more uses appear.

## Non-goals

- Building `TalkieMobileKit/UI/` into a full design system. The kit stays focused on keyboard runtime types.
- Cross-platform sharing with macOS in v1. macOS has its own `TalkiePage`; iOS gets its sibling. Convergence is a v2 conversation after both shapes stabilize.
- Touching legacy `Views/*.swift` (non-Next). The legacy surfaces will be deleted as the rebuild lands.
- Designing for Watch.
- New behavior in any surface. Migrations are paint-only; behavior is preserved.

## References

- macOS precedent: `apps/macos/Talkie/Components/TalkiePage.swift`
- OG iOS philosophy: `apps/ios/Talkie iOS/Views/TalkieNavigationHeader.swift`, `MinimalDictationOverlay.swift`
- Existing primitive seeds: `apps/ios/Talkie iOS/Views/SplashView.swift` (`TalkieStatusDot`, `TalkieEyebrow`), `apps/ios/Talkie iOS/Views/Configurator/SlotButtonPreview.swift` (`ConfiguratorDesign`)
- Chrome mechanism: `apps/ios/Talkie iOS/Views/Next/ChromeOverlay.swift`, `ScreenZones.swift`
- Inventory snapshot: 42 files in `apps/ios/Talkie iOS/Views/Next/`, audited 2026-05-23.
