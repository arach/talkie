# Talkie CLI capture/recording audit

> **Canonical spec**: [TLK-029 — Agent-Initiated Screen Capture](specs/tlk-029-agent-initiated-screen-capture.md)

Date: 2026-06-13
Author: talkie-card-d-11sq21 (Codex)
Scope: audit + PR plan only; no implementation.
Reference: `~/dev/action/docs/cli-capture-audit.agent.md`.

## TL;DR

- **Listing is present in source, absent in the installed built CLI.**
  `packages/npm/cli/src/commands/captures.ts` registers `talkie captures` and reads
  database assets, library captures, and tray manifests/files, including
  `~/Library/Application Support/Talkie/Tray/clips/`. The installed local binary is
  a stale `dist/index.js`: `talkie --version` prints `0.4.6`, but `talkie captures`
  exits with `error: unknown command 'captures'`. `/Applications/Talkie.app` is
  `2.5.23` build `16`, so there is also app-vs-CLI version ambiguity.
- **Triggering is not exposed anywhere as a headless CLI/API.** The native recorder
  exists in TalkieAgent (`ScreenRecordingService` + `ScreenRecordingController`) and
  is used by Hyper+R, but current start flows are HUD/overlay-driven and current stop
  persists the clip without returning the stored path.
- **The correct transport is signed `:8766` HTTP through Talkie.app, not hotkey
  synthesis and not Action's file-signal host script.** Talkie already has a trusted
  local-client auth model for screenshot routes. Add `desktop.record` + new capture
  routes, then have the CLI use the existing P-256 request signer pattern.
- **Minimal surface:** ship `talkie captures`; add `talkie capture record`,
  `talkie capture stop`, `talkie capture status`, and `talkie capture windows`.
- **Visibility is part of security:** CLI/automation recordings must show
  `CaptureSupervisionController` (border + HUD) by default. Overlays use
  `sharingType = .none` so louder affordances do not leak into the `.mp4`.
  See `docs/cli-capture-record-trigger.codex.md` §2.4.

## 1. What exists today

### Source CLI: listing exists

`packages/npm/cli/src/commands/captures.ts`:

- Registers `captures [id]` with filters and file actions at lines `102-135`.
- Defines tray/library roots at lines `84-91`, including
  `TRAY_CLIPS_DIR = ~/Library/Application Support/Talkie/Tray/clips`.
- Collects captures from database JSON, tray manifests, library files, tray files,
  and legacy buffer dirs at lines `138-169`.
- Reads `manifest.json` entries for tray screenshots/clips at lines `262-294`.
- `--path` prints raw capture file paths at lines `397-401`.

`packages/npm/cli/src/cli.ts` imports and registers the command at lines `6` and
`48`, and source help includes `talkie captures` at line `34`.

Local verification from the source runner works:

```bash
bun packages/npm/cli/src/index.ts captures --kind clip --source tray --limit 3 --path
# /Users/arach/Library/Application Support/Talkie/Tray/clips/Talkie Screen Clip - ... .mp4
```

### Installed CLI: listing is not shipped

Observed locally:

```text
$ command -v talkie
/Users/arach/.bun/bin/talkie -> ../install/global/node_modules/@talkie/cli/dist/index.js

$ talkie --version
0.4.6

$ talkie captures --kind clip --source tray --limit 1 --path
error: unknown command 'captures'
```

`packages/npm/cli/dist/index.js` was built before the `captures` command; its help
text says only "dictations, and workflows" and does not include captures. This is a
publish/build artifact skew, not a missing source feature.

### Tray clips exist and are first-class app data

There are two compatible tray readers/writers:

- Main app tray model: `apps/macos/Talkie/Services/Tray/Data/ClipTray.swift`
  documents `~/Library/Application Support/Talkie/Tray/clips/manifest.json` at
  lines `5-8`, defines the directory at lines `16-20`, and the manifest URL at
  lines `146-148`.
- Agent-owned tray writer: `apps/macos/TalkieKit/Sources/TalkieKit/LiveTray/AgentLiveTrayAssetStore.swift`
  keeps the historical tray layout at lines `162-180`, stores clips via
  `storeClip` at lines `525-598`, and resolves `clipsDirectory` at lines `604-606`.

The Agent recording controller writes both live-tray clips and durable library
captures:

- `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingController.swift`
  calls `AgentLiveTrayAssetStore.shared.storeClip` at lines `159-171`.
- It then calls `AgentCaptureLibraryWriter.persistClip` at lines `172-184`.
- `AgentCaptureLibraryWriter.persistClip` copies to `~/Library/Application Support/Talkie/Videos/`
  through `VideoClipStorage.save` at lines `86-127` of
  `apps/macos/TalkieAgent/TalkieAgent/Services/Capture/AgentCaptureLibraryWriter.swift`.

### Hotkeys trigger capture, but are interactive

Defaults:

- Hyper+R is `defaultScreenRecordChord` in
  `apps/macos/Talkie/Models/TalkieAgentSettings.swift:265-269`.
- Hyper+4 is `defaultCaptureRegion` in the same file at lines `283-286`.
- `HotkeyRegistry` labels them as `screenRecordChord` and `captureRegion` at
  `apps/macos/Talkie/Models/HotkeyRegistry.swift:26-35` and maps defaults at
  lines `84-95`.

Registration and handling live in TalkieAgent:

- Screen recording chord registration: `apps/macos/TalkieAgent/TalkieAgent/App/AppDelegate.swift:1372-1396`.
- Direct screenshot defaults Hyper+3/4/5/6: lines `1413-1446`.
- Hyper+R stop/start behavior and HUD dispatch: lines `1464-1503`.

This is useful for humans, but not acceptable for automation: it depends on global
keyboard focus, HUD selection, overlays, and timing.

### Native screen recording engine exists

`apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingService.swift`:

- Defines `ScreenRecordingTarget` for fullscreen/region/window at lines `62-74`.
- Interactive target selection goes through `selectTarget(mode:)` at lines `256-272`.
- Region/window selection still invokes `ScreenCaptureOverlay` at lines `378-407`.
- A non-interactive primitive already exists: `startRecording(target:)` at lines
  `416-574` builds the `SCContentFilter`, `SCStreamConfiguration`, and `AVAssetWriter`.
- `stopRecording()` returns temp URL, dimensions, and target at lines `578-609`.

`ScreenRecordingController` is the user-flow orchestrator:

- `startRecording(mode:)` selects interactively, then calls a private
  `startResolvedRecording` at lines `56-76` and `244-274`.
- `stopRecording()` persists the returned temp file to tray/library at lines
  `128-195`, but returns `Void`, so an HTTP caller cannot currently get the final
  clip path.

Root cause for CLI triggering: the low-level engine is usable, but the public
controller/API surface is interactive and does not return the stored artifact.

### Existing `:8766` HTTP routes and auth

`apps/macos/Talkie/Services/TalkieServer.swift`:

- TalkieServer listens on port `8766` and forwards to TalkieAgent via XPC
  (`lines 5-6`, `260-347`).
- Trusted local-client capabilities include `desktop.windows.read` and
  `desktop.screenshot.read` at lines `188-217`.
- Route capability mapping gates `/windows/claude`, `/screenshot/terminals`,
  `/screenshot/display`, and `/screenshot/window/:id` at lines `613-640`.
- Signed request verification checks `X-Talkie-Client-ID`, timestamp, nonce,
  SHA-256 body hash, and P-256 signature at lines `643-704`.
- Existing screenshot/window routes are wired at lines `840-883`; handlers call Agent
  XPC methods at lines `3270-3335` and `3355-3375`.

There is **no** `/capture/record/*` route today.

The signer already exists in TypeScript:

- `apps/macos/TalkieServer/src/bridge/talkie-local-client.ts` requests the current
  trusted capabilities at lines `7-20`.
- `talkieServerFetch` signs and retries after access request at lines `30-40`.
- P-256 signing headers are built at lines `43-72`.
- Access is requested from `/local-clients/request-access` at lines `75-107`.
- Identity is persisted in `~/Library/Application Support/Talkie/LocalBridge/` at
  lines `109-144`.

The npm CLI does **not** use this signer yet. `packages/npm/cli/src/commands/app.ts`
uses a bearer token file for the older `:8765` bridge (`lines 10-18`, `144-185`).
That path cannot call the trusted `:8766` screenshot/recording routes.

## 2. Capture triggering gap

Today Talkie has:

| Capability | Status | Notes |
|---|---:|---|
| List recent tray/library clips | Source-only | `talkie captures` exists in source, stale `dist` lacks it. |
| Start recording from CLI | Missing | No `talkie capture` command and no HTTP/XPC start route. |
| Stop recording from CLI | Missing | Controller stop returns no stored path. |
| Record explicit region | Native primitive exists | `ScreenRecordingService.regionTarget(for:)` and `startRecording(target:)`; no route. |
| Record explicit window | Native primitive exists | Can resolve `SCWindow` by ID; no headless public API. |
| Record display | Native primitive exists | Fullscreen target wraps `SCDisplay`; no explicit display selector route. |
| Enumerate automation windows | Partial | Agent has `ScreenshotService.listWindows()` on `:8767` Agent routes, but signed `:8766` only exposes `/windows/claude`. |
| Trusted HTTP auth | Exists | Add `desktop.record`; reuse signer. |

The correct fix is to expose the already-working native engine through a headless,
authenticated app route. Do **not** synthesize Hyper+R/Hyper+4: that would preserve
the UI timing/focus failure mode instead of solving the root cause.

## 3. What native surface should the CLI call?

Recommended path:

```text
talkie CLI
  → signed HTTP http://127.0.0.1:8766/capture/...
  → Talkie.app TalkieServer auth/capability gate
  → XPC to TalkieAgent
  → ScreenRecordingController headless API
  → ScreenRecordingService.startRecording(target:)
  → AgentLiveTrayAssetStore.storeClip + AgentCaptureLibraryWriter.persistClip
```

Why this route:

1. **Agent owns the always-on capture hotkeys and tray writes.** The Agent controller
   already handles metadata sampling, stop overlays, tray persistence, and durable
   library persistence.
2. **Talkie.app already owns signed local-client trust on `:8766`.** Use the same
   model that protects screenshots instead of adding a second unaudited auth scheme.
3. **`ScreenRecordingService.startRecording(target:)` is already the right primitive.**
   The missing part is a headless target resolver and a controller method that returns
   the persisted clip.

Avoid direct `:8767` Agent routes for this PR unless its auth story is tightened first.
`BridgeServer` advertises auth protection, but the visible router only extracts an
`x-talkie-client` identity header (`apps/macos/TalkieAgent/TalkieAgent/Services/BridgeRouter.swift:101-103`).
The signed `:8766` path is the safer existing contract.

### New native route/API requirements

Add these to `TalkieServer.swift`:

- `POST /capture/record/start`
- `POST /capture/record/stop`
- `GET /capture/record/status`
- `GET /capture/windows` or `GET /windows` for all visible capture targets

Add capability:

- `LocalBridgeCapability.desktopRecord = "desktop.record"`
- Gate start/stop/status on `desktop.record`.
- Gate all-window enumeration on `desktop.windows.read`.

Add Agent XPC methods in `TalkieAgentXPCServiceProtocol` and `TalkieAgentXPCService`:

- `startScreenRecording(specJSON: Data, reply: (Data?, String?) -> Void)`
- `stopScreenRecording(reply: (Data?, String?) -> Void)`
- `screenRecordingStatus(reply: (Data?, String?) -> Void)`
- optionally `listCaptureWindows(reply:)` if TalkieServer should not duplicate window JSON mapping.

Add Agent headless controller APIs:

- Resolve target spec to `ScreenRecordingTarget` without `ScreenCaptureOverlay`:
  - region: `x,y,width,height` + optional display selector
  - window: `CGWindowID` exact match
  - display: `displayID` or stable display index
- Start by calling the existing `startResolvedRecording(target:mode:)` path, but make
  it public/internal for headless XPC callers.
- Stop by reusing current persistence, but return JSON containing at least the live
  tray file path, durable library file path if created, dimensions, duration, mode,
  app/window/display metadata, and id.

## 4. Proposed CLI surface

### `talkie captures` — list existing assets

Ship the existing source command. Keep it plural and read-only.

Examples:

```bash
talkie captures --kind clip --source tray --limit 5
talkie captures --kind clip --source tray --limit 1 --path
talkie captures <id-prefix> --json
talkie captures --app "Chrome" --since 1d
```

### `talkie capture windows` — enumerate targets

Purpose: let external drivers (Playwright, browser automation, preframe tour drivers)
select an exact window before recording.

Suggested flags:

```bash
talkie capture windows [--app <name-or-bundle>] [--pid <pid>] [--json]
```

JSON row shape:

```json
{
  "windowID": 12345,
  "pid": 678,
  "bundleID": "com.google.Chrome",
  "appName": "Google Chrome",
  "title": "Tour Page",
  "bounds": { "x": 0, "y": 38, "width": 1440, "height": 900 },
  "displayID": 1,
  "displayName": "Studio Display",
  "isOnScreen": true,
  "zIndex": 0
}
```

Current Agent `ScreenshotService.listWindows()` already has most fields
(`windowID`, `pid`, `bundleId`, `appName`, `title`, `layer`, `bounds`, `isOnScreen`) at
`apps/macos/TalkieAgent/TalkieAgent/Services/ScreenshotService.swift:154-173`.
Add display and z-order if practical.

### `talkie capture record` — start recording

Suggested flags:

```bash
talkie capture record --region <x,y,w,h> [--display <id-or-index>] [--json]
talkie capture record --window <windowID> [--json]
talkie capture record --display <id-or-index> [--json]
talkie capture record ... --duration <seconds> [--path]
```

Notes:

- Exactly one of `--region`, `--window`, or `--display` is required.
- `--duration` is a CLI convenience: start, sleep, stop, print final path.
- `--path` should print the stored clip path after stop when `--duration` is supplied.
- Without `--duration`, print a compact JSON/plain status saying recording started and
  tell the user to run `talkie capture stop`.

Optional later flags:

```bash
--quality agent|balanced|archive
--system-audio
--microphone
--show-camera-bubble
```

These can initially follow shared settings; don't block v1 on per-command overrides.

### `talkie capture stop` — stop current singleton recording

```bash
talkie capture stop [--json] [--path]
```

Recommended response fields:

```json
{
  "ok": true,
  "id": "uuid",
  "path": "/Users/arach/Library/Application Support/Talkie/Tray/clips/....mp4",
  "libraryPath": "/Users/arach/Library/Application Support/Talkie/Videos/....mp4",
  "durationMs": 8123,
  "width": 1440,
  "height": 900,
  "captureMode": "window",
  "windowTitle": "Tour Page",
  "appName": "Google Chrome"
}
```

Use the current singleton model. Concurrent recordings are not supported by the native
state machine (`ScreenRecordingService.State` is `idle|recording` at lines `190-196`),
so adding recording IDs now would be ceremony without capability.

### `talkie capture status`

```bash
talkie capture status [--json]
```

Return `{recording, startedAt, elapsedMs, mode, target}`.

## 5. Transport/auth comparison with Action

| Concern | Action audit | Talkie recommendation |
|---|---|---|
| Native entrypoint | `native/engine/scripts/run-app-host.sh <verb>` | Running Talkie.app `:8766` HTTP gateway |
| Native engine | Host verbs already parse CLI flags | Agent `ScreenRecordingService.startRecording(target:)` already records; headless API missing |
| Stop lifecycle | File markers (`--stop-file`, `--finished-file`) | Stateful singleton: `POST start`, `POST stop`, `GET status` |
| Auth | Local shell script; no network auth | P-256 trusted local-client headers + capability grants |
| App lifecycle | Script auto-builds/launches host | Requires Talkie.app/TalkieAgent running; CLI can optionally open app then retry |
| Window targeting | Needs `list-windows` + `--window-id` to avoid heuristics | Add `talkie capture windows`; record by exact `windowID` |
| Artifact return | Host writes output path | Stop route returns tray/library path; `talkie captures` lists it after |

The key difference: Action should wrap its host script; Talkie should **not** invent a
host script. Its stable boundary is the already-running app/agent pair plus signed
local HTTP.

## 6. Minimal PR sequence

### PR 0 — Ship existing `talkie captures`

**Owner:** CLI/package owner.
**Purpose:** close listing/version-skew gap immediately.

Files:

- `packages/npm/cli/dist/index.js` — rebuild from current source.
- `packages/npm/cli/package.json` — bump package version if publishing (`0.4.7` or next).
- Release/publish scripts as needed.

Acceptance:

```bash
talkie captures --kind clip --source tray --limit 1 --path
# prints a tray clip path, not "unknown command"
```

### PR 1 — Agent headless recording API

**Owner:** TalkieAgent/native capture owner.
**Purpose:** make the existing recorder controllable without HUD/overlay and return
stored artifact metadata.

Files:

- `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingService.swift`
  - Add explicit target resolution helpers for region/window/display specs.
  - Reuse `startRecording(target:)`; do not duplicate SCStream/AVAssetWriter logic.
- `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingController.swift`
  - Expose `startHeadlessRecording(target:)` or equivalent using the existing
    `startResolvedRecording` path.
  - Add `stopRecordingReturningClip()` or update the stop internals so XPC can return
    tray/library paths and metadata.
- `apps/macos/TalkieAgent/TalkieAgent/Services/TalkieAgentXPCService.swift`
  - Add XPC methods for start/stop/status and all-window enumeration.
- `apps/macos/TalkieKit/Sources/TalkieKit/XPCProtocols.swift`
  - Add protocol methods and JSON DTO docs.

Acceptance:

- Start explicit region via XPC helper in dev build.
- Stop returns the path in `~/Library/Application Support/Talkie/Tray/clips/`.
- `bun packages/npm/cli/src/index.ts captures --kind clip --source tray --limit 1 --path`
  sees the newly recorded clip.

### PR 2 — `:8766` capture routes + auth capability

**Owner:** Talkie macOS app/server owner.
**Purpose:** expose the headless Agent API to trusted local clients.

Files:

- `apps/macos/Talkie/Services/TalkieServer.swift`
  - Add `desktop.record` capability to `LocalBridgeCapability.supported`.
  - Gate `POST /capture/record/start`, `POST /capture/record/stop`, and
    `GET /capture/record/status` on `desktop.record`.
  - Add `GET /capture/windows` or `GET /windows` gated on `desktop.windows.read`.
  - Forward each route to the new Agent XPC methods.
- `apps/macos/TalkieServer/src/bridge/talkie-local-client.ts`
  - Add `desktop.record` to `REQUESTED_CAPABILITIES` for bridge/dev clients.

Acceptance:

- Unsigned request to `POST /capture/record/start` gets `401` with required capability.
- Signed trusted client can start/stop and receives the stored clip path.
- Existing screenshot routes continue to work.

### PR 3 — npm CLI `talkie capture` group

**Owner:** CLI/package owner.
**Purpose:** provide the requested command-line surface.

Files:

- `packages/npm/cli/src/talkie-server-client.ts` (new)
  - Port/reuse the signer from `apps/macos/TalkieServer/src/bridge/talkie-local-client.ts`.
  - Request `desktop.record`, `desktop.windows.read`, and existing screenshot caps as needed.
  - Use `http://127.0.0.1:8766` by default; optionally start Talkie.app and retry like
    `bridgeFetchWithAppStart` does.
- `packages/npm/cli/src/commands/capture.ts` (new)
  - `record`, `stop`, `status`, `windows` subcommands.
  - Parse `--region x,y,w,h`, `--window <id>`, `--display <id-or-index>`,
    `--duration`, `--path`, `--json`.
- `packages/npm/cli/src/cli.ts`
  - Register `capture` and update help text.
- `packages/npm/cli/SKILL.md`
  - Document `capture` vs `captures`.
- `packages/npm/cli/dist/index.js` and package version after build.

Acceptance:

```bash
talkie capture windows --json
talkie capture record --region 0,0,800,600 --duration 5 --path
talkie capture record --window <windowID>
talkie capture stop --path
talkie captures --kind clip --source tray --limit 1 --path
```

### PR 4 — External driver cutover (separate repo)

**Owner:** preframe/tour driver owner.
**Purpose:** replace hotkey/AppleScript-style capture with first-class Talkie CLI.

Flow:

```text
talkie capture windows --json
→ choose row by pid/title/bundle
→ talkie capture record --window <windowID>
→ run guided tour
→ talkie capture stop --path
```

This mirrors the Action audit's explicit-window targeting fix while using Talkie's
signed HTTP transport instead of Action's `run-app-host.sh`.

## 7. Open decisions

1. **Route name:** use `/capture/record/*` as requested, or shorter `/recording/*`?
   Recommendation: `/capture/record/*` to match the CLI namespace.
2. **All-window route:** add `GET /capture/windows` or promote `GET /windows` on
   `:8766` beyond `/windows/claude`? Recommendation: `GET /capture/windows` for CLI
   clarity; keep `/windows/claude` compatibility.
3. **Stop result path:** return both live tray path and durable library path when both
   are created. CLI `--path` should print the live tray path because that is what
   `talkie captures --source tray` lists immediately.
4. **Per-command audio/camera flags:** defer to existing shared settings in v1 unless
   a tour driver specifically needs overrides.

## 8. Fastest safe path

- Rebuild/publish the npm CLI now so `talkie captures` works.
- Do not automate Hyper+R as a stopgap. It is brittle by design.
- Implement PR 1 + PR 2 together if one native owner is doing the work; PR 3 can land
  after the signed route contract is stable.
