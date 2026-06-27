# Review — Agent launch responsiveness & markup hotkeys

Branch: `codex/agent-quick-capture-markup`
Scope: narrow review against the stated hard invariants. No broad refactors proposed.

## 1. First-principles design

**Agent responsiveness.** The Agent's AppKit main thread (`@MainActor`) must never run a
synchronous, unbounded wait during boot. `Process.waitUntilExit()` on the MainActor is exactly
that: it blocks the run loop for the full lifetime of the child, so a slow/wedged child freezes the
status menu. Optional network providers (Tailscale) are the textbook offender — they can be absent,
stopped, mid-launch (GUI app cold start), or wedged. Therefore:

- Tailscale is **optional and off the critical path**. The Agent and the bridge it spawns must
  reach a healthy local state with zero Tailscale interaction by default.
- Any Tailscale enrichment (extra advertised host) is **opt-in, asynchronous, time-bounded, and
  CLI-only** — never the GUI app bundle binary, never awaited before the socket binds, never on the
  Agent's main thread.
- "Healthy" for the Agent = menu responsive + bridge answering `http://localhost:8765/health`.
  Remote route richness is explicitly lower priority than responsiveness.

**Markup hotkeys.** Tool *selection* and angle *snapping* are orthogonal. `Option-T` opens a tool
chord; the next key picks a tool. Shift is a drawing/reshaping modifier (snap to 15° steps), and must
not overload the meaning of a selection key. So `Option-T, A` → Arrow unconditionally; Shift only
changes geometry while a stroke is being drawn or an endpoint reshaped.

## 2. Does the implementation satisfy it?

**Responsiveness — the reported bug is fixed.**
- `TalkieServerSupervisor.swift`: `refreshTailscaleStatus()` (which ran
  `tailscale status --json` via `proc.waitUntilExit()` on the MainActor, with the GUI app bundle as a
  candidate path) is **deleted**, and its call site before `probeServerHealth` is removed. The
  advertised route is now hard-coded `"local"` via `startAdvertiser()`. This is precisely the
  main-thread block seen in the process sample; removing it restores menu responsiveness.
- `ExecutableResolver.swift`: `/Applications/Tailscale.app/Contents/MacOS/Tailscale` dropped from the
  `tailscale` candidate list — the resolver can no longer hand back the GUI binary.

These two changes fully resolve the **observed** symptom (Agent main thread back in the AppKit event
loop, no Tailscale child of the Agent process).

**Markup hotkeys — satisfied.**
- `overlay.js handleToolChord` `case "a": setTool("arrow")` ignores `shiftKey` (unchanged on this
  branch — it was already correct), while `case "l"` is the one that branches on Shift. So
  `Option-T, A` selects Arrow whether or not Shift/Option are still held.
- The branch's actual change is the **snap gating**: `adjustedSegmentPoint` now early-returns unless
  `event.shiftKey` (drawing), and the new `adjustedEndpointPoint` does the same for reshaping
  (`resizeSegmentEndpoint`). Previously snapping leaked in via a `forceSnap` parameter. Net: Shift
  snaps only while drawing or reshaping a line/arrow, and does not touch selection semantics. Both
  invariants hold.

## 3. Concrete gaps

**Gap A (transitive Tailscale probe at Agent startup) — real.**
The Agent spawns the bridge with `--nearby --allow-lan --require-approval`
(`TalkieServerSupervisor.swift:132`). In `TalkieServer/src/server.ts` the `NEARBY_MODE` branch runs:

```
472  } else if (NEARBY_MODE) {
473    serverConfig.hostname = getLocalBonjourHostname();
474    const tailscaleState = await getTailscaleState();   // ← probe, awaited before app.listen()
475    if (tailscaleState.status === "ready" || ...) appendAlternateHost(tailscaleState.hostname);
```

`getTailscaleState()` (`src/tailscale/status.ts:127`) executes `` `${tailscalePath} status --json` ``
with **no timeout** (`.quiet().nothrow()`), and `findTailscalePath()` still lists the GUI bundle
`/Applications/Tailscale.app/Contents/MacOS/Tailscale` (`status.ts:11`) as a candidate. So on a host
where Tailscale exists (especially **GUI-only**, the exact case called out), every Agent launch
shells out to `tailscale status --json` — potentially the GUI app's binary — and the bridge does not
bind until that returns. This is the same `Tailscale status --json` child seen in the hang, now
moved into the bridge subprocess.

Why it didn't show in your evidence: when Tailscale is fully absent, `findTailscalePath()` returns
null and the code falls back to a network-interface scan (no subprocess) — so `pgrep` was clean on a
machine without the CLI/GUI installed. The gap surfaces only when Tailscale is present.

Severity: does **not** freeze the Agent menu (separate process), so the reported responsiveness bug
stays fixed. But it (a) violates the literal invariant "Agent startup must not launch, probe, or
revive Tailscale," (b) can delay bridge `/health` readiness if that binary is slow/wedged (no
timeout → unbounded), and (c) can launch the GUI app's binary. Note: `server.ts`/`status.ts` are
**not** in this branch's diff — this is pre-existing and outside the Swift change, but the Swift-only
fix does not close it.

**Gap B (other MainActor `waitUntilExit` in boot path) — minor/pre-existing.**
- `installDependencies()` (`TalkieServerSupervisor.swift:506`) calls `proc.waitUntilExit()` and is
  `await`ed from `start()` on the MainActor. Only hit on first launch (missing `node_modules`), but a
  multi-second `bun install` would block the menu just like the Tailscale probe did.
- `portOccupantDescription()` (`:463`) also uses `waitUntilExit()` (lsof) on the MainActor; only on
  the conflict path and fast, so low risk.

**Gap C (cosmetic).** `tailscaleReady` is now dead state in the supervisor — always `false`, still
surfaced in `currentStatus`. Harmless; consider removing for clarity.

## 4. Must-fix vs follow-up

- **Must-fix to satisfy the literal "no Tailscale probe at startup" invariant — Gap A.** Make the
  nearby bridge local-only by default: gate `getTailscaleState()`/`appendAlternateHost` behind an
  explicit opt-in flag (default off) **or** move it after `app.listen()` and wrap it in a short
  timeout; and drop the GUI bundle path from `status.ts:TAILSCALE_PATHS` for parity with
  `ExecutableResolver`. Files: `apps/macos/TalkieServer/src/server.ts:472-479`,
  `apps/macos/TalkieServer/src/tailscale/status.ts:11`.
  - If the intent of this branch is *only* to fix the menu hang, Gap A can be tracked as a separate
    bridge-hardening task — but then the hard invariant is not yet literally met, and that should be
    stated explicitly rather than assumed closed.
- **Resolved (was the must-fix for the reported symptom):** Swift main-thread probe removal +
  resolver GUI-path removal. ✔
- **Follow-up:** Gap B (offload `installDependencies`/`portOccupantDescription` off the MainActor,
  e.g. async pipe reads), Gap C (remove dead `tailscaleReady`).
- **No action:** markup hotkeys — both invariants already satisfied.

## 5. Verification that would prove this solved

Responsiveness / Tailscale invariant — run the matrix, not just the absent case:
1. Tailscale **absent**, **stopped**, **GUI-only**, **wedged** (e.g. `kill -STOP` tailscaled). For
   each: launch a freshly built Agent and confirm
   - status menu opens immediately (sample shows main thread in `__CFRunLoopRun`, not
     `TalkieAgentServerSupervisor.start`);
   - `curl -s localhost:8765/health` returns 200 within the normal `waitForReady` window;
   - **no `tailscale`/`Tailscale.app` process appears in the Agent's *or the bridge's* process
     subtree during boot** — e.g. `pgrep -lf -P <bridgePid> tailscale` empty, or
     `sample <AgentPid>` / `fs_usage` shows no exec of a tailscale binary. This is the assertion that
     actually distinguishes "fixed" from "fixed only because Tailscale isn't installed."
   The GUI-only + wedged cases are the ones that would expose Gap A today.
2. Build/lint already green per your evidence: `./run.sh TalkieAgent --no-launch`,
   `node --check overlay.js`, `git diff --check`.

Markup:
3. With Arrow not selected, press `Option-T` then `A` (and again holding Shift) → tool becomes Arrow
   both times. Press `Option-T` then `L` → Line; `Option-T` then `Shift-L` → cycles line style
   (selection key meaning unchanged for Arrow).
4. Draw a line/arrow holding Shift → angle snaps to 15°; release Shift → free angle. Reshape an
   endpoint in select mode with Shift → snaps; without Shift → free. Selecting/moving never snaps.
5. `swift test` for `CaptureMarkupTests` (xcodebuild, since `#if DEBUG` paths matter) to cover the
   document/renderer arrow-style changes.
