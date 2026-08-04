# TLK-036 — Watch Ask Lifecycle and Ready Signal

**Status**: Proposed (slice 1 implemented)
**Owner**: arach
**Studio**: /eng/tlk-036
**Surface**: /watch-ask
**Related**: TLK-034 (Codex task creation + Watch dispatch), TLK-035 (shared local agent turn driver)
**Review**: Independent second opinion (Fable, `ref:8-npktvr`); reconciliation recorded in "Review reconciliation" below

## Summary

An Ask AI started on the Watch can finish without the wearer ever learning it
finished. Today the wrist's only completion cue is the `.click` inside
`handleAIAudio` — it fires only when TTS audio physically lands on the Watch,
which happens only when the AI voice route is `watch`. On route `phone` the cue
fires in the hand; on route `silent` no cue fires anywhere. The wrist is left
holding a question with no answer.

This spec defines a delivery contract: every completed answer produces exactly
one arrival cue, on exactly one device, and the wrist owns that cue by default.
It also records the Watch information architecture direction, which is
documentation-only in this slice.

## Principles

1. **Exactly one cue per answer.** Not zero, not two. The cue is per memo, not
   per carrier — WatchConnectivity delivers the same terminal update over up to
   three carriers and the answer audio is a fourth.
2. **The wrist owns the cue unless the wrist is about to speak.** The only
   device that can excuse the Watch from tapping is the Watch itself, playing
   the answer aloud.
3. **A cue is a promise that something is worth looking at.** Failures do not
   get one. A tap the wearer must raise their wrist to interpret is a tap that
   interrupts without informing.
4. **Fail toward signalling.** An unknown or absent delivery value means the
   Watch taps. A missed answer is the failure worth avoiding; a redundant tap is
   merely mild.
5. **Durability is application-level.** Consistent with the existing project
   doctrine, receipts and ledgers live above WatchConnectivity's own callbacks,
   because either app can suspend mid-transfer.

## Contract

### Delivery ownership

The phone attaches a `delivery` value to the terminal `answered` memo update,
derived at the emission site in `AppDelegate.answerDelivery(for:)` from
`WatchAIResponse.didSpeak` and `.speechRoute`:

| Condition | `delivery` | Who cues |
| --- | --- | --- |
| Spoke on the Watch | `watchAudio` | Watch playback `.click` (existing) |
| Spoke on the phone | `phoneAudio` | Watch `.notification` |
| Route silent, or configured route did not actually speak | `silent` | Watch `.notification` |
| Field absent or unrecognized | — | Watch `.notification` |

A route that was configured but did not speak (`didSpeak == false`) is treated
as `silent`, not as its nominal route. The wrist is still owed a signal.

The phone `Haptics.cue` that accompanies phone playback and the Watch
`.notification` are not duplicates: different device, different moment, and the
wearer feels at most one of them at a time.

### Failure

`failed` transitions carry no `delivery` and produce no haptic on either device.
Failure is communicated by memo status in the Watch list and by history. This is
a product decision, recorded here so it is not re-litigated as an oversight.

### Transport

`WatchSessionManager.sendMemoUpdate` (phone) now writes the same dictionary to
three carriers, mirroring the shape already proven by `sendCodexDispatchUpdate`:

- `updateApplicationContext` — last-known state, merged per memo by
  `mergedMemoUpdates` and capped at `maxContextMemoUpdates = 10`. The previous
  implementation assigned `context["memoUpdates"] = [update]`, so a later
  `thinking` update for one ask could erase a terminal `answered` for another.
  The cap matches the Watch's own `maxRecentMemos`: a memo that cannot be
  displayed there does not need carrying here.
- `transferUserInfo` — the durable leg, newly added. Any outstanding
  `memoUpdate` transfer for the same memo is cancelled first, so the queue
  carries at most one pending update per memo and last write wins.
- `sendMessage` — immediate optimization only, skipped when unreachable.

The wearer's preference rides on the payload itself as `readyHaptic`.

### Watch-side funnel

All three carriers plus the audio arrival path converge on one decoder and one
decision point in the Watch `WatchSessionManager`:

```
didReceiveMessage / didReceiveApplicationContext / didReceiveUserInfo
        └─> applyMemoUpdatePayload -> handleMemoUpdate -> signalReadyIfNeeded
handleAIAudio ──────────────────────────────────────────┘
```

`signalReadyIfNeeded` fires only for `answered`, only once per memo ID, and only
when `readyHaptic` was true on the payload that carried the answer.

### The ledger

`WatchSignalLedger`, persisted to `signaled_memos.json`, holds two things:

- `signaledMemoIDs` — memos already announced, capped at `maxRecentMemos * 4`.
  This must be durable and must outlive the display window:
  `didReceiveApplicationContext` replays the phone's last-known context on every
  activation, so an in-memory set would re-announce the same answer on every
  Watch app launch, and a cap equal to the display window could let a replayed
  context wrap it.
- `awaitingWatchAudio` — answers the phone promised to speak on the Watch,
  stamped with a wall-clock `promisedAt` and the preference as it stood at
  promise time.

If promised audio never arrives, `resolveOverdueWatchAudio()` converts the
promise into a plain tap after `watchAudioGrace = 12s`. A foreground
`Task.sleep` covers the ordinary case; the same function runs on
`activationDidCompleteWith` and `sessionReachabilityDidChange` so a suspended
Watch resolves the promise on its next wake instead of losing it. Both paths go
through the same `hasSignaled`/`markSignaled` guard, so at most one cue fires.

`handleAIAudio` closes the ledger entry only after `AVAudioPlayer` is prepared —
a failure before that point falls through to the plain tap rather than
swallowing the cue. It also reads `hasSignaled` *before* applying the update and
suppresses its `.click` when the grace fallback already tapped for that memo:
audio routinely lands seconds after activation on the same wake, and WC offers
no way to see an incoming transfer before it arrives, so without that check the
suspended-Watch path would double-cue as a matter of course rather than as an
edge case.

Two invariants hold this together and are stated here because neither can be
expressed in code across the target boundary:

- **`maxSignaledMemos` (40) ≥ `maxContextMemoUpdates` (10).** A memo can only be
  announced twice if it is evicted from the ledger while still present in a
  replayed context. With this ordering that is impossible: evicting it needs 40
  newer answers, which pushed it out of the ten-slot context long before.
- **`didSpeak` for the `watch` route means *queued*, not *delivered*.**
  `AIResponseSpeechRouter` returns `didSpeak: didSend`, and `didSend` only says
  the file was handed to WatchConnectivity. The `watchAudio` promise is honest
  only because the grace fallback exists.

Two accepted trades, both failing toward signalling:

- If the audio file beats every `memoUpdate` carrier (cross-carrier ordering is
  not guaranteed), `handleAIAudio` enters the funnel with `readyHaptic`
  defaulted to true, and `noteAwaitingWatchAudio` is first-writer-wins. A wearer
  who has the setting off could then get a fallback tap if playback setup fails.
- `saveSignalLedger` is `try?`. A failed write after `markSignaled` re-announces
  on next launch. Double, never a silent miss.

### Setting

`watchReadyHapticEnabled`, default **on**, lives in the AI voice/output section
of Settings as **Watch tap** ("Tap the wrist when a reply is ready"), directly
beneath the speak-replies and output-route controls. It is deliberately not
gated on the route: it matters most when the route is `silent` or `phone`, which
is exactly when nothing else would cue the wrist.

It is stored in `TalkieAppConfiguration.TTS`. That struct gained a hand-written
lenient `init(from:)` in the same change — a synthesized `Codable` does not
apply property defaults for missing keys, so adding a non-optional field would
have made every previously stored config fail to decode and silently reset the
user's whole voice section.

**Deviation from the original direction**, recorded deliberately: the preference
is carried on each `memoUpdate` payload rather than synced to the Watch as
separate state over the appearance-style channel. That removes a second channel
to keep coherent and means the wrist applies the preference as it stood at the
moment the answer completed, not whatever is current when a suspended Watch
finally wakes. The cost is that a preference change does not retroactively apply
to an answer already in flight, which is the correct behaviour anyway.

### State machine

Unchanged. `WatchMemo.MemoStatus` keeps its seven cases (`sending`, `sent`,
`received`, `thinking`, `transcribed`, `answered`, `failed`). Delivery ownership
is an attribute of the terminal transition, not a new state.

## Cross-target constraint

`Talkie-iOS.xcodeproj` uses Xcode 16 `PBXFileSystemSynchronizedRootGroup`s. Each
root group belongs to exactly one target, with membership exceptions only for
`Info.plist`. A Watch-folder file therefore cannot be shared with the phone
target. Cross-device types are exchanged as raw-string dictionary payloads, and
the delivery enum is declared once per target (`AnswerDelivery` on the phone,
`WatchAnswerDelivery` on the Watch) with the raw values as the contract. This is
the same pattern the existing `status` and `codexDispatchUpdate` payloads use.

## Watch information architecture (recommendation, not implemented here)

Navigation is not required by the haptic contract, so this slice ships no
navigation change. The direction is recorded so the next slice does not have to
rediscover it.

Current shape: `MainWatchView` is a two-page `TabView` — `PresetPickerView`
(capture) and `CodexWatchView` — with Style / Recent / About behind a toolbar
gear in `WatchMoreView`. `RecentMemosView` rows are inert.

**Recommendation: four concepts, two pages, one conditional third.**

The four concepts the user named are all real. They do not all deserve a page.

| Concept | Where it lives |
| --- | --- |
| Home | Page 1. The landing surface: last-ask status plus the primary action |
| Capture | The action on page 1, not a peer page |
| Codex | Page 2, present only when a lane/task is configured |
| Recent | Behind the status line on page 1 until its rows do something; a page later |

Order: **Home → Codex (conditional) → Recent (later).**

Rationale:

- **Home and Capture are the same surface.** On a 45mm screen the primary action
  *is* the status anchor. A separate Home costs a swipe before the thing the
  wearer does most, and a Home that is only a launcher is Capture wearing a
  lapel pin. Concretely: today's `PresetPickerView` grows a one-line last-ask
  status strip — thinking / answered / failed, tap-through to Recent — and that
  is the whole of the Home requirement, in roughly twenty points of height.
  Keeping "Home" as the name is right; keeping it as a page is not.
- **Home earns that strip only because of this slice.** The haptic contract is
  what gives it something true to show: a tapped wrist raises to a surface that
  says which ask landed. Status on the landing page is not a dashboard, it is
  the other half of the tap.
- **Codex must actually become conditional.** `MainWatchView` shows
  `CodexWatchView` unconditionally today, so a wearer with no lane configured
  swipes into a dead page. The "when a lane is configured" clause should be
  enforced in code, not merely documented.
- **Recent stays behind the gear until its rows act.** Its rows are inert.
  Promoting a dead end to a top-level page is exactly the generic-dashboard
  failure to avoid. Give rows a destination (full answer, replay) first; the
  status strip is the entry point in the meantime.

Explicitly rejected: a standalone Home page, a generic dashboard, any surface
that both lists history and starts captures, and duplicate capture entry points.

## Review reconciliation

An independent review (Fable, via Scout, `ref:8-npktvr`) was run against the four
decision points above. Outcome as owner:

| Point | Reviewer | Resolution |
| --- | --- | --- |
| Haptic ownership | Agree on the split; found a real double-cue race at wake | **Accepted and fixed** — `handleAIAudio` now suppresses its `.click` when the fallback already tapped. Wake-time resolution is not delayed; the suppression alone closes it |
| Preference transport | Agree; named the audio-first hole | **Accepted as documented trade**, above |
| Ledger | Safe, but on an accidental cross-target invariant | **Accepted** — invariant pinned in both files and here |
| Watch IA | Disagree with four surfaces; merge Home into Capture | **Largely accepted** — recommendation above keeps the user's "Home first" naming while merging the surfaces, which is what both the reviewer and the original draft independently concluded |

Reviewer notes taken but deferred, with reasons:

- `AppDelegate` bakes `"Spoken on iPhone: "` into the preview string —
  presentation in data, and it spends the 240-character preview budget. Correct
  criticism. Removing it now would drop provenance from the Watch entirely,
  since nothing renders `delivery` yet; it goes with the surface that starts
  rendering it (slice 2).
- `RecentMemosView` uses `.foregroundColor` and `String(format:)` against the
  house style. Fix when that surface is touched for the IA work, rather than
  widening this slice into a file it does not otherwise change.

Accepted immediately: raising the "session not activated" drop from `debug` to
`warning`, since that path drops all three carriers rather than deferring them.

## Unresolved product choices

1. **Home's existence.** Recommended above as a status strip on the capture
   landing page rather than a page of its own. Needs the user's sign-off before
   slice 2, since it is a deliberate reinterpretation of "Home first".
2. **`watchAudioGrace = 12s`.** Chosen to cover an ordinary file transfer without
   leaving the wearer wondering. Not measured against real transfer times on a
   cold Watch.
3. **Haptic style.** `.notification` for ready. Not yet compared on-device
   against `.success` or a `.click`/`.directionUp` pair; `.notification` was
   chosen because it is the system's "something arrived" idiom.
4. **Whether a phone-spoken answer should still tap the wrist when the phone is
   not on the wearer** (bag, desk, another room). Currently `phoneAudio` still
   taps the wrist, which is the safe reading, but it means a wearer holding the
   phone gets both cue types in close succession on different devices.
5. **Grouping.** Whether a burst of answers arriving together should coalesce
   into one tap. Not currently coalesced; unlikely to matter at present volumes.

## Slice plan

- **Slice 1 (this change)** — delivery contract, durable transport, deduplicated
  ready signal, persisted ledger, setting.
- **Slice 2** — the Home status strip on the capture landing page, conditional
  Codex page, `RecentMemosView` retheme to the `WatchDesign` token set with
  navigable rows, and provenance rendered from `delivery` instead of the baked
  preview prefix.
- **Slice 3** — phone in-flight indication (`AskInFlightRegistry` + chrome
  overlay) with truthful phases.
- **Slice 4** — `WatchAskThreadView` reading `AgentSessionStore` turns.

## Changed files (slice 1)

- `apps/ios/Talkie iOS/App/WatchSessionManager.swift`
- `apps/ios/Talkie iOS/App/AppDelegate.swift`
- `apps/ios/Talkie iOS/Services/TalkieAppSettings.swift`
- `apps/ios/Talkie iOS/Services/TalkieAppConfiguration.swift`
- `apps/ios/Talkie iOS/Views/Next/SettingsNext.swift`
- `apps/ios/TalkieWatch Watch App/WatchSessionManager.swift`
