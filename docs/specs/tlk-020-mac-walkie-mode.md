# TLK-020 — Mac Walkie Mode

**Status**: In progress — v1 shell and multi-provider orchestration wired
**Owner**: arach
**Design source**: `design/studio/components/studies/MacWalkieScope.tsx` (route: `/mac-walkie`)
**Related**: iPhone Ask AI (`apps/ios/Talkie iOS/Views/Next/AskAINext.swift`) — vocabulary harmonization, not code reuse

## Summary

A press-and-hold agent surface on macOS, bound by default to **Hyper+T** (`⇧⌃⌥⌘T`). Pressing the chord blooms a floating modal in the center of the screen — a single instrument panel dominated by an oscilloscope display. The user speaks while holding the key, releases to send, and the agent responds verbally (TTS to default audio device) with a short caption underneath. The modal dismisses on tap or after a brief idle.

Three things make this distinct from iPhone Ask AI, which is also a turn-based agent surface:

1. **Live surface is ephemeral, not a panel.** The walkie is a *moment*, invoked by a hotkey, dismissed when done. Durable activity belongs in Agent Home, not a new Walkie-branded place.
2. **Always-on, walkie-talkie pace.** The agent voice is conversational and brief ("Alright, we gotcha…"), not assistant-formal. The interaction is short by design.
3. **Two transmission modes, routed automatically.** Every TALKIE turn lands as either VERBAL (immediate spoken answer) or ASYNC (long-running computer-use job that acks now and reports later via the notch). The model decides which, the user doesn't choose.

Non-goal: replacing the existing dictation / compose / selection-readout flows. Those stay. Walkie is a new surface alongside them, with its own hotkey and its own session model.

## What exists today

We're not starting from zero. Existing pieces compose into walkie; this spec is the glue and the one new thing.

| Capability | Lives in | Reused by walkie how |
|---|---|---|
| Carbon `RegisterEventHotKey` wrapper | `apps/macos/TalkieAgent/.../Services/HotKeyManager.swift` | New `walkieHotKeyManager` with signature `<sig>WT`, hotkeyID 17 |
| Press-and-hold dictation lifecycle | `pttHotKeyManager` pattern in `TalkieAgent/.../AppDelegate.swift:23` | Same press/release shape, new destination |
| Selection readout (LLM → TTS) | `SelectionSpeechPlaybackController.speakSelection` (AppDelegate.swift:2128) | Walkie reuses the OpenAI/ElevenLabs/Apple fallback chain for verbal-out |
| LLM provider stack | `TalkieKit` `LLMProviderRegistry` + shared LLM settings | Top-level Walkie model is provider-agnostic and can route through OpenAI, Anthropic, Gemini, Groq, or the configured default |
| Agent runtime boundary | `WalkieAgentRuntime` in `TalkieAgent/Views/Walkie/` | Async mode hands work to a swappable executor runtime; Scout Agent Session is the intended first adapter |
| Node runtime shim | `TalkieAgent/Runtime/node/` | Bundled stdio dispatcher only; Talkie agent runtime packages are CLI-managed post-install tools under the user's runtime directory |
| iOS Ask AI vocabulary | `apps/ios/Talkie iOS/Views/Next/AskAINext.swift` | T01/T02 turn codes, USER/TALKIE speaker labels, model · latency · tokens meta — same words, different surface |

## The four phases

The whole arc of one transmission is four sequential moments. See `MacWalkieScope.tsx` for the visual locked-in design. This is the data side.

```
       press                              release
         │                                   │
         ▼                                   ▼
   ┌──────────┐ ┌────────────────┐ ┌──────┐ ┌──────────┐
   │  READY   │→│  TRANSMITTING  │→│ OVER │→│ RECEIVING│
   └──────────┘ └────────────────┘ └──────┘ └──────────┘
        ↑                                        │
        └──────── auto-dismiss after idle ───────┘
```

| Phase | Trigger | Duration | Audio | Visual |
|---|---|---|---|---|
| ready | Hyper+T pressed | ~150ms | none | scope at rest, channel armed |
| transmitting | continues while held | until release | mic capture | scope live with voice waveform |
| over | hotkey released | ~500ms | none | trace decays, "OVER" badge |
| receiving | LLM response ready | until done + idle timeout | TTS playback | scope shows TTS waveform + caption |

Async mode collapses *receiving* into a brief verbal ack ("On it — back in a minute") followed by an auto-dismiss; the actual agent invocation runs in the background and surfaces through the existing notch composer when done.

## Data model

Two primitives. **Channel** and **Transmission**.

```swift
struct WalkieChannel: Identifiable, Codable {
    let id: UUID
    var code: String          // "CH-01", "CH-02", ...
    var label: String         // "NIGHTOPS", "QUICK", ...
    var systemPrompt: String  // per-channel agent persona
    var topLevelProviderId: String?
    var topLevelModelId: String?
    var executorRuntimeId: String?
    var executorProviderId: String?
    var executorModelId: String?
    var createdAt: Date
    var lastTransmissionAt: Date?
}

struct WalkieTransmission: Identifiable, Codable {
    let id: UUID
    let channelId: UUID
    let code: String          // "T01", "T02", ... — per-channel sequence
    let userBody: String      // transcribed user voice
    let userDurationMs: Int   // hold duration
    let talkieBody: String?   // agent reply text
    let mode: Mode            // .verbal | .async
    let topLevelProviderId: String?
    let topLevelProviderName: String?
    let topLevelModelId: String?
    let executorRuntimeId: String?
    let executorRuntimeName: String?
    let executorProviderId: String?
    let executorModelId: String?
    let executorSessionId: String?
    let latencyMs: Int?
    let tokens: Int?
    let startedAt: Date
    let completedAt: Date?
    let jobState: JobState?   // nil for verbal; populated for async

    enum Mode: String, Codable { case verbal, async }
    enum JobState: Codable { case acked, working, done, failed }
}
```

**Vocabulary harmonization with iOS Ask AI.** Same `T01/T02` code shape, same `USER`/`TALKIE` speaker labels, same `provider · model · latency · tokens` meta line. iOS owns its own `AskAITurn` type (with a `Speaker` enum); Mac walkie has its own `WalkieTransmission` (no `Speaker` enum — speaker is implicit in field names). If iOS later grows the async mode, we promote the shared shape to TalkieMobileKit at that point. Until then: same words, separate types.

**Channel default.** First-launch channel is `CH-01 · NIGHTOPS` with a generic system prompt. User can create more from a settings surface (out of scope for v1 — single channel is fine).

## Model and runtime split

Walkie has two deliberately separate AI layers:

1. **Top-level LLM** — the conversational router. It sees the transcript, channel prompt, and turn metadata, then returns one JSON decision: answer verbally now, or acknowledge and hand off a concrete executor instruction.
2. **Executor runtime** — the long-running worker. It may be Scout Agent Session, a local code agent, a hosted agent session, or another multi-agent backend. Walkie records the runtime/session/model identity but does not bind the live UI to any one executor.

Settings follow that boundary:

- `walkie.topLevelProviderId`
- `walkie.topLevelModelId`
- `walkie.executorRuntimeId`
- `walkie.scoutRuntimeEnabled`
- `walkie.autoPlay`

If the Walkie-specific top-level provider/model is missing, v1 falls back to the global LLM provider/model settings, then to `LLMProviderRegistry.resolveProviderAndModel()`. That keeps Walkie multi-LLM by default instead of accidentally hard-coding the first prototype provider.

## Executor runtime protocol

The Swift side talks to executor runtimes through `WalkieAgentRuntime`.
The first concrete bridge is a local Node stdio dispatcher at
`TalkieAgent/Runtime/node/index.mjs`. It is deliberately small: one
JSON request per line, one JSON response per line.

The app bundle intentionally does **not** vendor `node_modules` or run `npm ci`
as part of Xcode archive. The dispatcher can report `scoutBridge: "pending"`
without failing the app. The Talkie Agent Runtime package is installed later by
an explicit CLI command, currently `Runtime/node/install-agent-runtime.sh`,
which hydrates `@talkie/agent-runtime` into `~/.talkie/agent-runtime`.

Supported operations:

```json
{ "op": "ping" }
```

```json
{
  "op": "invoke",
  "invocation": {
    "id": "UUID",
    "channel": { "code": "CH-01", "label": "NIGHTOPS" },
    "transcript": "raw user transcript",
    "instruction": "executor-ready instruction",
    "topLevelModel": {
      "providerId": "openai",
      "providerName": "OpenAI",
      "modelId": "gpt-5.5"
    },
    "requestedAt": "ISO-8601 date"
  }
}
```

```json
{ "op": "activityStatus", "sessionId": "walkie-UUID" }
{ "op": "cancelInvocation", "sessionId": "walkie-UUID" }
```

The dispatcher returns a runtime descriptor and an activity descriptor:

```json
{
  "ok": true,
  "runtime": {
    "id": "walkie-node-dispatcher",
    "name": "Walkie Runtime Dispatcher",
    "capabilities": ["readOnlyData", "longRunningJobs"],
    "scoutBridge": "pending"
  },
  "activity": {
    "id": "UUID",
    "sessionId": "walkie-UUID",
    "state": "acked",
    "ack": "spoken acknowledgement"
  }
}
```

`walkie-node-dispatcher` is the local contract holder. It can accept an
invocation and preserve the executor/session shape even before Scout is live.
`talkie-agent-runtime` remains the intended code/computer-use executor package,
backed by Scout Agent Sessions internally, but it only advertises availability
once the user-space CLI runtime exists and the Node dispatcher reports
`scoutBridge: "configured"`.

## Agent Home return path

Async mode needs a durable return path. That is **Agent Home**, not the
ephemeral Walkie scope. The scope handles the live voice moment and
immediate acknowledgement; Agent Home owns "what is running, what
happened, and what needs attention."

Initial Agent Home sections:

- **Now** — active executor work, dispatcher state, and recent activity.
- **Activity** — executor sessions plus recent voice/dictation captures.
- **Voice** — push-to-talk state as one input into Agent.
- **Executor** — bridge status and open work.

The notch/status pill remains a lightweight pointer back to Agent Home.
It should not become the durable history surface.

## Routing — verbal vs async

The user doesn't pick the mode. The top-level Walkie model does, on first read of the transcript.

The routing call returns:

```json
{
  "mode": "verbal",
  "reply": "short spoken answer or immediate ack",
  "executorInstruction": "specific instruction for the executor, or null",
  "confidence": 0.92,
  "rationale": "short private routing note"
}
```

Execution:

- If `verbal`: `reply` is the immediate answer; the panel enters *receiving*, shows it, and optionally speaks it.
- If `async`: `reply` is a brief ack; `executorInstruction` is passed to the resolved `WalkieAgentRuntime`. The panel can show the ack immediately while the runtime owns the longer invocation.

Routing heuristic (in the top-level model's system prompt, not Swift):
- Question with a likely short factual answer → verbal
- Single action that completes in <2s → verbal (it's faster to just do it)
- Multi-step work, requires tools, ambiguous outcomes → async
- Mixed ("answer X and then do Y") → verbal-first with a tail async (rare; v1 can degrade to async-only)

If the model fails to return JSON, v1 treats the raw text as a verbal reply. If it routes async and no executor runtime is connected, v1 speaks the ack plus an explicit "no executor runtime is connected yet" fallback. No silent stalls.

## Implementation plan

Four work units. Each is small enough to ship and verify independently.

### Unit 1 — Hyper+T hotkey + floating panel shell (spike)

- Add `walkieHotKeyManager` to `apps/macos/TalkieAgent/.../AppDelegate.swift` alongside the other managers (signature `<sig>WT`, hotkeyID 17).
- Default modifiers: `cmdKey | controlKey | optionKey | shiftKey`; default keyCode: 17 (T).
- Press handler opens a centered `NSPanel` (level `.floating`, `.borderless`, `.hidesOnDeactivate`, ignores mouse if not focused on caption).
- Release handler closes the panel.
- Panel hosts a SwiftUI view named `WalkieScopeView` that mirrors `MacWalkieScope.tsx` — initially a static "ready" composition.
- Verification: hold Hyper+T, see floating panel appear; release, see it dismiss.

This is the smallest useful step. Builds the modal mechanic without any audio or LLM wiring.

### Unit 2 — Live transcription bound to the panel

- Reuse the existing dictation engine selection (Apple Speech in foreground; Parakeet is for live flows but the v1 path stays Apple Speech for keyboard-extension parity).
- On press: start dictation, drive the scope's live waveform from the audio level meter (`AVAudioRecorder.averagePower`).
- On release: finalize the transcript, stash it in a `WalkieTransmissionDraft`, transition the panel to the *over* phase.
- The scope trace in v1 is a procedural sine derived from input level — no need to render real waveform samples yet. (Real waveform = polish.)

### Unit 3 — Verbal mode end-to-end

- After *over*, send the transcript to `WalkieOrchestrator`.
- Resolve the top-level LLM from Walkie-specific provider/model settings, then global provider/model settings.
- For verbal results, send the answer through `SelectionSpeechPlaybackController.speakSelection` (existing OpenAI/ElevenLabs/Apple chain).
- Panel transitions to *receiving*, shows the caption, plays the audio.
- After TTS finishes + 2s idle, panel auto-dismisses.

At this point the loop is closed: hold, talk, hear answer, done.

### Unit 4 — Async mode + notch reporting

- For async routing results, play/show the ack, then hand `executorInstruction` to the selected `WalkieAgentRuntime`.
- Current runtime target is `walkie-node-dispatcher`, which establishes the Swift → Node invocation/session contract.
- Scout Agent Session becomes the code/computer-use executor once the Node dispatcher can create a real Scout session; it is guarded by `walkie.scoutRuntimeEnabled` until that bridge is live.
- Record executor runtime id/name, optional provider/model id, session id, and job state on the transmission and Agent Home activity store.
- On completion, the existing `NotchComposer` pipeline (camera bubble / status pill primitives) shows a "Talkie Agent · done" affordance; tap opens Agent Home.

This unit needs the Agent Home activity model, which is its own follow-up (see *Open follow-ups*).

## Open follow-ups (not v1)

- **Agent Home activity model** — sessions persist as Agent activity items. Walkie/voice is an input; executor sessions, routines, and future agent work share the same home.
- **Multi-channel switcher** — UI to create/switch channels (each with its own system prompt). v1 ships single channel.
- **Settings surface** — hotkey binding, default channel, idle-dismiss duration, top-level model override, executor runtime override, Scout runtime enablement.
- **Visible HUD while holding key** — current spec assumes the modal IS the HUD. If the modal turns out to be too heavy for very-quick transmissions, we add a small notch-only "ambient" mode that bypasses the modal for sub-second presses.
- **Conversation context across transmissions** — within a channel, do prior transmissions get sent as context? Default for v1: no, each transmission is a fresh single-turn call. Cheap and predictable.
- **Talkie-from-iOS** — once Mac walkie ships, iPhone Ask AI grows the async mode and shared routing contract. We promote `WalkieChannel`/`WalkieTransmission` to TalkieMobileKit then.

## Risks

- **Routing latency is now the visible LLM latency.** The top-level model both routes and answers verbal turns, so verbal mode is one call, not classifier-plus-answer. Mitigation: keep the routing prompt small and allow a cheap/fast Walkie-specific model override.
- **Floating panel + global hotkey + dictation = three TCC permissions.** Microphone, accessibility (for hotkey), and screen recording (if we ever show the desktop behind faded — not v1). v1 only needs mic + accessibility, both already requested by Talkie.
- **Audio device conflicts.** If the user is in a call, TTS responses interrupt their meeting. v1 plays through default device anyway; the alternative (route to a secondary device) is a settings polish for later.

## What the studio already locked

See `/mac-walkie` for the visual canon. Key decisions locked from the studio iteration:

- Single floating panel ~640px wide, AMBER scheme (`#14181A` body), drop shadow + bezel highlights.
- Oscilloscope dominates the panel; scope IS the surface, no chrome around it.
- Status strip top: channel pill + T-code + phase badge + timecode + signal LED.
- Footer: chamfered keycap row with amber-lit T, phase-aware hint text.
- Receiving phase adds a caption row: "Talkie · spoken" eyebrow + display serif italic line.
- Hand-drawn SVG trace per phase; transmitting phase has a sweep dot.

Swift port: `WalkieScopeView.swift` lives in `apps/macos/TalkieAgent/TalkieAgent/Views/Walkie/`. Tokens for the AMBER scheme are already in `lib/schemes.ts`; export to Swift via the existing tokens pipeline (see `project_studio_to_native_tooling`).
