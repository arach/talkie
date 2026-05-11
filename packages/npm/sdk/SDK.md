# `@talkie/client` SDK Reference

> TypeScript SDK for connecting to Talkie's local macOS services over WebSocket JSON-RPC. Zero runtime dependencies, Bun target.

## Why This Exists

Talkie is a suite of macOS services (TalkieEngine, TalkieSync, TalkieAgent) that communicate over localhost WebSockets using a simple JSON-RPC protocol. Previously, each consumer (CLI, future apps like Lattices, Hudson) reimplemented the WebSocket connection logic. This SDK extracts it into a shared package.

**Key improvements over the old `bridge.ts` approach:**
- **Persistent WebSocket** — single connection, multiplexed concurrent calls via `id` field (old code created a new socket per call)
- **Auto-reconnect** — exponential backoff when a service restarts
- **Service discovery** — reads `~/.talkie/services.json` instead of hardcoded ports
- **Client identification** — lightweight auth handshake so services know who's connected

## Package

```
packages/npm/sdk/
  package.json          # @talkie/client, bun target, zero runtime deps
  tsconfig.json
  src/
    index.ts            # Barrel export
    client.ts           # TalkieClient (high-level API)
    transport.ts        # WebSocketTransport (persistent, multiplexed)
    discovery.ts        # Read ~/.talkie/services.json + file watch
    auth.ts             # Service key -> register -> session token
    dictation.ts        # DictationSession with event streaming
    types.ts            # All shared types
    errors.ts           # TalkieError, ConnectionError, AuthError, etc.
    events.ts           # Lightweight typed EventEmitter
    constants.ts        # Default ports, paths, timeouts
```

Install: `bun install` in `packages/npm/sdk/`. Build: `bun run build`. Typecheck: `bun run typecheck`.

---

## Quick Start

```typescript
import { TalkieClient } from "@talkie/client";

const client = new TalkieClient({
  service: "engine",           // "sync" | "engine" | "agent"
  clientId: "my-app",          // identifies this client to the service
  capabilities: ["status"],    // what you intend to use
});

await client.connect();

// Simple RPC call
const pong = await client.ping();                    // { pong: true }
const status = await client.call("status");          // service-specific result
const models = await client.call("models");          // { models: [...] }

// Streaming RPC call (with progress events)
const result = await client.callStreaming(
  "syncNow",
  { limit: 100 },
  (event, data) => console.log(event, data),         // progress callback
);

// Push events from the service (no request id)
client.onServiceEvent((event, data) => {
  console.log("Service pushed:", event, data);
});

// Dictation (TalkieAgent)
const session = client.createDictationSession();
session.on("stateChange", ({ state }) => console.log(state));
session.on("partialTranscript", ({ text }) => process.stdout.write(text));
const transcript = await session.start({ persist: false }); // ephemeral, no memo created

// Or cancel mid-dictation
await session.cancel();

await client.disconnect();
```

---

## Wire Protocol

All Talkie services use the same JSON-RPC-like protocol over WebSocket on `127.0.0.1`:

### Request (client -> service)
```json
{"id": "uuid", "method": "ping", "params": {"key": "value"}}
```
- `id` — UUID, used to match response to request
- `method` — the RPC method name
- `params` — optional parameters dict

### Response (service -> client)
```json
{"id": "uuid", "result": {"pong": true}}
```
or
```json
{"id": "uuid", "error": "Something went wrong"}
```

### Progress Event (service -> client, streaming methods only)
```json
{"id": "uuid", "event": "progress", "data": {"percent": 50}}
```
- Has both `id` (routes to the pending call) and `event`
- Resets the call timeout — the service is alive, just working

### Push Event (service -> client, unsolicited)
```json
{"event": "statusChanged", "data": {"recording": true}}
```
- Has `event` but no `id` — not tied to any request
- Forwarded to `onServiceEvent` listeners

---

## Service Ports

| Service | Port | What it does |
|---------|------|-------------|
| TalkieSync | 19820 | CloudKit sync orchestration |
| TalkieEngine | 19821 | On-device transcription (Whisper/Parakeet) |
| TalkieAgent | 19823 | Background dictation, real-time I/O |

Ports are resolved in order: `~/.talkie/services.json` -> hardcoded defaults.

---

## Available Methods by Service

### All Services
- `ping` -> `{pong: true}`

### TalkieSync (19820)
- `status` -> sync state JSON
- `syncNow` (streaming) -> progress events + final stats
- `runSyncPass` -> `{syncedCount: N}`
- `iCloudCheck` -> `{available: boolean}`
- `providers` -> `{providers: [...]}`
- `remoteMemoCount` -> `{count: N}`
- `fetchAudio` -> `{success: boolean}`

### TalkieEngine (19821)
- `status` -> engine state JSON
- `models` -> `{models: [...]}`
- `preload` -> `{success: true, modelId: "..."}`
- `transcribe` -> `{transcript: "..."}`
- `transcribeWithTimings` -> `{transcript: "...", segments: [...]}`
- `transcribeAudio` -> base64-encoded audio input
- `transcribeAudioWithTimings` -> base64-encoded with timings

### TalkieAgent (19823) — planned
- `register` -> `{sessionToken: "...", grantedCapabilities: [...]}`
- `startDictation` (streaming) -> state changes, partial/final transcript. Params: `{persist: boolean}`. Returns `{error: "mic_busy:owner_id"}` if another client holds the mic
- `stopDictation` -> finalize and stop active dictation
- `cancelDictation` -> abort active dictation without finalizing

---

## Auth Model

**Auth is client identification, not a security gate.** It's a friendly "hello, I'm Hudson" so the service knows who's connected. All access is granted regardless — capability gating is a future addition.

### Three States

1. **No `serviceKey` in discovery** -> legacy mode. `register` is never called. Full access.
2. **`serviceKey` present, server returns `"Unknown method: register"`** -> legacy mode. Server doesn't support auth yet. Full access.
3. **`serviceKey` present, server handles `register`** -> authenticated. Session token stored, injected into subsequent calls as `_sessionToken` in params.

The SDK **never throws on auth failure**. It always degrades gracefully to legacy mode.

### Discovery File (`~/.talkie/services.json`)

```json
{
  "version": 1,
  "services": {
    "agent": {"port": 19823, "serviceKey": "sk_a1b2c3..."},
    "engine": {"port": 19821},
    "sync": {"port": 19820}
  }
}
```

Services without a `serviceKey` -> no auth attempted. The file is optional; without it, hardcoded default ports are used.

### Register Handshake

```
Client                          Service
  |                                |
  |-- register({serviceKey,        |
  |     capabilities, clientId}) ->|
  |                                |
  |<- {sessionToken, granted...} --|
  |                                |
  |-- someMethod({...,             |
  |     _sessionToken: "tok"}) --> |
```

### Capabilities (informational for now)

- `status` — read service state
- `dictation` — start/stop dictation sessions
- `control` — lifecycle operations (shutdown, config changes)

---

## Architecture

```
┌────────────────────────────────────────────────┐
│                 TalkieClient                    │
│  connect() / disconnect() / call() / ping()    │
│  createDictationSession() / onServiceEvent()   │
├────────────────────────────────────────────────┤
│         ┌──────────┐  ┌──────────┐             │
│         │ Discovery │  │   Auth   │             │
│         │ resolve() │  │ register │             │
│         └────┬─────┘  └────┬─────┘             │
│              │              │                   │
│         ┌────▼──────────────▼────┐              │
│         │   WebSocketTransport   │              │
│         │  persistent, muxed     │              │
│         │  call() / callStream() │              │
│         └────────────────────────┘              │
└────────────────────────────────────────────────┘
                     │
                     │ ws://127.0.0.1:{port}
                     ▼
              ┌──────────────┐
              │ ServiceBridge │  (Swift, in each macOS service)
              │  JSON-RPC     │
              └──────────────┘
```

### Layer Responsibilities

- **TalkieClient** — high-level API, wires discovery + transport + auth, auto-reconnect with exponential backoff (500ms -> 10s cap)
- **WebSocketTransport** — single persistent WebSocket, multiplexes calls by UUID `id`, routes push events, manages pending call timeouts
- **ServiceDiscovery** — reads `~/.talkie/services.json`, falls back to hardcoded ports, watches file for changes (triggers reconnect on port change)
- **Auth** — sends `register` if `serviceKey` exists, catches errors, always degrades to legacy
- **DictationSession** — wraps streaming `startDictation` call with typed event emitter (stateChange, partialTranscript, finalTranscript, error). Supports `persist: false` for ephemeral dictation, `cancel()` to abort, and parses `mic_busy` errors into `MicBusyError` with the `.owner` field
- **Emitter** — minimal typed event emitter, zero deps, `on()` returns unsubscribe function

---

## Types

```typescript
// Service names
type ServiceName = "sync" | "engine" | "agent";

// Client options
interface TalkieClientOptions {
  service: ServiceName;
  capabilities?: Capability[];        // default: ["status"]
  clientId?: string;                  // default: "talkie-sdk"
  port?: number;                      // override (skips discovery)
  autoReconnect?: boolean;            // default: true
}

// Auth
type Capability = "status" | "dictation" | "control";
type AuthState =
  | { mode: "legacy" }
  | { mode: "authenticated"; sessionToken: string; grantedCapabilities: Capability[] };

// Dictation
type DictationState = "idle" | "starting" | "recording" | "processing" | "done" | "cancelled" | "error";

interface DictationOptions {
  persist?: boolean;               // default: true. false = ephemeral, no memo created
  [key: string]: unknown;          // additional params forwarded to startDictation
}

// Client events (subscribe via client.on(...))
interface ClientEvents {
  connected: undefined;
  disconnected: { code: number; reason: string };
  reconnecting: { attempt: number; delay: number };
  authStateChange: { auth: AuthState };
  serviceEvent: { event: string; data: Record<string, unknown> };
}

// Dictation events (subscribe via session.on(...))
interface DictationEvents {
  stateChange: { state: DictationState; previous: DictationState };
  partialTranscript: { text: string };
  finalTranscript: { text: string };
  error: { error: Error };
}
```

---

## Errors

All errors extend `TalkieError`:

| Error | When |
|-------|------|
| `ConnectionError` | WebSocket fails to connect or is lost. Has `.port` |
| `CallError` | Service returned `{error: "..."}`. Has `.method` |
| `TimeoutError` | Call exceeded timeout. Has `.method`, `.timeoutMs` |
| `AuthError` | Auth registration failed (not used currently — auth always degrades gracefully) |
| `MicBusyError` | `startDictation` when another client holds the mic. Has `.owner` (the clientId holding it) |

---

## Constants

| Constant | Value | Notes |
|----------|-------|-------|
| `DEFAULT_CALL_TIMEOUT` | 30,000ms | Standard RPC calls |
| `STREAMING_CALL_TIMEOUT` | 120,000ms | Streaming calls, resets on progress |
| `CONNECT_TIMEOUT` | 5,000ms | WebSocket open |
| `RECONNECT_BASE_DELAY` | 500ms | First reconnect attempt |
| `RECONNECT_MAX_DELAY` | 10,000ms | Reconnect cap |

---

## Auto-Reconnect Behavior

- On unexpected disconnect, exponential backoff: 500ms, 1s, 2s, 4s, 8s, 10s (capped)
- On reconnect, full sequence runs again: discover port, open WebSocket, re-register auth
- Reconnect stops on intentional `disconnect()` or `autoReconnect: false`
- Discovery file watch: if `services.json` changes and the port is different, triggers reconnect

---

## Dictation Flow

The primary use case for Lattices. Full lifecycle:

```typescript
import { TalkieClient, MicBusyError } from "@talkie/client";

const client = new TalkieClient({
  service: "agent",
  clientId: "lattices",
  capabilities: ["dictation"],
});

await client.connect();

const session = client.createDictationSession();

// Subscribe to events before starting
session.on("stateChange", ({ state, previous }) => {
  // idle -> starting -> recording -> processing -> done
  // or: idle -> starting -> error (mic_busy)
  // or: idle -> starting -> recording -> cancelled
  updateUI(state);
});

session.on("partialTranscript", ({ text }) => {
  showLiveText(text);
});

session.on("finalTranscript", ({ text }) => {
  insertText(text);
});

session.on("error", ({ error }) => {
  if (error instanceof MicBusyError) {
    showToast(`Mic in use by ${error.owner}`);
  }
});

try {
  // persist: false = don't create a memo, just give us the text
  const transcript = await session.start({ persist: false });
  // transcript is the final result (same as finalTranscript event)
} catch (err) {
  if (err instanceof MicBusyError) {
    // Another consumer (e.g. Talkie main app) is dictating
    console.log(`Mic held by: ${err.owner}`);
  }
}

// To stop mid-dictation (finalize what we have):
await session.stop();

// To cancel mid-dictation (discard everything):
await session.cancel();
```

### State Machine

```
         start()
idle ──────────> starting ──────────> recording
                    │                     │  \
                    │ mic_busy       stop()│   \ disconnect
                    ▼                     ▼    ▼
                  error              processing ──> done
                                         │
                                    cancel()
                                         ▼
                                     cancelled
```

### `persist` Parameter

| Value | Behavior |
|-------|----------|
| `true` (default) | TalkieAgent creates a memo from the dictation (appears in Talkie's memo list) |
| `false` | Ephemeral dictation — agent streams transcript but doesn't persist. Used by Lattices, Hudson, and other consumers that just want live text |

### `mic_busy` Error

When `startDictation` is called but another client already holds the mic, the server responds with:
```json
{"id": "uuid", "error": "mic_busy:lattices"}
```

The SDK parses this into a `MicBusyError` with `.owner = "lattices"`. The consuming app can show who's using the mic and let the user decide what to do.

### Disconnect Contract

**Closed WebSocket = implicit cancel.** When a client's WebSocket connection drops (crash, network, intentional disconnect during active dictation), TalkieAgent must:

1. Treat the in-flight `startDictation` streaming call as cancelled — stop recording, release the mic
2. Discard any partial transcript (same as `cancelDictation`)
3. Free the mic so other clients can acquire it immediately

This is a **TalkieAgent server-side requirement**, not enforced by the SDK. The SDK handles its side (auto-reconnect, re-register), but can't guarantee the server cleans up. TalkieAgent's `ServiceBridge` `removeConnection` handler should check for active dictation sessions tied to the departing connection and tear them down.

Why this matters: if Lattices crashes mid-dictation and TalkieAgent doesn't release the mic, every subsequent `startDictation` from any client returns `mic_busy:lattices` for a ghost session.

---

## Verified Against Live Services

Tested and confirmed working:
- **TalkieEngine (19821)**: `connect()` -> `ping()` -> `{pong: true}`
- **TalkieSync (19820)**: `connect()` -> `ping()` -> `{pong: true}`
- **Auth degradation**: Both services return `"Unknown method: register"` -> SDK silently enters legacy mode, no errors

---

## Server-Side Contract (ServiceBridge.swift)

For context on what the SDK connects to: each macOS service runs a `ServiceBridge` — a WebSocket JSON-RPC server using Network.framework.

```swift
// Server registers handlers
let bridge = ServiceBridge(port: 19821, serviceName: "TalkieEngine")
bridge.handle("ping") { params, reply in
    reply(["pong": true], nil)
}
bridge.handleStreaming("syncNow") { params, progress, reply in
    progress("step", ["message": "Syncing..."])   // sends {event: "step", data: {...}}
    reply(["syncedCount": 42], nil)               // sends {result: {...}}
}
bridge.start()

// Unknown methods return: {"error": "Unknown method: methodName"}
```

The `_sessionToken` field in params is ignored by current services (they don't check it). When auth gating is added server-side, the service will validate the token before dispatching to handlers — no SDK changes needed.
