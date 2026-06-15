# Talkie CLI capture record lifecycle semantics

> **Canonical spec**: [TLK-029 — Agent-Initiated Screen Capture](specs/tlk-029-agent-initiated-screen-capture.md)

Requested by: operator (Scout addendum).
Scope: audit + lifecycle contract only; no implementation.
Author: talkie-cli-codex. Date: 2026-06-13.
Extends: `docs/cli-capture-record-trigger.codex.md`.

## TL;DR

`talkie capture record` must not only start a fresh MP4; it must guarantee the recording ends if the driving agent crashes, is killed, loses its broker/network path, or forgets to call stop.

Action/Preframe already solves this with `RecordingLease`: idempotent `stop`, a detached watchdog that watches the parent PID and max duration, and signal/fatal handlers that write a stop file (`/Users/arach/dev/preframe/scripts/recording-lease.mjs:1-9`, `recording-lease.mjs:53-119`). Talkie should provide the same lifecycle guarantees natively rather than relying on tray polling or hotkey simulation.

Current Talkie status:

- `TalkieAgent` has singleton recording state through `ScreenRecordingController.shared` and `ScreenRecordingService.shared` (`apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingController.swift:18-39`, `apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingService.swift:190-209`).
- `ScreenRecordingService` already has a hard-coded 5-minute safety timer (`ScreenRecordingService.swift:211-212`) that auto-stops through the controller (`ScreenRecordingService.swift:560-565`). This prevents infinite recordings today.
- That safety valve is not enough for CLI lifecycle semantics: it is not caller-tunable, not tied to a `recordingId`, not tied to a parent process, and the stop path currently returns `Void` after storing the clip (`ScreenRecordingController.swift:128-190`). If a CLI caller dies today, the clip can continue for up to 5 minutes and the caller has no direct way to recover the path except later listing/history.

Decision: first implementation should keep Talkie's recorder **singleton** but model each recording as a durable **session lease** with `recordingId`, owner metadata, idempotent stop, Agent-owned watchdogs, cached final stop result, and **supervision UI for the full lease duration**.

Supervision (`CaptureSupervisionController` border + HUD) must remain visible from `state: recording` until `stopped`/`failed`, including during max-duration and parent-PID watchdog stops. Dismissing supervision before `SCStream` stops is a lifecycle bug, not a UX preference. All supervision panels use `sharingType = .none` so they never appear in the captured clip.

## 1. Session model

### 1.1 Singleton now; session id anyway

Use a singleton active recording for the first PR because the native implementation already assumes one active `ScreenRecordingController.shared` / `ScreenRecordingService.shared` (`ScreenRecordingController.swift:20-21`, `ScreenRecordingService.swift:171-172`) and state is `idle/selecting/recording` or `idle/recording` rather than a collection (`ScreenRecordingController.swift:25-39`, `ScreenRecordingService.swift:190-196`).

Still mint a `recordingId` on every automation start. It is required for:

- idempotent start retries after HTTP response loss;
- guarded stop so one client does not stop another client's recording by accident;
- returning the same final clip on duplicate stop calls;
- future multi-session support without changing the CLI contract.

Recommended Agent-side active session record:

```swift
struct CaptureRecordingSession: Codable, Sendable {
    var recordingId: UUID
    var ownerClientId: String
    var ownerLabel: String?
    var idempotencyKey: String?
    var startedAt: Date
    var target: CaptureRecordingTarget
    var maxDurationSeconds: Double
    var lease: CaptureRecordingLease
    var state: State // starting | recording | stopping | stopped | failed
    var stopReason: StopReason?
    var finalResult: CaptureStopResult?
}
```

Only one `activeSession` is allowed initially. A small `recentCompletedSessions` cache keyed by `recordingId` and `idempotencyKey` should retain final stop results for at least a few minutes so a caller can retry `stop` after a timeout and receive the clip path.

### 1.2 Ownership

Ownership belongs to `TalkieAgent`, not the CLI process:

- Agent owns the `SCStream`, `AVAssetWriter`, temp MP4, live tray write, and library persistence.
- `Talkie.app` `:8766` owns auth/capability checks and forwards commands over XPC.
- CLI owns request signing, signal handling, and optional local watchdog fallback, but the recording must be safe even when the CLI process disappears.

The active session should store:

```json
{
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "owner": {
    "clientId": "talkie-cli:preframe",
    "label": "preframe guided tour",
    "pid": 93341,
    "parentPid": 92810,
    "host": "arachs-mac-mini-local"
  },
  "lease": {
    "maxDurationSeconds": 120,
    "parentPid": 92810,
    "stopOnParentExit": true,
    "heartbeatTTLSeconds": null
  }
}
```

Important: the `parentPid` must be the long-lived driving process, not the short-lived `talkie capture record` process. If Preframe shells out to `talkie capture record` and the CLI exits normally after printing JSON, watching the CLI PID would immediately stop a valid recording. Therefore the CLI should expose `--lease-parent-pid <pid>` and Preframe should pass `process.pid`.

### 1.3 Start idempotency

Add an optional `idempotencyKey` to `POST /capture/record/start` and `talkie capture record --idempotency-key <key>`.

Semantics:

- If the same trusted client repeats `start` with the same `idempotencyKey` while the session is active, return the existing `recordingId` and state instead of starting a second recording.
- If the same key completed recently, return `409 already_completed` with the final result pointer, or `200` with `state: "stopped"` if the contract wants fully idempotent start completion.
- If a different target/options are supplied with the same key, return `409 idempotency_conflict`.

This covers the case where the HTTP response is lost after Agent started recording.

## 2. Guaranteed stop paths

Every CLI-triggered session should have at least two stop paths, and preferably three:

1. explicit stop;
2. Agent-owned max-duration watchdog;
3. owner-death watchdog (`parentPid`) and/or heartbeat TTL;
4. CLI-side signal/fatal handler and detached watchdog as a defense-in-depth fallback.

### 2.1 Explicit `capture stop`

`talkie capture stop --recording-id <id>` calls signed `POST /capture/record/stop`.

Rules:

- Stop is idempotent.
- Stop may be called from `finally`, signal handlers, detached watchdogs, or manual operator cleanup.
- Stop must return the stored tray/library clip metadata once finalization succeeds.
- If a stop call loses its HTTP response while Agent is finalizing, a retry with the same `recordingId` must return the cached final result.

### 2.2 Mandatory `--max-duration`

`--max-duration <seconds>` must be part of the start request, not only a CLI timer.

Current native timer exists but is hard-coded:

- `ScreenRecordingService.maxDuration` is `300` seconds (`apps/macos/TalkieAgent/TalkieAgent/Services/ScreenRecording/ScreenRecordingService.swift:211-212`).
- The timer calls `ScreenRecordingController.shared.stopRecording()` (`ScreenRecordingService.swift:560-565`).

Required change:

- Make max duration a per-session automation option, bounded by an absolute Agent cap.
- Default CLI max should be conservative, e.g. 120 seconds for automation, unless the user passes a higher value.
- The Agent timer should call the same metadata-returning stop/finalize path as explicit stop with `stopReason: "max_duration"`.
- If the timer fires and the caller later runs `talkie capture stop --recording-id <id>`, return `ok: true`, `state: "stopped"`, `alreadyStopped: true`, and the cached clip metadata.

### 2.3 Parent-PID watchdog

Add a native Agent lease watcher:

```json
"lease": {
  "parentPid": 92810,
  "stopOnParentExit": true,
  "pollIntervalMs": 500
}
```

Agent checks `kill(parentPid, 0)` (or a Swift process-liveness helper) on a timer while the session is active. If the parent disappears, Agent calls the same stop/finalize path with `stopReason: "parent_exit"`.

Why Agent-owned rather than only CLI-owned:

- `talkie capture record` is usually a short-lived command. A CLI child watchdog can die with its process group unless carefully detached.
- Agent continues running independently and already owns the recorder.
- If the caller loses its broker/network path but the local parent process dies, Agent still stops without another CLI call.

Still add CLI defense-in-depth: `talkie capture record --lease-parent-pid <pid> --watchdog` can spawn a detached helper that sleeps until parent death/max duration and then calls `talkie capture stop --recording-id <id>`. This mirrors Action's detached watchdog pattern (`/Users/arach/dev/preframe/scripts/recording-lease.mjs:71-107`).

### 2.4 Heartbeat / disconnect policy

HTTP `:8766` requests are short-lived, so there is no persistent connection to observe after `record` returns. A caller disconnecting from Scout or losing external network is invisible to Talkie if the local driving process keeps running.

Recommended policy:

- Do not rely on HTTP connection lifetime for recording lifetime.
- Provide optional heartbeat semantics for callers that want network/process disconnect handling independent of PID:
  - `POST /capture/record/heartbeat { recordingId }`
  - start lease option `heartbeatTTLSeconds`.
  - If no heartbeat arrives before TTL, Agent stops with `stopReason: "heartbeat_timeout"`.
- Preframe does not need heartbeat if it passes `--lease-parent-pid process.pid` and `--max-duration`; parent death + max duration cover its crash/kill cases.

For the specific requirement “agent loses network,” the reliable Talkie guarantee is: a local Agent-side max-duration timer always ends the recording, and a parent-PID watchdog ends it when the driving local process exits. If the driving process remains alive but loses only remote broker/network connectivity, max duration is the guaranteed backstop unless the integration also uses heartbeat.

### 2.5 Signal handling in the CLI

The CLI should mirror Action's signal/fatal stop behavior for any long-running or lease mode:

- Install `SIGINT`, `SIGTERM`, and `SIGHUP` handlers.
- On fatal/unhandled errors, attempt `capture stop` before exit.
- Make stop idempotent so handlers and `finally` blocks can race safely.

If `talkie capture record` remains a quick start command, signal handling mainly matters in a new convenience wrapper such as:

```bash
talkie capture run --region 200,120,640,480 --max-duration 120 -- <driver command>
```

But Preframe can also keep signal handling inside `capture-guided-tour.mjs` and call `talkie capture stop` in its own `finally`/signal handlers.

## 3. Orphan prevention

### 3.1 What happens today if CLI dies mid-record?

There is no CLI-triggered recording today. If a user starts recording through Hyper+R/HUD and then the caller/UI path disappears:

- The active native recording is singleton Agent state.
- `ScreenRecordingService` will auto-stop after 300 seconds (`ScreenRecordingService.swift:211-212`, `ScreenRecordingService.swift:560-565`).
- The stop path writes a tray clip and library capture (`ScreenRecordingController.swift:159-185`).
- No CLI caller receives the resulting path because `ScreenRecordingController.stopRecording()` returns `Void` (`ScreenRecordingController.swift:128-190`).

So Talkie already has a coarse orphan-prevention safety valve, but not an automation lifecycle contract.

### 3.2 Required orphan-prevention changes

Minimum changes before shipping `talkie capture record`:

1. **Per-session max duration:** required on Agent start; never trust only CLI timers.
2. **Cached final stop result:** store final clip metadata by `recordingId` for retry/recovery.
3. **Idempotent stop:** duplicate stop calls must not fail a healthy script.
4. **Owner-death watcher:** accept `lease.parentPid` and stop on parent exit.
5. **Startup rollback:** if `start` fails after creating temp files or partial writer state, tear down stream/writer and remove temp artifacts.
6. **Force-stop fallback:** if graceful `SCStream.stopCapture()` or writer finalization hangs, use a bounded timeout and then cancel writer / return a partial/failure result. `ScreenRecordingService.stopRecording()` currently awaits `SCStream.stopCapture()` and writer finish (`ScreenRecordingService.swift:578-608`, `ScreenRecordingService.swift:611-640`); automation stop should wrap that in a finite timeout.

### 3.3 Partial clip policy

If a forced stop happens after some frames were written but before a clean finalize, the API should distinguish:

- `status: "complete"` — normal MP4 finalized and stored.
- `status: "partial"` — forced stop produced a playable or possibly playable MP4 that was stored; include `warning`.
- `status: "failed"` — no usable clip; include error and cleanup status.

Do not silently report success if library persistence fails. If live tray storage succeeds but library copy fails, return `ok: true`, `status: "partial"`, include `clip.path`, and include `libraryError`.

## 4. HTTP and CLI lifecycle contract

### 4.1 Start request additions

Extend `POST /capture/record/start` from `docs/cli-capture-record-trigger.codex.md` with lease fields:

```json
{
  "idempotencyKey": "preframe-tour-2026-06-13T16-40-00Z",
  "target": {
    "kind": "region",
    "rect": { "x": 200, "y": 120, "width": 1440, "height": 900 }
  },
  "quality": "agent",
  "maxDurationSeconds": 120,
  "lease": {
    "parentPid": 92810,
    "stopOnParentExit": true,
    "heartbeatTTLSeconds": null,
    "detachWatchdog": true
  },
  "clientContext": {
    "driver": "preframe-guided-tour",
    "correlationId": "tour-2026-06-13T16-40-00Z"
  }
}
```

Response:

```json
{
  "ok": true,
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "state": "recording",
  "startedAt": "2026-06-13T16:40:00.123Z",
  "lease": {
    "maxDurationSeconds": 120,
    "parentPid": 92810,
    "stopOnParentExit": true,
    "expiresAt": "2026-06-13T16:42:00.123Z"
  }
}
```

### 4.2 Stop request / response

Request:

```json
{
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "reason": "explicit",
  "timeoutSeconds": 20
}
```

Normal stop response:

```json
{
  "ok": true,
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "state": "stopped",
  "alreadyStopped": false,
  "stopReason": "explicit",
  "clip": {
    "id": "9052eb56-1e4d-4e4e-9d23-a2b1b63c9850",
    "path": "/Users/arach/Library/Application Support/Talkie/Tray/clips/Talkie Screen Clip - 2026-06-13 16.40.12 - Region - 1440x900 - 9052eb56.mp4",
    "durationMs": 8241,
    "width": 1440,
    "height": 900,
    "captureMode": "region",
    "status": "complete"
  }
}
```

Duplicate stop after finalization:

```json
{
  "ok": true,
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "state": "stopped",
  "alreadyStopped": true,
  "stopReason": "explicit",
  "clip": { "path": "/Users/arach/Library/Application Support/Talkie/Tray/clips/...mp4", "status": "complete" }
}
```

Already idle with no matching recent result:

```json
{
  "ok": true,
  "state": "idle",
  "code": "already_idle",
  "alreadyStopped": true,
  "clip": null
}
```

Why `ok: true` for `already_idle`: it lets signal handlers, `finally` blocks, and detached watchdogs call stop safely without treating “nothing left to stop” as a fatal script error. If a caller supplied a `recordingId` and that id is unknown, include `code: "already_idle"` and optionally `warning: "No active or recently completed recording matched recordingId"`.

Mismatched active session:

```json
{
  "ok": false,
  "code": "recording_mismatch",
  "error": "Active recording belongs to a different recordingId",
  "activeRecordingId": "..."
}
```

HTTP status: `409`.

Partial forced stop:

```json
{
  "ok": true,
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "state": "stopped",
  "alreadyStopped": false,
  "stopReason": "max_duration",
  "clip": {
    "path": "/Users/arach/Library/Application Support/Talkie/Tray/clips/...mp4",
    "durationMs": 120000,
    "status": "partial",
    "warning": "Writer finalization timed out; clip was preserved from partial output"
  }
}
```

### 4.3 State response

`GET /capture/record/state?recordingId=<id>`:

```json
{
  "ok": true,
  "state": "recording",
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "startedAt": "2026-06-13T16:40:00.123Z",
  "elapsedMs": 4312,
  "expiresAt": "2026-06-13T16:42:00.123Z",
  "lease": {
    "parentPid": 92810,
    "parentAlive": true,
    "heartbeatDeadline": null
  }
}
```

If stopped recently, return the cached final result; if unknown, return `state: "idle"`.

### 4.4 CLI flags

Add these to `talkie capture record`:

```text
Lifecycle:
  --recording-id <uuid>       Optional caller-provided id; default generated by Agent.
  --idempotency-key <key>     Safe retry key for start.
  --max-duration <seconds>    Required for automation; CLI default 120s, Agent absolute cap.
  --lease-parent-pid <pid>    Stop if this process exits. Preframe should pass process.pid.
  --no-stop-on-parent-exit    Disable parent watcher when intentionally recording detached.
  --heartbeat-ttl <seconds>   Optional; requires caller to heartbeat or use a wrapper mode.
  --detached-watchdog         Spawn CLI-side watchdog that calls stop on parent exit/max duration.
```

Add these to `talkie capture stop`:

```text
Lifecycle:
  --recording-id <uuid>       Stop this session; mismatch fails with exit 5.
  --reason <reason>           explicit | signal | parent-exit | max-duration | heartbeat-timeout.
  --timeout <seconds>         Wait for final MP4; default 20s.
  --allow-idle                Treat already_idle as success; default true for signal/watchdog use.
```

CLI exit-code mapping from the trigger doc should treat `already_idle` as success when `--allow-idle` is true. A `recording_mismatch` remains exit `5`.

## 5. Preframe integration

Preframe currently imports `RecordingLease` for Action stop-file capture. That lease's core semantics are exactly what Talkie should preserve: idempotent stop, detached watchdog, signal/fatal cleanup, and max duration (`/Users/arach/dev/preframe/scripts/recording-lease.mjs:53-119`).

With Talkie, Preframe should not create stop files. It should pass lease metadata to Talkie and still keep local signal/finally cleanup.

### 5.1 Minimal shell-out pattern

```js
const correlationId = `preframe-tour-${new Date().toISOString()}`;
const maxDurationSeconds = 120;

const start = JSON.parse(await runText('talkie', [
  'capture', 'record',
  '--window', String(target.windowID),
  '--pid', String(target.pid),
  '--quality', 'agent',
  '--max-duration', String(maxDurationSeconds),
  '--lease-parent-pid', String(process.pid),
  '--idempotency-key', correlationId,
  '--detached-watchdog',
  '--json',
]));

let stopped = false;
async function stop(reason = 'explicit') {
  if (stopped) return;
  stopped = true;
  await runText('talkie', [
    'capture', 'stop',
    '--recording-id', start.recordingId,
    '--reason', reason,
    '--allow-idle',
    '--json',
  ]).catch((err) => {
    console.warn(`[talkie-capture] stop failed (${reason}): ${err.message}`);
  });
}

for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) {
  process.on(signal, () => { void stop(signal).finally(() => process.exit(128)); });
}
process.on('uncaughtException', (err) => { void stop('uncaughtException').finally(() => { throw err; }); });
process.on('unhandledRejection', (err) => { void stop('unhandledRejection').finally(() => { throw err; }); });

try {
  await driveTour(page);
} finally {
  await stop('finally');
}
```

### 5.2 Better wrapper pattern

A future `talkie capture run` can make this less error-prone:

```bash
talkie capture run \
  --window "$WINDOW_ID" \
  --pid "$CHROME_PID" \
  --quality agent \
  --max-duration 120 \
  --json-output "$OUT_DIR/talkie-capture.json" \
  -- bun scripts/drive-guided-tour-only.mjs
```

`capture run` would:

1. start recording;
2. arm CLI signal/fatal handlers;
3. spawn the child driver;
4. pass child PID as `lease.parentPid`;
5. stop in `finally`;
6. print/write the final clip path.

This wrapper is optional for first Preframe trial, but it is the safest long-term CLI UX because it makes the lifecycle guarantee the default.

## 6. PR addendum

Add this lifecycle work to the PR sequence from `docs/cli-capture-record-trigger.codex.md`:

### Native lifecycle additions

- Add `CaptureRecordingSession` and `CaptureStopResult` storage in `ScreenRecordingController` or a small Agent service.
- Make automation max duration per-session and mandatory.
- Add parent-PID watcher and optional heartbeat TTL watcher.
- Make stop metadata-returning and idempotent; cache final results.
- Add bounded forced-stop handling around stream/writer finalization.

### HTTP lifecycle additions

- Add `idempotencyKey`, `lease`, `reason`, and `already_idle` response semantics to `:8766` contracts.
- Add `GET /capture/record/state` and optional `POST /capture/record/heartbeat`.
- Ensure disconnect/retry behavior is deterministic: start retry returns same session, stop retry returns same final clip.

### CLI lifecycle additions

- Add lifecycle flags listed above.
- Generate an idempotency key by default for scripted JSON starts.
- Spawn a detached watchdog when `--detached-watchdog` is passed.
- Treat `already_idle` as success for stop cleanup paths.

Acceptance smoke:

```bash
START=$(talkie capture record --region 200,120,640,480 --max-duration 5 --lease-parent-pid $$ --idempotency-key smoke-$$ --json)
RID=$(echo "$START" | jq -r .recordingId)
sleep 1
talkie capture stop --recording-id "$RID" --reason explicit --json | jq .
# Duplicate stop must succeed, not fail:
talkie capture stop --recording-id "$RID" --reason duplicate --allow-idle --json | jq '.ok == true'
```

Crash/parent-death smoke:

```bash
node -e '
const { spawn } = require("node:child_process");
const child = spawn("bash", ["-lc", "talkie capture record --region 200,120,640,480 --max-duration 30 --lease-parent-pid $$ --json > /tmp/talkie-lease-start.json; sleep 300"], { detached: true, stdio: "ignore" });
child.unref();
setTimeout(() => { try { process.kill(-child.pid, "SIGKILL"); } catch {} }, 1500);
'
sleep 5
talkie capture stop --allow-idle --json | jq .
```

Expected result: either the parent-PID watcher already stopped and returns `already_idle` / cached clip, or the explicit cleanup stop stops it. In no case should the recording continue beyond `--max-duration`.
