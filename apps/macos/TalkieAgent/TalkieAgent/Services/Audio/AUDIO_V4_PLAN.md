# Audio Capture v4: Back to Basics

## Problem Analysis

### What's Failing in v3

The logs show a clear pattern:
1. **First recording works** - Engine initializes, 33 buffers captured, transcription succeeds
2. **Second recording fails** - "engine reused" → no buffers after 365ms → recovery fails
3. **Recovery creates new engine** - Also fails, even with fresh AVAudioEngine instance
4. **HAL errors throughout** - `throwing -10877` and `1852797029 (nope)` indicate corrupted HAL state

### Root Cause

V3's "persistent engine" architecture is fundamentally flawed:

```swift
// V3 approach - BROKEN
engine.inputNode.removeTap(onBus: 0)
engine.stop()
// DON'T nil engine - keep it for next recording  <-- THIS IS THE PROBLEM
```

After `stop()`, AVAudioEngine's internal AudioUnit state becomes corrupted. The engine object exists but the HAL connection is in a bad state. Trying to `start()` again produces no buffers.

### Why v1.9.0 Worked

V1.9.0 used a single engine instance (`private let engine = AVAudioEngine()`), but critically:
- No complex recovery logic
- No engine recreation mid-session
- Simple: install tap → start → remove tap → stop
- If it failed, it failed cleanly

The paradox: v1.9.0's single engine worked across multiple recordings, but v3's "optimized" version doesn't. The difference is all the added complexity:
- Recovery loops that corrupt state further
- Engine nullification and recreation
- First-buffer timeout checks creating race conditions

## Architecture: v4 "Session-Based Capture"

### Core Principle

**One fresh engine per recording session. No reuse. No recovery. Fail fast.**

```
┌─────────────────────────────────────────────────────────────┐
│                    Recording Session                        │
├─────────────────────────────────────────────────────────────┤
│  1. Create AVAudioEngine                                    │
│  2. Configure device (UID-based)                            │
│  3. Install tap                                             │
│  4. Start engine                                            │
│  5. Capture buffers → Write to file                         │
│  6. Stop engine                                             │
│  7. Remove tap                                              │
│  8. Destroy engine (set to nil)                             │
│  9. Return result                                           │
└─────────────────────────────────────────────────────────────┘
```

### Key Differences from v3

| Aspect | v3 (Broken) | v4 (Proposed) |
|--------|-------------|---------------|
| Engine lifecycle | Persistent, reused | Fresh per recording |
| Recovery logic | 3 retry attempts | None - fail fast |
| First buffer check | Async timeout + recovery | None |
| Warmup | Separate, engine persists | Inline, engine discarded |
| Device config | Every recording | Every recording (same) |
| Complexity | High | Low |

### Why Fresh Engine Per Recording?

1. **HAL State Reset**: Creating a new engine forces fresh HAL initialization
2. **No Corrupted State**: Previous recording's state can't affect next recording
3. **Simpler Code**: No recovery logic, no state machine, no timeouts
4. **Predictable Behavior**: Either it works or it fails - no partial states

### Warmup Strategy

**Option A: No Warmup (Recommended)**
- First recording pays ~300-500ms HAL init cost
- Subsequent recordings are fast (engine creation is cheap after first HAL init)
- System caches HAL state, so new engines start quickly

**Option B: Background Pre-warm**
- Create and immediately destroy an engine on app launch
- Triggers HAL caching without keeping state
- Adds complexity for minimal gain

## Implementation Plan

### Phase 1: AudioCaptureServiceV4

Create a new, clean implementation:

```swift
/// Audio capture v4: Session-based, no reuse, no recovery
final class AudioCaptureServiceV4: LiveAudioCapture {

    // MARK: - State

    private var engine: AVAudioEngine?
    private var isRecording = false
    private let fileWriter = AudioFileWriter()

    // MARK: - Recording

    func startCapture(onChunk: @escaping (String) -> Void) {
        guard !isRecording else { return }

        // 1. Create fresh engine
        let engine = AVAudioEngine()
        self.engine = engine

        // 2. Configure device (UID-based)
        configureDevice(engine: engine)

        // 3. Set up file writer
        let fileURL = createTempFileURL()

        // 4. Install tap
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        // 5. Start engine
        do {
            try engine.start()
            isRecording = true
        } catch {
            cleanup()
            onCaptureError?("Failed to start: \(error)")
        }
    }

    func stopCapture() {
        guard isRecording, let engine = engine else { return }

        // 1. Stop recording
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // 2. Finalize file
        let result = fileWriter.finalize()

        // 3. CRITICAL: Destroy engine
        self.engine = nil

        // 4. Return result
        if let result = result, result.size > 1000 {
            onChunk?(result.url.path)
        }
    }
}
```

### Phase 2: UID-Based Device Selection

Keep v3's UID-based device resolution (this part works):

```swift
private func configureDevice(engine: AVAudioEngine) {
    // Read from shared settings
    let mode = loadMicrophoneMode()

    switch mode {
    case .systemDefault:
        return  // AVAudioEngine uses system default automatically

    case .fixedUID:
        guard let uid = loadSelectedMicrophoneUID(),
              let deviceID = findDeviceByUID(uid) else {
            log.warning("Configured device unavailable, using default")
            return
        }

        // Set device on audio unit
        if let audioUnit = engine.inputNode.audioUnit {
            var mutableID = deviceID
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
        }
    }
}
```

### Phase 3: Remove Complexity

Delete from current implementation:
- [ ] Recovery logic (`handleRecovery`, `retryCount`, `forceSystemDefault`)
- [ ] First buffer timeout (`scheduleFirstBufferCheck`, `handleNoBuffers`)
- [ ] Engine warmup as separate operation
- [ ] `AudioCaptureState` enum (just use `isRecording` bool)
- [x] `DeviceChangeObserver` (deleted - not needed with fresh engines)
- [ ] Config observer (not needed - we don't try to recover)

### Phase 4: File Writing

Keep the existing `AudioFileWriter` and `AudioArchiver` - they work fine.

Output format: PCM WAV (as currently done in v3)
- Simpler than AAC
- No encoder flush issues
- Transcription engines prefer raw audio

## Migration Plan

1. **Create `AudioCaptureServiceV4.swift`** - New clean implementation
2. **Keep `AudioCaptureService.swift`** - For reference/fallback
3. **Update `BootSequence.swift`** - Use v4 for audio capture
4. **Test thoroughly** - Multiple recordings, device changes, etc.
5. **Remove old code** - Once v4 is proven stable

## Success Criteria

1. **Reliability**: 100 consecutive recordings without failure
2. **Latency**: First buffer within 500ms of start
3. **Device switching**: Works after Bluetooth connect/disconnect
4. **No recovery needed**: Either works or fails cleanly

## Files to Modify

```
apps/macos/TalkieAgent/TalkieAgent/Services/Audio/
├── AudioCaptureServiceV4.swift  [NEW]
├── AudioCaptureService.swift    [KEEP for reference]
├── AudioCapture.swift           [KEEP - MicrophoneCapture still used?]
├── Core/
│   └── AudioCaptureConfiguration.swift  [KEEP]
└── ... (other files unchanged)
```

## Testing Checklist

- [ ] Single recording works
- [ ] Multiple back-to-back recordings work
- [ ] Recording after app idle (5+ minutes)
- [ ] Recording with USB mic
- [ ] Recording with Bluetooth mic
- [ ] Recording after device change
- [ ] Recording with system default
- [ ] Short recording (<1s)
- [ ] Long recording (>30s)
- [ ] Recording interrupted by stop
