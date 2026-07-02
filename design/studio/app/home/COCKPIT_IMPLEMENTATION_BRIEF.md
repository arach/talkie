# Home Communication Cockpit Swift Implementation Brief

## Goal

Implement the selected **Communication Cockpit** direction in the iOS Home surface. The user wants this to become a real SwiftUI component, not just a Studio study.

The desired feel is a compact retrofuturist communication center: one useful instrument that summarizes live communication state. It should borrow the ambiance of a small hardware radio / cockpit display without becoming a literal car dashboard, radar, satellite, or constellation.

## Source Of Truth

- Studio implementation: `design/studio/components/studies/Home.tsx`
- Cockpit content models: `design/studio/components/studies/Home.tsx`, variants:
  - `communication-cockpit`
  - `cockpit-notifications`
  - `cockpit-wide`
- Notes: `design/studio/app/home/NOTES.md`
- Swift target: `apps/ios/Talkie iOS/Views/Next/HomeNextView.swift`
- Existing chrome helpers: `apps/ios/Talkie iOS/Resources/DesignSystem.swift`

## Product Direction

Use the cockpit to replace the little Today stats strip at the top of Home. The user has said the Today stats are not useful enough. Home should prioritize utility and a communication-center feeling:

1. Header
2. Communication Cockpit
3. Quick action strip
4. Command/search bar
5. Recents
6. Explore

Keep Quick actions and Recents recognizable. Do not duplicate Library in Explore because Recents already carries the `ALL` route.

## Visual Direction

Default to the `communication-cockpit` / dots module:

- outer raised chassis using existing `bezelChassis(..., metal: true)` with a matte tactical backing
- inner always-dark instrument screen with tactical orange accents
- top screen header: `TALKIE`, `LIVE`, time-like readout
- three comms lanes:
  - Bridge / Art's Mac mini / Ready / high level
  - Shares / 2 drafts / Queued / medium level
  - Replies / 1 prompt / Waiting / lower level
- compact Life-in-Dots style module on the right with BRDG / SEND / WAIT rows
- a single truncated detail line under the screen
- visible command/search bar below Quick actions:
  - text filters Recents as the user types
  - submitting a non-empty phrase opens Ask AI seeded with that phrase
  - the mic affordance should stay conservative until iOS voice commands have a dedicated architecture pass

Avoid:

- radar, constellation, satellite, proximity widgets
- loud accent overload
- multiple new boxes competing with each other
- generic dashboard cards

## Behavior

Make the cockpit tappable. For the first implementation, route tap to the most useful existing destination:

- If paired/connected to a Mac, open Deck or Bridge detail, whichever fits current Home patterns best.
- If not paired, open Bridge detail.

Accessibility should describe the current state and destination.

Lane-level tap targets are intentionally follow-up work. The first shipped version keeps one whole-cockpit tap destination.

## Data

It is fine for the first version to use derived/local placeholder-ish state while wiring live values where cheap:

- Use `BridgeManager.shared` for paired/connected state and Mac display name where available.
- Shares/replies may be static labels for now if there is no obvious source in `HomeFeed`.
- Keep strings short and truncating.

Follow-up product direction: the cockpit should not become a small admin queue. The next content pass should explore more meaningful stations around personal communication state, for example streaks, recent actions, and Mac presence, rather than generic command verbs like fix/view/review/open.

## Implementation Constraints

- Keep the change scoped.
- Prefer adding private subviews in `HomeNextView.swift` over creating a new design system unless the file becomes unwieldy.
- Use existing Talkie tokens and modifiers:
  - `.talkieType(...)`
  - `theme.chrome.panel*`
  - `.bezelChassis(...)`
  - current hairline/corner conventions
- No third-party dependencies.
- No `print`, `os.log`, or `NSLog`.
- Do not rewrite unrelated dirty worktree changes.
- Do not add "Generated with Claude Code" or co-authoring footers.

## Checks

Please run a narrow build check if practical:

```bash
mkdir -p "$HOME/Library/Caches/codex-builds"
DERIVED_DATA_DIR="$(mktemp -d "$HOME/Library/Caches/codex-builds/deriveddata.XXXXXXXX")"
xcodebuild -project "apps/ios/Talkie-iOS.xcodeproj" -scheme Talkie -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath "$DERIVED_DATA_DIR" build
rm -rf "$DERIVED_DATA_DIR"
```

If the full build is slow or fails for unrelated existing reasons, report the exact blocker and at least do a Swift syntax-oriented review of the changed file.

## Report Back

Return:

- files changed
- what the new Home structure is
- any assumptions/data placeholders
- checks run and result
- any follow-up recommendations
