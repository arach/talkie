# Codex Command Deck — implementation slice

Worktree: `/Users/arach/dev/talkie-codex-command-deck` (branch `codex/codex-command-deck`, based on `master` @ `94367365`).
The dirty camera-bubble work in `/Users/arach/dev/talkie` was left untouched.

Source of truth: `/Users/arach/dev/usetalkie-command-deck-article/docs/marketing/codex-command-deck-article-brief.md`.

## Design decisions

**Exact-task routing has two supported paths.**
`apps/macos/TalkieServer/src/bridge/codex-desktop-bridge.cjs` first uses Codex Desktop's
private follower IPC when a Desktop client owns the selected task. That path preserves
live start-versus-steer behavior. The mapper also lists recent tasks that are not open in
a Desktop window, so an ownership-only transport made valid keys fail as unavailable.
For those tasks, the adapter now starts Codex's supported app-server over JSONL stdio,
resumes the same task ID, and uses `turn/start` or `turn/steer` on that exact task. Both
paths verify the private rollout file before reading the result. Neither path uses global
keystrokes, the frontmost window, or a guessed repository.

**Talkie never approves a Codex action.**
If app-server asks the client for an approval, the adapter fails closed with
`approval-required`. The user must review that request in Codex Desktop.

**A lane binding and a lane lock are different things.**
The binding is a user decision and persists. The lock is a claim that Codex Desktop owns
that exact task *right now*, is never persisted, and is re-earned by validating against
the Mac. A restored lane comes back selected but unconfirmed, and the deck draws it with a
dashed edge until the Mac confirms it.

**A TTS failure never demotes a successful Codex turn.**
`AIResponseSpeechRouter.speak` was extended additively with a `failure` field instead of
throwing, so narration problems are reported alongside the response rather than in place
of it.

## Changed files

### Mac (TalkieServer)

| File | Change |
| --- | --- |
| `src/bridge/routes/codex.ts` | **new** — wraps the vendored adapter. `GET /codex/tasks`, `POST /codex/validate`, `POST /codex/submit`. Submit accepts `auto`, `queue`, and `steer`; a per-task coordinator serializes queued turns while allowing steering receipts through immediately. Maps adapter error codes to 503 (unavailable) vs 502, attaches per-code recovery hints, defense-in-depth re-check that the returned task ID equals the requested one, and validates the delivery contract. |
| `src/bridge/index.ts` | wires the three routes ahead of the terminal block. |
| `src/bridge/codex-desktop-bridge.cjs` | **new** — lists recent tasks, prefers live Desktop follower IPC, falls back to exact-task app-server resume when no Desktop client owns the task, and tails only the verified private rollout for the returned answer. Explicit `steer` acknowledges as soon as the active turn accepts the message; `queue` waits for that turn and starts a new one. |
| `src/bridge/routes/codex.test.ts` | **new** — verifies immediate steering, ordered queue delivery, and queueing behind a turn that was already active outside Talkie. |

Transport encryption is inherited, not re-implemented: `supportsTransportEncryption` excludes
only `/pair`, so `/codex/*` requests decrypt via `readJsonBody` and 200s are sealed by the
global `.mapResponse` in `src/server.ts`. Error bodies stay plaintext by design, which is
what lets the phone read the recovery hint.

### iOS

| File | Change |
| --- | --- |
| `Codex/CodexLane.swift` | **new** — `CodexTaskSummary` (term-wise diacritic-folded search over title/preview/cwd/id, recency label, project name), `CodexMessageMode`, `CodexTurnDelivery`, `CodexLane` (1…9) + `CodexLaneVoiceOverride`, `CodexLanePhase` (idle/validating/listening/transcribing/submitting/preparingSpeech/speaking/failed), `CodexTurnRecord`, `CodexLaneFailure`. |
| `Codex/CodexLaneStore.swift` | **new** — the controller. Persistence, assignment, validated activation, the voice loop, narration interruption, phase machine, turn retention, and concurrent capture while a turn is running. Queue is the safe default; steer is explicit. |
| `Codex/CodexLaneMapperView.swift` | **new** — mapper sheet: searchable live catalog, lane strip, assign/clear, auto-refresh on open and while visible (15s), pull-to-refresh. |
| `Codex/CodexLaneBar.swift` | **new** — the deck strip (lane chips, capture control, phase line) + `CodexResponseSheet` for full response text. |
| `Bridge/BridgeClient.swift` | `codexTasks` / `codexValidate` / `codexSubmit` + payload structs. A normal turn gets a 31-minute request ceiling; queue gets 61 minutes because it may wait for one turn and then run another. |
| `Bridge/BridgeManager.swift` | the three facade methods, each going through a shared `requireConnectedBridge()` so a Codex request never silently degrades into a no-op. |
| `Services/WalkieFX.swift` | `stopVoicePlayback()`. Stops the FX `player` as well as `voicePlayer` — the closing squelch/kerchunk are pre-scheduled and would otherwise fire into the next utterance. |
| `Services/AIResponseSpeechRouter.swift` | interrupts prior playback before speaking; reports `failure` and `speechDuration` instead of collapsing everything to `didSpeak: false`. |
| `Views/Next/DeckMirrorNext.swift` | `CodexLaneBar()` above the cockpit; bridge-status change drops the lock claim (bindings survive). The 4×4 grid and cockpit are otherwise untouched. |

## How each contract point is met

- **Bridge stays transport.** No new pairing, auth, or encryption path; the routes sit on the existing signed/encrypted bridge.
- **4×4 stays primary.** The lane strip is ~50pt; the mapper and full response are sheets.
- **A lane is one exact task.** Identity is the Codex task ID end to end; nothing keys off repo or frontmost window.
- **Revalidate before claiming locked.** `activate()` validates the exact task through Desktop IPC or app-server; `isLocked(_:)` is the only thing the UI may gate the word on. Submits revalidate when the confirmation is missing or older than 60s.
- **Fail closed with recovery.** The adapter validates task identity, executable ownership, IPC socket ownership, and rollout location. Any submit failure clears the lock and returns a recovery hint.
- **Voice on the phone.** Reuses `InlineDictationController` → `TranscriptionService` (`.keyboard` use case).
- **Idle vs active turn, reported.** `CodexTurnDelivery` is decoded from the Mac's string; an unrecognized value fails loudly rather than being smoothed over. The delivery label is shown verbatim.
- **Talk during a turn.** The capture surface stays live while Codex works. Queue runs the utterance as the next turn and is selected by default; Steer injects it into the active turn immediately. A steer receipt does not produce duplicate narration because the original submit remains the sole owner of the final response.
- **Narration through the existing route.** `AIResponseSpeechRouter` + `TalkieAppSettings` + `TTSService`. No second provider-config system. Per-lane voice override is stored but not yet applied — deliberately, since the brief calls it room-to-grow rather than a blocker.
- **Interrupt.** Capture during `.speaking` stops audio and starts listening.
- **Honest phases.** Every phase in the brief is a case, including `.failed(String)`.

## Verification run

**Mac, against live Codex Desktop and Codex app-server:**

- The machine had four TalkieServer processes bound to port 8765. Three ran from an old
  checkout without `/codex/*`. They were stopped, and the launch agent now owns one
  listener from this worktree with nearby/LAN pairing enabled.
- The adapter catalog returned six recent tasks. Five were owned by Desktop clients; one
  was catalogued but not open in a Desktop window.
- All six exact task IDs now validate successfully. The previously unavailable task
  resumes through app-server and returns the same ID.
- The authenticated, phone-facing `POST /codex/validate` route returned HTTP 200 for the
  previously unavailable task on four consecutive requests through port 8765.
- `POST /codex/validate {}` still returns HTTP 400 `taskId is required`.
- `POST /codex/submit {taskId}` still returns HTTP 400 `text is required`; `{}` returns
  HTTP 400 `taskId is required`.

No test instruction was injected into an existing user task. Validation and exact-task
resume were exercised end to end; live `turn/start` and `turn/steer` remain for the device
acceptance pass because exercising them would create a real Codex turn.

**iOS:** Simulator and signed physical-device builds both succeeded. The signed build was
installed and launched with `--deck` on the paired iPhone 13 mini. The 4x4 uses a physical
key index independent of lane number: the response-output dial is key 01, six task lanes
occupy keys 02 through 07, and open sockets remain at the two bottom corners (13 and 16).

The during-turn implementation also passes a fresh generic iOS Simulator build. The
TalkieServer coordinator has three passing Bun tests, its focused TypeScript check passes,
and the vendored Node adapter passes `node --check`.

## Not verified — the acceptance pass has not been run

The device is paired and the signed build is installed. The following interaction pass
still needs to be completed by tapping and speaking on the phone:

1. Map two live tasks from different repos to two lanes.
2. Activate each and confirm the exact task before "locked".
3. Speak into an idle task → narrated response.
4. Steer an active turn → distinct delivery label.
5. Map a task that is not open in a Desktop window → app-server resumes the exact task.
6. Disconnect the Mac → assignments preserved, no live lock claim.
7. Disable narration → text still returns.
8. Force a TTS error → response still readable.
9. Interrupt narration with a new capture.

Exact-task mapping and validation are verified through the live phone-facing endpoint.
Voice capture, turn submission, returned text, narration, interruption, and TTS failure
handling have not yet been exercised as one continuous on-device interaction.

## Article claims

The article may describe the deck layout and exact-task mapper in the present tense. The
full spoken-turn loop should remain in future tense until the on-device interaction pass
succeeds.

Nothing in the article was found to be *wrong* — no claim needs correcting on the merits.
The gate is evidence, not accuracy.

## Next owner

Run the installed build on the iPhone 13 mini. Start with the formerly unavailable mapped
task, then complete the spoken-turn and narration steps above. That is the remaining gate
on the article's voice-loop claims.
