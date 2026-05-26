# Command Deck Donor

Snapshot of the pre-Next iOS Command Deck implementation, extracted from:

- Tag: `pre-ios-shell-rebuild`
- Commit: `a7929fdba61f127b75d0763636a015ef193e7638`
- Tag note: "Pre-iOS-shell rebuild snapshot"

The files under `source/` preserve their original repository paths so they can be compared against current app sources with normal diff tools.

## Primary Donor

`source/apps/ios/Talkie iOS/Views/CompanionShortcutModeView.swift`

Useful anchors:

- `isTrackpadInteracting` state: line 35
- Scroll lock while trackpad is active: line 152
- Trackpad mounted in the cockpit/status strip: lines 688-695
- Suggested command rail: lines 869-930
- Mac navigation rail for window/tab/app switching: lines 933-970
- Shortcut card split action / embedded convenience button: lines 830-847, 1760-1774, 1853-1897
- `TrackpadSurface` implementation: lines 2922-3005
- Command definitions for Enter/Delete/Copy/Paste/arrows/Space/window/tab/app/Spaces: lines 3289-3547

## Entry Points And Settings

- `source/apps/ios/Talkie iOS/Views/HomeView.swift`
  - Auto-open predicate: lines 134-140
  - Manual Command Deck toolbar button: lines 670-679
- `source/apps/ios/Talkie iOS/Views/SettingsView.swift`
  - `Auto-Open Command Deck` toggle: lines 184-206
- `source/apps/ios/Talkie iOS/Services/TalkieAppSettings.swift`
  - App setting backing the follow/auto-open behavior.

## Bridge And Server Path

- `source/apps/ios/Talkie iOS/Bridge/BridgeClient.swift`
  - iOS client methods for companion trigger and trackpad events.
- `source/apps/ios/Talkie iOS/Bridge/BridgeManager.swift`
  - Companion state and surface visibility integration.
- `source/apps/macos/Talkie/Services/TalkieServer.swift`
  - Native macOS handler for companion trigger and trackpad requests.
- `source/apps/macos/TalkieServer/src/bridge/routes/companion.ts`
  - Node bridge route that proxies companion actions into Talkie.
- `source/apps/macos/TalkieServer/src/bridge/routes/companion-events.ts`
  - Companion event stream state.

## Board Spec

The `source/docs/specs/companion-shortcut-board*` files are included because the donor view builds its pages from the published companion shortcut board shape.

## Related Next Replacement

The Next-era replacement starts at `ios-next-m9-shipped` / `54708c8a26373537c3eea5024f44c780e815a25d` and current sources center on:

- `apps/ios/Talkie iOS/Views/Next/DeckMirrorNext.swift`
- `apps/ios/Talkie iOS/Models/DeckBoardSnapshot.swift`

The parity audit marks the missing donor behavior at `design/studio/components/studies/ParityAudit.tsx`, especially the trackpad interaction entry.
