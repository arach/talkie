# TLK-028 - Agent Home and Shared Runtime Settings

**Status**: Engineering proposal
**Owner**: Talkie macOS + TalkieAgent
**Date**: 2026-06-09
**Studio**: /eng/tlk-028
**Surface**: /agent-home
**Related**: [TLK-021](tlk-021-agent-home-architecture.md) (Agent Home), [TLK-027](tlk-027-agent-owned-overlays-and-assistant-workflow.md) (Agent-owned live surfaces), [agent-manageable-configuration](agent-manageable-configuration.md)

## Summary

Build a first-class **Agent Home** in TalkieAgent using the macOS Hudson/OpenScout
shell as the product and interaction donor: navigation rail, status bar,
inspector, keyboard-first operation, diagnostics cards, and live runtime layout.

Do **not** move all Talkie settings into Agent. Instead, define a narrow shared
runtime-settings contract that both Talkie and Agent can edit, while Talkie keeps
its broader product/library/settings universe.

Target boundary:

```text
Talkie owns product settings, library, workflows, durable media, and sync.
TalkieAgent owns live desktop runtime, capture, tray, overlays, hotkeys, and status.
TalkieKit owns the explicit shared settings contract between them.
```

This follows TLK-027: if Agent owns live tray/capture assets, Agent also needs a
real operational home for those capabilities.

## Motivation

Agent is becoming more than a helper process:

- It owns dictation runtime, hotkeys, overlays, audio capture, paste, live tray,
  screen/capture permissions, TalkieServer supervision, and runtime health.
- The current Agent settings surface exists, but it is not yet a durable app
  shell with navigation/status/inspector affordances.
- Talkie still exposes many settings that are product-only and should not become
  Agent concerns.

The correct next move is not a settings dump. It is an **Agent cockpit**: a place
for live runtime state, operational controls, shared Agent-owned settings, logs,
permissions, and future assistant/workflow affordances.

## Donor Surface

Use `/Users/art/dev/openscout` as the macOS/Hudson donor for shell and operating
surface patterns, while excluding voice-specific code.

Recommended donor pieces:

| Concern | Donor path | Notes |
| --- | --- | --- |
| Hudson app shell | `/Users/art/dev/openscout/apps/macos/Sources/Scout/ScoutRootView.swift` | `HudChromeShell`, resizable sidebar, trailing panel, status bar |
| App/chrome setup | `/Users/art/dev/openscout/apps/macos/Sources/Scout/ScoutApp.swift` | regular window, Hudson chrome window, commands |
| Navigation rail | `/Users/art/dev/openscout/apps/macos/Sources/Scout/ScoutRootView.swift` | compact/expanded sidebar, footer settings affordance |
| Commands + hotkeys | `/Users/art/dev/openscout/apps/macos/Sources/Scout/ScoutCommands.swift` | command menu, notification command bus, local key monitor |
| Cheatsheet | `/Users/art/dev/openscout/apps/macos/Sources/Scout/ScoutKeyboardCheatsheet.swift` | `⌘/`, `j/k/h/l`, section-aware help |
| Agent roster | `/Users/art/dev/openscout/apps/macos/Sources/OpenScoutMenu/HUD/HUDAgentsView.swift` | compact rows and larger 3-pane roster/context/detail layout |
| Diagnostics settings | `/Users/art/dev/openscout/apps/macos/Sources/OpenScoutMenu/Views/SettingsWindow.swift` | service cards, status lights, log reveal actions |
| Menu status deck | `/Users/art/dev/openscout/apps/macos/Sources/OpenScoutMenu/Views/MainView.swift` | compact service/status tiles |

Explicitly out of scope:

- `HudsonVoice`
- `ScoutVoiceService`
- Vox-style voice service import paths
- mic/dictation composer controls from OpenScout

Talkie already owns voice/dictation runtime details through Agent. Hudson is the
shell/layout donor, not a capture pipeline donor.

## Settings Boundary

Shared settings must be an **allowlist**, not a mirror of all Talkie settings.

### Talkie-only settings

Remain in Talkie. Agent should not know or care about them.

Examples:

- library UI preferences
- home/dashboard layout
- durable media editing preferences
- workflows and workflow editor behavior
- CloudKit/iOS sync settings
- local transcript/audio export
- account/paywall/update surfaces
- broad model library administration
- Talkie-only theme and typography choices
- app-scoped dictionaries that do not affect live runtime

### Agent runtime settings

Owned and applied by TalkieAgent. Talkie may expose some of them as settings, but
Agent is the process that enforces them.

Examples:

- hotkey registrations
- microphone selection
- transcription model used by live dictation
- routing/paste behavior
- push-to-talk mode
- overlay/pill/notch presentation
- live tray behavior
- capture presets for screenshots and screen recordings
- permissions needed by Agent
- dictation retention / live storage cleanup
- sounds for live events
- TalkieServer supervision mode/status

### Shared contract

Lives in TalkieKit as a narrow Codable model plus compatibility projection to the
current shared defaults keys.

Candidate shape:

```swift
public struct AgentRuntimeSettings: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var hotkeys: HotkeySettings
    public var audioInput: AudioInputSettings
    public var dictation: DictationRuntimeSettings
    public var output: OutputRoutingSettings
    public var capture: CaptureRuntimeSettings
    public var tray: TrayRuntimeSettings
    public var overlay: OverlayRuntimeSettings
    public var permissions: PermissionRuntimeSettings
    public var storage: RuntimeStorageSettings
    public var sounds: RuntimeSoundSettings
    public var server: AgentServerSettings
}
```

The model should cover only the knobs Agent must read at runtime. When in doubt,
keep a setting Talkie-only until Agent has a concrete runtime need.

## Current Code Seams

Useful existing Talkie seams:

- Shared defaults and key names:
  `/Users/art/dev/talkie/apps/macos/TalkieKit/Sources/TalkieKit/SharedSettings.swift`
- Agent runtime settings reader/writer:
  `/Users/art/dev/talkie/apps/macos/TalkieAgent/TalkieAgent/Models/LiveSettings.swift`
- Talkie declarative configuration:
  `/Users/art/dev/talkie/apps/macos/Talkie/Services/TalkieSettingsConfiguration.swift`
- File-backed configuration store:
  `/Users/art/dev/talkie/apps/macos/Talkie/Services/TalkieSettingsConfigurationStore.swift`
- Talkie-side Agent settings mirror:
  `/Users/art/dev/talkie/apps/macos/Talkie/Models/TalkieAgentSettings.swift`

Existing settings groups already map well to the future shared contract:

| Existing area | Target bucket |
| --- | --- |
| hotkeys in `AgentSettingsKey` | shared contract |
| mic/model/routing in `LiveSettings` | shared contract |
| `TalkieSettingsConfiguration.Capture` | partly shared runtime, partly Talkie presentation |
| `TalkieSettingsConfiguration.Camera` | shared if Agent captures camera/live clips; otherwise Talkie-only |
| `TalkieSettingsConfiguration.Tray` | shared runtime for Agent tray, with Talkie durable viewer prefs kept separate |
| `TalkieSettingsConfiguration.Notch` | shared runtime if Agent owns notch surfaces |
| bridge/server toggles | split: Talkie product enablement vs Agent supervision/runtime status |
| appearance/theme | mostly app-specific; share only Agent overlay appearance if needed |

## Proposed Agent Home Sections

Initial Agent Home should feel operational, not encyclopedic.

1. **Overview**
   - capture/dictation state
   - Agent process/build status
   - Talkie connection/XPC state
   - TalkieServer health
   - permission warnings
   - live tray counts

2. **Capture**
   - screenshot preset
   - screen recording quality
   - capture launcher behavior
   - recent capture state
   - capture hotkeys

3. **Tray**
   - live screenshots/clips count
   - pin/clear/delete actions
   - shelf/viewer behavior
   - paste latest controls

4. **Dictation**
   - mic selection
   - transcription model
   - toggle/PTT hotkeys
   - routing mode
   - context capture detail

5. **Overlays**
   - pill style/placement
   - notch/island enablement
   - tray strip/badge controls
   - sounds

6. **Server**
   - TalkieServer process state
   - port/route/mode
   - restart/stop controls
   - rollover/adoption status

7. **Permissions**
   - microphone
   - accessibility
   - input monitoring
   - screen recording
   - reveal system settings actions

8. **Logs**
   - Agent log tail
   - TalkieServer log tail
   - recent errors
   - reveal/copy diagnostics

Advanced or experimental subsections can hide behind an explicit “Advanced” mode
instead of polluting the default shell.

## UI Architecture

Agent Home should adopt the OpenScout/Hudson structure in SwiftUI:

```text
AgentHomeApp
└─ HudChromeShell
   ├─ HudResizableNavigationSidebar
   ├─ content section
   ├─ trailing inspector
   └─ status bar
```

Recommended state objects:

- `AgentHomeStore` — aggregates runtime snapshots and shared settings.
- `AgentRuntimeSettingsStore` — TalkieKit-backed shared allowlist model.
- `AgentStatusStore` — process/XPC/server/permission state.
- `AgentHomeNavigationModel` — selected section, sidebar width, inspector state.
- `AgentHomeCommandBus` — command menu + keyboard monitor integration.

The status bar should be useful on every screen:

```text
REC idle · tray 2 screenshots / 1 clip · server healthy · perms ok · ⌘/ help
```

Keyboard vocabulary should start small:

| Chord | Action |
| --- | --- |
| `⌘1`…`⌘8` | switch section |
| `j/k` | next/previous row when not typing |
| `h/l` | collapse/expand or move between panes |
| `g/⇧G` | top/bottom |
| `⌘R` | refresh current section |
| `⌘/` or `?` | cheatsheet |
| `⌘,` | settings/preferences focus |
| `Esc` | close inspector/modal/help |

## Data Flow

```text
Talkie Settings UI ─┐
                    ├─ AgentRuntimeSettingsStore (TalkieKit) ── shared config/defaults ── TalkieAgent runtime
Agent Home UI  ─────┘

TalkieAgent runtime ── status snapshots/events ── Agent Home
TalkieAgent runtime ── durable recordings/assets ── Talkie library views
```

Talkie and Agent may both edit shared runtime settings. To keep this safe:

- settings writes should be section-scoped and atomic;
- each shared setting should have one canonical key/path;
- Agent should observe reload notifications or file/defaults changes;
- Talkie-only settings must never be required for Agent boot;
- shared settings must decode with defaults for forwards/backwards compatibility.

## Migration Plan

### Milestone 1 — Contract Inventory

- Inventory all `AgentSettingsKey` reads/writes.
- Classify each key as `shared`, `agent-private`, `talkie-only`, or `deprecated`.
- Create a markdown table beside this doc or in a follow-up review artifact.

Acceptance:

- every current shared key has an owner and bucket;
- no new Agent Home UI is blocked by unknown settings ownership.

### Milestone 2 — TalkieKit Shared Settings Model

- Add `AgentRuntimeSettings` to TalkieKit.
- Add a store that can load/save it and project to/from legacy shared defaults.
- Keep legacy defaults in place during migration.

Acceptance:

- Agent and Talkie can round-trip the model without losing legacy settings;
- adding optional fields uses `decodeIfPresent` and defaults.

### Milestone 3 — Agent Home Shell

- Create the Hudson-shaped Agent Home shell.
- Add sidebar, status bar, inspector toggle, hotkey bus, and cheatsheet.
- Populate Overview, Permissions, Server, and Logs with read-only live data first.

Acceptance:

- Agent Home can open independently;
- status bar reflects Agent/TalkieServer/permission state;
- keyboard navigation works without stealing text input.

### Milestone 4 — Shared Runtime Editors

- Add Capture, Tray, Dictation, and Overlays editors bound to the shared contract.
- Keep Talkie Settings views as another surface over the same shared subset.

Acceptance:

- changing a shared runtime setting in Agent is reflected in Talkie;
- changing the same setting in Talkie is reflected/applied by Agent;
- Talkie-only settings are not exposed in Agent Home.

### Milestone 5 — Cleanup and Ownership Tightening

- Retire duplicated `LiveSettings`/`TalkieAgentSettings` fields once the shared
  store is stable.
- Remove stale one-off defaults keys or mark compatibility-only.
- Add focused tests for decode/migration/projection.

Acceptance:

- a clean allowlist exists in TalkieKit;
- Agent boot does not depend on Talkie app being open;
- Talkie remains a durable media/product surface, not a live runtime host.

## Open Questions

1. Should Agent Home ship as part of `TalkieAgent.app` only, or also be openable
   from Talkie as an embedded/sibling window?
2. Which capture settings are truly runtime-critical versus Talkie presentation
   preferences?
3. Should TalkieServer settings split into product enablement (Talkie-only) and
   process supervision/runtime health (Agent-owned)?
4. Do we want a JSON file as the primary shared contract, or continue shared
   defaults with a Codable blob plus legacy scalar projection?
5. What is the minimum useful Agent Home MVP: Overview + Server + Permissions,
   or Overview + Capture + Tray?

## Recommendation

Proceed with TLK-028 as a small architecture branch before more Swift surface
work:

1. inventory the current shared settings keyspace;
2. add a TalkieKit `AgentRuntimeSettings` allowlist model;
3. scaffold Hudson-shaped Agent Home around read-only status;
4. then add shared runtime editors section by section.

This gives Agent a future-proof operating surface without turning it into a copy
of Talkie Settings.
