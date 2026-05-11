# TalkieServer Architecture

**TalkieServer** is the unified TypeScript backend for Talkie. It runs as a single process and exposes HTTP endpoints (and optionally a Unix socket) for the Swift app to communicate with.

## Nomenclature

| Term | What it is |
|------|------------|
| **TalkieServer** | The TypeScript process that runs Bridge + Gateway |
| **Bridge** | Module for local system integration (Claude sessions, windows, pairing) |
| **Gateway** | Module for external API translation (OpenAI, Anthropic, etc.) |
| **Module** | A self-contained Elysia app that gets mounted on the server |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Swift App (Talkie)                      │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTP or Unix Socket
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      TalkieServer                           │
│                   (single process)                          │
│                                                             │
│  ┌─────────────────────────┐  ┌──────────────────────────┐  │
│  │        Bridge           │  │        Gateway           │  │
│  │                         │  │                          │  │
│  │  • Claude sessions      │  │  • /inference            │  │
│  │  • Window management    │  │  • Provider abstraction  │  │
│  │  • Device pairing       │  │  • OpenAI, Anthropic     │  │
│  │  • Terminal matching    │  │                          │  │
│  └─────────────────────────┘  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                          │
          ┌───────────────┼───────────────┐
          ▼               ▼               ▼
    ~/.claude/      TalkieServer     External APIs
    (sessions)      (Swift app)      (OpenAI, etc.)
```

## Bridge Module

**Purpose:** Local system integration. Everything that talks to the Mac itself.

**Routes:**
- `GET /health` - Server health check
- `GET /sessions` - List Claude Code sessions
- `GET /sessions/:id` - Get session messages
- `POST /sessions/:id/message` - Send message to session (UI or headless)
- `GET /windows` - List Claude terminal windows
- `GET /windows/:id/screenshot` - Capture window screenshot
- `POST /pair` - Device pairing (iOS ↔ Mac)
- `GET /match` - Terminal-to-session matching

**Depends on:**
- `~/.claude/projects/` - Claude session transcripts
- `TalkieServer` (Swift) - For window operations (port 8766)
- Tailscale - For remote access authentication

## Gateway Module

**Purpose:** External API translation. Unified interface to cloud inference providers.

**Routes:**
- `POST /inference` - Run inference through any provider
- `GET /inference/providers` - List available providers
- `GET /inference/models` - List models for a provider

**Request format:**
```json
{
  "provider": "anthropic",
  "model": "claude-3-5-sonnet-20241022",
  "messages": [
    { "role": "user", "content": "Hello" }
  ],
  "temperature": 0.7,
  "maxTokens": 1024
}
```

**Supported providers:**
- `openai` - GPT models
- `anthropic` - Claude models
- `google` - Gemini models (planned)
- `groq` - Fast inference (planned)

## Running

```bash
# Development (local mode, no Tailscale required)
bun run src/server.ts --local

# Production (requires Tailscale)
bun run src/server.ts

# Explicit LAN discovery/pairing
bun run src/server.ts --nearby --allow-lan --require-approval
```

**Ports:**
- `8765` - Production (Tailscale)
- `8767` - Local development
- `/tmp/talkie-server.sock` - Unix socket (enabled in local mode)

## Module Design

Bridge and Gateway are Elysia apps that get composed:

```typescript
// server.ts
import { bridge } from "./bridge";
import { gateway } from "./gateway";

const app = new Elysia()
  .use(bridge)
  .use(gateway)
  .listen(PORT);
```

Each module is self-contained and could theoretically run standalone:

```typescript
// If you ever needed separate processes
bridge.listen(8765);
gateway.listen(8766);
```

But the default (and recommended) setup is combined: one process, one port.

## Directory Structure

```
TalkieServer/
├── src/
│   ├── server.ts           # Entry point, mounts modules
│   ├── log.ts              # Logging
│   ├── paths.ts            # File paths
│   │
│   ├── bridge/             # Bridge module
│   │   ├── index.ts        # Elysia app export
│   │   └── routes/         # Route handlers
│   │
│   ├── gateway/            # Gateway module
│   │   ├── index.ts        # Elysia app export
│   │   ├── routes/         # Route handlers
│   │   └── providers/      # Provider implementations
│   │
│   ├── auth/               # HMAC authentication
│   ├── crypto/             # Key management
│   ├── devices/            # Paired device registry
│   ├── discovery/          # Session discovery & caching
│   ├── matching/           # Terminal ↔ session matching
│   └── tailscale/          # Tailscale status checking
```

## Authentication

- **Local mode (`--local`)**: loopback TCP plus Unix socket; sensitive local routes require the bearer token in the local token file
- **Nearby mode (`--nearby --allow-lan`)**: explicit LAN/Tailscale advertising for nearby device pairing
- **Production**: HMAC signature verification on paired-device requests, bound to Tailscale
- **Exempt paths**: `/health`, `/pair/info`, `GET /pair`

## Gateway Protocol

TalkieServer is the **reference implementation** of the [Talkie Gateway Protocol](../../docs/specs/gateway-protocol.md) — a WebSocket contract that lets Talkie connect to any AI backend for inference, transcription, and speech synthesis.

### Why a protocol?

Today, Talkie talks to TalkieServer over HTTP for inference. The Gateway Protocol adds a WebSocket endpoint (`/gateway`) that supports streaming inference, real-time ASR, and future TTS — capabilities that don't map well to request/response HTTP.

More importantly, the protocol is **implementation-agnostic**. Anyone can build a server that speaks the Gateway Protocol — run local Whisper, proxy to cheap APIs, host your own models. Point Talkie at a port, done.

### How it fits

```
┌─────────────────────────────────────────────────────────────┐
│                     Swift App (Talkie)                      │
└──────────┬──────────────────────┬───────────────────────────┘
           │ HTTP (existing)      │ WebSocket (Gateway Protocol)
           ▼                      ▼
┌─────────────────────────────────────────────────────────────┐
│                       TalkieServer                          │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Bridge      │  │   Gateway    │  │   Extensions     │  │
│  │   (system)    │  │  (AI svcs)   │  │  (browser ext)   │  │
│  │              │  │              │  │                  │  │
│  │  /sessions   │  │  /inference  │  │  ws://…/ext      │  │
│  │  /windows    │  │  ws://…/gw   │  │                  │  │
│  │  /pair       │  │              │  │                  │  │
│  └──────────────┘  └──────────────┘  └──────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

The HTTP inference routes are preserved. The WebSocket endpoint is additive.

### Extensions vs Gateway Protocol

| | Extensions (`/extensions`) | Gateway Protocol (`/gateway`) |
|---|---|---|
| **Direction** | External clients → TalkieServer | Talkie → External server |
| **Purpose** | Browser extensions consume Talkie services | Talkie consumes AI services from any backend |
| **Auth** | Token-based (required) | None for v1 (localhost) |
| **Status** | Implemented | Spec defined, endpoint planned |

### Spec & implementation docs

- **Protocol spec**: [`docs/specs/gateway-protocol.md`](../../docs/specs/gateway-protocol.md) — the wire format
- **Reference guide**: [`docs/specs/gateway-reference.md`](../../docs/specs/gateway-reference.md) — how TalkieServer implements it, how tinkerers can build their own

## Future Considerations

1. **Gateway Protocol endpoint** - Add `ws://localhost:8765/gateway` to the Gateway module
2. **Unix socket as primary IPC** - Swift calls through socket, HTTP for debugging
3. **More providers** - Google, Groq, local models
4. **Streaming inference** - Via Gateway Protocol WebSocket
5. **Module hot-reload** - Update modules without full restart

---

*This architecture is intentionally simple. One process, one port, three modules. Complexity can be added when needed.*
