# TalkieKeys: Keyboard Extension Architecture

> How the custom keyboard extension loads, communicates with the main app,
> records audio, transcribes speech, and inserts text — all across iOS process boundaries.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                        HOST APP (e.g. Safari, Notes)                │
│                                                                     │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                   TalkieKeys Extension                      │   │
│   │              (runs inside host app process)                 │   │
│   │                                                             │   │
│   │   KeyboardViewController                                   │   │
│   │   ├── LED Display Bar (status, mode knob)                  │   │
│   │   ├── Slot Grid (12 configurable buttons + dictate row)    │   │
│   │   ├── CompactKeyboardView (ABC/QWERTY mode)                │   │
│   │   ├── MinimalKeyboardView (single-row layout)              │   │
│   │   └── VoiceEmojiOverlay (voice → emoji search)             │   │
│   │                                                             │   │
│   │   textDocumentProxy ←── inserts text into host app          │   │
│   └──────────────────────────┬──────────────────────────────────┘   │
│                              │                                      │
└──────────────────────────────┼──────────────────────────────────────┘
                               │
                   App Group UserDefaults
                    (cross-process IPC)
                               │
┌──────────────────────────────┼──────────────────────────────────────┐
│                              │                                      │
│   ┌──────────────────────────┴──────────────────────────────────┐   │
│   │              HeadlessDictationService                        │   │
│   │         (records audio, transcribes, publishes results)     │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│                     TALKIE APP (separate process)                    │
└─────────────────────────────────────────────────────────────────────┘
```

**Key constraint**: iOS keyboard extensions run inside the host app's process, not the Talkie app's process. The extension and app cannot share memory — all communication goes through App Group UserDefaults.

---

## Extension Lifecycle

The keyboard extension's lifecycle is controlled by iOS, not by us. iOS can load, unload, and reload the extension at any time. Understanding this is critical to everything else.

### Startup Sequence

```
viewDidLoad()          ← Extension loaded (may happen multiple times)
    │
    ├── setupUI()      ← Build view hierarchy immediately (fast path)
    ├── restorePersistedModeSelection()
    ├── updateGridForMode()
    │
    └── DispatchQueue.main.async {
            loadState()    ← Deferred: heavy state sync after first paint
        }

viewWillAppear()       ← Keyboard becoming visible
    │
    ├── startHeartbeat()   (1.0s timer → shared store)
    │
    └── DispatchQueue.main.async {
            checkForDictationResult()
            checkRecordingState()
        }

viewDidAppear()        ← Keyboard fully visible
    │
    └── DispatchQueue.main.async {
            loadState()    ← Full state sync
        }
```

**Design principle**: UI renders instantly on `viewDidLoad`. All state loading, result checks, and IPC reads are deferred to after the first paint. This keeps keyboard appearance fast (<100ms) regardless of shared state complexity.

### Disappearance & Teardown

```
viewWillDisappear()    ← User switched apps, closed keyboard, etc.
    │
    ├── stopHeartbeat()     (keyboard heartbeat goes stale)
    ├── stopPolling()       (state polling stops)
    └── stopActivityShimmer()
```

When the keyboard disappears, all timers stop. The extension process may continue running (iOS keeps it alive briefly) or may be killed. **No in-memory state survives a kill** — everything must be recoverable from App Group UserDefaults.

### Memory Model

```
┌─────────────────────────────────────────────────────────────┐
│                    Host App Process                          │
│                                                             │
│   ┌────────────────────┐   ┌────────────────────────────┐  │
│   │   Host App Memory  │   │  TalkieKeys Extension      │  │
│   │   (Safari, Notes)  │   │  Memory (shared process)   │  │
│   │                    │   │                            │  │
│   │                    │   │  48 MB LIMIT               │  │
│   │                    │   │  (iOS enforced)            │  │
│   └────────────────────┘   └────────────────────────────┘  │
│                                                             │
│   Killed by iOS when:                                       │
│   • Memory pressure (host app needs RAM)                    │
│   • Extension exceeds 48 MB                                 │
│   • Host app is terminated                                  │
│   • iOS system optimization                                 │
└─────────────────────────────────────────────────────────────┘
```

**Consequence**: Every piece of state that matters must be persisted to App Group UserDefaults. When the extension reloads, `viewDidLoad` → `loadState()` reconstructs everything from shared storage.

---

## UI Architecture

### Layout Modes

The keyboard has three visual layouts, switchable at runtime:

```
┌─────────────────────────────────────────────────────────────┐
│ STANDARD LAYOUT (slot grid)                                 │
│                                                             │
│ ┌─LED Bar──────────────────────────────────────────────────┐│
│ │ 🔴 talkie     READY              [FN ← →]               ││
│ └──────────────────────────────────────────────────────────┘│
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐    Row D (slots 9-12) │
│ │ FYI  │ │  @   │ │ Re:  │ │ B.R. │                        │
│ └──────┘ └──────┘ └──────┘ └──────┘                        │
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐    Row C (slots 5-8)  │
│ │ ESC  │ │ DEL  │ │ TAB  │ │  Aa  │                        │
│ └──────┘ └──────┘ └──────┘ └──────┘                        │
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐    Row B (slots 1-4)  │
│ │ COPY │ │PASTE │ │SPACE │ │  .   │                        │
│ └──────┘ └──────┘ └──────┘ └──────┘                        │
│ ┌──────┐ ┌──────────────────────┐ ┌──────┐  Row A (dictate)│
│ │SELECT│ │       ● DICTATE      │ │ENTER │                  │
│ └──────┘ └──────────────────────┘ └──────┘                  │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ COMPACT LAYOUT (ABC/QWERTY mode)                            │
│                                                             │
│ ┌─LED Bar──────────────────────────────────────────────────┐│
│ │ 🟢 talkie     ● DICTATING        [ABC ← →]              ││
│ └──────────────────────────────────────────────────────────┘│
│ ┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐       │
│ │ Q ││ W ││ E ││ R ││ T ││ Y ││ U ││ I ││ O ││ P │       │
│ └───┘└───┘└───┘└───┘└───┘└───┘└───┘└───┘└───┘└───┘       │
│  ┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐           │
│  │ A ││ S ││ D ││ F ││ G ││ H ││ J ││ K ││ L │           │
│  └───┘└───┘└───┘└───┘└───┘└───┘└───┘└───┘└───┘           │
│ ┌────┐┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐┌───┐┌────┐          │
│ │ ⇧  ││ Z ││ X ││ C ││ V ││ B ││ N ││ M ││ ⌫  │          │
│ └────┘└───┘└───┘└───┘└───┘└───┘└───┘└───┘└────┘          │
│ ┌────┐┌────┐┌────────────────────────┐┌────┐┌────┐        │
│ │ 😀 ││ 🎙 ││     SPACE / ■ STOP    ││ ⏎  ││mode│        │
│ └────┘└────┘└────────────────────────┘└────┘└────┘        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ MINIMAL LAYOUT (single row, 42pt total)                     │
│                                                             │
│ ┌──────┐ ┌──────┐ ┌──────────────────────┐ ┌──────┐ ┌──────┐
│ │ COPY │ │PASTE │ │       ● DICTATE      │ │SPACE │ │ENTER │
│ └──────┘ └──────┘ └──────────────────────┘ └──────┘ └──────┘
└─────────────────────────────────────────────────────────────┘
```

### Mode System

Modes define what each slot button does. The user cycles through modes via swipe gestures or the mode knob on the LED bar.

```
Mode Cycling (swipe left/right):

    ┌──────┐     ┌──────┐     ┌──────┐     ┌──────┐     ┌──────┐
    │ ABC  │ ──→ │  FN  │ ──→ │ 123  │ ──→ │ #$&  │ ──→ │ Emoji│ ──→ (wraps)
    │      │ ←── │      │ ←── │      │ ←── │      │ ←── │      │
    └──────┘     └──────┘     └──────┘     └──────┘     └──────┘

    ABC mode:   Shows CompactKeyboardView (full QWERTY), hides slot grid
    FN mode:    Quick actions (TAB, COPY, PASTE, DEL, ESC, Aa, SPACE, .)
    123 mode:   Number pad (0-9, decimal, delete)
    #$& mode:   Symbols and punctuation
    Emoji mode: Emoji picker via slot grid
```

**Mode persistence**: The active mode is saved to `KeyboardBridge.lastSelectedModeId` (24hr TTL) and restored on every `viewDidLoad`. Without this, the keyboard would always start on FN mode after an extension reload.

---

## Cross-Process Communication (IPC)

The keyboard extension and main app communicate through **three overlapping channels** in App Group UserDefaults. Each exists for a reason, but the overlap creates complexity.

### Channel Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    App Group UserDefaults                        │
│                    (group.to.talkie.app)                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  CHANNEL 1: DictationSharedStore (JSON blob)            │    │
│  │  Key: "dictation.sharedState"                           │    │
│  │                                                         │    │
│  │  ★ AUTHORITATIVE for recording lifecycle ★              │    │
│  │                                                         │    │
│  │  • phase (idle/arming/recording/stopping/...)           │    │
│  │  • command + commandAck (request/response protocol)     │    │
│  │  • lastResult / lastError (transcription output)        │    │
│  │  • epoch (reset generation counter)                     │    │
│  │  • capability (none/foregroundOnly/warm)                 │    │
│  │  • activeSessionId                                      │    │
│  │  • heartbeats (app + keyboard, separate keys)           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  CHANNEL 2: DictationStateMachine (individual keys)     │    │
│  │  Keys: "dictation.state", "dictation.stateTimestamp",   │    │
│  │        "dictation.resultText", "dictation.error"        │    │
│  │                                                         │    │
│  │  Legacy/diagnostic — shadows Channel 1                  │    │
│  │  Used by KeyboardActivationView (reconciled)            │    │
│  │  Knows about .ready state (Channel 1 doesn't)           │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  CHANNEL 3: KeyboardBridge (fast signal booleans)       │    │
│  │  Keys: keyboard.isRecording, keyboard.appReady,         │    │
│  │        keyboard.stopRequested, keyboard.startRequested,  │    │
│  │        keyboard.dictationResult, keyboard.audioLevel,    │    │
│  │        keyboard.modelWarm, keyboard.voiceEmojiMode, ...  │    │
│  │                                                         │    │
│  │  Fast signals for UI responsiveness                     │    │
│  │  Boolean flags avoid JSON encode/decode overhead        │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Why Three Channels?

| Channel | Strengths | Weaknesses |
|---------|-----------|------------|
| **SharedStore** (JSON blob) | Rich structured data, atomic command protocol, epoch validation | JSON encode/decode on every read, can't represent `.ready` state |
| **StateMachine** (individual keys) | Fast reads, `.ready` state, simple | No command protocol, no session tracking, diverges from SharedStore |
| **Bridge** (boolean flags) | Fastest reads, zero decode overhead | No structure, boolean flags can go stale, no epoch protection |

**In practice**: The SharedStore is the source of truth for the dictation lifecycle. The StateMachine provides the `.ready` state that SharedStore lacks. The Bridge provides fast UI signals (LED color, button state) without JSON overhead.

### Heartbeat Protocol

Both processes send periodic heartbeats so each can detect if the other is alive:

```
Keyboard Extension                          Talkie App
       │                                         │
       ├── updateKeyboardHeartbeat() ──→          │  (every 1.0s via heartbeatTimer)
       │                                         │
       │          ←── updateAppHeartbeat()  ──────┤  (every poll cycle)
       │                                         │
       │                                         │
  isAppHeartbeatFresh()                          │
  (< 6s → instant start OK)              isKeyboardHeartbeatFresh()
  (> 6s → need deep link)                (> 12s → drop ready mode)
```

---

## Dictation Lifecycle

### Two Recording Paths

The keyboard has two fundamentally different ways to start a recording:

```
                        recordTapped()
                             │
                    instantStartAvailable?
                     /                \
                   YES                 NO
                    │                   │
          ┌─────────┴─────────┐  ┌─────┴──────────────┐
          │   INSTANT START   │  │    DEEP LINK PATH   │
          │   (No app switch) │  │  (App switch req'd) │
          │                   │  │                      │
          │  App is in bg     │  │  Open talkie://      │
          │  w/ warm recorder │  │  dictate URL         │
          │  Keyboard sends   │  │                      │
          │  start command    │  │  App launches/       │
          │  via SharedStore  │  │  foregrounds         │
          │                   │  │                      │
          │  App detects via  │  │  HeadlessDictation   │
          │  ready-poll (1s)  │  │  .handleDictation    │
          │                   │  │  Request()           │
          │  Marks segment    │  │                      │
          │  in warm recorder │  │  Starts new recorder │
          │                   │  │  or warm recorder    │
          │  ← No user-       │  │                      │
          │    visible switch  │  │  Returns to keyboard │
          │                   │  │  (manual or auto)    │
          └─────────┬─────────┘  └─────┬──────────────┘
                    │                   │
                    └─────────┬─────────┘
                              │
                     Keyboard polls (0.2s)
                     for phase transitions
                              │
                    User taps stop / timeout
                              │
                     App stops recording
                     App transcribes audio
                     App publishes result
                              │
                     Keyboard detects done
                     Keyboard inserts text
                     Keyboard consumes result
```

### Instant Start (Warm Recorder)

The warm recorder is the key innovation for seamless dictation. Instead of creating a new audio file for each recording, the app keeps a continuously-running recorder in the background:

```
enterReadyMode()
    │
    ├── startWarmRecorder()
    │   └── AVAudioRecorder records to warm-<uuid>.m4a
    │       (continuously, even when user isn't dictating)
    │
    ├── bridge.setAppReady(true)
    ├── sharedStore.setCapability(.warm)
    └── startReadyPolling() (1.0s interval)

                    ... time passes ...

User taps record (keyboard)
    │
    beginWarmSegment(sessionId)
    │
    ├── warmSegmentStartTime = recorder.currentTime  ← mark START in timeline
    ├── isRecording = true
    └── (warm recorder keeps running)

                    ... user speaks ...

User taps stop (keyboard)
    │
    endWarmSegmentAndTranscribe()
    │
    ├── warmSegmentEndTime = recorder.currentTime    ← mark END in timeline
    ├── recorder.stop()
    │
    ├── AVAssetExportSession                         ← extract [start:end] segment
    │   └── Export to segment-<uuid>.m4a
    │
    ├── startWarmRecorder()                          ← immediately restart for next recording
    │
    └── TranscriptionService.transcribe(segmentURL)  ← transcribe extracted segment
```

**Result**: The user can do multiple dictations without ever switching apps. The warm recorder provides <100ms start latency vs 1-2 seconds for the deep link path.

### Command Protocol (V2)

Start and stop requests use a formal command/ack protocol with epoch validation:

```
KEYBOARD                              SHARED STORE                           APP
   │                                      │                                    │
   ├─ keyboardRequestStart(sessionId) ──→ │                                    │
   │   command: {                         │                                    │
   │     id: <uuid>,                      │                                    │
   │     kind: .start,                    │                                    │
   │     sessionId: <uuid>,               │                                    │
   │     epoch: 174                       │                                    │
   │   }                                  │                                    │
   │   phase: .arming                     │                                    │
   │                                      │                                    │
   │                                      │ ←── acceptStartCommandIfPresent() ─┤
   │                                      │     Validates:                     │
   │                                      │     • epoch matches                │
   │                                      │     • not already acked            │
   │                                      │     • < 10s old                    │
   │                                      │                                    │
   │                                      │ ←── appAcknowledgeCommand() ───────┤
   │                                      │     commandAck: {                  │
   │                                      │       id: <same uuid>,             │
   │                                      │       phase: .arming               │
   │                                      │     }                              │
   │                                      │                                    │
   │                                      │                        (recording) │
   │                                      │                                    │
   │                                      │ ←── appSetPhase(.recording) ───────┤
   │                                      │                                    │
   │ ←── poll detects .recording ─────────│                                    │
   │     (show recording UI)              │                                    │
   │                                      │                                    │
   ├─ keyboardRequestStop(sessionId) ──→  │                                    │
   │   command: { kind: .stop, ... }      │                                    │
   │   phase: .stopping                   │                                    │
   │                                      │                                    │
   │                                      │ ←── accepts stop ─────────────────┤
   │                                      │                                    │
   │                                      │ ←── appSetPhase(.transcribing) ───┤
   │                                      │                                    │
   │                                      │ ←── appSetResult(text, sessionId) ┤
   │                                      │     phase: .done                   │
   │                                      │     lastResult: {                  │
   │                                      │       text: "Hello world",         │
   │                                      │       sessionId: <uuid>            │
   │                                      │     }                              │
   │                                      │                                    │
   │ ←── poll detects .done ──────────────│                                    │
   │                                      │                                    │
   ├─ insertTextReliably("Hello world")   │                                    │
   │                                      │                                    │
   ├─ keyboardConsumeResult(sessionId) ─→ │                                    │
   │   lastResult: nil                    │                                    │
   │   phase: .idle                       │                                    │
   │                                      │                                    │
```

**Epoch mechanism**: Every `forceReset()` increments the epoch. Commands with stale epochs are rejected. This prevents zombie commands from surviving app crashes.

### Result Insertion & Retry

Text insertion is the most failure-prone part of the system. `textDocumentProxy.insertText()` can silently fail when the host app's text field is disconnected (common during app switches).

```
checkForDictationResult()
    │
    ├── Read sharedStore.lastResult
    │
    ├── insertTextReliably(text)
    │   └── textDocumentProxy.insertText(text)
    │
    ├── Verify: documentContextBeforeInput != nil ?
    │       │
    │       ├── nil (proxy disconnected)
    │       │   │
    │       │   ├── retry < 3?  → return WITHOUT consuming
    │       │   │                 (polling continues, will retry in 0.2s)
    │       │   │
    │       │   └── retry >= 3? → consume anyway (avoid stall)
    │       │                     publishKeyboardDebug("insertFailed")
    │       │
    │       └── non-nil (proxy connected)
    │           └── publishKeyboardDebug("insertOK")
    │
    └── keyboardConsumeResult()  ← only after success or max retries
```

---

## State Machines

### DictationState (StateMachine)

```
                                    ┌───────────┐
                                    │   IDLE    │ ← initial state
                                    └─────┬─────┘
                                          │
                          ┌───────────────┼───────────────┐
                          │               │               │
                          ▼               ▼               ▼
                   ┌──────────────┐ ┌──────────┐  ┌──────────┐
                   │WAITING_FOR_APP│ │ RECORDING│  │  READY   │
                   └──────┬───────┘ └────┬─────┘  └────┬─────┘
                          │              │              │
                          ▼              ▼              │
                   ┌──────────┐   ┌──────────┐         │
                   │ RECORDING│   │ STOPPING │         │
                   └────┬─────┘   └────┬─────┘         │
                        │              │              │
                        ▼              ▼              │
                   ┌──────────┐  ┌──────────────┐     │
                   │TRANSCRIBING│ │ TRANSCRIBING │     │
                   └────┬──────┘ └──────┬───────┘     │
                        │               │              │
                        ▼               ▼              │
                   ┌──────────┐   ┌──────────┐        │
                   │   DONE   │   │   DONE   │        │
                   └────┬─────┘   └────┬─────┘        │
                        │              │              │
                        └──────┬───────┘              │
                               │                      │
                               ▼                      │
                          ┌─────────┐                 │
                          │  IDLE   │ ────────────────┘
                          └─────────┘    (app enters ready mode)
```

### DictationSharedState.Phase

```
    ┌────────┐
    │  idle  │ ← keyboard consumed result, or initial state
    └───┬────┘
        │
        ▼
    ┌────────┐
    │ arming │ ← keyboard sent start command, app preparing
    └───┬────┘
        │
        ▼
    ┌───────────┐
    │ recording │ ← audio capture active
    └───┬───────┘
        │
        ▼
    ┌──────────┐
    │ stopping │ ← stop command sent, wrapping up
    └───┬──────┘
        │
        ▼
    ┌──────────────┐
    │ transcribing │ ← speech-to-text in progress
    └───┬──────────┘
        │
        ├────────────────┐
        ▼                ▼
    ┌────────┐      ┌────────┐
    │  done  │      │ error  │
    └───┬────┘      └───┬────┘
        │               │
        └───────┬───────┘
                ▼
           ┌─────────┐
           │  idle   │
           └─────────┘
```

### Phase ↔ State Reconciliation

The `KeyboardActivationView` (in the Talkie app) reconciles both sources:

```swift
func reconcileState(sharedPhase: Phase, machineState: DictationState) -> DictationState {
    switch sharedPhase {
    case .recording:    return .recording      // SharedStore wins
    case .stopping:     return .stopping       // SharedStore wins
    case .transcribing: return .transcribing   // SharedStore wins
    case .done:         return .done           // SharedStore wins
    case .error:        return .idle           // error shown separately
    case .arming:       return .waitingForApp  // SharedStore wins
    case .idle:         return machineState    // StateMachine wins (.ready)
    }
}
```

**Rule**: SharedStore is authoritative for active phases. StateMachine is authoritative for idle/ready distinction.

---

## Timer Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   KeyboardViewController Timers                 │
│                                                                 │
│  heartbeatTimer (1.0s)                                          │
│  ├── Started: viewWillAppear                                    │
│  ├── Stopped: viewWillDisappear                                 │
│  └── Action: sharedStore.updateKeyboardHeartbeat()              │
│                                                                 │
│  pollTimer (0.2s)                                               │
│  ├── Started: recordTapped(), checkRecordingState(),            │
│  │            handleStateSignal()                               │
│  ├── Stopped: result consumed, timeout, viewWillDisappear       │
│  └── Action: pollForUpdates() → check phase, update UI,        │
│              detect results, handle timeouts                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                   HeadlessDictationService Timers                │
│                                                                 │
│  readyPollTimer (1.0s)                                          │
│  ├── Started: enterReadyMode() (app in bg with warm recorder)   │
│  ├── Stopped: recording starts, deactivation                    │
│  └── Action: checkForStartRequest() — watch for keyboard cmds   │
│                                                                 │
│  stopPollTimer (0.5s)                                           │
│  ├── Started: recording begins                                  │
│  ├── Stopped: stop detected, transcription starts               │
│  └── Action: checkForStopRequest() — watch for keyboard stop    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Timeout Safety Nets

| Condition | Timeout | Recovery |
|-----------|---------|----------|
| App launch (arming) | 10s | Force reset, show "Timeout - try again" |
| Recording duration | 60s | Force reset if bridge confirms no activity |
| Stop request | 15s | Force reset, show "Timeout - try again" |
| Stale state on reload | 30s | Force reset on `loadState()` |
| Keyboard heartbeat stale | 12s | App drops ready mode |
| App heartbeat stale | 6s | Keyboard falls back to deep link path |

---

## Edge Cases & Recovery

### Extension Killed Mid-Recording

```
Recording in progress → iOS kills keyboard extension
    │
    ├── Keyboard timers stop (heartbeat goes stale)
    │
    ├── App detects stale keyboard heartbeat (> 12s)
    │   └── Drops ready mode, but recording may continue
    │
    ├── User taps text field again → extension reloads
    │
    └── viewDidLoad → loadState() → checkRecordingState()
        ├── Phase is .recording → showRecordingUI(), startPolling()
        ├── Phase is .done → checkForDictationResult() → insert text
        └── Phase is .idle → normal state
```

### App Backgrounded During Recording

```
Recording via warm recorder → user switches away from Talkie
    │
    ├── UIApplication.willResignActive notification
    │   └── HeadlessDictation.handleAppWillResignActive()
    │       └── Recording continues (audio session stays active)
    │       └── Background task started for transcription
    │
    ├── Stop command arrives from keyboard
    │   └── stopPollTimer fires, processes stop
    │   └── Transcription happens in background
    │   └── Result published to SharedStore
    │
    └── Keyboard detects result via polling
        └── Text inserted via textDocumentProxy
```

### Dual State Channel Divergence

```
SharedStore says .recording    but    StateMachine says .idle
    │                                        │
    └── This happens when:                   │
        • App wrote to SharedStore            │
        • But StateMachine write failed       │
        • Or timing mismatch between writes   │
                                              │
    Fix: reconcileState() prefers SharedStore │
         for active phases                    │
```

---

## File Reference

### Keyboard Extension (TalkieKeys target)

| File | Lines | Responsibility |
|------|-------|----------------|
| `KeyboardViewController.swift` | ~4300 | Main lifecycle, state polling, UI coordination, dictation orchestration |
| `CompactKeyboardView.swift` | ~950 | Full QWERTY keyboard, long-press accents, dictation state on spacebar |
| `MinimalKeyboardView.swift` | ~500 | Single-row layout, recording animations, success flash |
| `VoiceEmojiOverlay.swift` | ~400 | Voice → emoji search overlay, particle effects |

### Shared Framework (TalkieMobileKit)

| File | Lines | Responsibility |
|------|-------|----------------|
| `DictationSharedState.swift` | ~160 | Data model: Phase, Command, CommandAck, ResultPayload, ErrorPayload |
| `DictationSharedStore.swift` | ~330 | JSON encode/decode of shared state, heartbeat management, command protocol |
| `DictationStateMachine.swift` | ~310 | Legacy state enum with validated transitions, UserDefaults persistence |
| `KeyboardBridge.swift` | ~550 | Fast boolean/string signals via individual UserDefaults keys |
| `KeyboardMode.swift` | ~300 | Mode definitions, slot configs, keyboard config, mode cycling |

### Main App (Talkie iOS target)

| File | Lines | Responsibility |
|------|-------|----------------|
| `HeadlessDictationService.swift` | ~1550 | Recording lifecycle, warm recorder, transcription, result publishing |
| `KeyboardActivationView.swift` | ~800 | SwiftUI view shown when user opens Talkie via deep link during dictation |
| `DeepLinkManager.swift` | ~300 | URL scheme handler for `talkie://dictate` and x-callback-url |

---

## Glossary

| Term | Meaning |
|------|---------|
| **Warm recorder** | A continuously-running AVAudioRecorder that enables instant-start dictation without app switch |
| **Instant start** | Recording begins immediately via background warm recorder, no deep link needed |
| **Deep link path** | Fallback: keyboard opens `talkie://dictate` to bring the app to foreground |
| **Phase** | Current step in the dictation lifecycle (DictationSharedState.Phase) |
| **Epoch** | Generation counter in SharedStore; bumped on force reset to invalidate stale commands |
| **Command protocol** | Formal request/ack system where keyboard sends commands and app acknowledges them |
| **Segment** | A time range within the warm recorder's continuous audio file, extracted for transcription |
| **Text proxy** | `textDocumentProxy` — iOS-provided interface for keyboard extensions to insert text into the host app's text field |
| **Heartbeat** | Periodic timestamp written to shared storage so each process can detect if the other is alive |
| **Ready mode** | App state where warm recorder is running and the app is listening for start commands |
| **Bridge** | `KeyboardBridge` — fast boolean/string signal layer for UI-critical state |
