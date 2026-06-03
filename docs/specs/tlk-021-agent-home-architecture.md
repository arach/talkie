# TLK-021 — Talkie Agent Home Architecture

**Status**: Draft
**Owner**: arach
**Related**: TLK-020 Talking to Agents
**Influences**: Lattices unified window, HudsonKit shell primitives
**Studio**: /eng/tlk-021
**Surface**: /mac-agent-home
**Review**: Claude-side Scout pass in `docs/specs/tlk-021-review-claude.md`

## Summary

Talkie Agent needs a real home surface: one place to see what the local agent
is doing, what it heard, what it handed to an agent, and what needs follow-up.
This should not become a separate branded app or another gimmicky destination.
Talking to agents is an input mode. Agent Home is the durable place.

The current first pass proves the product shape: a normal Talkie Agent window
with Now, Activity, Voice, and Agents sections. The next architectural pass is
not just a page split. It must first firm up the runtime/activity boundary so the
home surface does not multiply expensive status reads or depend on a private
`jobs.json` backchannel.

## Goals

- Give Talkie Agent a first-class home window, reachable from the menu bar,
  keyboard shortcuts, and deep links.
- Treat voice, agent sessions, routines, and future agent work as activity inside
  one Agent surface.
- Keep the live talking-to-agents scope ephemeral. It handles press-to-talk and immediate
  acknowledgement, then returns durable work to Agent Home.
- Preserve multi-LLM and multi-agent boundaries. The home UI displays runtime,
  provider, model, and session identity without coupling itself to one worker.
- Reuse proven architecture patterns from Lattices and HudsonKit without
  importing their visual identity wholesale.
- Make agent activity a typed projection over voice captures, agent sessions,
  routines, and future work.

## Non-Goals

- Bring back Walkie as product language.
- Build a second standalone app surface for long-running agent work.
- Move agent orchestration into SwiftUI views.
- Copy HudsonKit or Lattices component code directly before there is a clear
  package boundary.
- Make Agent Home the default activation posture for the menu bar helper.

## Product Model

Agent Home is the durable return path for agent work.

Initial sections:

- **Now** — active work, current runtime status, latest meaningful event, and a
  compact digest. It is a dashboard, not a second full feed.
- **Activity** — completed and in-progress agent work across voice, routines,
  and agent sessions.
- **Voice** — recent captures and voice-mode health.
- **Agents** — a conversation trace where voice turns are the trunk and
  agent/action threads branch from those turns. Dispatcher, Scout bridge,
  provider/model, and open session state remain visible inside each thread.

Future sections can include **Routines**, **Agent Context**, or **Settings**,
but the first architectural move is to make the shell capable of adding them
without turning the view into a switch-heavy monolith.

Avoid a vague **Memory** section until there is a concrete object. If the future
surface means browsing agent context/state, name it that. If it means surfacing
memos, link to the existing memo primitive instead of introducing a fourth word.

## Critical Prerequisites

These come before the UI page split.

### Persistent Runtime Transport

`WalkieNodeRuntimeClient` should not spawn a fresh Node process for every ping or
activity status read. The Node runtime is already shaped as a long-lived stdin loop,
so Agent Home should talk to a persistent child process, daemon, unix socket, or
XPC bridge.

Polling every few seconds is fine only if reads are cheap. A page split without
this fix risks multiplying process-spawn overhead across stores.

### Typed Runtime Status IPC

Agent Home should not decode the runtime's private `jobs.json` file directly.
The Node runtime should expose typed IPC operations:

```json
{ "op": "status" }
```

The `status` operation returns runtime identity plus public activity records:

```json
{
  "ok": true,
  "runtime": {
    "id": "walkie-node-dispatcher",
    "name": "Agent Runtime Dispatcher",
    "capabilities": ["readOnlyData", "longRunningJobs"],
    "scoutBridge": "configured"
  },
  "activities": [
    {
      "id": "UUID",
      "sessionId": "walkie-UUID",
      "state": "running",
      "ack": "spoken acknowledgement",
      "instruction": "agent-ready instruction",
      "transcript": "raw source transcript",
      "providerId": "openai",
      "modelId": "gpt-5.5",
      "conversationId": "channel-ch-01",
      "parentSessionId": "walkie-previous",
      "source": "voice",
      "channelCode": "CH-01",
      "createdAt": "ISO-8601",
      "updatedAt": "ISO-8601"
    }
  ]
}
```

The file can remain an implementation detail of the runtime, but it is not the UI
contract. If the runtime writes a file, writes should be atomic.

First pass status: `WalkieNodeRuntimeClient.status()` now drives Agent Home
agent activity through the runtime boundary. Persistent child-process transport
and richer output/progress fields are still pending.

### Activity Projection

Define an `AgentHomeActivityFeed` before splitting pages. The feed projects
multiple sources into one typed stream:

```swift
struct AgentHomeActivityItem: Identifiable {
    enum Kind {
        case agentSession(AgentHomeExecutorJob)
        case dictation(LiveRecording)
        case routine(AgentHomeRoutineSnapshot)
        case voiceCapture(AgentHomeVoiceCapture)
    }

    let id: String
    let originId: String?
    let kind: Kind
    let title: String
    let subtitle: String
    let status: AgentHomeActivityStatus
    let occurredAt: Date
}
```

Pages filter or summarize this projection; they do not each reach into
`UnifiedDatabase`, runtime pings, and job storage independently.

### Source of Truth for Completed Output

For v1, agent session state and output are exposed through the runtime `status` IPC
operation. The Node store is an operational cache with rotation/eviction, not a
forever product database. If agent output becomes user-visible history beyond
the Agent Home activity window, promote it into a proper Agent activity store in
Talkie-owned persistence before broadening the UI.

Every longer-running invocation must carry a stable `originId` that joins back to the source
voice turn or dictation. Without that, the inspector cannot reliably
show transcript, instruction, and output together.

### Conversation Loop and Trace

Agent Home is not just a queue viewer. It is the durable place where the user can
continue an agent conversation after the original voice or typed turn.

Every invocation should carry:

- `conversationId` — the stable thread identity that lets Agent Home group turns.
- `parentSessionId` — the prior runtime session when a turn explicitly continues
  earlier work.
- `source` — the input surface, for example `voice` or `agent-home`.

The top-level LLM remains focused on the immediate conversational loop. Side work
runs through agents and reports back into the trace. When the runtime
starts a follow-up session, it can include a compact recent context from prior
turns in the same `conversationId`, using user text plus concise returned output.
That gives the agent enough continuity without making the UI responsible for
prompt assembly or agent-session internals.

Continuing a completed turn should create a new visible conversation turn, but it
should not force a fresh underlying agent session when the previous one can be
resumed. If the parent activity has an `agentSessionId`, the runtime should reuse
that id for the follow-up so adapters such as Codex can resume their persisted
thread.

Agent output should also produce a short returned summary that Talkie can show
or speak as the returned turn. The full agent result remains available,
but the loop needs a compact "what came back" object for voice playback, trace
scanning, and future compaction.

## Architecture

The target shape is a Talkie-native version of the Lattices/HudsonKit pattern:

```text
AgentHomeController
  owns NSWindow lifecycle
  hosts AgentHomeRootView

AgentHomeRootView
  owns navigation and selection state
  starts/stops stores

AgentHomeShell
  leading navigation
  main content slot
  optional inspector slot
  status bar slot

AgentHome pages
  NowPage
  ActivityPage
  VoicePage
  AgentsPage

AgentHome stores
  ActivityStore
  ActivityFeed
  RuntimeStatusStore
  SelectionState
```

### Window Controller

`AgentHomeController` should remain the single owner of the window. It should:

- create and reuse the `NSWindow`;
- keep settings secondary, not the default Agent surface;
- provide `show()`, `dismiss()`, and eventually `show(section:selection:)`;
- avoid hardcoded application paths;
- use Talkie logging.

The window should be a normal resizable app window, not a transient overlay.
Talkie Agent remains menu-bar-helper-first: Home is opt-in and should not borrow
Lattices' window-first activation semantics wholesale.

Once created, the window should be reused for the lifetime of the process.
Closing can hide/order out the window, but should not destroy scroll position,
navigation, and selection unless `dismiss()` intentionally resets state.

### Shell

`AgentHomeShell` should be a reusable layout primitive with slots:

- leading navigation;
- content;
- optional inspector;
- bottom status bar.

This borrows HudsonKit's slot-based shell idea while staying Talkie-native.
It also borrows Lattices' "one unified window with typed pages" pattern.

The sidebar should use stable navigation entries:

```swift
enum AgentHomeSection: String, CaseIterable, Hashable {
    case now
    case activity
    case voice
    case agents
}
```

A future sidebar collapse should follow HudsonKit's fixed-icon-rail approach so
icons do not shift when labels appear or disappear.

Do not package HudsonKit for this milestone. Borrow the pattern, keep Talkie
tokens and Studio as the design source of truth.

### Pages

Each section should become its own small SwiftUI page. The root view should not
own all row rendering.

Suggested split:

- `AgentHomeNowPage`
- `AgentHomeActivityPage`
- `AgentHomeVoicePage`
- `AgentHomeAgentsPage`
- `AgentHomeInspector`
- `AgentHomePrimitives`

The pages consume stores and selection state; they do not read files, ping
runtimes, or make agent-routing decisions directly.

### Inspector

The inspector is optional in v1 but important architecturally.

Clicking an activity item, capture, or runtime entry should be able to reveal details in a
right-side inspector without navigating away from the feed. Good first inspector
payloads:

- agent session details;
- raw transcript/instruction;
- runtime/provider/model identity;
- errors and bridge status;
- selected voice capture metadata;
- last runtime error, such as missing runtime, timeout, or bridge failure.

Selection is per-section and owned by `AgentHomeNavigationState`. It should
survive switching sections while the window is open, and reset when the Agent
Home window is intentionally dismissed.

### Command Palette

Agent Home should eventually have a small command palette, likely `⌘K`,
for local Agent actions:

- refresh activity;
- open settings;
- copy latest transcript;
- retry or cancel selected invocation;
- reveal agent logs;
- start talking-to-agents voice input;
- open diagnostics.

This should be command metadata plus actions, not view-specific button glue.
Do not ship commands before the runtime boundary exists. For example, `cancel`
requires a runtime `cancelInvocation` implementation, and `retry` requires an explicit
retry operation rather than view-local reconstruction.

## State Boundaries

Keep state split. Avoid a monolithic surface object.

| State | Owner | Notes |
|---|---|---|
| Navigation | root view or `AgentHomeNavigationState` | selected section, selected item |
| Activity sources | `AgentHomeActivityStore` | activity records, captures, refresh cadence |
| Activity projection | `AgentHomeActivityFeed` | typed `[AgentHomeActivityItem]` |
| Runtime health | `AgentHomeRuntimeStatusStore` | Node dispatcher, Scout bridge, provider availability |
| Window lifecycle | `AgentHomeController` | NSWindow only |
| Agent work | `WalkieAgentRuntime` / Node dispatcher | never SwiftUI-owned |

The current `AgentHomeActivityStore` is acceptable as a first proof. Before the
surface grows, split runtime pinging and activity projection out of it.

## Data Flow

Long-running voice turn:

```text
Talk-to-agents hotkey
  -> WalkieOrchestrator routes immediate reply vs longer agent work
  -> agent invocation starts through WalkieAgentRuntime
  -> Node dispatcher persists operational invocation/session status
  -> AgentHomeActivityStore reads via typed runtime IPC
  -> AgentHomeActivityFeed projects sessions + captures into activity items
  -> notch/status affordance points back to Agent Home
```

Agent Home should display this flow, not own it.

## Entry Points

Required:

- menu bar item: **Open Agent Home**;
- keyboard shortcut, currently `⌥⌘0`;
- deep link for internal return path, e.g. `talkieagent://home` and
  dev equivalent.

The deep link handler should use the same macOS Apple Event path as the main
Talkie app, because relying only on `application(_:open:)` can be unreliable for
already-running agent helpers.

The URL scheme must also be registered in the Agent app's `Info.plist` /
project build settings for both production and dev schemes.

## Design Principles

- Quiet, operational, scan-friendly.
- No new gimmick brand surface.
- Dense rows over oversized cards.
- Status is visible but not loud.
- Use Talkie-native tokens and logging.
- Borrow structure from Lattices/HudsonKit, not their exact product identity.
- Keep Studio as the design canon. If this remains code-first, explicitly note
  that a Studio route such as `/mac-agent-home` should follow before polish.

## Implementation Plan

1. Keep the current prototype behavior intact.
2. Add typed runtime status IPC and remove direct UI reads of runtime files.
3. Add persistent Node runtime transport. No view changes.
4. Define `AgentHomeActivityItem` and `AgentHomeActivityFeed`.
5. Extract `AgentHomeShell`, sidebar, and reusable row/status primitives.
6. Split Now, Activity, Voice, and Agents into page views.
7. Add inspector and explicit selection-state lifetime.
8. Register deep links and handle them through Apple Events.
9. Add command palette once runtime actions such as cancel/retry exist.
10. Add or sync the Studio design route before visual polish.

## Open Questions

- Should Agent Home remain a menu item while the floating pill stays primary?
- What is the first "routine" object shown in Agent Home?
- How much of HudsonKit should become a package-level dependency versus a source
  of patterns for Talkie-native components?
