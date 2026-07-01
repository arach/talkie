# TalkieAgent — Turn / Conversation UX & Implementation Review

_2026-06-29 · read-only investigation. No source files were modified._

Scope: the Agent **Home** conversation surface (turns, continuation, status) plus the
Node dispatcher runtime that actually drives the executor (Codex / Claude Code / …).

---

## 0. How a turn flows (orientation)

```
AgentHomeView (SwiftUI)
  composer / idle hero  ──onSend──▶ AgentHomeActivityStore.invokeAgent(text, conversationId, parentSessionId)
                                       │  builds AgentInvocation, source="agent-home"
                                       ▼
                                 AgentRuntimeClient.invoke  ──stdin JSON──▶  Runtime/node/index.mjs
                                                                              op:"invoke" → record{state:"working"} → spawnWorker (detached)
                                                                              worker: SessionRegistry.createSession(adapterType, {model, systemPrompt})
                                                                                      registry.send(prompt) → block:delta / turn:end → record.state="done"
  AgentHomeActivityStore.refresh()  ◀──poll every 5s── AgentRuntimeClient.status()  ◀── reads persisted job records
  → executorJobs → executorTurns(in:topic) → AgentHomeTranscriptView → AgentHomeTurnBlock
```

Key files:
- `apps/macos/TalkieAgent/TalkieAgent/Views/Home/AgentHomeView.swift` — the conversation view, turn blocks, composer, continuation chip.
- `apps/macos/TalkieAgent/TalkieAgent/Views/Home/AgentHomeActivityStore.swift` — state: jobs, polling, status derivation, `invokeAgent`.
- `apps/macos/TalkieAgent/TalkieAgent/Runtime/AgentRuntime.swift` / `AgentRuntimeClient.swift` — Swift→Node bridge + invocation model.
- `apps/macos/TalkieAgent/TalkieAgent/Runtime/node/index.mjs` — the dispatcher/worker, adapter + model selection.

---

## 1. Continuing a previous conversation is too hidden

### What's there today
There are **two** "Continue" affordances and **one implicit** path:

1. **Hover-only "Continue" link** in the Talkie speaker header line:
   `AgentHomeView.swift:952-965` — rendered only `if let onContinue, hovered`, and only on
   finished turns (`onContinue: isLive ? nil : onContinue`, line 791). It lives in
   `speakerLine` — i.e. *above the message body* (matches the user's "only available above the
   message"). Icon `arrow.turn.down.right` + "Continue", brass, fades in on hover.
2. **A second "Continue" button** inside the collapsed "Details" work block:
   `AgentHomeView.swift:1042-1054`, only shown when `turn.spokenSummary != nil` and only after the
   user expands "Details" (`showWork`). Doubly buried.
3. **Implicit auto-threading (the important one):** when you just type a reply into an open
   conversation, `invokeAgent` already resumes the prior session:
   `AgentHomeActivityStore.swift:749` — `parentSessionId = explicitParentSessionId ?? latestSessionId(in: conversationId)`.
   The runtime then reuses the parent's executor session id
   (`index.mjs:501` `agentSessionId = parentRecord?.agentSessionId ?? …`, resolved by
   `continuationRecordFor`, `index.mjs:751-763`) **and** injects the last 6 turns as text context
   (`conversationContextFor`, `index.mjs:727-749`).

### The actual problem
- The robust path (just reply → it continues) is **invisible**: nothing tells the user a reply
  carries memory of the prior turns. The continuation chip (`AgentHomeView.swift:1439-1458`) only
  appears after you click the hidden hover "Continue", so most replies show no continuity signal.
- The explicit "Continue" is **hover-gated and turn-anchored**, so resuming an *older/closed*
  conversation (e.g. one re-opened from the sidebar) means hunting for a button that only appears
  on mouse-over of the right turn. Selecting a topic from the sidebar even clears continuation
  (`selectTopic` → `continuation = nil`, `AgentHomeView.swift:380-381`).
- Two visually identical "Continue" controls with different semantics (continue-latest vs
  branch-from-this-turn) but no labelling of the difference.

### Recommendation
Make continuity the legible default; reserve the explicit button for *branching*.

1. **Always-visible continuation state on the composer.** When `selectedTopic.turnCount > 0`,
   show a persistent, non-hover chip such as `↳ Continuing "<topic>" · N turns` (reuse the chip at
   `AgentHomeView.swift:1439-1458`, but drive it from `selectedTopic`, not only from an explicit
   `continuation`). This tells the user every reply has memory. Keep the `xmark` to "start fresh"
   (which would route to `startNewTopic()`, `AgentHomeView.swift:373-377`).
2. **Promote per-turn "Continue" to a branch action.** Relabel it ("Branch from here" /
   "Reply to this turn") and make it always-visible-but-quiet (not hover-only) on finished turns —
   drop the `hovered` gate at `AgentHomeView.swift:952`, or render it in the turn footer row next
   to "Details" (`AgentHomeView.swift:805-818`) instead of the header line. Remove the duplicate
   in the work block (`:1042-1054`) or keep only one.
3. **Sidebar/closed-conversation resume.** The sidebar already groups conversations
   (`AgentHomeActivityStore.swift:638-697`). Make "select a conversation + type" the canonical
   resume, and surface a one-click "Continue" on each conversation row so reopening doesn't require
   the transcript at all. (Sidebar rows live in `AgentHomeShellView.swift`.)

### Risks / tests
- Risk: chip wording implying continuity must match actual runtime behavior — verify the
  auto-thread path still resolves `continuationRecordFor` after app restarts (records persist via
  `loadJobs()`/`persistRecord`, so `parentSessionId` from `latestSessionId` survives).
- Risk: branching from a non-latest turn sets `parentSessionId = turn.id`
  (`AgentHomeContinuationContext.init`, `AgentHomeView.swift:488-501`); confirm the runtime reuses
  that turn's `agentSessionId`, not the latest, so a branch truly forks.
- Tests: unit-test `latestSessionId(in:)` and `currentPromptTarget()` for (a) fresh topic,
  (b) reply with history, (c) explicit branch. Snapshot-test the composer with/without history to
  confirm the persistent chip renders.

---

## 2. Default agent effort is too high / slow

### What's there today
There is **no reasoning-effort knob anywhere** in TalkieAgent or its Node runtime today — neither
in the Swift invocation model nor passed to the executor.

- Swift `AgentInvocation` (`AgentRuntime.swift:59-69`) carries `topLevelModel`, `channel`,
  `conversationId`, `parentSessionId` — **no effort/model-for-executor field**. Agent Home hardcodes
  `topLevelModel = ("talkie-agent","Talkie Agent","agent-home")` and uses `.defaultChannel`
  (`AgentHomeActivityStore.swift:756-763`).
- `AgentChannel.defaultChannel` (`AgentRuntime.swift:38-50`) leaves `executorModelId`,
  `executorProviderId`, `executorRuntimeId` all **nil**.
- **Default executor adapter = `codex`** — `index.mjs:834` (`return normalized ?? 'codex'`).
  `resolveAdapterType` order: `TALKIE_AGENT_SESSION_ADAPTER` env → record → channel → providerId
  (`index.mjs:827-835`).
- Options actually sent to the adapter (`adapterOptions`, `index.mjs:687-702`) are only
  `{ systemPrompt, model }`, where `model = process.env.TALKIE_AGENT_SESSION_MODEL ?? record.modelId ?? undefined`.
  Since `executorModelId` is nil, `model` is usually `undefined` → the **executor CLI's own
  defaults decide model + reasoning effort** (for Codex/GPT-5-codex that defaults to a high
  reasoning tier; combined with Codex spin-up this is the "too high/slow" feel).

So the "default effort" the user feels is **inherited from the Codex CLI**, because the runtime
passes nothing to cap it.

### Recommendation
Introduce an explicit, low-friction effort default of **medium**, threaded end-to-end, without
removing higher tiers.

1. **Add an effort field to the contract.** Add `executorEffort: String?` (values
   `low|medium|high`) to `AgentInvocation` (`AgentRuntime.swift:59-69`) and to the Node `record`
   (`index.mjs:504-537`). Mirror it in `AgentRuntimeClient` request encoding and
   `AgentRuntimeActivitySnapshot`/`AgentHomeExecutorJob` if you want it visible per turn.
2. **Default to medium in one place.** In `adapterOptions` (`index.mjs:687-702`):
   ```js
   const effort = process.env.TALKIE_AGENT_SESSION_EFFORT ?? record.executorEffort ?? 'medium';
   options.reasoningEffort = effort;        // adapter maps to codex `-c model_reasoning_effort=…` etc.
   ```
   Verify the `@openscout/agent-sessions` adapter option name (it's loaded at
   `index.mjs:434-466`; codex adapter is `createCodexAdapter`, `index.mjs:679`). If the package
   doesn't accept `reasoningEffort` yet, map it to the codex CLI config flag inside the runtime's
   spawn (or set `TALKIE_AGENT_SESSION_*` env per-invocation).
3. **Expose, don't hide, the higher tiers.** Surface a small effort selector in the composer
   cluster (next to the agent chip, `AgentHomeView.swift:1373` `AgentHomeAgentChip`), defaulting to
   medium, persisted in `LiveSettings`/`TalkieSharedSettings`. Pass it into `invokeAgent` →
   `AgentInvocation.executorEffort`. This keeps low/high available per-turn.
4. **Consider a faster default model for chat-style turns.** Because Agent Home is conversational
   (not long code edits), consider defaulting `executorModelId` to a lighter model for the
   `agent-home` source while leaving voice/long-job sources untouched (branch on
   `record.source === 'agent-home'`, already known at `index.mjs:503`).

### Risks / tests
- Risk: the external `@openscout/agent-sessions` adapter may name the option differently
  (`reasoning`, `model_reasoning_effort`, …) — confirm against the installed package at
  `~/.talkie/agent-runtime/node_modules/@openscout/agent-sessions` before wiring, otherwise the
  option is silently dropped. **This is the one external dependency to verify.**
- Risk: forcing `medium` could regress complex code tasks routed through the same runtime from
  voice; gate the default on `source === 'agent-home'` or make it user-overridable.
- Tests: runtime smoke (`npm run smoke:invoke` in `Runtime/node`) asserting the effort lands in
  the adapter options; a Swift test that `executorEffort` round-trips through
  `AgentRuntimeClient` encode/decode.

---

## 3. Recognising "working" vs "finished / not working"

### What's there today
Status surfaces, but with three weaknesses.

- Job state from runtime is `working|done|failed` (and theoretically `acked`). Swift maps it
  (`AgentHomeActivityStore.swift:252-263`): `working|running|started → .running`,
  `done → .done`, `failed → .failed`, **everything else → .waiting**.
- A turn is "live" when `running || waiting` (`AgentHomeView.swift:756-758`). Live styling:
  amber dot + pulsing ring + "working" meta + italic quote body + amber left rail
  (`AgentHomeView.swift:785-801, 936-948`). Wire-trace colour also tracks status
  (`AgentHomeView.swift:853-862`). Footer identity line says "queued/working/needs attention/done"
  (`:1059-1070`). Header subtitle appends "working now" when `activeCount > 0`
  (`AgentHomeView.swift:361`).

**Weaknesses:**

1. **No live streaming; up to 5s blind window.** The worker streams `block:delta` into the record
   (`index.mjs:631-633`), but the macOS app only **polls every 5 s** (`startRefreshing`,
   `AgentHomeActivityStore.swift:713-721`). So "working" is a static italic "Working on it…" with
   no moving text, and a finished turn can keep showing "working" for up to 5 s before the poll
   flips it. Feels stuck / laggy.
2. **Orphaned jobs stay "working" forever.** `invoke` sets `state:"working"` then spawns a
   **detached** worker (`index.mjs:586-594`, `detached:true, stdio:'ignore', child.unref()`). The
   only timeout is *inside* that worker (`waitForTerminalTurn`, 10 min, `index.mjs:816-825`). If the
   worker dies/crashes, the machine sleeps, or the process is killed, **nothing ever flips the
   record to failed** — the turn shows "working" indefinitely. There is no heartbeat/watchdog.
   This is the core "is it actually working or dead?" failure.
3. **"Queued" vs "actively running" is collapsed.** On invoke the record goes straight to
   `working` (`index.mjs:511`); the detached worker also sets `working` (`index.mjs:608`). The
   `acked`/`.waiting` path is essentially unreachable for normal turns, so a turn that's really just
   queued behind other work looks identical to one mid-execution. The UI has the vocabulary
   ("Queued"/"Working", `AgentHomeActivityStore.swift:572-581`) but the runtime never feeds it.

### Recommendation
1. **Heartbeat + stale watchdog (highest value).** Have the worker write a `heartbeatAt` into the
   record on each event (extend the `onEvent` handler at `index.mjs:617-647`). In the dispatcher's
   `status`/`listActivities` (`index.mjs:866-870`) or in the Swift refresh, treat
   `state == working && now - heartbeatAt > threshold` (e.g. 60–90 s) as **stalled** → render a
   distinct "stalled / lost contact" state (amber→grey, "Reconnecting…/Check agent") with a Retry
   that calls the existing `retryInvocation` (`index.mjs:549-571`). This kills the infinite
   "working".
2. **Tighten the poll while live, or stream.** Cheap win: when `activeJobs` is non-empty, run the
   timer at ~1 s and back off to 5 s when idle (`AgentHomeActivityStore.swift:713-721`). Better:
   stream — keep a long-lived runtime connection (the bridge already spawns a process per request;
   a persistent stdout subscription would let `block:delta` drive the italic body live instead of
   the static ack).
3. **Distinguish queued from running.** Add a real `queued` state in the runtime when a worker
   can't start immediately (there's already an `acked` filter at `index.mjs:350` and a queue
   concept), and surface it via the existing "Queued" branch label
   (`AgentHomeActivityStore.swift:573-574`).
4. **Add an elapsed timer + clearer "done".** While live, show elapsed time in the meta
   (`AgentHomeView.swift:767-770` `talkieMeta`) so the user perceives progress; on completion the
   `latencyLabel` already gives "done in Xs" — make the transition crisp (animate the amber rail
   off, swap the dot for a check).
5. **Window/dock-level activity glance.** A persistent indicator (e.g. menu-bar/tab badge) when
   `activeJobs > 0` so the user knows work is running without opening the transcript
   (`AgentHomeActivityStore.activeJobs`, `:630-632`).

### Risks / tests
- Risk: a too-aggressive stale threshold could mark genuinely long turns (10-min budget) as
  stalled — base the watchdog on `heartbeatAt`, not on `createdAt`, so long-but-alive turns are
  fine.
- Risk: faster polling spawns a Node process each tick (`AgentRuntimeClient.send` runs a fresh
  process, `AgentRuntimeClient.swift:198-262`) — measure cost; this is the argument for a
  persistent streaming connection instead of 1 s polling.
- Tests: runtime unit test that a record with old `heartbeatAt` is reported stalled; Swift test
  that status mapping yields a `.stalled`/`.failed` presentation; manual: start a turn, `kill -9`
  the detached worker, confirm the UI flips off "working" within the threshold.

---

## Suggested prioritisation

| # | Change | Effort | Payoff |
|---|--------|--------|--------|
| 3.1 | Heartbeat + stale watchdog (no more infinite "working") | M | High — correctness |
| 1.1 | Always-visible "Continuing <topic> · N turns" composer chip | S | High — legibility |
| 2.2 | Default executor effort = `medium` in `adapterOptions` | S | High — speed (verify adapter option name) |
| 3.2 | Faster poll while live (1 s active / 5 s idle) | S | Medium |
| 1.2 | De-hover / relabel per-turn Continue as "Branch", drop the duplicate | S | Medium |
| 2.3 | Composer effort selector (low/med/high), persisted | M | Medium |
| 3.5 | Window/dock activity indicator | M | Medium |

**One hard external dependency to verify before #2:** the option name the
`@openscout/agent-sessions` codex adapter expects for reasoning effort (installed under
`~/.talkie/agent-runtime/node_modules/@openscout/agent-sessions`, loaded at `index.mjs:434-466`).
Everything else is self-contained in this repo.
