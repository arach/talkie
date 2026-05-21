# Parity swarm protocol

The Parity Audit at `design/studio/app/parity/page.tsx` enumerates donor → Next gaps in six clusters. This doc is the coordination protocol for the swarm of agents working those clusters in parallel.

The audit page reads `streams.json` (this directory) at build time. Anything you append to a stream's `notes` array shows up in the audit UI under the matching section the next time the studio rebuilds.

## Streams

Six streams, one per cluster:

| key | title | scope |
|-----|-------|-------|
| C1  | Home · Library · History | HomeNextView, HomeFeed, LibraryNextView, LibraryFeed, DictationHistoryNext |
| C2  | Capture | CaptureDetailNext, CameraCaptureNext, WebCaptureBrowserNext, ScanPreviewOverlay, CaptureAICommandsSheet equivalent |
| C3  | Compose · Memo detail | ComposeNextView, ComposeStore, VoiceMemoDetailNext, ReadAloudNext, attachments, agent + CLI sheets |
| C4  | Settings · Onboarding · Sign-In | SettingsNext, OnboardingNext, SignInNext, AICredentialsNext, WorkspaceSwitcherNext |
| C5  | Bridge · Mac · Deck | ConnectionCenterNext, BridgeDetailNext, DeckMirrorNext, NetworkStatusBanner, MacConnectionChip |
| C6  | Recording · Workflows · Feedback · Ask AI | RecordingSheetNext, MinimalDictationOverlayNext, KeyboardActivationNext, VoicePivotButton, QuickEntriesBar, WorkflowsNext, FeedbackNext, AskAINext |

Each stream's findings live in `ParityAudit.tsx` under the matching cluster `key`. The page generates a stable `findingKey` for every row: `${clusterKey}::${donor}::${title}`. Use that exact string when you want a note attached to a specific finding.

## Lifecycle

Statuses: `queued` → `in-flight` → `done` (or `blocked`).

1. **Claim** — pick a stream with `status: "queued"` and `owner: null`, set `owner` to your agent handle (e.g. `talkie-codex-rw`, `explore-c1`), set `status: "in-flight"`, set `lockedAt` to `new Date().toISOString()`. Save.
2. **Look back** — every time you resume, re-read the current `streams.json`. The user may have changed decisions (PORT / DROP / DEFER) on findings in the audit UI; those land in browser localStorage, not here, but they may also leave guidance for you as notes. Read all notes for your stream before deciding what to touch next.
3. **Work** — implement, refactor, investigate. Stay inside your cluster's scope. If you discover something that belongs to another cluster, log a `level: "info"` note on that cluster's stream so its owner picks it up — do not edit the other cluster's files.
4. **Update** — after every meaningful step (proposal, in-flight work, commit landed, blocker), append a `StreamNote` to your stream's `notes` array. See schema below.
5. **Finish** — when your cluster has no remaining findings the user wants ported, set `status: "done"`, post a `level: "info"` summary note, clear `owner` to `null`, leave `lockedAt` for history.

## Note schema

```ts
interface StreamNote {
  ts: string;        // ISO timestamp, e.g. "2026-05-21T14:32:00Z"
  agent: string;     // your handle
  level: "info" | "progress" | "landed" | "blocked" | "proposal" | "question";
  findingKey?: string;  // "C1::HomeView::Full-screen search" — omit for stream-wide notes
  message: string;   // 1–3 sentences. File:line refs welcome.
  ref?: string;      // optional: commit sha, PR url, or file:line
}
```

Levels:

- **info** — observation, context, summary.
- **progress** — work started or partially landed (still open).
- **landed** — change is on the branch (include `ref` with commit sha).
- **blocked** — can't proceed. Explain the dependency in `message`.
- **proposal** — concrete plan awaiting user signoff. Stop and wait.
- **question** — needs the user. Stop and wait.

## Write protocol

`streams.json` is shared mutable state. To avoid clobbering concurrent writes:

1. Read the file fresh right before you write.
2. Patch only your own stream's entry (match by `key`).
3. Append to `notes`, never rewrite or reorder existing entries.
4. Bump the top-level `updatedAt` to your current ISO timestamp.
5. Write back. Commit the change with a message like `📝 parity C3: <short summary>`.

If two agents are racing, the later writer's git push will fail on non-fast-forward. Pull, replay your append, push again. Don't blindly accept theirs over yours.

## Boundaries

- **One cluster per agent.** Never edit files outside your cluster's scope without an explicit handoff via the other stream's notes.
- **Constant look-back.** Re-read the parity audit + streams.json before each significant action. The user's decisions are the source of truth for what to port vs. drop vs. defer.
- **No new clusters.** If you find an entirely new surface, add a `level: "info"` note flagging it. Do not invent a 7th stream.
- **Stay in sync with the audit.** If your work resolves a finding (you implemented MISSING X), append a `landed` note keyed to that finding so the audit can show it as resolved.
- **iOS write boundary.** Per project memory, Claude does not write SwiftUI state objects, gesture wiring, or service bridges. Those go to Codex. Claude declares contracts + paints; Codex implements infrastructure.

## Pair protocol — Claude × Codex, 1:1 per cluster

Each cluster is a track with two agents:

- **Claude sibling** (handle: `investigator-c<N>` for investigation, `painter-c<N>` for impl) — read-only investigation, paint surfaces, declare contracts. Runs on the main worktree.
- **Codex sibling** (handle: `talkie-codex-c<N>`) — workspace-write. Implements @StateObject bindings, gesture wiring, service bridges, persistence, transport. Runs on its own worktree at `~/dev/talkie-parity-c<N>` on branch `parity/c<N>`.

Both write to the same `design/studio/data/parity/streams.json` (on `feat/ios-shell-phase-0`). The Codex sibling pulls that branch into its worktree to read the latest notes.

### Sequence

1. **Investigation** — Claude sibling investigates, posts `proposal` notes with file:line, size, risk, "needs Codex" flag. Status moves to `done` when the cluster is fully surveyed.
2. **Triage** — user reads `/parity`, sets PORT / DROP / DEFER on findings, optionally leaves per-finding notes. Decisions land in browser localStorage; when the user is ready to dispatch they paste them into the cluster's stream as a `level: "info"` note (or invoke a future "publish decisions" action).
3. **Implementation** — Codex sibling reads the cluster's stream:
   - filters to findings with a PORT signal from the user
   - works through them in size order (XS → L), one finding per commit
   - posts a `progress` note when starting a finding (so the page shows live status)
   - posts a `landed` note with the commit sha (`--ref <sha>`) when shipped
   - skips findings where Claude's proposal says "needs Claude paint first" until the painter sibling lands the contract
4. **Coordination** — when a finding needs both (Claude declares contract + Codex implements):
   - Claude sibling posts a `proposal` note describing the contract (router payload, store shape, callback signature)
   - Codex sibling posts a `progress` note confirming it can implement against that contract
   - Claude lands the paint, posts `landed`
   - Codex lands the wiring, posts `landed`
5. **Done** — when no remaining PORT findings, Codex posts a `level: "info"` summary, opens a PR from `parity/c<N>` → `feat/ios-shell-phase-0`, posts the PR url as a final note, then sets stream status to `done`.

### Coordination via Scout

Each pair has a Scout DM channel between the Claude painter and Codex builder. Both agents use Scout to:

- Ask quick questions ("does the router payload need image data?") — `scout ask --to <sibling-handle> "..."`
- Hand off contracts ("here's the declared MemoCLISheet protocol, ready for Codex") — `scout send --to <sibling-handle> "..."`
- Flag blockers visible to both ("waiting on C3 contract for ReadAloud source") — `scout send --to <sibling-handle> "..."`

Scout messages are real-time signals; streams.json notes are the durable record. Don't write the same content in both — use Scout for *I'm-doing-X-now*, use notes for *X-is-done*.

### Conflict rules

- **One Codex worktree per cluster.** Never run two Codex siblings on the same worktree.
- **Branch isolation.** Each Codex works on `parity/c<N>` and only that branch. Don't push to `feat/ios-shell-phase-0` directly; open a PR.
- **Cluster scope is hard.** If Codex needs a change in another cluster's files, it posts a `level: "info"` note on that cluster's stream and waits for that cluster's siblings to handle it.
- **Shared streams.json.** When committing notes from a Codex worktree, always `git pull --rebase` first to pick up other workers' notes — your changes only add entries, so a rebase is safe.
