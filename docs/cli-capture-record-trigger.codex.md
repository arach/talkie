# Talkie CLI capture record trigger audit

> **Canonical spec**: [TLK-029 — Agent-Initiated Screen Capture](specs/tlk-029-agent-initiated-screen-capture.md)

Requested by: operator (Scout handoff).
Scope: audit + PR plan + smoke-test spec only; no implementation.
Author: talkie-cli-codex. Date: 2026-06-13.

## TL;DR

Preframe needs a **trigger**, not a history reader: an external agent should start a fresh Talkie screen capture, drive UX with Playwright/Action/Codex, stop recording, and get a new `.mp4` path.

Talkie has most of the native recorder, but **no automation entrypoint exists today**:

- Current screen recording start is UI-first: Hyper+R enters `TalkieAgent`'s capture HUD and/or countdown before calling `ScreenRecordingController.shared.startRecording(mode:)` (`apps/macos/TalkieAgent/TalkieAgent/App/AppDelegate.swift:1464-1503`).
- Current native recording engine can record fullscreen, region, and window targets through `ScreenRecordingService.startRecording(target:)` (`apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingService.swift:416-558`).
- Current stop path persists the temp MP4 into the Agent live tray and capture Library (`apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingController.swift:128-185`), but returns `Void`; callers cannot get the stored file URL without polling manifests/history.
- Current `:8766` HTTP server is the right ingress because it is loopback-only and already has trusted local client capability checks (`apps/macos/Talkie/Services/TalkieServer.swift:392-397`, `apps/macos/Talkie/Services/TalkieServer.swift:576-640`). It has screenshot/window routes but **no capture record routes**.
- Current XPC protocol has screenshot methods only (`apps/macos/TalkieKit/Sources/TalkieKit/XPCProtocols.swift:113-135`); there is no `startScreenRecording` / `stopScreenRecording` / all-windows enumeration method.

Fastest durable path: add authenticated `:8766` routes that forward over XPC to `TalkieAgent`, add non-interactive target resolution + metadata-returning stop in Agent, then add a thin `talkie capture` CLI command group. Do **not** simulate Hyper+R.

## 1. Exact native call chain

### 1.1 Current UI/hotkey call chain (works, but not suitable for Preframe)

The working native UI path is Agent-owned:

1. `TalkieAgent` registers the capture and screen-record hotkeys when capture is enabled (`apps/macos/TalkieAgent/TalkieAgent/App/AppDelegate.swift:1359-1396`). Defaults include Hyper+R for screen recording (`apps/macos/TalkieAgent/TalkieAgent/App/AppDelegate.swift:1372-1376`).
2. Hyper+R calls `handleAgentCaptureChord(initialMode: .video)` (`apps/macos/TalkieAgent/TalkieAgent/App/AppDelegate.swift:1388-1394`).
3. If already recording, the same path stops through `ScreenRecordingController.shared.stopRecording()` (`apps/macos/TalkieAgent/TalkieAgent/App/AppDelegate.swift:1464-1467`).
4. Otherwise it first tries `ScreenRecordingController.shared.startReusableRecordingWithCountdown()` (`apps/macos/TalkieAgent/TalkieAgent/App/AppDelegate.swift:1479-1489`). This is interactive and can show the countdown/selection UI.
5. If selection is needed, `CaptureHUDController().beginChord(...)` shows the capture HUD (`apps/macos/TalkieAgent/TalkieAgent/App/AppDelegate.swift:1491-1493`).
6. The `.screenRecord(let mode)` HUD result calls `ScreenRecordingController.shared.startRecording(mode:)` (`apps/macos/TalkieAgent/TalkieAgent/App/AppDelegate.swift:1496-1503`).
7. `ScreenRecordingController.startRecording(mode:)` sets `.selecting`, calls `ScreenRecordingService.shared.selectTarget(mode:)`, then calls its private `startResolvedRecording(target:mode:)` (`apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingController.swift:54-76`).
8. `ScreenRecordingService.selectTarget(mode:)` checks Screen Recording permission and routes by mode (`apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingService.swift:244-271`):
   - fullscreen: `selectFullscreen()` uses `SCShareableContent` and display under cursor (`ScreenRecordingService.swift:363-376`);
   - region: `selectRegion()` invokes `ScreenCaptureOverlay().selectRegion()` (`ScreenRecordingService.swift:378-393`);
   - window: `selectWindow()` invokes `ScreenCaptureOverlay().selectWindow()` and resolves the selected `SCWindow` (`ScreenRecordingService.swift:395-411`).
9. `ScreenRecordingController.startResolvedRecording(...)` calls `ScreenRecordingService.shared.startRecording(target:)`, activates Notch/active overlay UI, samples visual metadata, and records state (`ScreenRecordingController.swift:244-273`).
10. `ScreenRecordingService.startRecording(target:)` builds the `SCContentFilter`, `SCStreamConfiguration`, `AVAssetWriter`, optional audio inputs, starts `SCStream`, writes a temp MP4 under `FileManager.default.temporaryDirectory/TalkieAgentScreenRecording`, saves the reusable target preset, and starts a 5-minute safety timer (`ScreenRecordingService.swift:416-568`).
11. Stop calls `ScreenRecordingService.stopRecording()` to stop the stream and finish the writer (`ScreenRecordingService.swift:578-608`).
12. `ScreenRecordingController.stopRecording()` computes duration/metadata, stores the temp MP4 in the live tray via `AgentLiveTrayAssetStore.shared.storeClip(...)`, copies/persists into the capture Library via `AgentCaptureLibraryWriter.persistClip(...)`, then resets UI state (`ScreenRecordingController.swift:128-195`).
13. `AgentLiveTrayAssetStore.storeClip(...)` moves the temp MP4 to `~/Library/Application Support/Talkie/Tray/clips/`, writes `manifest.json`, posts `to.talkie.tray.assetsDidChange`, and returns `AgentLiveTrayStoredClip` with `id`, `fileURL`, and `filename` (`apps/macos/TalkieKit/Sources/TalkieKit/LiveTray/AgentLiveTrayAssetStore.swift:527-598`, directory at `AgentLiveTrayAssetStore.swift:604-606`).
14. `AgentCaptureLibraryWriter.persistClip(...)` also copies the stored clip into `~/Library/Application Support/Talkie/Videos/`, creates visual-context metadata, and saves a `TalkieObject` capture in `UnifiedDatabase` (`apps/macos/TalkieAgent/TalkieAgent/Services/Capture/AgentCaptureLibraryWriter.swift:87-163`, `AgentCaptureLibraryWriter.swift:167-199`; videos dir in `apps/macos/TalkieKit/Sources/TalkieKit/VideoClipStorage.swift:14-20`).

There is a duplicate/legacy main-app recorder under `apps/macos/Talkie/Services/ScreenRecording/`, and `Talkie.app` also has a local capture chord path (`apps/macos/Talkie/App/AppDelegate.swift:1972-2234`). For the CLI trigger, prefer the **Agent** chain above because it owns the always-on recorder and Agent live tray persistence.

### 1.2 Current HTTP/XPC surfaces (partial, not enough)

`Talkie.app` exposes the local HTTP relay on `:8766`:

- Server definition and port: `TalkieServer` listens on `8766` (`apps/macos/Talkie/Services/TalkieServer.swift:254-261`).
- It accepts only loopback connections (`TalkieServer.swift:392-397`).
- Sensitive local routes are gated by trusted local client capabilities (`TalkieServer.swift:576-640`). Supported current capabilities include `desktop.windows.read` and `desktop.screenshot.read` (`TalkieServer.swift:188-211`).
- Trusted request signing headers are `x-talkie-client-id`, `x-talkie-timestamp`, `x-talkie-nonce`, `x-talkie-body-sha256`, and `x-talkie-signature` (`TalkieServer.swift:281-291`), checked with timestamp, nonce replay, body hash, and P-256 signature (`TalkieServer.swift:643-704`).
- The existing `:8766` route table includes `/windows/claude`, `/screenshot/terminals`, `/screenshot/display`, `/screenshot/window/<id>`, and `/tray/<uuid>.png` (`TalkieServer.swift:840-888`).
- Existing screenshot handlers forward over fresh XPC using `callAgent(...)` (`TalkieServer.swift:3270-3375`, helper at `TalkieServer.swift:3579-3624`).

`TalkieAgent` exposes a separate bridge on `:8767`:

- `BridgeServer` binds to `0.0.0.0:8767` and routes `/v1/agent/*` (`apps/macos/TalkieAgent/TalkieAgent/Services/BridgeServer.swift:14-22`, `BridgeServer.swift:153-159`).
- Legacy aliases include `/windows`, `/windows/claude`, `/screenshot/display`, and `/screenshot/terminals` (`apps/macos/TalkieAgent/TalkieAgent/Services/BridgeRouter.swift:49-56`).
- `AgentRoutes` has `GET /windows` and screenshot routes (`apps/macos/TalkieAgent/TalkieAgent/Services/AgentRoutes.swift:11-44`).
- Despite the `BridgeServer` comment saying auth-protected, the inspected `BridgeRouter` only reads `x-talkie-client` as identity (`apps/macos/TalkieAgent/TalkieAgent/Services/BridgeRouter.swift:98-117`); it does not enforce the same trusted-local-client capability model.

Therefore, external automation should use `:8766`, not direct `:8767`, for recording triggers.

### 1.3 Proposed automation call chain (start → stop → new MP4 path)

Target chain after the minimal native change:

```text
preframe/scripts/capture-guided-tour.mjs
  └─ talkie capture windows --json
      └─ packages/npm/cli/src/commands/capture.ts
          └─ signed GET http://127.0.0.1:8766/capture/windows
              └─ TalkieServer.processRequest + authorizeLocalClientIfNeeded
                  └─ TalkieServer.handleCaptureWindows
                      └─ XPC TalkieAgentXPCServiceProtocol.listCaptureWindows
                          └─ TalkieAgentXPCService.listCaptureWindows
                              └─ ScreenshotService.shared.listWindows() + display/z-order enrichment

preframe drives Playwright UX

preframe starts recording
  └─ talkie capture record --region x,y,w,h --json
      └─ signed POST http://127.0.0.1:8766/capture/record/start
          └─ TalkieServer.handleCaptureRecordStart
              └─ XPC startScreenRecording(requestJSON:)
                  └─ TalkieAgentXPCService.startScreenRecording
                      └─ ScreenRecordingService.resolveTarget(request.target)
                      └─ ScreenRecordingController.startAutomationRecording(target:options:)
                          └─ ScreenRecordingService.startRecording(target:)

preframe stops recording
  └─ talkie capture stop --json
      └─ signed POST http://127.0.0.1:8766/capture/record/stop
          └─ TalkieServer.handleCaptureRecordStop
              └─ XPC stopScreenRecording()
                  └─ TalkieAgentXPCService.stopScreenRecording
                      └─ ScreenRecordingController.stopAutomationRecording()
                          └─ ScreenRecordingService.stopRecording()
                          └─ AgentLiveTrayAssetStore.storeClip(...)
                          └─ AgentCaptureLibraryWriter.persistClip(...)
                      ← {id,path,durationMs,width,height,captureMode,...}
```

Required code seams:

- `apps/macos/Talkie/Services/TalkieServer.swift`: add routes, auth mapping, JSON handlers, and XPC forwarding next to existing screenshot handlers.
- `apps/macos/TalkieKit/Sources/TalkieKit/XPCProtocols.swift`: add recording/window XPC methods.
- `apps/macos/TalkieAgent/TalkieAgent/Services/TalkieAgentXPCService.swift`: implement those methods and marshal JSON.
- `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingService.swift`: add explicit target resolvers for `region`, `windowID`, and `displayID`. Current `regionTarget(for:)` exists for rects (`ScreenRecordingService.swift:328-357`), but explicit window/display recording is not a public automation API.
- `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingController.swift`: add a non-interactive start method and a metadata-returning stop method. Current `startResolvedRecording` is private and always shows active UI (`ScreenRecordingController.swift:244-273`); current `stopRecording()` stores the clip but does not return the `stored.fileURL` (`ScreenRecordingController.swift:128-195`).
- `packages/npm/cli/src/commands/capture.ts`: new thin command group over signed `:8766` calls; register from `packages/npm/cli/src/cli.ts` beside the existing plural `captures` history command (`packages/npm/cli/src/cli.ts:45-55`).

## 2. HTTP contract for `:8766`

### 2.1 Capabilities

Add one new capability and reuse one existing capability:

| Capability | Routes | Rationale |
| --- | --- | --- |
| `desktop.windows.read` | `GET /capture/windows` | Existing narrow read capability for window metadata. |
| `desktop.capture.record` | `POST /capture/record/start`, `POST /capture/record/stop`, optional `GET /capture/record/state` | New sensitive recording-control capability. Do not overload `desktop.screenshot.read`. |

Add `desktop.capture.record` to `LocalBridgeCapability.supported` (`apps/macos/Talkie/Services/TalkieServer.swift:188-211`) and to `requiredLocalClientCapability(...)` (`TalkieServer.swift:613-640`).

Signed requests use the existing trusted local client model:

```http
x-talkie-client-id: <client id>
x-talkie-timestamp: <unix seconds>
x-talkie-nonce: <random unique nonce>
x-talkie-body-sha256: <hex sha256 of exact body bytes; empty body hashes as sha256("")>
x-talkie-signature: <base64 DER P-256 ECDSA signature over METHOD + "\n" + rawPath + "\n" + timestamp + "\n" + nonce + "\n" + bodyHash>
```

### 2.2 `GET /capture/windows`

Purpose: enumerate deterministic targets for external drivers. This should include pid/window-id parity with the Action audit so Preframe can map Playwright's browser pid to a concrete macOS window.

Request:

```http
GET /capture/windows?bundleID=com.google.Chrome&pid=12345&title=Preframe&onScreen=true HTTP/1.1
Host: 127.0.0.1:8766
...
```

Query parameters are optional filters. The CLI can also filter client-side, but server filters keep output small:

- `bundleID`: exact bundle identifier.
- `pid`: exact process id.
- `app`: localized app name substring.
- `title`: title substring.
- `onScreen`: default `true`.
- `minWidth`, `minHeight`: defaults around `80` / `60` if needed.

Response `200`:

```json
{
  "ok": true,
  "windows": [
    {
      "windowID": 18422,
      "pid": 93341,
      "bundleID": "com.google.Chrome",
      "appName": "Google Chrome",
      "title": "Preframe — Guided Tour",
      "frame": { "x": 200, "y": 120, "width": 1440, "height": 900 },
      "displayID": 1,
      "displayName": "Studio Display",
      "isOnScreen": true,
      "isFrontmost": true,
      "zIndex": 0
    }
  ],
  "count": 1,
  "generatedAt": "2026-06-13T16:40:00Z"
}
```

Notes:

- Current `ScreenshotService.listWindows()` returns `windowID`, `pid`, `bundleId`, `appName`, `title`, `layer`, `bounds`, and `isOnScreen` (`apps/macos/TalkieAgent/TalkieAgent/Services/ScreenshotService.swift:152-178`, type at `ScreenshotService.swift:284-295`). Extend it with display and z-order rather than creating a second window model.
- Match response keys as `bundleID` and `frame`; the current Agent bridge uses `bundleId` and `bounds` (`apps/macos/TalkieAgent/TalkieAgent/Services/AgentRoutes.swift:352-370`). The CLI can tolerate aliases, but the new `capture/windows` contract should be stable and Action-parity-friendly.

Error examples:

```json
{ "ok": false, "error": "TalkieAgent not connected", "code": "agent_unavailable" }
```

```json
{ "ok": false, "error": "Local client is missing required capability", "requiredCapability": "desktop.windows.read" }
```

### 2.3 `POST /capture/record/start`

Purpose: start a fresh recording without HUD selection or hotkey simulation.

Request shape:

```json
{
  "target": {
    "kind": "region",
    "rect": { "x": 200, "y": 120, "width": 1440, "height": 900 },
    "displayID": 1
  },
  "quality": "agent",
  "audio": { "system": false, "microphone": false },
  "maxDurationSeconds": 180,
  "presentation": {
    "supervision": true,
    "showCaptureChrome": true,
    "showNotch": true
  },
  "clientContext": {
    "driver": "preframe-guided-tour",
    "correlationId": "tour-2026-06-13T16-40-00Z",
    "clientId": "talkie-cli",
    "label": "Preframe guided tour"
  }
}
```

Target variants:

```json
{ "target": { "kind": "region", "rect": { "x": 200, "y": 120, "width": 1440, "height": 900 }, "displayID": 1 } }
```

```json
{ "target": { "kind": "window", "windowID": 18422, "pid": 93341, "bundleID": "com.google.Chrome" } }
```

```json
{ "target": { "kind": "display", "displayID": 1 } }
```

Field notes:

- `target.kind`: required; one of `region`, `window`, `display`. Map `display` to the existing native `.fullscreen` capture mode (`apps/macos/TalkieKit/Sources/TalkieKit/Capture/CaptureTypes.swift:4-8`).
- `quality`: optional, one of `agent`, `balanced`, `archive`, matching `ScreenRecordingQualityPreset` (`ScreenRecordingService.swift:18-58`). If omitted, use the current shared setting.
- `audio`: optional override. If omitted, use existing shared settings (`ScreenRecordingService.swift:173-186`, `ScreenRecordingService.swift:883-908`).
- `maxDurationSeconds`: optional safety valve. Native hard-coded max is currently 300s (`ScreenRecordingService.swift:211-212`, timer at `ScreenRecordingService.swift:560-566`); automation should be able to request a shorter max.
- `presentation.showHUD`: must default `false` for this route. The route is for explicit targets, not selection.
- `presentation.supervision`: defaults `true`. Shows a full-display red border pulse plus a corner **RECORDING** HUD with caller label and STOP. Uses `NSWindow.sharingType = .none`, so it is visible to the user but excluded from ScreenCaptureKit output.
- `presentation.showCaptureChrome`: defaults `true`. Keeps the existing amber in-region brackets and `REC` badge (also `sharingType = .none`).
- `presentation.showNotch`: defaults `true`. Expands the TalkieAgent notch island during capture.
- Opt-out flags (`supervision: false`, etc.) exist for debugging only; automation and CLI must not default them off.

Response `202` or `200`:

```json
{
  "ok": true,
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "state": "recording",
  "startedAt": "2026-06-13T16:40:00.123Z",
  "target": {
    "kind": "region",
    "rect": { "x": 200, "y": 120, "width": 1440, "height": 900 },
    "displayID": 1,
    "displayName": "Studio Display"
  },
  "quality": { "preset": "agent", "fps": 12, "bitrate": 2000000 },
  "audio": { "system": false, "microphone": false },
  "maxDurationSeconds": 180
}
```

Errors:

- `400 invalid_target`: rect is malformed, dimensions too small, target kind missing.
- `404 target_not_found`: window/display disappeared between `windows` and `record/start`.
- `409 already_recording`: Agent is already recording.
- `422 permission_missing`: Screen Recording permission is unavailable. Do not pop System Settings from a headless route unless explicitly requested.
- `503 agent_unavailable`: TalkieAgent XPC unavailable.

### 2.4 Recording supervision and visibility

Recording must be unmistakable for every path: Hyper+R, CLI automation, and `:8766` triggers.

Talkie already draws capture chrome with `sharingType = .none` on overlay panels (`ScreenRecordingController.swift` — `ScreenRecordingActiveOverlayController`). That means louder affordances do **not** leak into the recorded `.mp4`. Security and marketing capture are not in tension.

Visibility stack (defense-in-depth for awareness):

| Layer | Component | In the `.mp4`? |
| --- | --- | --- |
| OS | macOS menu bar screen-recording indicator | N/A |
| Consent | `POST /local-clients/request-access` with `desktop.capture.record` | N/A |
| Border | `CaptureSupervisionController` — pulsing red ring on every display | No |
| HUD | Corner pill: **RECORDING** + elapsed + caller (`clientContext.label` / `driver`) + STOP | No |
| Chrome | Amber brackets + `REC` badge around capture rect | No |
| Notch | `NotchOverlayController.activateScreenRecording` | Usually outside region |

Pairing copy when `desktop.capture.record` is requested must be explicit, not generic bridge language:

> **Allow {displayName} to record your screen via Talkie?**
>
> This client can start and stop screen recordings on this Mac. Recordings are always visible while active.

`clientContext.driver` and `clientContext.label` feed the supervision HUD so the user sees *who* started capture, not just that Talkie is recording.

### 2.5 `POST /capture/record/stop`

Purpose: stop the active recording and return the **stored** clip path, not only the temp writer URL.

Request:

```json
{
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "timeoutSeconds": 15
}
```

`recordingId` is optional for ergonomic CLI use. If present, reject mismatch with `409 recording_mismatch` so concurrent future callers do not stop each other's clips.

Response `200`:

```json
{
  "ok": true,
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "state": "stopped",
  "clip": {
    "id": "9052eb56-1e4d-4e4e-9d23-a2b1b63c9850",
    "kind": "clip",
    "path": "/Users/arach/Library/Application Support/Talkie/Tray/clips/Talkie Screen Clip - 2026-06-13 16.40.12 - Region - 1440x900 - 9052eb56.mp4",
    "libraryPath": "/Users/arach/Library/Application Support/Talkie/Videos/Talkie Screen Clip - 2026-06-13 16.40.12 - Region - 1440x900 - 9052eb56.mp4",
    "filename": "Talkie Screen Clip - 2026-06-13 16.40.12 - Region - 1440x900 - 9052eb56.mp4",
    "durationMs": 8241,
    "width": 1440,
    "height": 900,
    "captureMode": "region",
    "windowTitle": "Preframe — Guided Tour",
    "appName": "Google Chrome",
    "displayName": "Studio Display",
    "capturedAt": "2026-06-13T16:40:00.123Z"
  }
}
```

Implementation note: this requires `ScreenRecordingController.stopRecording()` to return a DTO. It currently obtains `stored.fileURL` and `stored.id`, then logs and discards them (`ScreenRecordingController.swift:159-185`).

Errors:

- `404 not_recording`: no active recording.
- `409 recording_mismatch`: caller supplied an id that does not match the active recording.
- `500 write_failed`: recording stopped but tray/library write failed; include temp URL only in diagnostics if it still exists.
- `503 agent_unavailable`: XPC unavailable.

### 2.5 Optional `GET /capture/record/state`

Useful for robust scripts but not required for first Preframe cutover.

Response:

```json
{
  "ok": true,
  "state": "recording",
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "startedAt": "2026-06-13T16:40:00.123Z",
  "elapsedMs": 4312,
  "target": { "kind": "region", "rect": { "x": 200, "y": 120, "width": 1440, "height": 900 } }
}
```

## 3. CLI command spec

Keep plural history (`talkie captures`) separate from singular trigger (`talkie capture`).

### 3.1 `talkie capture windows`

Usage:

```text
talkie capture windows [--bundle <bundle-id>] [--pid <pid>] [--app <name>] [--title <substring>] [--frontmost] [--json]
```

Behavior:

- Calls signed `GET /capture/windows` with `desktop.windows.read`.
- `--frontmost` filters to `isFrontmost === true` client-side if server returns all windows.
- Exit `0` if the route returns successfully, even with zero windows.

Pretty example:

```text
WINDOW    PID     APP             TITLE                         FRAME
18422     93341   Google Chrome   Preframe — Guided Tour        200,120 1440x900
```

JSON example:

```json
{
  "ok": true,
  "windows": [
    {
      "windowID": 18422,
      "pid": 93341,
      "bundleID": "com.google.Chrome",
      "appName": "Google Chrome",
      "title": "Preframe — Guided Tour",
      "frame": { "x": 200, "y": 120, "width": 1440, "height": 900 },
      "displayID": 1,
      "displayName": "Studio Display",
      "isOnScreen": true,
      "isFrontmost": true,
      "zIndex": 0
    }
  ],
  "count": 1
}
```

### 3.2 `talkie capture record`

Usage:

```text
talkie capture record (--region <x,y,w,h> | --window <window-id> | --display [display-id]) [options]
```

Flags:

```text
Target (required, exactly one):
  --region <x,y,w,h>        Record explicit screen rect in global screen coordinates.
  --window <window-id>      Record exact window ID from `talkie capture windows`.
  --display [display-id]    Record a display; omitted id means main/display-under-cursor.

Target guards:
  --pid <pid>               Optional guard for --window; fail if window pid differs.
  --bundle <bundle-id>      Optional guard for --window; fail if bundle differs.
  --title <substring>       Optional guard for --window; fail if title differs.

Recording options:
  --quality <preset>        agent | balanced | archive. Default: current Talkie setting.
  --system-audio            Request system audio for this recording.
  --no-system-audio         Disable system audio for this recording.
  --microphone              Request microphone for this recording.
  --no-microphone           Disable microphone for this recording.
  --max-duration <seconds>  Safety valve; CLI default 120s, Agent absolute cap 300s.
  --no-supervision          Debug only: hide border pulse + corner HUD (not recommended).
  --no-capture-chrome       Debug only: hide amber in-region brackets.
  --lease-parent-pid <pid>  Stop when parent process exits (pass driver script PID).

Output:
  --json                    Print machine-readable response.
```

Response example:

```json
{
  "ok": true,
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "state": "recording",
  "startedAt": "2026-06-13T16:40:00.123Z",
  "target": {
    "kind": "region",
    "rect": { "x": 200, "y": 120, "width": 1440, "height": 900 },
    "displayID": 1,
    "displayName": "Studio Display"
  }
}
```

### 3.3 `talkie capture stop`

Usage:

```text
talkie capture stop [--recording-id <id>] [--json | --path] [--open] [--reveal]
```

Flags:

```text
  --recording-id <id>       Guard against stopping the wrong active recording.
  --json                    Print full JSON.
  --path                    Print only the stored MP4 path, for scripts.
  --open                    Open resulting clip.
  --reveal                  Reveal resulting clip in Finder.
```

JSON output example:

```json
{
  "ok": true,
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "clip": {
    "id": "9052eb56-1e4d-4e4e-9d23-a2b1b63c9850",
    "kind": "clip",
    "path": "/Users/arach/Library/Application Support/Talkie/Tray/clips/Talkie Screen Clip - 2026-06-13 16.40.12 - Region - 1440x900 - 9052eb56.mp4",
    "durationMs": 8241,
    "width": 1440,
    "height": 900,
    "captureMode": "region"
  }
}
```

`--path` output example:

```text
/Users/arach/Library/Application Support/Talkie/Tray/clips/Talkie Screen Clip - 2026-06-13 16.40.12 - Region - 1440x900 - 9052eb56.mp4
```

### 3.4 Exit codes

| Exit | Meaning |
| --- | --- |
| `0` | Success. For `windows`, a valid empty list is still success. |
| `1` | CLI usage/argument error, invalid JSON, or local filesystem/open/reveal failure. |
| `2` | Talkie.app `:8766` unreachable or TalkieAgent XPC unavailable. |
| `3` | Authorization/pairing failure (`401`/`403`, missing required capability). |
| `4` | Permission or target failure: Screen Recording permission missing, target disappeared, ambiguous window. |
| `5` | Recording lifecycle conflict: already recording, not recording, recording id mismatch. |
| `6` | Native record/stop/write failure after route accepted. |

### 3.5 Preframe usage target

After the CLI exists, Preframe should replace Action's current `record-region` / stop-file path in `/Users/arach/dev/preframe/scripts/capture-guided-tour.mjs` with this shape:

```js
const windows = JSON.parse(await $`talkie capture windows --bundle ${CHROME_BUNDLE_ID} --json`.text());
const chromePid = browser.process()?.pid;
const target = windows.windows.find((w) => w.pid === chromePid) ?? windows.windows.find((w) => w.isFrontmost);
if (!target) throw new Error('No Chrome capture target');

const started = JSON.parse(await $`talkie capture record --window ${target.windowID} --pid ${target.pid} --quality agent --json`.text());
try {
  await driveTour(page);
} finally {
  const stopped = JSON.parse(await $`talkie capture stop --recording-id ${started.recordingId} --json`.text());
  console.log(stopped.clip.path);
}
```

If window capture is not stable enough on day one, use `--region x,y,w,h` with the Playwright-owned Chrome window frame returned by `talkie capture windows`; that still avoids hotkey simulation and old-recording polling.

## 4. PR plan for fastest path

### PR 1 — Native Agent automation start/stop primitives

Owner: macOS Agent/native owner.

Files:

- `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/CaptureSupervisionController.swift` (new)
- `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingController.swift`
- `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingService.swift`
- `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenshotService.swift`
- `apps/macos/TalkieAgent/TalkieAgent/Services/TalkieAgentXPCService.swift`
- `apps/macos/TalkieKit/Sources/TalkieKit/Capture/CaptureRecordingAutomation.swift` (new DTOs)
- `apps/macos/TalkieKit/Sources/TalkieKit/XPCProtocols.swift`

Work:

1. Add codable DTOs in TalkieKit or Agent-local JSON structs for capture targets, start options, state, and stop clip metadata.
2. Add `listCaptureWindows(reply:)`, `startScreenRecording(requestJSON:reply:)`, `stopScreenRecording(requestJSON:reply:)`, and optionally `getScreenRecordingState(reply:)` to `TalkieAgentXPCServiceProtocol`.
3. Extend `ScreenshotService.listWindows()` to include display metadata, z-order/frontmost, and stable `frame` fields.
4. Add explicit target resolution in `ScreenRecordingService`:
   - `resolveRegionTarget(rect:displayID:)` can wrap current `regionTarget(for:)` (`ScreenRecordingService.swift:328-357`).
   - `resolveWindowTarget(windowID:pid:bundleID:title:)` should find exact `SCWindow` from `SCShareableContent`; fail loudly on mismatch.
   - `resolveDisplayTarget(displayID:)` should map to `.fullscreen(SCDisplay)`.
5. Add `CaptureSupervisionController` (border pulse + corner HUD, Action-parity, `sharingType = .none`). Wire from `startResolvedRecording` when `presentation.supervision == true`.
6. Add `ScreenRecordingController.startAutomationRecording(request:) -> CaptureRecordingStartResponse` by reusing `startResolvedRecording`, skipping selection HUD/countdown, with supervision **on by default**.
7. Change/add `stopAutomationRecording(recordingId:)` that returns stored tray clip metadata. Keep existing UI `stopRecording()` as a wrapper.
8. Update `promptForLocalClientAccess` in `TalkieServer.swift` for capture-specific pairing copy when `desktop.capture.record` is in the capability list.
9. Keep root-cause semantics: no synthetic hotkeys, no manifest polling as the route's primary result.

Acceptance before HTTP/CLI:

- A test harness or temporary debug invocation can call XPC `startScreenRecording` with a region, sleep, call `stopScreenRecording`, and receive an existing `.mp4` path.
- Existing Hyper+R UI path still records/stops.

### PR 2 — `:8766` authenticated capture routes

Owner: Talkie.app bridge/native owner.

Files:

- `apps/macos/Talkie/Services/TalkieServer.swift`
- `apps/macos/TalkieKit/Sources/TalkieKit/XPCProtocols.swift` if shared DTOs land there.

Work:

1. Add `desktop.capture.record` to `LocalBridgeCapability` and supported capabilities.
2. Add `requiredLocalClientCapability` mappings:
   - `GET /capture/windows` → `desktop.windows.read`
   - `POST /capture/record/start` → `desktop.capture.record`
   - `POST /capture/record/stop` → `desktop.capture.record`
   - optional `GET /capture/record/state` → `desktop.capture.record`
3. Add route cases in `processRequest(...)` next to screenshot routes.
4. Add handlers that validate JSON, call the new XPC methods through `callAgent(...)`, and return the JSON envelopes above.
5. Add route-level timeouts long enough for stop finalization and short enough not to hang a CLI. Existing screenshot XPC calls use 8s (`TalkieServer.swift:3290-3323`); stop may need 15-30s for writer finalization.

Acceptance:

```bash
# with a trusted local client signer
GET  http://127.0.0.1:8766/capture/windows
POST http://127.0.0.1:8766/capture/record/start '{"target":{"kind":"region","rect":{"x":200,"y":120,"width":640,"height":480}}}'
POST http://127.0.0.1:8766/capture/record/stop '{}'
```

### PR 3 — CLI trusted local client helper + `talkie capture` command group

Owner: CLI/package owner with native review.

Files:

- `packages/npm/cli/src/commands/capture.ts` (new)
- `packages/npm/cli/src/cli.ts`
- `packages/npm/cli/src/local-client.ts` or `packages/npm/cli/src/talkie-server-client.ts` (new)
- `packages/npm/cli/package.json`
- CLI docs/README as appropriate

Work:

1. Implement or centralize the `:8766` trusted local client pairing/signing flow. Current CLI only has simple bridge bearer-token helpers for `:8765` and doctor fetches from `:8766` (`packages/npm/cli/src/commands/app.ts:144-185`, `app.ts:390-447`); it does not sign trusted local client requests.
2. On first use, request capabilities `desktop.windows.read` and/or `desktop.capture.record` via `POST /local-clients/request-access` (existing server route at `TalkieServer.swift:755-756`, request handling at `TalkieServer.swift:895-1079`).
3. Add `talkie capture windows`, `talkie capture record`, and `talkie capture stop` with flags and exit codes above.
4. Register the command in `packages/npm/cli/src/cli.ts` next to `registerCapturesCommand`.
5. Ensure source and installed binary expose the same commands. The prior audit found source help already lists `talkie captures`, but the installed binary may lag (`docs/cli-capture-audit.codex.md`).

Acceptance:

```bash
talkie capture windows --json
talkie capture record --region 200,120,640,480 --quality agent --max-duration 10 --json
sleep 3
talkie capture stop --json
```

### PR 4 — Preframe trial integration

Owner: Preframe automation owner.

Files outside this repo:

- `/Users/arach/dev/preframe/scripts/capture-guided-tour.mjs`

Work:

1. Replace `ACTION_ROOT/native/engine/scripts/run-app-host.sh record-region` with `talkie capture ...` behind an env switch such as `CAPTURE_TOOL=talkie`.
2. Prefer `talkie capture windows --bundle com.google.Chrome --json` + pid matching against Playwright's browser process.
3. Fall back to `--region` using the selected window frame if window-target recording has any ScreenCaptureKit edge cases.
4. Persist Talkie's returned `.mp4` path into Preframe's capture manifest.

## 5. Blockers and minimal native changes

Current blockers for CLI-triggered recording:

1. **No `:8766` recording routes.** `TalkieServer` has screenshot routes only (`apps/macos/Talkie/Services/TalkieServer.swift:840-888`).
2. **No XPC recording methods.** `TalkieAgentXPCServiceProtocol` has screenshot methods but no screen-record start/stop (`apps/macos/TalkieKit/Sources/TalkieKit/XPCProtocols.swift:113-135`).
3. **Current start APIs are selection/UI-first.** Public `ScreenRecordingController.startRecording(mode:)` always calls `ScreenRecordingService.selectTarget(mode:)`, which can show `ScreenCaptureOverlay` for region/window (`ScreenRecordingController.swift:54-76`, `ScreenRecordingService.swift:256-271`, `ScreenRecordingService.swift:378-411`).
4. **Private resolved-target start.** The useful lower-level `startResolvedRecording(target:mode:)` is private and also activates UI feedback (`ScreenRecordingController.swift:244-273`).
5. **Stop discards the result path.** `stopRecording()` stores the clip but returns `Void` (`ScreenRecordingController.swift:128-195`).
6. **No first-class all-window XPC enumeration on `:8766`.** Agent bridge has `/windows`, and Agent XPC has `listClaudeWindows`, but `:8766` only exposes `/windows/claude` today (`TalkieServer.swift:840-849`; XPC protocol at `XPCProtocols.swift:115-117`).
7. **CLI cannot sign trusted local requests yet.** Current CLI has no `x-talkie-*` signer despite server support.

Minimal native change that removes the blocker:

- Add explicit target resolution (`region`, `windowID`, `displayID`) in `TalkieAgent`.
- Add a non-interactive `startAutomationRecording` path that skips selection HUD/countdown and enables supervision overlays by default (`sharingType = .none` — visible to user, excluded from capture).
- Add metadata-returning `stopAutomationRecording` that returns `AgentLiveTrayStoredClip.fileURL` and related metadata.
- Expose those over XPC and then `:8766` with `desktop.capture.record`.

This is the root-cause fix. Simulating Hyper+R or polling old tray clips would remain flaky because it couples automation to user hotkeys, overlays, focus, and prior recording history.

## 6. Smoke test script

After PRs 1-3, an agent should be able to prove the full trigger with this script. It starts a new explicit region recording, writes visible timing metadata, stops, verifies the returned `.mp4` exists, and prints JSON for Preframe.

```bash
#!/usr/bin/env bash
set -euo pipefail

REGION="${TALKIE_CAPTURE_REGION:-200,120,640,480}"
DURATION="${TALKIE_CAPTURE_DURATION:-3}"

echo "[talkie-smoke] windows (best effort)" >&2
talkie capture windows --json >/tmp/talkie-capture-windows.json || true

echo "[talkie-smoke] start region ${REGION}" >&2
START_JSON="$(talkie capture record --region "$REGION" --quality agent --max-duration 15 --json)"
echo "$START_JSON" | jq . >&2
REC_ID="$(echo "$START_JSON" | jq -r '.recordingId')"

sleep "$DURATION"

echo "[talkie-smoke] stop ${REC_ID}" >&2
STOP_JSON="$(talkie capture stop --recording-id "$REC_ID" --json)"
echo "$STOP_JSON" | jq . >&2
CLIP_PATH="$(echo "$STOP_JSON" | jq -r '.clip.path')"

test -n "$CLIP_PATH"
test -f "$CLIP_PATH"
test "${CLIP_PATH##*.}" = "mp4"

printf '{"ok":true,"path":%s,"bytes":%s}\n' \
  "$(jq -Rn --arg p "$CLIP_PATH" '$p')" \
  "$(stat -f %z "$CLIP_PATH")"
```

One-liner variant:

```bash
START=$(talkie capture record --region 200,120,640,480 --quality agent --max-duration 10 --json) && RID=$(echo "$START" | jq -r .recordingId) && sleep 3 && STOP=$(talkie capture stop --recording-id "$RID" --json) && PATH_MP4=$(echo "$STOP" | jq -r .clip.path) && test -f "$PATH_MP4" && echo "$STOP"
```

If routes are initially stubbed behind a feature flag, keep the same command shape and return deterministic `501` JSON until the native path is enabled:

```json
{
  "ok": false,
  "code": "feature_disabled",
  "error": "Capture recording API is compiled but disabled",
  "requiredFeatureFlag": "captureRecordAPI"
}
```

A stub smoke then proves auth/routing without pretending recording works:

```bash
talkie capture windows --json >/dev/null && \
talkie capture record --region 200,120,640,480 --json 2>err.log; \
grep -q 'captureRecordAPI\|recordingId' err.log
```
