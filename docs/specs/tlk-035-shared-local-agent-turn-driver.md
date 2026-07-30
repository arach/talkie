# TLK-035 — Shared Local Agent Turn Driver

**Status**: Proposed
**Owner**: arach
**Studio**: /eng/tlk-035
**Related**: TLK-034, OpenScout local agent turn layer, Lattices agent runner

## Summary

Talkie, Lattices, and OpenScout currently overlap at the same boundary: starting a
local agent process, speaking its native protocol, resuming a task, delivering a
turn, and interpreting completion. That machinery should have one source of
truth in OpenScout.

OpenScout should own a reusable local-agent turn driver and the Codex app-server
implementation. Talkie and Lattices should retain their product policy and use
small runtime shims that configure and call that driver. Talkie must not move
Watch durability, channel selection, or user-facing delivery policy into Scout.

This is an extraction and consolidation, not a rewrite of the Talkie bridge or a
new generic agent framework.

## Evidence in the current checkouts

- OpenScout already contains `CodexAppServerTransport` under
  `packages/agent-sessions` and uses it from the Codex adapter.
- The OpenScout Codex adapter currently chooses `steerTurn` whenever a turn is
  active and otherwise chooses `startTurn`.
- OpenScout also has a second Codex app-server runtime implementation. Its local
  agent turn-layer proposal already calls for deduplicating these paths.
- Lattices contains the prototype `@openscout/agent-runner`, which depends on
  `@openscout/agent-sessions`, maps Codex to `createCodexAdapter`, and says that
  the package is intended to move into OpenScout.
- TalkieServer independently owns Codex process startup, JSON-RPC framing,
  task creation and resume, turn delivery, rollout observation, and terminal
  receipts in `codex-desktop-bridge.cjs`.

The duplication is therefore implementation-level: process lifecycle, protocol
framing, session identity, delivery semantics, event normalization, and terminal
state are being solved in more than one repository.

## Ownership boundary

### OpenScout owns

- Codex executable discovery and app-server process lifecycle.
- Initialization and JSON-RPC framing.
- Native task start, list, and resume operations.
- Native turn start, steer, and interrupt operations.
- Driver-managed queue sequencing when the native harness does not expose a
  queue operation.
- Normalized acceptance and terminal events.
- Native terminal meanings: completed, failed, and interrupted.
- Capability reporting for steering, queuing, resuming, and streaming.
- Stable request identity and retry behavior at the driver boundary.
- Transport-level crash detection and session recovery.

### Talkie owns

- Watch audio capture, transfer, and transcription.
- The durable phone-side Watch dispatch queue and background continuation.
- Host, project, channel, and lane selection.
- The default delivery policy: queue is safe; steer is explicit.
- HTTP compatibility for Talkie clients.
- Domain job persistence, user-facing receipts, narration, and notifications.
- The truthful distinction between accepted, queued, running, completed,
  failed, and interrupted in the iPhone and Watch UI.

### Lattices owns

- Its workspace and surface-specific session policy.
- Presentation of local-agent state and events.
- Product-specific defaults and permission affordances.

Neither Talkie nor Lattices should parse Codex app-server JSON-RPC after the
migration. Both may expose a product-named package that re-exports and configures
the OpenScout driver.

## Required shared contract

The shared API must not infer delivery mode from whether a turn happens to be
active. That would erase a product decision that Talkie exposes directly.

One representative TypeScript shape is:

```ts
type DeliveryMode = "start" | "steer" | "queue";

type ThreadTarget =
  | { mode: "new"; cwd: string }
  | { mode: "existing"; threadId: string };

type TurnRequest = {
  requestId: string;
  target: ThreadTarget;
  delivery: DeliveryMode;
  text: string;
};

type TurnReceipt = {
  requestId: string;
  threadId: string;
  turnId?: string;
  state: "queued" | "accepted" | "running" | "completed"
    | "failed" | "interrupted";
  error?: { code: string; message: string };
};

interface LocalAgentTurnDriver {
  submit(request: TurnRequest): Promise<TurnReceipt>;
  status(requestId: string): Promise<TurnReceipt>;
  interrupt(input: { threadId: string; turnId: string }): Promise<void>;
  events(): AsyncIterable<TurnReceipt>;
}
```

The production interface may separate session startup from submission, but it
must preserve these semantics:

1. The caller explicitly chooses start, steer, or queue.
2. Every submission has a caller-generated request ID.
3. Retrying a request ID returns the same logical receipt or a conflict; it does
   not silently create another task or turn.
4. A fresh-task request returns the exact new task identity.
5. Queue is ordered by the driver when the harness has no native queue.
6. Failed and interrupted are terminal outcomes, not rollout-file timeouts.
7. Acceptance is distinct from completion.

## Idempotency and crash boundary

Codex app-server does not currently accept a caller idempotency key for
`thread/start`. OpenScout can deduplicate before issuing the native request and
persist a receipt after it returns, but a process crash between those events
leaves an unavoidable uncertainty window.

The shared driver must expose that uncertainty as a specific outcome. It must
not guess by working directory, title, or creation time. A stronger atomic
create-and-start guarantee ultimately requires native Codex support for request
identity or a queryable correlation field.

Talkie may persist a domain job before calling the driver and retry safe states,
but it must show an indeterminate/retry-required receipt when the driver cannot
prove whether a native task was created.

## Migration plan

1. **Consolidate inside OpenScout.** Extract one
   `CodexAppServerTurnDriver` from the existing agent-sessions transport and the
   duplicate runtime implementation without changing current behavior.
2. **Make delivery explicit.** Add start, steer, and driver-managed queue modes,
   normalized terminal outcomes, request receipts, and capability reporting.
3. **Add durability semantics.** Persist request-to-task/turn receipts and test
   retry, conflict, process restart, interrupted turns, and the uncertain
   `thread/start` crash window.
4. **Move the runner.** Move the Lattices `@openscout/agent-runner` prototype
   into OpenScout and have it call the shared driver rather than layering a
   second Codex policy over `send()`.
5. **Introduce a Talkie shim.** Keep the current Talkie HTTP and receipt shapes,
   but replace Codex process and protocol internals with the OpenScout driver.
6. **Run conformance in shadow.** Replay fixtures through the old Talkie bridge
   and new driver for task creation, resume, queue, steer, completion, failure,
   interruption, and restart. Compare normalized receipts.
7. **Cut over and soak.** Switch the TalkieServer route internals behind the
   unchanged client contract. Remove the app-server implementation from
   `codex-desktop-bridge.cjs` only after the Watch and iPhone paths have soaked.

## Compatibility requirements

- The current Talkie HTTP routes and Watch receipt payloads remain compatible
  during the first cutover.
- Talkie's queue default and explicit steer selection remain unchanged.
- Existing exact-task routing remains based on Codex task ID.
- A Scout update cannot change Talkie delivery policy through an automatic
  `send()` heuristic.
- Product-specific persistence stays outside the shared driver.
- The shared runner can be consumed without starting the Scout broker.

## Acceptance criteria

- There is one Codex app-server framing and process-lifecycle implementation in
  OpenScout.
- Talkie and Lattices contain no Codex JSON-RPC framing.
- Start, steer, and queue are explicit and independently tested.
- Completed, failed, and interrupted have identical normalized meanings for all
  consumers.
- Retrying a known request ID never creates a second logical task or turn.
- The unprovable hard-crash window is represented truthfully and documented.
- Talkie's existing iPhone and Watch dispatch tests pass against the shared
  driver.
- Lattices consumes the same published OpenScout package through a thin shim.
- OpenScout has conformance fixtures for task create/resume and turn terminal
  states.

## Non-goals

- Moving WatchConnectivity, audio, transcription, lanes, or Talkie UI state
  into OpenScout.
- Making the Scout broker part of Talkie's local dispatch critical path.
- Automatically approving agent permissions.
- Generalizing every harness before the Codex contract is proven.
- Changing the current Talkie client API during the first extraction.

## Studio follow-up

Use `/eng/tlk-035` to review the ownership boundary, delivery-state vocabulary,
and migration order before changing the Talkie bridge dependency. A visual
study is not required for the transport extraction; any later receipt-state UI
work should use the existing Codex Deck surface.
