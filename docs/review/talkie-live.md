# TalkieLive

`macOS/TalkieLive/` - Background helper for live dictation

**Total LOC**: ~28,000 lines across 40+ files

Runs as login item, handles always-on dictation with hotkey activation.

---

## Critical Hotspots

| File | Lines | Risk |
|------|-------|------|
| `Views/Settings/SettingsView.swift` | 4,274 | 🔴 CRITICAL |
| `Debug/DebugKit.swift` | 4,099 | 🟡 MEDIUM (debug) |
| `Views/OnboardingView.swift` | 2,263 | 🟠 HIGH |
| `Views/HomeView.swift` | 1,846 | 🟠 HIGH |
| `App/LiveController.swift` | 1,195 | 🟠 HIGH |
| `App/AppDelegate.swift` | 960 | 🟡 MEDIUM |

### SettingsView.swift (4,274 lines) - NEEDS SPLIT

**Current State**: All settings UI in one massive view.

**Recommended Split**:
```
Views/Settings/
├── SettingsView.swift          # Navigation (~300 lines)
├── HotkeySettingsTab.swift     # Hotkey recording (~500 lines)
├── AudioSettingsTab.swift      # Device selection (~400 lines)
├── AppearanceSettingsTab.swift # Theme, overlay (~400 lines)
├── PermissionsSettingsTab.swift # Permission requests (~500 lines)
├── AdvancedSettingsTab.swift   # Debug, advanced (~400 lines)
└── SettingsComponents.swift    # Shared components (~400 lines)
```

---

## Architecture Overview

TalkieLive is a background helper app that provides:
- Global hotkey listening (toggle or push-to-talk)
- Audio capture via AVAudioEngine
- XPC communication to TalkieEngine for transcription
- XPC service for Talkie main app to observe state
- Floating UI overlays (pill, recording indicator)

**Flow:** Hotkey → Context capture → Audio recording → Transcription → Paste/Queue

---

## App

### AppDelegate.swift
Application lifecycle, login item setup.

**Discussion:**
- Registers as login item for auto-start
- Initializes hotkey listeners
- Manages menu bar icon
- Sets up XPC services

---

### BootSequence.swift
Startup sequence.

**Discussion:**
- Ordered initialization of services
- Engine connection with retry
- Hotkey registration
- UI setup (floating pill, overlays)

---

### LiveController.swift (~1135 lines)
Main orchestration - coordinates audio, transcription, state.

**Discussion:**
- **State Machine:** Uses `LiveStateMachine` for validated state transitions
  - States: `idle`, `listening`, `transcribing`, `routing`
  - Events: `startRecording`, `stopRecording`, `beginRouting`, `complete`, `error`, `cancel`, `forceReset`
- **Recording Modes:**
  - Toggle mode: press to start, press to stop
  - PTT mode: hold to record, release to stop
- **Capture Intents (mid-recording modifiers):**
  - Shift: Route to interstitial editor
  - Shift+A: Save as memo
  - Default: Paste to cursor
- **Context Capture:** Captures active app/window at recording start for metadata
- **Watchdog Timer:** Detects stuck states (transcribing >120s, routing >30s) and auto-recovers
- **XPC Broadcast:** State changes broadcast to Talkie via `TalkieLiveXPCService`
- **UI Updates:** Updates FloatingPillController and RecordingOverlayController on state changes

**Key Methods:**
- `toggleListening(interstitial:)` - Main entry point for toggle mode
- `pttStart()/pttStop()` - Push-to-talk handlers
- `cancelListening()` - Cancel during recording (preserves audio)
- `pushToQueue()` - Save for later when stuck
- `forceReset()` - Emergency state reset

**Performance Tracing:**
- Uses `LiveTranscriptionTrace` to track hotkey→paste latency
- Logs breakdown: pre-processing, engine, post-processing

---

## Services

### EngineClient.swift (~880 lines)
XPC client for TalkieEngine communication.

**Discussion:**
- **Singleton:** `EngineClient.shared`
- **Connection States:** `disconnected`, `connecting`, `connected`, `connectedWrongBuild`, `error`
- **Environment-Aware:** Connects to production/staging/dev engine based on `TalkieEnvironment`
- **Auto-Retry:** Transcription waits for busy engine (up to 60s for model loading)
- **Model Management:** Preload, unload, download models via XPC
- **Status Monitoring:** Fetches `EngineStatus` (loaded model, memory usage, uptime)
- **Signpost Profiling:** XPC round-trip profiling via os_signpost

**Key APIs:**
- `connect()` - Connect using environment-specific service name
- `ensureConnected()` - Connect with retries, launches engine if needed
- `transcribe(audioPath:modelId:priority:)` - Main transcription entry point
- `preloadModel(_:)` / `unloadModel()` - Model lifecycle
- `downloadModel(_:)` - Download models from HuggingFace

**Error Handling:**
- `EngineClientError`: `.notConnected`, `.transcriptionFailed`, `.preloadFailed`, `.downloadFailed`, `.emptyResponse`

---

### AudioCapture.swift (~410 lines)
Microphone capture using AVAudioEngine.

**Discussion:**
- **MicrophoneCapture Class:** Implements `LiveAudioCapture` protocol
- **Device Selection:** Supports specific microphone via `AudioDeviceManager`
- **Format Handling:** Creates audio file lazily to match actual buffer format
- **Output Format:** M4A (AAC) for compact size
- **Silence Detection:** `AudioLevelMonitor` tracks RMS level, alerts after 2s silence

**Key Features:**
- Handles audio engine configuration changes mid-recording
- Validates device exists before capture (handles Bluetooth disconnects)
- Minimum file size check (>1000 bytes) to reject empty recordings
- Buffer count logging for debugging short recordings

**AudioLevelMonitor:**
- Singleton for UI visualization
- Publishes `level` (0-1), `isSilent`, `selectedMicName`
- Plays alert sound when recording appears silent

---

### TalkieLiveXPCService.swift
XPC interface for Talkie main app.

**Discussion:**
- Implements `TalkieLiveXPCServiceProtocol` from TalkieKit
- Allows Talkie to:
  - Observe live state changes
  - Get current state/elapsed time
  - Trigger recording start/stop
  - Check permissions
- Uses observer pattern for real-time IPC

---

## UI Components

### FloatingPillController
Desktop overlay pill showing live state.

### RecordingOverlayController
Top-of-screen recording indicator bar.

---

## TODO

- [ ] Review BootSequence for initialization order issues
- [ ] Verify XPC reconnection handles all edge cases
- [ ] Consider reducing LiveController size (1135 lines)

## Done

- [x] Complete documentation of core components
- [x] LiveController state machine documented
- [x] EngineClient connection flow documented
- [x] AudioCapture implementation documented
