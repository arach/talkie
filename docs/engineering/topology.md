# Talkie Process Topology

Snapshot of the running services and how they relate. Naming here reflects the direction we're moving (e.g. `TalkieAgentServer`); some code still uses older names — noted inline.

## Processes

| Process | Ownership | Lifecycle | Role |
|---|---|---|---|
| **Talkie.app** | User | Foreground, user-invoked | Main UI, workflows, data |
| **TalkieAgent** | launchd (`to.talkie.agent.dev`) | Always-on (KeepAlive) | Mic, keyboard injection, in-process transcription (Parakeet/Whisper) |
| **TalkieSync** | launchd (attached to Talkie) | Attached (today) / on-demand (aspirational) | CloudKit ↔ GRDB bridge |
| **TalkieAgentServer** *(bun process, historically "the Bridge")* | TalkieAgent (supervised via `TalkieAgentServerSupervisor`) | With Agent | Bun backend — Bridge module + Gateway module |

Note: There is no standalone `TalkieEngine` process anymore. Engine logic runs in-process inside TalkieAgent via `TalkieEngineCore` (SPM). The `TalkieHelper.engine` enum case is vestigial.

## In-process services (inside Talkie.app)

| Service | Port | Role |
|---|---|---|
| `TalkieServer.swift` (aspirational: **TalkieHTTP**) | 8766 | Thin HTTP adapter exposing Talkie.app capabilities (`/message`, `/screenshot/*`, `/windows/claude`, `/workflows/host/execute-step`, `/tray/*`) over localhost for TalkieAgentServer to call into |
| `BridgeManager` | — | Controller for TalkieAgentServer: lifecycle (via Agent XPC), paired devices, Tailscale status, prereqs |

## Data flow: iOS remote message → terminal

```
iOS device (remote)
      │ HTTPS over Tailscale
      ▼
┌────────────────────────────────────────────┐
│ TalkieAgentServer (bun, :8765)             │  supervised by Agent
│                                            │
│  ├─ Bridge module — pairing, sessions,     │
│  │    window match, smart message routing, │
│  │    TTS, Scout handoff, compose, ingest  │
│  │                                         │
│  └─ Gateway module — /inference over       │
│       OpenAI/Anthropic/Groq/Google         │
└─────────────────────┬──────────────────────┘
                      │ HTTP localhost:8766
                      ▼
┌────────────────────────────────────────────┐
│ TalkieHTTP (Swift, :8766, in Talkie.app)   │
│   thin adapter → XPC                       │
└─────────────────────┬──────────────────────┘
                      │ XPC
                      ▼
┌────────────────────────────────────────────┐
│ TalkieAgent                                │
│   keyboard inject, mic, transcription      │
└────────────────────────────────────────────┘

BridgeManager (Talkie.app)
    ├── XPC → Agent (control TalkieAgentServer process)
    └── HTTP → TalkieAgentServer :8765 (pairing, devices, status)
```

## The inversion

Most of the smart logic lives in **TypeScript** (TalkieAgentServer), owned by the **Agent** process. The Swift HTTP surface in Talkie.app is the dumb passthrough.

- **TalkieAgentServer** (bun): routes screen-lock-aware delivery, correlates terminal windows to Claude sessions, owns paired devices, proxies LLM providers, orchestrates Scout/compose/ingest flows.
- **TalkieHTTP** (Swift, :8766): exposes a handful of Talkie.app XPC capabilities over localhost so the bun backend can call in.
- **Talkie.app**: UI + user intent. `BridgeManager` is the controller that wraps the bun process's state for the UI.

Read this as: **Agent is both executor _and_ backend host**. Talkie.app is UI + orchestration + a thin HTTP door.

## Helper lifecycle modes (aspirational)

Three modes per helper; user can override defaults:

- **Always-on** — runs independently of Talkie.app. Default: Agent.
- **Attached** — starts with Talkie, stops with Talkie. Default: Sync.
- **On-demand** — user manually invokes. Good fit for Sync if user prefers explicit control.

TalkieAgentServer's lifecycle is nested under Agent's supervisor, not a direct helper. It inherits Agent's always-on-ness but has its own enable/disable via `SettingsManager.talkieServerEnabled` (setting key retained to avoid migration — naming debt).

## Port map

| Port | Listener | Purpose |
|---|---|---|
| 8765 | TalkieAgentServer (bun) | External-facing (Tailscale + localhost) |
| 8766 | TalkieHTTP (Swift, in Talkie.app) | Localhost only — bun → Swift door |
| Mach | `to.talkie.agent.dev` | XPC to TalkieAgent |
| Mach | `to.talkie.app.sync.dev` | XPC to TalkieSync |

## Known naming debt

Completed (this pass):
- Swift types/XPC methods renamed `TalkieServer*` → `TalkieAgentServer*` where they refer to the bun process: `TalkieAgentServerSupervisor`, `TalkieAgentServerStatus`, `getTalkieAgentServerStatus`, `controlTalkieAgentServer`, `talkieAgentServerStatusDidChange`, `broadcastTalkieAgentServerStatus`.

Still outstanding:
- **Filenames** lag behind types: `TalkieServerSupervisor.swift`, `TalkieServerStatus.swift` still have old names. Rename when we do a pbxproj-safe pass.
- **Directory** `apps/macos/TalkieServer/` (bun source) still uses old name — cascades to Xcode projects and `BridgeManager`'s `bridgeSourcePath`.
- **Setting key** `SettingsManager.talkieServerEnabled` (and UserDefaults key `"talkieServerEnabled"`) retained to avoid migration.
- **Swift sidecar** (`TalkieServer.swift` on :8766) still called `TalkieServer` — aspirational: **TalkieHTTP**.
- **BridgeManager** scope is fuzzy — it's really the controller for TalkieAgentServer's Bridge module. Candidate rename later.
- **`TalkieHelper.engine`** case is vestigial (no standalone engine process anymore).
- **Log/comment strings** containing "TalkieServer" referring to the bun process weren't updated in this pass — cleanup pending.
