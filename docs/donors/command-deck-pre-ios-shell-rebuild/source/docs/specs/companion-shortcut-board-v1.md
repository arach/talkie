# Device Shortcut Board V1

## Purpose

Define a file-backed, Mac-authored shortcut board for paired iPhone and iPad devices.
V1 intentionally stays narrow:

- exactly 3 swipeable spaces
- exactly 4 columns x 4 rows per space
- Mac-defined actions rendered by mobile devices
- live device tiles for active capture tasks like memo recording and dictation

This is the next shape after the current 12-slot `companionShortcutSlots` implementation.

## Canonical Storage

Do not add a new `Talkie/Companion/...` directory in App Support for this.
The board definition should live inside the existing macOS declarative settings file, under a broader device-settings concept:

- canonical file: `~/Library/Application Support/Talkie/settings/config.json`
- owning schema/store:
  - `apps/macos/Talkie/Services/TalkieSettingsConfiguration.swift`
  - `apps/macos/Talkie/Services/TalkieSettingsConfigurationStore.swift`

### Proposed settings path

```json
{
  "bridge": {
    "shortcutBoardEnabled": true
  },
  "devices": {
    "defaults": {
      "shortcutBoard": {
        "...": "default board definition"
      }
    },
    "classes": {
      "ipad": {
        "shortcutBoardOverride": {
          "...": "ipad patch"
        }
      },
      "iphone": {
        "shortcutBoardOverride": {
          "...": "iphone patch"
        }
      }
    },
    "overrides": {
      "<device-id>": {
        "displayName": "Arach iPad Pro",
        "platform": "ipad",
        "shortcutBoardOverride": {
          "...": "device-specific patch"
        }
      }
    }
  }
}
```

This keeps the board close to the rest of the direct-connect / device surface and avoids inventing another editable file root under `~/Library/Application Support/Talkie`.

The intent here is to keep companion configuration visibly grouped with the rest of Talkie's durable settings:

- settings stay under the existing `settings` folder surface
- device authoring stays in `settings/config.json`
- per-device behavior should still resolve from that same canonical object

## Migration Rule

V1 should coexist with the current `bridge.companionShortcutSlots` field during rollout.

Recommended migration approach:

1. `devices.defaults.shortcutBoard` becomes the new authored source of truth.
2. `companionShortcutSlots` stays as a compatibility mirror while the current iOS renderer still expects a slot list.
3. The compatibility mirror can be derived from the first 12 tiles of the `talkie` space until the full board payload ships over the bridge.

This keeps the current experience working while we expand from 12 keys to 3 spaces of 16.

## Board Model

The board object itself is described by:

- schema: [companion-shortcut-board.schema.json](/Users/example/dev/talkie-main-sync/docs/specs/companion-shortcut-board.schema.json)
- example: [companion-shortcut-board.example.json](/Users/example/dev/talkie-main-sync/docs/specs/companion-shortcut-board.example.json)

Those files describe the board object itself.
Device-level overrides live in the broader `devices` settings shape shown above.

### Top-level rules

- `version` is `1`
- `spaces` is fixed at exactly `3`
- each space uses a fixed `4x4` layout
- each space owns exactly `16` tiles
- the device app renders spaces horizontally and supports gesture-based paging between them

## Device-specific companion settings

The iPad and iPhone should be able to share one authored board while still diverging where that is useful.

### Resolution order

When publishing the board to a companion device:

1. start with the default board definition
2. apply `devices.classes.<platform>.shortcutBoardOverride` if present
3. apply `devices.overrides.<device-id>.shortcutBoardOverride` if present

That gives us a simple cascade:

- default board
- device class patch
- specific device patch

### Why this is the right v1 shape

This supports the common case cleanly:

- the iPad mostly uses the default board
- the iPhone swaps a few tiles or labels
- a single paired device can tweak one or two details without forking the entire board

### Override scope

V1 only needs lightweight patching:

- override a space title
- reorder tiles inside a space
- override a subset of tile definitions by `id`

This matches the goal of defining only the things that are different.

### V1 spaces

1. `talkie`
   - capture, summarize, search, queue, voice-command, and other Talkie-first actions
2. `workspace`
   - browser, editor, terminal, windows, project switching, and other Mac environment actions
3. `command`
   - favorite routes, favorite workflows, command palette, and launch-style actions

## Tile Taxonomy

V1 only needs two tile kinds.

### `action`

An immediate Mac-routed action.

Use this for:

- screenshot
- open search
- open latest memo
- open terminal
- show windows
- open settings
- run a favorite workflow

Expected behavior:

- tap runs immediately
- tile may show a pressed / triggering state
- no embedded timer or waveform

### `liveAction`

A tile that both triggers and reflects an active process.

Use this for:

- memo recording
- dictation
- screen recording

Expected behavior:

- tap while idle starts the action
- tap while active stops the action
- tile reflects current state from runtime data published by the Mac
- tile can display timer, waveform, and stop affordance without leaving the board

## Runtime State Model

Runtime state should stay separate from the board definition.
The definition says what the board is.
Runtime says what is currently happening.

### Proposed runtime payload

```json
{
  "activeSpaceId": "talkie",
  "tileStates": [
    {
      "tileId": "memo-record",
      "phase": "recording",
      "canStop": true,
      "detail": "Memo recording in action",
      "elapsedMs": 18342,
      "waveformLevels": [0.12, 0.38, 0.21, 0.67, 0.28, 0.11, 0.42, 0.31]
    },
    {
      "tileId": "dictation",
      "phase": "recording",
      "canStop": true,
      "detail": "Dictation in action",
      "elapsedMs": 12408,
      "waveformLevels": [0.22, 0.18, 0.41, 0.73, 0.33, 0.19, 0.27, 0.16]
    }
  ]
}
```

### Runtime field guidance

- `tileId`
  - matches the tile definition id in the board file
- `phase`
  - should align with the current server-side runtime states:
    - `preparing`
    - `recording`
    - `processing`
- `canStop`
  - whether tapping the active tile should stop/cancel the current action
- `detail`
  - short human-readable copy for the tile body
- `elapsedMs`
  - powers the visible timer for live tiles
- `waveformLevels`
  - small normalized sample set for a compact sparkline / waveform treatment on the tile

For V1, only `memo-record` and `dictation` should be treated as required live-action tiles.
`screen-record` can use the same shape but is optional if we need to keep the first ship tight.

## UX Rules

### Paging

- spaces are horizontal pages
- a two- or three-finger swipe switches spaces
- the board itself remains visible; no heavy settings chrome should appear on the companion surface

### Live tile behavior

Memo and dictation tiles should feel complementary to the main app, not like separate mini-apps.

When active, the tile should show:

- active visual state
- elapsed timer
- subtle waveform or signal animation when available
- tap-to-stop affordance

This is the main UI distinction that makes the board feel useful every day rather than decorative.

### Editing model

The Mac owns the board definition.
The iPad and iPhone render it.

The settings UI should remain a view/editor for the same file-backed object, not a competing source of truth.
Agents should also be able to update the same object directly through the file-backed configuration layer.

## Starter V1 Board

The example file ships a recommended default board with:

- `Talkie`
  - memo, dictate, screenshot, screen record, Ask Screen, OCR Screen, latest memo, quick summary, extract tasks, workflow, search, memos, queue, failed, voice command, Talkie
- `Workspace`
  - browser, editor, terminal, chat, windows, GitHub, Linear, Notes, Calendar, Slack, SSH, reconnect, logs, dev server, tests, project
- `Command`
  - daily review, weekly review, meeting start, meeting end, follow-up, save to Notes, Reminders, Event, Raycast, Raycast AI, Claude, sessions, recent project, settings, favorites, command palette

This is intentionally opinionated:

- `talkie` is the core daily page
- `workspace` gives the companion board range beyond Talkie
- `command` is the home for favorites and launch-style routes without yet introducing spoken shorthand inside the tile

## Non-goals for V1

Do not include these in the first ship:

- global spoken shorthand grammar
- per-tile spoken phrase dictionaries
- typed or spoken parameter entry inside tiles
- dynamic per-app space switching
- nested folders inside spaces

Per-device overrides are allowed, but only as lightweight patches on top of one board definition. Fully separate board files per device are not part of V1.

Those fit the future design language, but not the first implementation.

## Implementation Notes

Current implementation seams that this board is meant to replace or extend:

- current mobile renderer:
  - [CompanionShortcutModeView.swift](/Users/example/dev/talkie-main-sync/apps/ios/Talkie%20apps/ios/Views/CompanionShortcutModeView.swift)
- current bridge payload:
  - [BridgeClient.swift](/Users/example/dev/talkie-main-sync/apps/ios/Talkie%20apps/ios/Bridge/BridgeClient.swift)
  - [companion.ts](/Users/example/dev/talkie-main-sync/apps/macos/TalkieServer/src/bridge/routes/companion.ts)
- current macOS authoring surface:
  - [DictationSettings.swift](/Users/example/dev/talkie-main-sync/apps/macos/Talkie/Views/Settings/DictationSettings.swift)
- current settings schema:
  - [TalkieSettingsConfiguration.swift](/Users/example/dev/talkie-main-sync/apps/macos/Talkie/Services/TalkieSettingsConfiguration.swift)

Recommended implementation order:

1. add a `devices` section plus `devices.defaults.shortcutBoard` to the declarative settings schema/store
2. load and validate the board file-backed object from `settings/config.json`
3. support override resolution for `ipad`, `iphone`, and specific paired device ids
4. keep deriving `companionShortcutSlots` as a compatibility mirror
5. extend the bridge payload from `shortcutSlots` to full `spaces`
6. update the iOS renderer to page across spaces and render `liveAction` tiles from runtime state
