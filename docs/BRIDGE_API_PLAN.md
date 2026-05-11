# BridgeServer Unified API + Shared Data Layer

## Overview

Move TalkieObject model and read-only queries into TalkieKit. Make Agent's BridgeServer (:8767) the single local API. CLI becomes a thin HTTP client.

## Current State

| Component | Location | Protocol | Status |
|-----------|----------|----------|--------|
| TalkieObject model | `apps/macos/Talkie/Data/Models/Recording.swift` | — | App-internal, imports SwiftUI |
| TalkieObjectRepository | `apps/macos/Talkie/Data/Database/RecordingRepository.swift` (1454 lines) | — | App-internal, depends on DatabaseManager |
| Agent BridgeServer | `apps/macos/TalkieAgent/.../BridgeServer.swift` | HTTP :8767 | 5 routes (health, windows, screenshots) |
| Agent UnifiedDatabase | `apps/macos/TalkieAgent/.../UnifiedDatabase.swift` | — | Has `LiveRecording` parallel struct, raw GRDB |
| TalkieServer (Swift) | `apps/macos/Talkie/Services/TalkieServer.swift` | HTTP :8766 | In main app process, bridges Agent XPC |
| TalkieServer (TS) | `apps/macos/TalkieServer/src/server.ts` | HTTP :8765 | Cloud gateway only |
| CLI | `packages/npm/cli/src/` | Direct SQLite + WebSocket | Duplicates query logic, fictional WS ports |
| Engine/Sync/Inference | XPC services | XPC only | No network ports |

## Target Architecture

```
External clients (SDK, Lattices, CLI, iOS Bridge)
         |
         v
   Agent BridgeServer (:8767)
         |
    +---------+------------------+
    |         |                  |
    v         v                  v
  GRDB     XPC->Engine      Agent internals
  (read    (transcribe,     (dictation, mic,
  memos,    models)          keyboard, screenshots)
  dictations,
  stats)
```

## Route Namespaces

### `/talkie` — Data (GRDB direct)

| Route | Method | Source | Description |
|-------|--------|--------|-------------|
| `/talkie/memos` | GET | TalkieObjectReader | List memos. Params: `limit`, `offset`, `sort`, `search`, `since` |
| `/talkie/memos/:id` | GET | TalkieObjectReader | Single memo by ID (or ID prefix) |
| `/talkie/dictations` | GET | TalkieObjectReader | List dictations. Same params |
| `/talkie/dictations/:id` | GET | TalkieObjectReader | Single dictation |
| `/talkie/search` | GET | TalkieObjectReader | Full-text search. Params: `q`, `type`, `limit` |
| `/talkie/stats` | GET | TalkieObjectReader | Aggregate stats (counts, durations, streak, top apps) |
| `/talkie/activity` | GET | TalkieObjectReader | Activity heatmap data. Params: `days` |

### `/agent` — I/O (mic, keyboard, screen)

| Route | Method | Source | Description |
|-------|--------|--------|-------------|
| `/agent/health` | GET | Direct | Agent status, uptime |
| `/agent/status` | GET | Direct | Current state (recording, idle, etc.) |
| `/agent/dictation/start` | POST | DictationCoordinator | Start dictation |
| `/agent/dictation/stop` | POST | DictationCoordinator | Stop dictation |
| `/agent/paste` | POST | KeyboardService | Inject text into active app |
| `/agent/windows` | GET | ScreenshotService | List windows (existing) |
| `/agent/windows/claude` | GET | ScreenshotService | Claude windows (existing) |
| `/agent/screenshots/terminals` | GET | ScreenshotService | Terminal screenshots (existing) |
| `/agent/screenshots/window/:id` | GET | ScreenshotService | Window screenshot (existing) |

### `/engine` — Transcription (XPC proxy)

| Route | Method | Source | Description |
|-------|--------|--------|-------------|
| `/engine/transcribe` | POST | XPC -> TalkieEngine | Transcribe audio file |
| `/engine/models` | GET | XPC -> TalkieEngine | List available models |
| `/engine/status` | GET | XPC -> TalkieEngine | Engine health + loaded model |

## Implementation Phases

### Phase 1: Move TalkieObject Model to TalkieKit

**Goal**: Data model importable by all targets. No behavior change.

**Create in TalkieKit** (`Sources/TalkieKit/Data/`):

| File | Contents |
|------|----------|
| `TalkieObject.swift` | Core struct + GRDB conformances (FetchableRecord, PersistableRecord, TableRecord, Columns enum) |
| `TalkieObjectTypes.swift` | `TalkieObjectType`, `RecordingSource`, `RecordingTranscriptionStatus`, `RecordingFilter`, `RecordingSortField` |
| `TalkieObjectMetadata.swift` | `RecordingMetadata`, `TalkieObjectAssets`, `AppContext`, `RichContext`, `PerformanceMetrics`, `RoutingInfo`, `AudioMetrics`, `RefinementInfo` |

**What stays in main app** (`Recording.swift` becomes thin extension):
- `audioURL` computed property (depends on `AudioStorage`)
- `toMemoModel()` bridge (depends on `MemoModel`)
- Migration initializers `init(from: MemoModel)`, `init(from: LiveDictation)`
- GRDB associations to app-internal types (`TranscriptVersionModel`, `WorkflowRunModel`)

**Key detail**: TalkieKit already `@_exported import SwiftUI`, so `RecordingSource.color` can stay on the type. No need for a separate UI extension.

**Steps**:
1. Create three new files in TalkieKit with `public` access modifiers
2. Remove `AudioStorage` and `MemoModel` dependencies from TalkieKit version
3. Slim down main app's `Recording.swift` to `extension TalkieObject` with app-specific properties
4. Build all targets, verify

### Phase 2: Create TalkieObjectReader in TalkieKit

**Goal**: Shared read-only query layer usable by any target with a `DatabaseReader`.

**Create**: `Sources/TalkieKit/Data/TalkieObjectReader.swift`

```swift
public struct TalkieObjectReader: Sendable {
    private let reader: any DatabaseReader

    public init(reader: any DatabaseReader) {
        self.reader = reader
    }

    public func fetchRecordings(
        type: TalkieObjectType? = nil,
        sortBy: RecordingSortField = .createdAt,
        ascending: Bool = false,
        limit: Int = 50,
        offset: Int = 0,
        searchQuery: String? = nil,
        filters: Set<RecordingFilter> = []
    ) throws -> [TalkieObject] { ... }

    public func fetchRecording(id: UUID) throws -> TalkieObject? { ... }
    public func searchRecordings(query: String, limit: Int = 50) throws -> [TalkieObject] { ... }
    public func countMemos() throws -> Int { ... }
    public func countDictations() throws -> Int { ... }
    public func totalDuration(type: TalkieObjectType? = nil) throws -> Double { ... }
    public func calculateDictationStreak() throws -> Int { ... }
    public func topDictationApps(limit: Int = 5) throws -> [(name: String, bundleID: String?, count: Int)] { ... }
    public func dictationActivityByDay(days: Int = 91) throws -> [String: Int] { ... }
    // ... etc
}
```

**Design decisions**:
- Takes `any DatabaseReader` (protocol both `DatabaseQueue` and `DatabasePool` conform to)
- Methods are synchronous + throwing (not async). Callers wrap in Task as needed
- Main app's `TalkieObjectRepository` delegates read calls to an internal `TalkieObjectReader`
- Agent creates `TalkieObjectReader(reader: UnifiedDatabase.shared)`

**Steps**:
1. Extract ~25 read methods from `RecordingRepository.swift` into `TalkieObjectReader`
2. Refactor `TalkieObjectRepository` to hold internal reader, delegate reads
3. Wire Agent's `UnifiedDatabase` to expose a `TalkieObjectReader`
4. Build all targets, verify

### Phase 3: Wire BridgeServer Routes

**Goal**: BridgeServer serves `/talkie/*` and reorganized `/agent/*` routes.

**Create in Agent** (`Services/`):

| File | Purpose |
|------|---------|
| `BridgeRouter.swift` | URL parsing, query params, prefix routing |
| `TalkieRoutes.swift` | `/talkie/*` handlers using `TalkieObjectReader` |
| `AgentRoutes.swift` | `/agent/*` handlers (existing routes moved + new dictation endpoints) |

**Refactor `BridgeServer.swift`**:
- Replace flat `switch` with prefix-based router
- Add URL query parameter parsing
- Add request body reading for POST routes
- Keep old paths as aliases during transition

**JSON serialization**: `TalkieObject` is `Codable` — use `JSONEncoder` with `.iso8601` date strategy, `.string` UUID strategy.

**Steps**:
1. Add URL/query-param parsing to BridgeServer
2. Create `TalkieRoutes` with `/talkie/*` handlers
3. Move existing routes to `AgentRoutes` under `/agent/*` prefix
4. Register both at startup with reader from `UnifiedDatabase`
5. Build, test with `curl`

### Phase 4: Engine/Inference Proxy Routes

**Goal**: BridgeServer proxies to Engine and Inference via XPC.

**Create**: `EngineProxyRoutes.swift`, `InferenceProxyRoutes.swift`

Agent already has XPC connections to Engine (for transcription). These routes translate HTTP -> XPC calls. Can be deferred — CLI can keep using existing WebSocket bridges initially.

### Phase 5: Migrate CLI to HTTP Client

**Goal**: CLI uses BridgeServer instead of direct SQLite.

**Changes**:

| Before | After |
|--------|-------|
| `import { getDb } from "./db"` | `import { apiGet } from "./api"` |
| `queryAll("SELECT ... FROM recordings ...")` | `apiGet("/talkie/memos", { limit })` |
| `callBridge(19821, "transcribe", ...)` | `apiPost("/engine/transcribe", ...)` |

**New file**: `packages/npm/cli/src/api.ts` — HTTP client for `http://127.0.0.1:8767`

**Delete**: `packages/npm/cli/src/db.ts` (or keep as fallback if BridgeServer is down)

**Fallback**: Detect BridgeServer availability, fall back to direct SQLite for reads. Remove fallback once Agent auto-launch is reliable.

### Phase 6: Consolidate Agent's LiveRecording

**Goal**: Agent writes `TalkieObject` directly, deletes `LiveRecording`.

After Phase 1, `TalkieObject` is in TalkieKit. Agent replaces:
- `LiveRecording` struct -> `TalkieObject` with factory `TalkieObject.newDictation(...)`
- Custom INSERT logic -> `TalkieObject`'s `PersistableRecord` conformance
- Custom SELECT queries -> `TalkieObjectReader` methods

**Deletes**: `LiveRecording` struct, most of `UnifiedDatabase.swift`'s custom code.

## Phase Dependencies

```
Phase 1 (Model -> TalkieKit)
  |
  v
Phase 2 (TalkieObjectReader)
  |
  +----> Phase 3 (BridgeServer routes)
  |        |
  |        +----> Phase 4 (Engine/Inference proxy)
  |        |
  |        +----> Phase 5 (CLI migration)
  |
  +----> Phase 6 (Consolidate LiveRecording)
```

Each phase produces a working build. Phases 3-6 can be parallelized after Phase 2.

## File Structure (Final)

```
apps/macos/TalkieKit/Sources/TalkieKit/
  Data/
    TalkieObject.swift                  # Core struct + GRDB
    TalkieObjectTypes.swift             # Enums
    TalkieObjectMetadata.swift          # Metadata, Assets
    TalkieObjectReader.swift            # Read-only query layer

apps/macos/Talkie/Data/Models/
  Recording.swift                       # Slim: extension TalkieObject (app-specific)

apps/macos/TalkieAgent/.../Services/
  BridgeServer.swift                    # Refactored with router
  BridgeRouter.swift                    # URL parsing, prefix routing
  TalkieRoutes.swift                    # /talkie/* -> TalkieObjectReader
  AgentRoutes.swift                     # /agent/* -> existing + dictation
  EngineProxyRoutes.swift               # /engine/* -> XPC
packages/npm/cli/src/
  api.ts                                # HTTP client for BridgeServer
  commands/memos.ts                     # Rewritten: apiGet("/talkie/memos")
  commands/dictations.ts                # Rewritten: apiGet("/talkie/dictations")
  commands/search.ts                    # Rewritten: apiGet("/talkie/search")
  commands/stats.ts                     # Rewritten: apiGet("/talkie/stats")
```

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| GRDB version mismatch between TalkieKit and app | Build failure | Workspace-level Package.resolved handles this |
| Reader blocking BridgeServer's Network.framework queue | Server stalls | Dispatch reader calls to background queue |
| Column parity between Agent and app migrations | Silent data corruption | Verify migrations match before Phase 6 |
| CLI fallback complexity (direct SQLite + HTTP) | Maintenance burden | Remove direct SQLite once BridgeServer proven reliable |
| BridgeServer HTTP parsing is minimal | Edge cases | Only handles localhost; keep parsing simple |
