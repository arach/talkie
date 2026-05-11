# TalkieKeys Recording Flow

Technical documentation of the keyboard extension recording architecture.

## Architecture Overview

Three-tier communication via App Group (`group.com.example.talkie`):

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   TalkieKeys    │     │  KeyboardBridge │     │    Main App     │
│   (Extension)   │     │  (App Group)    │     │ (Background)    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
    UIInputViewController   UserDefaults          HeadlessDictationService
```

## Key Components

| Component | File | Purpose |
|-----------|------|---------|
| KeyboardViewController | `TalkieKeys/KeyboardViewController.swift` | Extension UI, tap handling, polling |
| KeyboardBridge | `TalkieKit/Keyboard/KeyboardBridge.swift` | App Group read/write |
| DictationStateMachine | `TalkieKit/Keyboard/DictationStateMachine.swift` | State management |
| HeadlessDictationService | `Talkie iOS/Services/HeadlessDictationService.swift` | Recording & transcription |

## State Machine

```
idle → waitingForApp → recording → stopping → transcribing → done → idle
  │                                                              │
  └──────────────── (if app ready, instant start) ──────────────►┘
```

### States

| State | Description |
|-------|-------------|
| `idle` | No activity, ready for new request |
| `ready` | App in background, listening for instant start |
| `waitingForApp` | Keyboard requested, waiting for app to respond |
| `recording` | Audio capture in progress |
| `stopping` | Stop requested, waiting for app to stop |
| `transcribing` | Audio captured, transcription in progress |
| `done` | Result ready for keyboard to consume |

## Recording Sequence

### 1. User Taps Mic (KeyboardViewController:1280)

```swift
func recordTapped() {
    // Check current state
    if state == .recording {
        requestStop()
    } else {
        requestStart()
    }
}
```

### 2. Two Start Modes

**Instant Start** (fast, no app switch):
- Condition: `state == .ready && bridge.isAppReady()`
- App already listening in background (30s TTL)
- Keyboard sets `startRequested` flag
- App polls (0.2s), sees flag, starts recording

**Deep Link** (slower, app switch):
- Condition: App not ready
- Keyboard opens `talkie://dictate` URL
- App launches/foregrounds
- DeepLinkManager handles, starts recording

### 3. App Starts Recording (HeadlessDictationService)

```swift
func startRecording() {
    // Configure audio session
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playAndRecord, mode: .default,
        options: [.defaultToSpeaker, .allowBluetoothHFP])

    // Create recorder (AAC, 44100 Hz, mono, 128 kbps)
    audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
    audioRecorder.record()

    // Update state
    stateMachine.appStartedRecording()
    bridge.setRecordingInProgress(true)
}
```

### 4. Keyboard Shows Recording State

Polling loop (100ms) at KeyboardViewController:1913:
- Reads state from DictationStateMachine
- Updates UI: red LED, "RECORDING" status, STOP button
- Timeout protection: 60s max recording

### 5. User Taps Stop

```swift
stateMachine.keyboardRequestedStop()  // State → .stopping
bridge.requestStopRecording()         // Set flag for app
```

### 6. App Stops & Transcribes

```swift
func stopRecording() {
    audioRecorder.stop()
    stateMachine.appStartedTranscribing()

    TranscriptionService.shared.transcribe(audioURL: fileURL) { result in
        switch result {
        case .success(let text):
            stateMachine.appFinishedWithResult(text)
        case .failure(let error):
            stateMachine.appFinishedWithError(error.localizedDescription)
        }
    }
}
```

### 7. Keyboard Consumes Result (KeyboardViewController:1424)

```swift
func checkForDictationResult() {
    guard let text = stateMachine.resultText else { return }

    // Smart spacing
    let textToInsert = addSpacingIfNeeded(text)

    // Insert via text proxy
    textDocumentProxy.insertText(textToInsert)

    // Cleanup
    stateMachine.keyboardConsumedResult()
    bridge.clearDictationResult()
}
```

## Bridge Keys (UserDefaults)

| Key | Type | Purpose |
|-----|------|---------|
| `keyboard.pendingDictation` | Bool | Legacy: dictation requested |
| `keyboard.dictationResult` | Data | JSON-encoded DictationResult |
| `keyboard.isRecording` | Bool | Recording in progress |
| `keyboard.stopRequested` | Bool | Keyboard wants to stop |
| `keyboard.appReady` | Bool | App listening in background |
| `keyboard.appReadyTimestamp` | Double | TTL check (30s) |
| `keyboard.startRequested` | Bool | Keyboard wants to start |

## Timeouts & Recovery

| Scenario | Timeout | Action |
|----------|---------|--------|
| Recording too long | 60s | Force reset |
| Stop not acknowledged | 15s | Force reset |
| App failure cooldown | 8s | Block retry |
| Ready state TTL | 30s | Must refresh |

## Performance

- **Instant start**: No app switch, immediate
- **Deep link start**: 500ms-1s for app activation
- **Polling overhead**: Minimal (100-200ms intervals)
- **Communication**: Local App Group only, no network

## Warm Recorder Optimization

When keyboard active + app in background:

1. `enterReadyMode()` → `startWarmRecorder()` keeps mic reserved
2. On tap → `beginWarmSegment()` (marks boundary, no new session)
3. On stop → `endWarmSegmentAndTranscribe()`
4. Result: Faster response, no audio session setup overhead
