# iOS Chrome Rebuild — Game Plan

**Date:** 2026-05-17
**Status:** Planning → ready for Phase 0
**Driver:** The `design/studio/` Next.js app has locked in a new
interaction model (universal voice-pivot + summon-on-demand chrome)
and a refreshed iOS theme system (Scope · Midnight · Tactical ·
Ghost · Lift, all articulated). The studio mocks set the quality bar.
The iOS app needs to catch up.

## TL;DR

**In-place chrome swap.** Keep the existing iOS target. Swap the
`HomeView()` root in `talkieApp.swift:75` for a new `AppShellNext`
that hosts the new screens. Existing services (audio, persistence,
AI providers, SSH, sync, iCloud, TTS) are donors — used by new
views, not rewritten. Existing screens stay in the codebase but
become unreachable from the new shell. No feature flag.

**Two milestones before committing to a full port:**

1. **Home** with summon UX feels as good as the studio mock
2. **Compose** with summon UX + voice-command-to-diff feels as
   good as the studio mock

If both signals are positive, port the remaining screens
(Library, Recording, Settings, Capture flows). If not, adjust
the chrome system before going further.

## Approach

| Layer | What we do |
|---|---|
| **Chrome (nav, design system, interaction)** | Rewrite from scratch inside `apps/ios/Talkie iOS/Views/Next/`. Matches the studio. |
| **Services (audio, persistence, AI, SSH, sync, iCloud, TTS)** | Keep as-is. New views call into them. 99% of the app's actual functionality. |
| **Existing SwiftUI views** | Stay in the codebase. Not routed to from the new shell. Eventually retired. |
| **Entry point** | One line in `talkieApp.swift:75`: `HomeView()` → `AppShellNext()`. |

## Phase 0 · Foundation

Goal: a minimal new shell wrapping a placeholder Home, with the
voice-pivot ambient button + summon chrome working end-to-end.
No real Home content yet — that's M1.

### Token sync

Update `apps/ios/Talkie iOS/Resources/DesignSystem.swift` +
`ThemeManager.swift` to reconcile with the studio's bundles:

- **Add Lift theme** — 5th iOS theme, pure-white surfaces, indigo
  accent (#6366F1), hierarchy from `--theme-card-shadow-strong`
  elevation. New `cachedLiftColors` + `liftChrome`. Add `.lift`
  case to the theme enum + a Settings → Appearance picker option.
- **Reconcile Tactical** — studio bumped amber to `#FF8800` (was
  `#FF6B00`). Pick one source of truth; the studio's brighter
  orange reads better on near-black per iOS-rendering tests.
- **Reconcile glow + corner + hairline tokens** — studio added
  `--theme-glow-radius`, `--theme-chrome-corner`,
  `--theme-hairline-w`, `--theme-eyebrow-leader` per theme.
  Mirror as `ChromeTokens.glowRadius`, `.chromeCorner`,
  `.hairlineWidth`, `.eyebrowLeader` (Swift already has these
  fields — verify values match the studio).

### New components

Live in `apps/ios/Talkie iOS/Views/Next/`:

- **`AppShellNext.swift`** — root container. Wraps any screen
  content; provides the voice-pivot button + summon overlay. New
  screens go inside.
- **`VoicePivotButton.swift`** — bottom-left ambient button with
  three states (resting / expanded / listening). Long-press
  enters listening (walkie-talkie). Uses `LongPressGesture`.
- **`ChromeOverlay.swift`** — corner slots (Done top-left,
  Settings top-right, Keyboard bottom-right, Share TBD bottom-
  right or omitted) + bottom liquid-glass tray (Camera · Record
  FAB · Compose). Fades in when shell is in `.expanded` state.
- **`ListeningBubble.swift`** — appears above the voice button
  during `.listening`. Live waveform + smallcap label + italic
  transcription snippet. Release-on-end semantic.
- **`HomeNextStub.swift`** — placeholder content the shell wraps
  for Phase 0. Just a title + "soon" placeholder until M1 fills
  it in.

### Entry-point swap

In `apps/ios/Talkie iOS/App/talkieApp.swift` line 75:

```swift
// Before:
HomeView()
    .environment(Clerk.shared)
    .environment(\.managedObjectContext, controller.container.viewContext)
    ...

// After:
AppShellNext(content: { HomeNextStub() })
    .environment(Clerk.shared)
    .environment(\.managedObjectContext, controller.container.viewContext)
    ...
```

The `.environment` chain stays — services hand off identically.

### Phase 0 done when

- [ ] App builds, launches, shows the new shell with placeholder
- [ ] Voice button visible bottom-left at rest
- [ ] Tap → corner pills + tray fade in (300ms ease); button gets
      brass ring
- [ ] Long-press the lit button → listening bubble appears with
      animated waveform; release dismisses
- [ ] All 5 themes (Scope · Midnight · Tactical · Ghost · Lift)
      selectable in Settings → Appearance and each theme renders
      the shell correctly (button + chrome adapt to theme tokens)

## Milestone 1 · Home

Goal: ship `HomeNextView` inside the shell with the PICK UP card +
smart Action Bus + tightened Recent list — matching
`design/studio/app/home/` and its `NOTES.md`.

Detail spec: **`design/studio/app/home/SWIFT_PORT.md`** (to be
written when M1 starts).

Key bridges to existing services:
- `Persistence` — query last-opened capture/document for PICK UP
- `CaptureStore` (or whatever it's called) — query last 24h
  counts for Action Bus; auto-roll period if 24h is empty
- `ListRow` model — recent captures with title, preview snippet,
  relative time

Signal: does Home + the voice-pivot summon feel as good as
`http://localhost:3000/home` in the studio?

## Milestone 2 · Compose

Goal: ship `ComposeNextView` — text-editing turns on an existing
document, with inline dictation + voice-command-to-diff.

Detail spec: **`design/studio/app/compose/SWIFT_PORT.md`** (to be
written when M2 starts).

Key bridges:
- `AudioRecorderManager` — for inline dictation
- AI provider services — for voice-command transformations
- Persistence — load/save document
- Diff renderer — new component (no existing equivalent)

Signal: does long-press → voice command → diff feel right at
thumb level?

## Decision point

After M1 + M2 land + ship internally:

| Signal | Decision |
|---|---|
| Both feel as good as studio mocks, no obvious chrome bugs | Port Library, Recording, Settings in sequence |
| Chrome feels off, summon UX awkward | Iterate on Phase 0 before porting more |
| Mixed | Identify the specific friction, fix it, re-test |

## Phase 3+ · Remaining ports (after decision)

In rough priority order:
1. **Library** — soft underline tabs, 2-line `ListRow`, integrated
   search. Spec: `design/studio/app/library/SWIFT_PORT.md`.
2. **Recording sheet** — pick a waveform variant (brass · hybrid
   ranked from the recording-sheet study), meter row, brass stop
   button. Spec: `design/studio/app/recording-sheet/SWIFT_PORT.md`.
3. **Settings → Appearance** — theme picker upgrade for Lift +
   live thumbnails per theme (mira's `09` critique).
4. **Capture flows** — Compose-with-AI sheet, Capture detail,
   Capture launcher.
5. **Onboarding** — if needed, rebuild against the new chrome.

Eventually: delete the existing views that are no longer routed
to. NOT done until after the decision point + full parity.

## Spec artifacts (committed)

| Path | What lives there |
|---|---|
| `docs/planning/2026-05-17-ios-rebuild.md` | This master plan |
| `design/studio/app/<study>/SWIFT_PORT.md` | One spec per screen-port. The contract Codex builds against + the visual reference Claude paints from. |

## Scratch coordination (not committed)

Claude and Codex coordinate operationally via a throwaway shared
workspace at `/tmp/talkie-coord/`:

- `notes.md` — shared rolling notes (substantive events only; no chatter)
- `briefs/` — per-task Codex briefs (operational, not lasting artifacts)
- `drafts/` — Swift code Claude pre-writes ahead of moving it into `Views/Next/`

These are throwaway by design. They don't enter git. If the local
scratch is lost, nothing in the actual project is at risk — the
spec artifacts above are the canonical record of what we're
building.

## Build process — contract-driven cascade

**The pattern**: Claude declares contracts + paint. Codex builds
infrastructure that fulfills the contracts. Codex hands back a
working harness; Claude paints into it.

| Claude owns | Codex owns |
|---|---|
| The **architecture contract** for each screen — entry-point signature, state shape, props in, mutators exposed, navigation hooks, gesture semantics | The **infrastructure that fulfills it** — state machines, ObservableObjects, environment plumbing, navigation glue, service bridges, gesture wiring, build verification, screenshot loop |
| The **paint** — every SwiftUI view body, layout, typography, color application, animation timing, transition feel | The empty shells + scaffolding to compile against, fix narrow plumbing bugs (typos, imports, theme-accessor mismatches), report visual anomalies (don't fix them) |

### What Phase 0 taught us

Claude wrote `ShellChrome` (state machine), the long-press gesture
wiring, the `@StateObject` orchestration — all infrastructure. That
should have been Codex's. Claude should have specified the contract
("the shell exposes chrome state I can read; mutators `tap` /
`longPressBegan` / `longPressEnded` / `dismiss`; long-press fires
at 0.35s; let me instantiate with `AppShellNext { content }`") and
let Codex build the state machine + gesture wiring against that
contract. Then Claude only paints `VoicePivotButton` /
`ChromeOverlay` / `ListeningBubble` (props in, no internal state).

### What this means in practice

**Old, wrong workflow** (Phase 0):
- Claude: writes full SwiftUI files including state machines, gesture handlers, ObservableObjects
- Codex: scaffolds empty stubs + fixes compile errors

**New, right workflow** (M1 onward):
- Claude: writes contract spec (`design/studio/app/<study>/SWIFT_PORT.md`) that declares: what the screen accepts, what state shape it reads, what mutators it can call, what service bridge Codex must implement
- Codex: builds the state objects + service bridges + scaffolding so the screen is instantiable with mocked data; returns a working harness
- Claude: paints the SwiftUI view bodies that consume the harness — pure visual + interaction-as-design, no internal state plumbing
- Codex: builds + screenshots + reports anomalies
- Claude: iterates paint based on screenshots

### Contract sharpness

A SWIFT_PORT spec must say:

1. **Entry point** — how does Claude call this screen?
   (`HomeNextView()` with no args, or `ComposeNextView(documentID:)`)
2. **Data shape** — what `ObservableObject` does the view consume?
   What `@Published` properties + methods does it expose?
3. **Mutator contract** — what methods does the view call on the
   store, and what should they do?
4. **Service bridge** — which existing services does the store
   bridge to? (`Persistence`, `AudioRecorderManager`, AI providers)
5. **Mock-mode** — what's the contract for instantiation without
   real data (so paint work isn't blocked on service wiring)?

If those 5 are precise, Codex returns infrastructure Claude can
paint into immediately.

### Hard rule going forward

Claude does NOT write infrastructure code in the iOS app. If a
SwiftUI view body needs an `@StateObject` / `@EnvironmentObject`,
the contract spec includes a stubbed protocol or a mock instance
Codex provides; Claude consumes it as a prop or environment value
and writes only the visual layer.

| Owned by **Claude** | Owned by **Codex** |
|---|---|
| Every file in `Views/Next/` | Xcode project membership for new files |
| Component visuals, layout, typography | File-creation scaffolding (empty stubs) |
| Gesture handlers + animations (interaction IS design) | Environment plumbing (`@Environment`, `@EnvironmentObject` wiring) |
| Token application + theme conditionals in views | Service bridges (CoreData fetch requests, AudioRecorderManager hooks, AI provider routing) |
| The `talkieApp.swift:75` entry-point swap | Build verification (`xcodebuild` + `xcrun simctl`) |
| Per-screen `SWIFT_PORT.md` specs | Simulator screenshot capture loop |
| Reviewing screenshots against studio mocks | Reporting build errors back with file + line |

Per-screen workflow:

1. **Claude** writes the `SWIFT_PORT.md` spec in
   `design/studio/app/<screen>/`. Covers: target files,
   components needed, exact behavior, services to bridge,
   visual reference (link to studio route + screenshot).
2. **Codex** creates the empty Swift files + adds them to the
   Xcode target + writes the service bridge layer (a thin
   wrapper exposing what `Views/Next/` needs from existing
   services).
3. **Claude** writes the actual SwiftUI view code into the
   stubs. Pixel-level work; studio is the spec.
4. **Codex** builds, boots the iPhone 17 Pro simulator, takes
   screenshots, drops them to
   `design/screenshots/<date>/<screen>/`. Reports build status.
5. **Claude** reviews screenshots side-by-side with the studio
   mock; iterates the view code; signals Codex to rebuild.
6. **Claude** opens the PR; merge.

Coordinated via Scout. Codex tasks via `scout ask --to codex …`.

## Donor inventory (services already in tree we'll reuse)

| Service | What it does | File |
|---|---|---|
| `AudioRecorderManager` | Inline + sheet recording | `Models/AudioRecorderManager.swift` |
| `Persistence` | CoreData (captures, documents) | `Models/Persistence.swift` |
| AI providers | Multi-provider routing + credentials | `Services/TalkieAIProvider*` |
| `TTSService` | Speech output | `Services/TTSService.swift` |
| `iCloudSyncProvider` | iCloud sync | `Services/Sync/iCloudSyncProvider.swift` |
| `BridgeManager` | Mac-iOS bridge | `Bridge/BridgeManager.swift` |
| `SSHTerminalDictationController` | SSH dictation | `SSH/SSHTerminal*` |
| `HeadlessDictationService` | Background dictation | `Services/HeadlessDictationService.swift` |
| `ThemeManager` | Theme state + persistence | `Resources/ThemeManager.swift` |
| `DesignSystem` | Tokens + chrome | `Resources/DesignSystem.swift` |

Everything in `Views/` is up for replacement. Everything in
`Models/`, `Services/`, `Bridge/`, `SSH/`, `Resources/` stays.

## Out of scope (for now)

- New iOS target / package (`Talkie Next`) — overhead doesn't pay
  for itself when the in-place swap is one line.
- Backend changes.
- macOS app.
- Watch app — `WatchDesign.swift` was a recent addition; left
  alone in this phase.
- Voice-command routing model — the long-press captures + sends
  to the model layer; routing to specific app actions is a
  separate downstream concern.
