# Audit: CLI-driven screen recording (`talkie capture record`) — parity with Action

> **Canonical spec**: [TLK-029 — Agent-Initiated Screen Capture](specs/tlk-029-agent-initiated-screen-capture.md)

Requested by: operator (preframe tour capture parity). Companion to
`~/dev/action/docs/cli-capture-audit.agent.md`.
Scope: what it takes to start/stop a region/window/display recording from the
terminal, list recent tray clips, and return paths.
Author: talkie-card-x-aq0dvb (project-native agent). Date: 2026-06-13.

## TL;DR

- **The "list clips / return paths" half is already built — it's a publish gap, not a
  code gap.** `packages/npm/cli/src/commands/captures.ts` already enumerates tray
  clips from `~/Library/Application Support/Talkie/Tray/clips/` (manifest + files) and
  supports `--kind clip --source tray --path`. The installed `talkie` (2.5.23) predates
  it. **Shipping the current CLI closes this half immediately** — no new code.
- **The "trigger a recording" half is the real gap, but the native engine is already
  complete.** `ScreenRecordingService.shared.startRecording(target:) -> Bool` and
  `stopRecording() -> (url,width,height,target)?`
  (`apps/macos/Talkie/Services/ScreenRecording/ScreenRecordingService.swift:459,576`)
  do headless region/window/fullscreen capture *given a resolved target*, and persist
  to `Tray/clips` via `ClipTray` + `VideoClipStorage`. The only UI-coupled piece is the
  interactive region/window **selection overlay** — a CLI path must bypass it by taking
  an explicit rect / window-id / display index.
- **Transport is the key difference from Action.** Action shells out to
  `run-app-host.sh` with a file-signal lifecycle. Talkie's natural transport is the
  **already-running app's `:8766` HTTP server**, using the **trusted-local-client
  (P-256 ECDSA signed) auth** the screenshot endpoints already use
  (`TalkieServer.swift`). No `/record` endpoint exists yet — that's the one native add.
- **The CLI auth lift is small: a TS signer already exists.**
  `apps/macos/TalkieServer/src/bridge/talkie-local-client.ts` signs `:8766` requests
  (P-256, headers `X-Talkie-Client-ID/Timestamp/Nonce/Body-SHA256/Signature`, auto
  enroll via `POST /local-clients/request-access`). The npm CLI just needs to reuse it;
  today `app.ts:bridgeFetch` only does the `:8765` Bearer path and **cannot** call the
  gated `:8766` routes.

## Architecture comparison

| Concern | Action | Talkie |
|---|---|---|
| Native capture verbs exist? | Yes (`ActionHostMain`) | Yes (`ScreenRecordingService`) |
| Transport | shell → `run-app-host.sh` | HTTP `:8766` to the running app |
| Auth | none (local script, auto-builds) | P-256 trusted local client (already gates screenshots) |
| Lifecycle | `--stop-file` / `--finished-file` markers | stateful recorder singleton; needs start + stop endpoints |
| List clips → paths | n/a | **already shipped** in `captures.ts` |
| CLI surface | none (`action capture …` missing) | `talkie captures` exists; `talkie capture record` missing |
| TS client to reuse | needs new `host.ts` | **`talkie-local-client.ts` already exists** |

Net: Talkie is *ahead* of Action on listing + has a ready signer, but *behind* on the
trigger endpoint. The work is narrower than Action's because the host transport and
auth already exist.

## What's missing (the gaps)

1. **No HTTP trigger on `:8766`.** Routes stop at `/screenshot/*`, `/companion/*`,
   `/windows/claude`. No `/capture/record/*`.
2. **Headless start is overlay-coupled.** `ScreenRecordingController.startRecording(mode:)`
   runs interactive selection (`ScreenCaptureOverlay`). The *service* method already
   takes a resolved `ScreenRecordingTarget` (`.fullscreen(SCDisplay)` /
   `.region(SCDisplay,CGRect)` / `.window(SCWindow)`), so a headless adapter that
   resolves a target from explicit args is thin, not a rewrite.
3. **No `desktop.record` capability.** Mirror `desktop.screenshot.read`
   (`LocalBridgeCapability`, `TalkieServer.swift:188`) + add the route→capability mapping
   in `requiredLocalClientCapability` (`:613`).
4. **CLI can't sign `:8766` requests.** `app.ts:bridgeFetch` is Bearer-only. Reuse the
   existing `talkie-local-client.ts` signer.
5. **No `capture` command group.** Only the `captures` *listing* exists (`cli.ts:48`).
6. **No headless target naming.** Need `--region x,y,w,h`, `--window <id>`,
   `--display <n>`. Window enumeration is cheap — `desktop.windows.read` /
   `/screenshot/window/:id` and the `SCWindow` selectors already exist.

## One design decision for the owner

The recorder is a **stateful singleton** (one active recording at a time). Pick the
stop model:
- **(a) Singleton (recommended):** `start` takes no id; `stop` stops the current
  recording and returns the saved clip path. Matches the native model and the single
  HUD pill. Simplest.
- **(b) Stateless:** `start` returns a `recordingId`; `stop <id>`. Only worth it if we
  ever allow concurrent recordings (we don't today).

Also confirm transport: **signed `:8766` HTTP** (can return the saved path
synchronously) vs a `talkie://` URL scheme (fire-and-forget, **cannot** return paths —
rejected for that reason).

## Minimal PR plan

### PR 0 — Publish the current CLI (today, zero code)
Ship `packages/npm/cli` so `talkie captures` lands. Immediately closes the list/return-
paths half and the version-skew complaint:
```
talkie captures --kind clip --source tray --limit 5 --path   # recent tray clip paths
talkie captures <id> --json                                  # one clip, with metadata
```

### PR 1 — Native: headless recorder + `:8766` endpoints
`ScreenRecording/ScreenRecordingService.swift` (or a small `…Controller` adapter):
- Add `startRecording(spec:)` that resolves a `ScreenRecordingTarget` from explicit
  inputs (display index → `SCDisplay`; rect → `.region`; window id → `SCWindow`) with
  **no overlay**, then calls the existing `startRecording(target:)`.
`Services/TalkieServer.swift`:
- `POST /capture/record/start` — body `{mode, x,y,w,h | windowId | display, fps?, scale?}`
  → `{ok, mode, target}` (or `{ok, recordingId}` under model b).
- `POST /capture/record/stop` → `{ok, path, width, height, durationMs}` (the
  `ClipTray`-persisted URL, so it also appears in `talkie captures`).
- `GET /capture/record/status` → `{recording, target, startedAt}`.
- Add `LocalBridgeCapability.desktopRecord = "desktop.record"` + map the three routes in
  `requiredLocalClientCapability`. Reuse `authorizeLocalClientIfNeeded`.

Verify:
```
# with a trusted client enrolled:
curl -sX POST :8766/capture/record/start -d '{"mode":"region","x":0,"y":0,"w":800,"h":600}'  # +signed headers
curl -sX POST :8766/capture/record/stop
talkie captures --kind clip --source tray --limit 1 --path     # the new clip
```

### PR 2 — CLI: signer + `capture` command group
- `packages/npm/cli/src/talkie-server-client.ts` (new): port/share
  `talkie-local-client.ts` (same identity file under `…/Talkie/Bridge`). Auto-enroll on
  first 401 via `/local-clients/request-access` (user approves once in-app).
- `packages/npm/cli/src/commands/capture.ts` (new):
  - `talkie capture record (--region x,y,w,h | --window <id> | --display <n>) [--duration <s>]`
  - `talkie capture stop` → prints saved clip path (and `--json`)
  - `talkie capture status`
  - `talkie capture windows` → enumerate targets `{windowId,title,app,frame}` (via
    `desktop.windows.read`)
- `cli.ts`: register `capture`; extend help. `bin: talkie` already exists.

Verify:
```
bun packages/npm/cli/src/index.ts capture windows --json
bun packages/npm/cli/src/index.ts capture record --window <id> --duration 8
bun packages/npm/cli/src/index.ts capture stop          # prints the path
bun run --cwd packages/npm/cli typecheck
```

### PR 3 — preframe/tour parity (separate repo), after PR 1
Tour driver: `talkie capture windows` → pick target → `talkie capture record --window
<id>` → `talkie capture stop` → read returned path. No AppleScript/host-script dance.

### Sequencing
PR 0 ships the list half now. PR 1 is the only native work and unblocks triggering
(preframe can hit signed `:8766` directly even before PR 2). PR 2 is the ergonomic
`talkie capture` surface. PR 3 is the tour cutover.

### Fastest stopgap (today, zero native code)
Publish PR 0 for listing. For *triggering* there is no safe zero-code path — the only
trigger today is the Hyper+R HUD (interactive). Synthesizing the hotkey is fragile and
**not** recommended; wait for PR 1.

## Owner / next move
Talkie-native work — talkie-card can own PR 0/1/2 once greenlit. Operator decision
needed: (1) confirm signed-`:8766`-HTTP transport, (2) pick the singleton stop model
(a). PR 3 lands in the preframe/action repo and depends on PR 1.
