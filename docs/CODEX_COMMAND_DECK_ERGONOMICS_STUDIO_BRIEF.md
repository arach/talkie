# Codex Command Deck — lane picker and host signals Studio brief

## Assignment

Revamp the existing `/ios-deck-codex` Talkie Studio study into a focused second-round decision tool. This is a design study only. Do not build or change the production Swift app.

The first round is settled: **T2 · Bottom Sill Rail is the selected voice-control foundation.** Remove the five competing phone treatments from the main study. Preserve only a compact decision record explaining that T2 won and why. Spend the route on deeper iterations of the lane picker and the truthful data signals received from the Mac host.

Optimize first for ergonomic ease of use on an iPhone 13 mini, then glanceability, exact-task confidence, and honest state reporting. The bottom voice rail must remain fixed in the lowest reachable band across every iteration so the comparison isolates the picker and signals.

## Current evidence

- Current phone screenshot: `/var/folders/jm/ygrbdbjd7618slznbdm43sf00000gn/T/codex-clipboard-501ae7db-0892-43cb-87b4-f3d48b7984e5.png`
- Existing Studio route: `/ios-deck-codex`
- Prior study: retired from the route; its T1–T5 outcome is preserved as a compact decision record in the new study.
- Existing decisions log: `design/studio/app/ios-deck-codex/NOTES.md`
- Current Swift surface: `apps/ios/Talkie iOS/Codex/CodexCommandDeckSurface.swift`
- Current lane strip: `apps/ios/Talkie iOS/Codex/CodexLaneBar.swift`
- Current models: `apps/ios/Talkie iOS/Codex/CodexLane.swift`
- Current Mac route: `apps/macos/TalkieServer/src/bridge/routes/codex.ts`
- Current adapter: `apps/macos/TalkieServer/src/bridge/codex-desktop-bridge.cjs`
- Implementation notes: `docs/CODEX_COMMAND_DECK_SLICE.md`

## Settled foundation

- T2 Bottom Sill Rail is the winner. Do not reopen the T1–T5 decision.
- The voice action is a wide, inset rail pinned to the bottom safe/reachable band, outside the 4×4 navigation grid.
- Its position and footprint are invariant across variants. State-dependent copy and affordances may change, but the target must not jump.
- Lane selection remains above the rail. It is less frequent than talking, so it may sit higher, but it must still be quick, predictable, and readable.
- Queue is the safe default during an active turn. Steer is explicit. Talkie never approves a Codex action.

## Truth boundary: signals we actually have

The study must distinguish host-authoritative data from phone-local state and proposed future telemetry. Never render an invented live signal as if the Mac currently sends it.

### Host-authoritative data currently available

- Task catalog: exact task `id`, `title`, `preview`, `cwd`, and `updatedAt`.
- Validation receipt: exact task `id`, `title`, and `cwd`, or a typed error.
- Delivery receipt: `taskId`, optional `turnId`, optional final `response`, and one of `started-turn`, `queued-turn`, or `steered-active-turn`.
- Typed failures with a host-provided recovery `hint`, including unavailable host/catalog/task ownership, approval required, task/protocol mismatch, timeout, empty response, and safety failures.

### Phone-local state derived from host interactions

- Bridge connected/disconnected.
- Persisted lane binding and currently selected lane.
- Exact-task lock/confirmation and its freshness.
- Voice-loop phase: idle, validating, listening, transcribing, submitting, preparing speech, speaking, or failed.
- Locally chosen Queue/Steer mode and the last delivery receipt.

### Not continuously available today

- A live idle/active/awaiting-approval status feed for every mapped lane.
- Queue depth or position.
- Percent progress, ETA, token usage, tool name, or granular execution stage.
- A reliable per-lane activity light before validation/submission probes the host.

If a treatment explores one of these future signals, label it clearly as **proposed host telemetry** and keep it visually separate from the current-contract treatments.

## Iteration requirement

Create **five meaningfully different lane-picker and signal treatments** above the same T2 rail. Change interaction composition and information hierarchy, not merely color. Each treatment should answer:

1. How are six stable numbered lanes scanned and selected?
2. How does the selected lane reveal project and task identity without consuming the screen?
3. How are mapped, selected-but-unconfirmed, exact-task-confirmed, active-local-phase, delivery, and recoverable failure states distinguished?
4. What is visible all the time versus revealed on selection or tap?
5. What is the treatment's governing ergonomic idea and its failure mode?

Useful axes include a fixed six-slot strip, selected-lane expansion, two-tier identity, status embedded per lane versus centralized below it, text versus shape/outline, recent-task recency, long task titles, empty/unmapped lanes, and progressive disclosure into the mapper. Avoid horizontally scrolling the six primary positions.

Expose a small set of live parameters per treatment. Useful parameters include selected-lane emphasis, task-label density, identity-line placement, confirmation freshness, status persistence, failure disclosure, recency visibility, mapped-lane count, long-title stress, host connectivity, phone phase, and whether proposed telemetry is enabled. Do not force identical controls onto every treatment.

## Required scenarios

The study must make these states easy to compare across all five treatments:

- No lanes mapped
- Several mapped lanes, none selected
- Selected and validating
- Selected but unconfirmed/stale
- Selected and exact-task confirmed
- Listening and transcribing
- Waiting for Codex after a Talkie-originated submission
- Queue accepted and Steer accepted delivery receipts
- Approval required with Mac recovery guidance
- Host disconnected or unavailable
- Long task title plus same-title tasks in two projects

Use only one authored motion cue: reserve it for a genuinely live local phase such as listening or waiting. Do not animate generic mapped/confirmed dots.

## Studio deliverable

- Keep the discoverable route `/ios-deck-codex` and existing Studio registry entry.
- Replace the broad five-phone ergonomics board with a focused T2 lane-picker and host-signal iteration lab.
- Render five interactive iPhone 13 mini-like treatments, all using the same bottom sill rail geometry.
- Add a compact signal-source legend that labels **Host**, **Phone**, and **Proposed** truth.
- Include a concise comparison matrix scored for lane-switch speed, exact-task confidence, truthful state reporting, long-title resilience, and visual noise.
- Make a clear recommendation, including which pieces should be implemented now using the current data contract and which require a host API extension.
- Move the original T1–T5 exploration into a short archived decision section; do not keep the rejected treatments as full interactive phones.
- Rewrite `design/studio/app/ios-deck-codex/NOTES.md` as the new decision log. Preserve the fact that T2 was selected and record what was removed.
- Keep the study usable at ordinary laptop widths without excessive horizontal scrolling.

## Scope and verification

- Work only in `design/studio/` plus this brief if an annotation is useful.
- Do not modify anything under `apps/ios/` or `apps/macos/`.
- Do not commit or push.
- Run the relevant Bun/Next build or typecheck and report the exact result.
- Visually inspect the route at an ordinary laptop viewport and an iPhone-sized treatment viewport. Check keyboard focus, disabled/error/empty states, contrast, overflow, and long-title behavior.
- Run the Impeccable detector over changed UI files if it is available.
- Return the route, files changed, recommended picker/signal treatment, exact current-vs-proposed signal boundary, checks run, and unresolved product decisions.
