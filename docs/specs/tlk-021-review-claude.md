# TLK-021 Review — Claude-side sibling pass

**Reviewer**: claude (talkie sibling)
**Target**: `docs/specs/tlk-021-agent-home-architecture.md`
**Cross-checked against**: current code under `apps/macos/TalkieAgent/TalkieAgent/Views/Home/` and `…/Views/Walkie/`, the Node runtime at `…/Runtime/node/index.mjs`.

## Top recommendations before you refactor

1. **Fix IPC transport before splitting view files.** `AgentHomeActivityStore.refresh()` polls every 5s; `WalkieNodeRuntimeClient.send(_:)` spawns a fresh `node index.mjs` process per call (`WalkieNodeRuntimeClient.swift:150–214`). The Node runtime is already written as a long-lived stdin loop (`index.mjs:22–51`), so the cost is gratuitous. This will dominate every other architectural decision in TLK-021 — pages, inspector, command palette all assume cheap status reads. Land a persistent transport (daemonized child or unix socket / XPC) **before** the view split, or the per-page stores you introduce in step 3 of the Implementation Plan will each amplify the spawn cost.

2. **Pick a real IPC contract for jobs.** `AgentHomeActivityStore.loadExecutorJobs()` reads `jobs.json` from disk while the Node process writes it (no atomic write, no fsync, no inotify). The store decodes a schema that lives nowhere except `AgentHomeExecutorJob` ↔ `publicJob()` in `index.mjs:140–153`. Promote this to a typed `jobs` op on the runtime (paginated, returns `[Job]`), and let `AgentHomeActivityStore` ask the runtime, not the disk. Spec should either name the file as the contract or replace it; right now it's an undocumented backchannel.

3. **Define the activity *projection* before splitting pages.** Today `AgentHomeActivityStore` braids three streams (executor jobs from JSON, dictations from `UnifiedDatabase`, runtime ping from `WalkieNodeRuntimeClient`). The spec splits pages but not the store. If you skip the projection layer, each new page either reaches into the monolith or duplicates the read. Recommend an `AgentHomeActivityFeed` projection that returns `[ActivityItem]` over a typed union (`job`, `dictation`, `routine`, `voiceCapture`), and let pages filter it. That's the same move Lattices makes; copying the page split without it is the worst of both patterns.

## Architecture risks

- **Now vs. Activity overlap.** Current `nowContent` renders Now + Activity + Recent Captures into one scroll (`AgentHomeView.swift:140–191`). The spec says NowPage is its own page but doesn't say whether it's *active work only* or *active + digest*. If it's a digest, ActivityPage is a denser superset and Now should be one card, not a page. Decide before the split or you'll re-architect a third time.
- **`AgentHomeController.show()` recreates window on each invocation.** Lines 28–30 `window?.close(); window = nil` run whenever the window exists but isn't visible. State, scroll, selection are all reset. Spec says "create and reuse" — make that the rule: never destroy the window for the lifetime of the process; only `orderOut` / `makeKeyAndOrderFront`.
- **No cancel/retry runtime correspondent.** Command palette lists "retry or cancel selected job"; only `cancelJob` exists in the Node dispatcher, no retry op. Either land both ops before the palette ships, or drop "retry" from the spec — don't accumulate UI commands that error at the runtime boundary.
- **Dispatcher / runtime / executor confusion.** `WalkieRuntimeRegistry` already exposes two runtimes (`WalkieNodeDispatcherRuntime`, `WalkieScoutAgentSessionRuntime`) that both call the *same* Node process today (`WalkieAgentRuntime.swift:126`). The spec's "Executor" tab presents this as a single dispatcher with a Scout *bridge*. Pick one mental model: either (a) the Node process is a multiplexing dispatcher and Scout is a downstream provider it can route to, or (b) Scout is a sibling runtime equal to Node. The UI taxonomy ("Bridge: configured/pending") implies (a); the registry code implies (b). Align before naming Inspector/Executor fields.

## Missing boundaries

- **Join key between dictation and job is unspecified.** Inspector wants "raw transcript/instruction" alongside an executor job, but `LiveRecording` lives in `UnifiedDatabase` and `AgentHomeExecutorJob` lives in `jobs.json`. There's no shared id today (`WalkieAgentJob.id` is a fresh UUID at orchestrator time — `WalkieOrchestrator.swift:53`). Spec should require: every async job carries the originating dictation/transmission id, and the activity feed exposes it.
- **Where does completed executor output live?** This is Open Question #2 in the spec — it is the most important one and blocks the refactor. If `jobs.json` becomes the long-term store, you need rotation/eviction; if a SQLite table next to memos becomes the store, you need migration. Pick before splitting pages, because Activity/Now both read this and you don't want to dual-write later.
- **Deep-link scheme not registered.** Spec calls for `talkieagent://home`. There's no URL type registered in the agent's Info today (grep `CFBundleURLSchemes` under `apps/macos/TalkieAgent/`). Add as an explicit prerequisite in the Implementation Plan, not a side effect of step 5.
- **Selection state ownership.** Spec lists `SelectionState` and an optional inspector but says nothing about lifetime — does selection survive section switches? Should it survive window close? Recommend: selection is per-section, lives on `AgentHomeNavigationState`, resets on `dismiss()`. Make this explicit; otherwise inspector behavior will drift across pages.

## Lattices / HudsonKit leverage

- **HudsonKit fixed-icon-rail is the right borrow.** Good call. Keep as a Talkie-native primitive; don't package HudsonKit until a second surface (e.g. Memos library window) needs the same shell. Premature packaging here will fork your design tokens — the studio canon is the source of truth, not HudsonKit.
- **Lattices' "one unified window with typed pages" pattern is a moderate fit, not a perfect one.** Talkie Agent is fundamentally a menu-bar helper with one occasional window. Lattices is window-first. Don't import its activation/focus semantics wholesale — Agent Home shouldn't become the default activation target on dock click (Open Question #1: leave the floating pill primary, Home as opt-in).
- **Studio canon missing.** Per house workflow, design lives in `design/studio/` first and Swift catches up. Spec doesn't reference a studio route for Agent Home (e.g. `/mac-agent-home`). Either commit to one before refactor, or call out explicitly that this is a code-first surface and studio will follow.
- **"Memory" as a future section is suspicious.** Talkie has three primitives — memos, dictations, notes. Don't introduce a fourth "Memory" section in Agent Home; if it means "agent context/state browsing," name it that. If it means surfacing memos, link to the existing primitive.

## Smaller notes

- `AgentHomeSection` is declared as `Hashable` in source (`AgentHomeActivityStore.swift:13`) but the spec example declares it `String, CaseIterable, Hashable` (`tlk-021…:117–123`). Align: `String, CaseIterable, Hashable` is correct — needed for deep-link parsing.
- `runtimePing` is `@Published` on the activity store but mutated inside a detached `Task` (`AgentHomeActivityStore.swift:198`) without ordering against the disk read. Low-impact today, but when you split runtime status off (Implementation Plan step 7), make the new `AgentHomeRuntimeStatusStore` own its own actor or `@MainActor` boundary.
- `TalkieSharedSettings.bool(...)` is read directly inside the view (`AgentHomeView.swift:248`). When you split pages, push that read into the store so previews don't depend on shared defaults.
- Spec is silent on **error surfacing**. `WalkieNodeRuntimeError` cases include `runtimeTimedOut`, `missingNodeRuntime`, `runtimeFailed`. None of these reach the user; `runtimePing` just goes nil. Inspector should be the home for these, and the Executor page should distinguish "offline" from "errored on last call."

## Suggested ordering (replacement for Implementation Plan)

1. Persistent Node runtime transport (daemon or socket). No view changes.
2. Typed `jobs` op + remove direct disk reads from `AgentHomeActivityStore`.
3. Define `ActivityItem` projection union + `AgentHomeActivityFeed`.
4. Extract `AgentHomeShell` and sidebar primitives (current step 2).
5. Split pages (current step 3) — now cheap because feed/transport are clean.
6. Inspector + selection state.
7. Deep link + URL scheme registration (currently buried in step 5).
8. Command palette — gated on cancel/retry runtime ops existing.
9. Optional: split runtime status store.

The current spec's steps 4 (rows/badges) and primitives can slot wherever; they're not on the critical path.
