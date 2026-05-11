# Gateway Protocol — Reference Implementation

> TalkieServer's implementation of the Gateway Protocol.

## Overview

TalkieServer (TypeScript/Bun) is Talkie's own backend. It ships as a single process serving three modules — Bridge, Gateway, and Extensions. The Gateway module is the first implementation of the [Gateway Protocol](gateway-protocol.md), dogfooding the spec with real LLM inference.

You don't need TalkieServer. If you want to bring your own backend — local Whisper, self-hosted LLMs, cheap cloud proxies — build a server that implements the WebSocket contract from [gateway-protocol.md](gateway-protocol.md) and point Talkie at it.

## Current State

TalkieServer currently provides **HTTP routes** for inference. The WebSocket Gateway Protocol endpoint (`/gateway`) is planned as an addition alongside the existing HTTP API.

### Existing HTTP routes (preserved)

| Method | Route | Description |
|--------|-------|-------------|
| `POST` | `/inference` | Run inference through any provider |
| `GET` | `/inference/providers` | List available providers |
| `GET` | `/inference/models` | List models for a provider |

### Planned WebSocket endpoint

| Endpoint | Protocol | Description |
|----------|----------|-------------|
| `ws://localhost:8765/gateway` | Gateway Protocol v1 | WebSocket endpoint implementing the spec |

The HTTP routes and WebSocket endpoint will coexist. Existing Swift code that uses HTTP continues to work. New capabilities (streaming inference, real-time transcription) will use the WebSocket protocol.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Swift App (Talkie)                      │
└──────────┬──────────────────────┬───────────────────────────┘
           │ HTTP (existing)      │ WebSocket (Gateway Protocol)
           ▼                      ▼
┌─────────────────────────────────────────────────────────────┐
│                       TalkieServer                          │
│                     (single process)                        │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Bridge      │  │   Gateway    │  │   Extensions     │  │
│  │              │  │              │  │                  │  │
│  │  • Sessions  │  │  • HTTP API  │  │  • ws://…/ext    │  │
│  │  • Windows   │  │  • WS /gw ← │  │  • Browser ext   │  │
│  │  • Pairing   │  │  • Providers │  │  • Transcription  │  │
│  └──────────────┘  └──────┬───────┘  └──────────────────┘  │
│                           │                                 │
│                    ┌──────┴───────┐                          │
│                    │  Providers   │                          │
│                    │  • OpenAI    │                          │
│                    │  • Anthropic │                          │
│                    │  • Google *  │                          │
│                    │  • Groq *    │                          │
│                    └──────────────┘  (* = planned)           │
└─────────────────────────────────────────────────────────────┘
```

## Extensions vs Gateway Protocol

These are **separate WebSocket endpoints for opposite directions**:

| | Extensions (`/extensions`) | Gateway Protocol (`/gateway`) |
|---|---|---|
| **Direction** | External clients → TalkieServer | Talkie → External server |
| **Purpose** | TalkieServer provides services to browser extensions | External server provides AI services to Talkie |
| **Auth** | Token-based (required) | None for v1 |
| **Status** | Fully implemented | Spec defined, endpoint planned |

They share design patterns (capability negotiation, namespaced messages, JSON frames) but serve opposite purposes. The Extensions endpoint lets browsers talk to Talkie. The Gateway Protocol lets Talkie talk to any AI backend.

## Provider System

TalkieServer routes inference to cloud providers through a unified `Provider` interface.

### Provider interface

```typescript
interface Provider {
  name: string;
  inference(request: InferenceRequest): Promise<InferenceResponse>;
  listModels?(): Promise<string[]>;
}
```

### Adding a provider

1. Create `src/gateway/providers/your-provider.ts`
2. Implement the `Provider` interface
3. Register it in `src/gateway/providers/index.ts`:

```typescript
import { YourProvider } from "./your-provider";

// In initProviders():
providers.set("your-provider", new YourProvider());
```

4. Add the name to the `ProviderName` union type in `src/gateway/providers/types.ts`

### Current providers

| Provider | File | API Key Env Var |
|----------|------|-----------------|
| OpenAI | `src/gateway/providers/openai.ts` | `OPENAI_API_KEY` |
| Anthropic | `src/gateway/providers/anthropic.ts` | `ANTHROPIC_API_KEY` |

## Directory Structure

```
TalkieServer/
├── src/
│   ├── server.ts              # Entry point, mounts modules
│   ├── log.ts                 # Logging
│   ├── paths.ts               # File paths
│   │
│   ├── bridge/                # Bridge module (system integration)
│   │   ├── index.ts
│   │   └── routes/
│   │
│   ├── gateway/               # Gateway module (inference)
│   │   ├── index.ts           # Elysia app, HTTP routes
│   │   ├── routes/
│   │   │   └── inference.ts   # POST /inference handler
│   │   └── providers/
│   │       ├── index.ts       # Provider registry
│   │       ├── types.ts       # Provider interface + request/response types
│   │       ├── openai.ts      # OpenAI provider
│   │       └── anthropic.ts   # Anthropic provider
│   │
│   ├── extensions/            # Extensions module (browser clients)
│   │   ├── index.ts           # WebSocket endpoint + HTTP routes
│   │   ├── types.ts           # Protocol v2 message types
│   │   ├── handlers.ts        # Message handlers
│   │   ├── auth.ts            # Token authentication
│   │   └── headless.ts        # Headless transcription
│   │
│   ├── auth/                  # Authentication (HMAC + local bearer)
│   ├── crypto/                # Key management
│   ├── devices/               # Paired device registry
│   ├── discovery/             # Session discovery & caching
│   ├── matching/              # Terminal ↔ session matching
│   └── tailscale/             # Tailscale status checking
```

## Running

```bash
# Development (local mode, no Tailscale, port 8765)
cd apps/macos/TalkieServer
bun run src/server.ts --local

# Production (requires Tailscale, port 8765)
bun run src/server.ts

# With Unix socket for Swift IPC
bun run src/server.ts --local --unix
```

**Ports:**

| Mode | Port | Binding |
|------|------|---------|
| Default | 8765 | `127.0.0.1` (localhost only) |
| Unix socket | `/tmp/talkie-server.sock` | local only |

Custom port: `bun run src/server.ts --local --port 9000`

## For Tinkerers

You don't need TalkieServer. Build your own Gateway Protocol server.

### Minimal inference-only server (conceptual)

```python
# Python example — not production code, just showing the shape

import asyncio, json, websockets

async def handler(ws):
    # Send hello
    await ws.send(json.dumps({
        "type": "hello",
        "version": "1",
        "capabilities": ["inference"]
    }))

    # Wait for client hello
    msg = json.loads(await ws.recv())
    assert msg["type"] == "hello"

    # Handle messages
    async for raw in ws:
        msg = json.loads(raw)

        if msg["type"] == "ping":
            await ws.send(json.dumps({"type": "pong"}))

        elif msg["type"] == "inference:request":
            # Call your LLM here
            result = call_my_llm(msg["messages"])
            await ws.send(json.dumps({
                "type": "inference:result",
                "id": msg["id"],
                "content": result,
                "model": "my-local-model"
            }))

asyncio.run(websockets.serve(handler, "localhost", 9000))
```

### Connecting Talkie to your server

1. Build a server that implements the [Gateway Protocol](gateway-protocol.md)
2. Start it on a port (e.g., `localhost:9000`)
3. In Talkie: **Settings > Advanced > Gateway URL** → `ws://localhost:9000/gateway`

### What you can build

- **Local Whisper server** — Implement `transcribe` capability, route audio to whisper.cpp
- **Cheap cloud proxy** — Implement `inference`, route to Groq/Together/your-favorite-api
- **Multi-model router** — Accept any model hint, route to the cheapest/fastest provider
- **On-device LLM** — Run Llama/Mistral locally via llama.cpp, expose as `inference`
- **Custom TTS** — Implement `synthesize`, use Coqui/Bark/your-favorite-tts
