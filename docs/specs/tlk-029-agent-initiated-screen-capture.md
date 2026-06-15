# TLK-029 — Agent-Initiated Screen Capture

**Status**: Draft
**Owner**: Talkie macOS + TalkieAgent + CLI
**Date**: 2026-06-13
**Studio**: /eng/tlk-029 (not scheduled; not approved for implementation)
**Related**: [TLK-001](tlk-001-bridge-api-unification.md) (trusted local bridge), [TLK-017](tlk-017-media-capture-quality.md) (capture quality), [TLK-026](tlk-026-visual-context-capture.md) (visual context bundles), [TLK-027](tlk-027-agent-owned-overlays-and-assistant-workflow.md) (Agent-owned capture), [TLK-015](tlk-015-security-notifications.md) (security UX)

This document is a **draft** — it consolidates Scout audit handoffs and has not
been reviewed or signed off for shipping.

**Audit supplements** (Scout handoffs, more line-level detail):

- `docs/cli-capture-audit.codex.md`
- `docs/cli-capture-record-trigger.codex.md`
- `docs/cli-capture-record-lifecycle.codex.md`

## Summary

External agents (CLI tools, Codex sessions, Playwright drivers, workflow runners)
need to **start a fresh screen recording, drive UX, stop recording, and receive a
new `.mp4` path** — without simulating Hyper+R, polling tray history, or reading
old clips.

Talkie already records screen video through `TalkieAgent` (`ScreenRecordingService`
+ `ScreenRecordingController`). What is missing is a **non-interactive automation
entrypoint** with explicit security, lifecycle guarantees, and unmistakable
recording visibility.

The durable shape:

```text
Agent driver (e.g. preframe capture script)
  → signed HTTP :8766 (Talkie.app)
  → XPC (TalkieAgent)
  → ScreenCaptureKit record start/stop
  → stored tray clip path returned to caller
```

Do **not** route automation through `:8767` (weaker auth) or hotkey synthesis.

## Motivation

Agent workflows need deterministic capture:

- enumerate windows (pid, bundle, title, frame) to align with Playwright/Chrome
- start recording against an explicit region, window, or display
- stop and get the **stored** MP4 path in the response
- survive caller crash, kill, or forgotten `stop`

Today:

- Hyper+R and the capture HUD are UI-first and interactive.
- `stopRecording()` persists clips but returns `Void`; callers must poll manifests.
- `:8766` has screenshot routes and trusted-local-client auth, but no record routes.
- XPC has screenshot methods only; no `startScreenRecording` / `stopScreenRecording`.

Listing existing clips (`talkie captures`) is useful but solves a different
problem than **triggering** a new recording.

## Product boundary

| Layer | Owns |
| --- | --- |
| **Talkie.app** `:8766` | Loopback HTTP, trusted-local-client pairing, capability checks, route forwarding |
| **TalkieAgent** | `SCStream`, writer, temp MP4, tray/library persistence, supervision UI, session lease |
| **TalkieKit** | Shared DTOs, XPC protocol additions |
| **CLI** (`talkie capture`) | P-256 request signing, thin command surface, optional detached watchdog |
| **Driver** (Preframe, etc.) | Playwright UX, `--lease-parent-pid`, `finally` stop, correlation metadata |

Prefer the **Agent** recorder chain over the legacy main-app duplicate under
`apps/macos/Talkie/Services/ScreenRecording/`.

## Goals

1. `GET /capture/windows` — deterministic window metadata for external drivers.
2. `POST /capture/record/start` — non-interactive start with explicit target.
3. `POST /capture/record/stop` — idempotent stop returning stored clip metadata.
4. Separate capability `desktop.capture.record` (do not overload screenshot read).
5. Supervision UI on by default; excluded from capture via `sharingType = .none`.
6. Session `recordingId`, tunable max duration, parent-PID lease, cached stop results.
7. `talkie capture windows | record | stop` CLI over signed `:8766`.

## Non-goals (v1)

- Simulating Hyper+R or capture HUD chords.
- Polling `talkie captures` / tray manifests as the primary stop result.
- Direct automation on `:8767` without trusted-local-client capabilities.
- Multi-session concurrent recordings (singleton recorder; mint `recordingId` anyway).
- Popping System Settings from headless routes unless explicitly requested.

## Security model

Local capture is CLI-grade power with extra OS friction. A hostile script should
fail at multiple layers:

1. **Pairing** — unsigned or untrusted clients cannot call protected routes.
2. **Capability** — `desktop.capture.record` is approved separately from
   `desktop.screenshot.read`.
3. **TCC** — Screen Recording permission on TalkieAgent.
4. **Visibility** — supervision border + HUD + notch + macOS menu bar indicator.

### Trusted local client

Reuse the existing `:8766` P-256 signed request model (`TalkieServer.swift`):

```http
x-talkie-client-id: <client id>
x-talkie-timestamp: <unix seconds>
x-talkie-nonce: <unique nonce>
x-talkie-body-sha256: <sha256 of body; empty body = sha256("")>
x-talkie-signature: <base64 DER P-256 ECDSA over METHOD + "\n" + path + "\n" + ts + "\n" + nonce + "\n" + bodyHash>
```

Pairing: `POST /local-clients/request-access` with requested capabilities.

When `desktop.capture.record` is requested, pairing copy must be explicit:

> **Allow {displayName} to record your screen via Talkie?**
>
> This client can start and stop screen recordings on this Mac. Recordings are
> always visible while active.

CLI identity: `talkie-cli` with its own key file under
`~/Library/Application Support/Talkie/LocalBridge/talkie-cli-p256.json`.

### Capabilities

| Capability | Routes |
| --- | --- |
| `desktop.windows.read` | `GET /capture/windows` |
| `desktop.capture.record` | `POST /capture/record/start`, `POST /capture/record/stop`, optional `GET /capture/record/state` |

## Recording visibility

Recording must be unmistakable for Hyper+R, CLI, and `:8766` triggers.

Talkie overlay panels already use `sharingType = .none` (`ScreenRecordingActiveOverlayController`). Louder affordances do **not** leak into the `.mp4`.

| Layer | Component | In the `.mp4`? |
| --- | --- | --- |
| OS | macOS menu bar screen-recording indicator | N/A |
| Consent | Pairing prompt for `desktop.capture.record` | N/A |
| Border | `CaptureSupervisionController` — pulsing red ring per display | No |
| HUD | Corner **RECORDING** pill + caller + elapsed + STOP | No |
| Chrome | Amber brackets + `REC` badge around capture rect | No |
| Notch | `NotchOverlayController.activateScreenRecording` | Usually outside region |

Defaults for automation (`presentation` on start request):

```json
{
  "supervision": true,
  "showCaptureChrome": true,
  "showNotch": true
}
```

Opt-out flags exist for debugging only; CLI and automation must not default them off.

`clientContext.driver` / `clientContext.label` feed the supervision HUD so the
user sees *who* started capture.

## HTTP contract (`:8766`)

### `GET /capture/windows`

Query filters: `bundleID`, `pid`, `app`, `title`, `onScreen`, `minWidth`, `minHeight`.

Response includes `windowID`, `pid`, `bundleID`, `appName`, `title`, `frame`,
`displayID`, `displayName`, `isFrontmost`, `zIndex` — Action-parity for Playwright
pid → window mapping.

### `POST /capture/record/start`

```json
{
  "target": {
    "kind": "region",
    "rect": { "x": 200, "y": 120, "width": 1440, "height": 900 },
    "displayID": 1
  },
  "quality": "agent",
  "maxDurationSeconds": 120,
  "presentation": {
    "supervision": true,
    "showCaptureChrome": true,
    "showNotch": true
  },
  "clientContext": {
    "driver": "preframe-guided-tour",
    "correlationId": "tour-2026-06-13",
    "clientId": "talkie-cli",
    "label": "Preframe guided tour"
  },
  "lease": {
    "parentPid": 92810,
    "stopOnParentExit": true
  }
}
```

Target kinds: `region`, `window`, `display`.

Response includes `recordingId`, `state: "recording"`, `startedAt`.

Errors: `400 invalid_target`, `404 target_not_found`, `409 already_recording`,
`422 permission_missing`, `503 agent_unavailable`.

### `POST /capture/record/stop`

```json
{
  "recordingId": "b5dc8af6-0c63-4d32-a3f7-63d5f2891f2d",
  "timeoutSeconds": 15
}
```

Idempotent. Returns stored tray `clip.path`, dimensions, `durationMs`, `captureMode`.
Retry after timeout must return cached final result for the same `recordingId`.

`recordingId` mismatch → `409 recording_mismatch`.

### Optional `GET /capture/record/state`

For scripts that want polling without stop; not required for v1.

## Lifecycle and guaranteed stop

Model each automation start as a **session lease** even while the native recorder
remains a singleton.

Mint `recordingId` on every start for:

- idempotent start retries after lost HTTP responses
- guarded stop (wrong client cannot stop another session)
- duplicate stop returning the same clip metadata
- future multi-session support without CLI contract changes

### Stop paths (at least two, preferably three)

1. Explicit `capture stop` / `POST /capture/record/stop`
2. Agent max-duration timer (per-session, bounded by 300s absolute cap; CLI default 120s)
3. Parent-PID watchdog (`lease.parentPid`) — **not** the short-lived `talkie capture record` PID
4. Optional CLI detached watchdog (defense-in-depth; mirrors Action `recording-lease.mjs`)

Supervision UI stays visible from `recording` until `stopped`/`failed`, including
watchdog-triggered stops.

### Parent PID semantics

Pass the long-lived driver PID (e.g. `capture-guided-tour.mjs` `process.pid`), not
the ephemeral CLI child. If the CLI exits after printing JSON, watching the CLI PID
would immediately stop a valid recording.

### Idempotency

Optional `idempotencyKey` on start. Same client + key + active session → return
existing `recordingId`. Completed session + same key → `409 already_completed` or
idempotent `stopped` payload.

## CLI surface

```bash
talkie capture windows [--bundle <id>] [--pid <pid>] [--json]
talkie capture record (--region x,y,w,h | --window <id> | --display [id]) \
  [--max-duration 120] [--lease-parent-pid <pid>] [--driver <label>] [--json]
talkie capture stop [--recording-id <id>] [--json | --path]
```

Signing: port `apps/macos/TalkieServer/src/bridge/talkie-local-client.ts` pattern
into `packages/npm/cli` with `talkie-cli` identity and capture capabilities.

`talkie captures` remains the history/listing command; `talkie capture` is the
trigger group.

## Native call chain (target)

```text
talkie capture record --region …
  → signed POST :8766/capture/record/start
  → TalkieServer.handleCaptureRecordStart
  → XPC startScreenRecording(requestJSON:)
  → ScreenRecordingService.resolveAutomationTarget(...)
  → ScreenRecordingController.startAutomationRecording(...)
  → ScreenRecordingService.startRecording(target:)
  → CaptureSupervisionController.show(...)   // sharingType = .none

talkie capture stop
  → signed POST :8766/capture/record/stop
  → XPC stopScreenRecording(requestJSON:)
  → ScreenRecordingController.stopAutomationRecording(...)
  → AgentLiveTrayAssetStore.storeClip(...) → returns clip.path
```

Required seams:

- `TalkieServer.swift` — routes, capability map, pairing copy, XPC forward
- `XPCProtocols.swift` — `listCaptureWindows`, `startScreenRecording`, `stopScreenRecording`
- `TalkieAgentXPCService.swift` — JSON marshal implementations
- `ScreenRecordingService.swift` — explicit region/window/display resolvers; per-session max duration
- `ScreenRecordingController.swift` — automation start/stop returning DTOs
- `CaptureSupervisionController.swift` — border + HUD (new)
- `CaptureRecordingAutomation.swift` — shared DTOs in TalkieKit
- `packages/npm/cli/src/commands/capture.ts` — thin HTTP client

## PR plan

| PR | Scope | Owner |
| --- | --- | --- |
| **1** | Agent primitives: supervision, automation start/stop, target resolvers, XPC, DTOs | macOS Agent |
| **2** | `:8766` routes + `desktop.capture.record` + pairing copy | Talkie.app bridge |
| **3** | CLI signer + `talkie capture` commands | CLI |
| **4** | Optional driver integrations (Preframe, workflows) | Integrations |

Acceptance (PRs 1–3):

```bash
talkie capture windows --json
talkie capture record --region 200,120,640,480 --max-duration 10 --json
sleep 3
talkie capture stop --json   # → clip.path exists, .mp4 on disk
```

## Relationship to Action

Action (`run-app-host.sh`, supervision overlay, `recording-lease.mjs`) is a valid
parallel capture stack for agent drivers that do not require Talkie tray/library
integration. TLK-029 does not replace Action; it defines Talkie's native path when
clips should land in Talkie's capture library and visual-context pipeline (TLK-026).

Drivers may choose per integration:

- **Action** — minimal deps, file-signal host, Preframe-style leases
- **Talkie** — signed local bridge, tray persistence, visual-context metadata

## Open questions

- Should automation recordings always persist to the capture library, or support
  ephemeral temp-only mode for one-off marketing captures?
- Heartbeat TTL vs parent-PID-only lease for remote-agent disconnect scenarios.
- Window-target stability vs region fallback when ScreenCaptureKit window filters drift.