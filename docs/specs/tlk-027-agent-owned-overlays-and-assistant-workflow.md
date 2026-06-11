# TLK-027 - Agent-Owned Overlays and Assistant Workflow

**Status**: Architecture proposal
**Owner**: Talkie macOS + TalkieAgent
**Date**: 2026-06-09
**Studio**: /eng/tlk-027
**Related**: [TLK-021](tlk-021-agent-home-architecture.md) (Agent Home), [TLK-022](tlk-022-media-augmentation-pipeline.md) (media sidecars), [TLK-026](tlk-026-visual-context-capture.md) (visual context capture)

## Summary

Consolidate desktop overlays and the assistant workflow surface into
`TalkieAgent`. Keep intelligence and execution in TalkieServer plus the Agent
runtime.

The target boundary is simple:

```text
TalkieAgent owns live desktop behavior.
Talkie owns review, settings, library, and authoring surfaces.
TalkieKit owns shared data contracts.
```

In practice, this means Agent owns the notch/island surface, floating recording
pill, capture HUD, tray shelf/viewer, screenshot and screen-clip capture, quick
paste, and assistant routing triggered from live input. Server/runtime own the
model calls, planning, tools, and workflow execution. Talkie can still show
settings, browse saved media, edit workflows, and inspect history, but it should
stop being the process that renders global desktop overlays or performs live
assistant work.

## Motivation

The current split is halfway there:

- `TalkieAgent` owns dictation state, audio capture, transcription, paste,
  hot-state writes, OCR helpers, region picking, and some overlay views.
- `Talkie` still owns richer capture UI, screenshot and screen recording
  capture, tray storage, tray viewer/shelf/badge, notch composer, capture markup
  workflow helpers, and several global hotkey handlers.
- Agent currently accepts live screenshots through XPC, but still pulls tray
  assets back from Talkie when finishing a dictation.

That creates a fragile loop:

```text
Agent records -> Talkie captures/trays media -> Agent asks Talkie for media -> Agent stores result
```

The desired shape is:

```text
Agent records/captures/trays media -> Agent stores result -> Talkie observes/reviews result
```

This aligns permissions, latency, and user expectations. The process that is
always running and reacting to desktop context should own the desktop context.

## Product Boundary

### TalkieAgent Owns

- Global hotkeys for live capture, tray, paste, island, and assistant actions.
- All floating desktop surfaces:
  - notch/island
  - island tray popup
  - recording pill
  - capture HUD/bar
  - region/window picker overlays
  - screenshot preview
  - tray shelf
  - tray viewer
  - drag-source panels
  - assistant interstitials and live sidecars
- Screen capture and screen recording:
  - fullscreen, region, and window screenshots
  - screen clips and visual context sessions
  - capture target memory and countdowns
- Mutable live media state:
  - screenshot tray
  - clip tray
  - selection tray
  - pin/clear/delete/copy/paste state
- Assistant workflow presentation and coordination:
  - dictation routing
  - quick actions
  - live sidecar tasks
  - capture markup assistant entry points
  - dispatching live-triggered workflow requests to Server/runtime
- Permission prompts for capabilities it uses directly:
  - microphone
  - accessibility
  - input monitoring
  - screen recording

### Talkie Owns

- Main app navigation and durable library views.
- Saved media browser, main-app capture views, and capture detail review.
- Workflow editor, settings, diagnostics, and onboarding.
- Starting/stopping/relaunching Agent and showing health.
- Agent command buttons, but not the desktop surfaces those commands open.
- Read-only or command-based views over Agent live state.

### TalkieKit Owns

- Shared Codable contracts.
- Storage path helpers.
- Capture, tray, and visual-context metadata types.
- XPC command and event protocols, plus existing HTTP bridge contracts where
  they are already public.
- Reusable renderers that do not assume process ownership.

## Current Code Touchpoints

These are the main pieces to move, split, or replace.

| Area | Current owner | Target owner |
| --- | --- | --- |
| `NotchComposer`, `NotchPanel`, notch views/settings bridge | Talkie | Agent |
| `ScreenshotCaptureService` | Talkie | Agent |
| `ScreenRecordingService` / `ScreenRecordingController` | Talkie | Agent |
| `CaptureHUDController`, `CaptureBarController`, panels | Talkie | Agent |
| `TrayViewer`, `TrayShelf`, `TrayBadge`, tray drag/paste | Talkie | Agent |
| `ScreenshotTray`, `ClipTray`, `SelectionTray` mutable stores | Talkie | Agent, with shared contracts in TalkieKit |
| `CaptureMarkupAgentService` workflow helpers | Talkie | Agent |
| live screenshot side channel | Talkie -> Agent | removed; direct Agent capture |
| `fetchTrayAssets` observer callback | Agent -> Talkie | removed; Agent-local merge |
| Talkie settings for surface/capture | Talkie | Talkie UI writing shared config, Agent applying it |

## Target Architecture

```text
              settings / review / commands
Talkie.app  --------------------------------->  TalkieAgent
   |                                                |
   |       state snapshots / saved history          |
   <----------------------------------------------- |
   |                                                |
   v                                                v
library views                                overlay + assistant runtime

TalkieKit:
  shared contracts, storage helpers, XPC protocols, renderers
```

Agent becomes the only writer for live overlay state and mutable tray state.
Talkie observes through typed snapshots, durable database refreshes, or explicit
commands. It should not instantiate live overlay singletons to render state that
Agent already owns.

## IPC Contract

Extend `TalkieAgentXPCServiceProtocol` with a typed surface API. Keep new tray
and overlay commands off the HTTP bridge for v1 unless Talkie already exposes the
same contract through an existing shared route.

Suggested command set:

```swift
enum AgentSurfaceCommand: String, Codable, Sendable {
    case showTray
    case toggleTrayShelf
    case dismissTray
    case beginCaptureChord
    case captureScreenshot
    case startScreenRecording
    case stopScreenRecording
    case pasteLatestTrayItem
    case openCaptureMarkup
    case showIsland
    case captureOverlaySnapshot
}
```

Suggested event snapshot:

```swift
struct AgentSurfaceSnapshot: Codable, Sendable {
    var liveState: LiveState
    var activeOverlay: String?
    var trayCounts: AgentTrayCounts
    var screenRecordingState: String
    var capturePermissionState: AgentPermissionSnapshot
    var currentDisplayID: UInt32?
}
```

Rules:

- Commands are idempotent where practical.
- Commands return typed success/error values, not log-only failures.
- Snapshots are low frequency. Audio-level and high-frequency animation state
  stays Agent-local once Agent renders the island itself.
- Talkie should never need to fetch raw tray assets at dictation finish.

## Storage Boundary

The existing file locations can remain stable for compatibility:

```text
~/Library/Application Support/Talkie/Tray/
~/Library/Application Support/Talkie/Screenshots/
~/Library/Application Support/Talkie/VisualContexts/
```

The ownership changes:

- Agent writes live tray manifests and capture files.
- Agent drains tray items into dictation assets.
- Agent promotes standalone captures into durable objects when appropriate.
- Talkie reads durable library objects for review.
- Talkie sends Agent commands for live tray operations.

The tray manifest should become an Agent-owned implementation detail. If Talkie
needs live tray state for a settings preview or diagnostics surface, it asks
Agent for a snapshot instead of reading/writing tray singletons directly.

## Assistant Workflow Boundary

Assistant workflow means "work triggered by live input or overlay actions."

Agent Swift owns the assistance UI layer:

- translating live dictation into capture intent
- deciding paste vs scratchpad vs save-as-memo
- presenting quick action routing, progress, and results
- attaching screenshots and visual contexts to the resulting record
- creating activity records for Agent Home
- invoking capture-markup assistant entry points
- sending final paste/notification/interstitial output

TalkieServer plus the Agent runtime own intelligence and execution:

- model/provider calls
- planning and tool selection
- workflow execution
- long-running runtime jobs
- capture-markup description, planning, and render work

Talkie owns:

- viewing, editing, and saving workflow definitions
- showing saved workflow run history
- replaying or re-running saved work by commanding Agent
- surfacing errors and configuration

This keeps the assistant loop near the permissions and desktop APIs it depends
on.

## Migration Plan

### Phase 1 - Define Contracts

- Add `AgentSurfaceCommand`, `AgentSurfaceSnapshot`, and tray/capture command
  response types to TalkieKit.
- Add XPC methods for surface commands and snapshots.
- Keep existing Talkie-owned surfaces running while commands are introduced.

### Phase 2 - Move Capture Write Path

- Port `ScreenshotCaptureService` behavior into Agent:
  permission check, fullscreen/region/window capture, metadata, PNG encode,
  preview thumbnail, and AI-sized JPEG helper.
- Port screen recording target selection, presets, countdown, and writer service.
- Make Talkie capture hotkeys call Agent commands instead of local services.

### Phase 3 - Move Tray State and Surfaces

- Move tray data models/contracts to TalkieKit.
- Rehome mutable tray stores and tray overlay UI in Agent.
- Replace Talkie `TrayViewer.shared.show()`, `TrayShelf.shared.toggle()`, and
  paste calls with Agent commands.
- Remove Agent's `fetchTrayAssets` callback into Talkie after Agent drains its
  own tray assets locally.

### Phase 4 - Move Island Ownership

- Port the richer `NotchComposer` priority model into Agent.
- Retire the Talkie-side hot-state reader path for the island; Agent can read its
  own state directly.
- Expose only a lightweight XPC status snapshot for Talkie settings and
  diagnostics, such as current display, active overlay kind, and permission
  state. This is not a render/update path for the island.
- Remove Talkie startup of `NotchComposer`.

### Phase 5 - Wire Assistant Workflow Routing

- Move live-triggered capture markup entry points and quick action presentation
  into Agent Swift.
- Route intelligence and workflow execution through TalkieServer plus the Agent
  runtime.
- Keep workflow authoring and saved-run review in Talkie.
- Make Agent Home the durable review surface for assistant activity, with Talkie
  linking into it instead of duplicating the review surface.

### Phase 6 - Delete Compatibility Paths

- Remove Talkie local capture hotkey handling.
- Remove Talkie live tray mutation.
- Remove `recordLiveScreenshot` and `fetchTrayAssets` cross-process workarounds.
- Keep temporary aliases only for older helpers if needed.

## Implementation Notes

- Preserve existing storage paths until a separate migration says otherwise.
- Avoid moving SwiftUI views by copy/paste without untangling their dependencies
  on `SettingsManager`, `FeatureFlags`, and Talkie-only singletons.
- Any setting Agent needs at runtime should live in shared configuration, not in
  Talkie-only defaults wrappers.
- Agent should own TCC prompts for capabilities it uses. Talkie settings can
  request those prompts through Agent.
- The first code milestone should invert the tray asset dependency; it is the
  clearest proof that Agent owns the live workflow.

## Review Decisions

- Keep live tray snapshots off the HTTP bridge for v1. Add no
  `/v1/agent/tray/*` route unless an existing Talkie-shared bridge route already
  exposes this contract.
- When Agent needs Talkie's main-app surfaces for view/edit/save, load Talkie via
  deep link instead of adding a tray bridge route.
- The island tray popup, meaning the popup shown when the user engages with the
  tray icon in the island, is Agent-owned. Talkie keeps main-app capture and
  saved-media views only.

## Open Questions

- Should capture markup's web resources move into TalkieKit resources, Agent
  resources, or a shared package?

## Success Criteria

- Quitting Talkie does not break live dictation overlays, capture HUD, tray
  shelf, screen capture, screen recording, quick paste, or assistant routing.
- Talkie can launch, configure, and inspect Agent without rendering live desktop
  overlays itself.
- A dictation with screenshots or clips finishes without Agent calling back into
  Talkie to fetch tray assets.
- Screen Recording permission is requested for the process that captures the
  screen.
- There is one visible island/notch implementation at runtime, not competing
  Talkie and Agent overlays.
