# TalkieKit Package

`macOS/TalkieKit/` - Shared components for Talkie apps (19 files)

---

## Logging

### TalkieLogger.swift (~354 lines)
Unified logging system with multi-output routing.

**Discussion:**
- Excellent architecture diagram in comments
- Routes to: Console (DEBUG), os.Logger (Instruments), File (persistent)
- Categories: system, audio, transcription, database, xpc, sync, ui, workflow
- Levels: debug, info, warning, error, fault
- `critical: true` flag for crash-safe startup logging (uses NSLog)
- `Log()` struct for clean per-file usage

**Observations:**
- Well-documented with clear usage examples
- Thread-safe via DispatchQueue
- `.public` privacy for os.Logger visibility in Console.app

---

### TalkieLogFileWriter.swift
File-based log persistence.

**Discussion:**
- **Two-tier durability:**
  - `.critical` - Immediate flush, crash-safe (for transcription errors)
  - `.bestEffort` - Buffered writes, periodic flush (routine logging)
- **LogSource:** Talkie, TalkieLive, TalkieEngine
- **LogEventType:** SYNC, RECORD, WHISPER, WORKFLOW, ERROR, SYSTEM
- Writes to `~/Library/Application Support/{app}/logs/`
- Daily log rotation with date-based filenames
- Buffer: max 50 entries, flush every 0.5s
- Thread-safe via dedicated DispatchQueue

---

## UI

### DesignSystem.swift (~114 lines)
Shared design tokens.

**Discussion:**
- Spacing: xxs (2) → xxl (32)
- CornerRadius: xs (4) → xl (24)
- SemanticColor: success, warning, error, info, pin, processing
- TalkieTheme with midnight palette
- Backwards-compatible foreground aliases

---

### LivePill.swift
Live status indicator pill.

**Discussion:**
- Visual indicator showing current live recording state
- Animated transitions between states
- Color-coded: idle (gray), listening (blue), transcribing (orange), routing (green)
- Compact display for menu bar or floating UI

---

### LiveState.swift
Live state definitions.

**Discussion:**
- Enum: `.idle`, `.listening`, `.transcribing`, `.routing`
- Display properties: `displayName`, `icon`, `color`
- Equatable and Hashable conformance
- Used by LiveStateMachine for state tracking

---

### LiveStateMachine.swift
State machine for live dictation.

**Discussion:**
- **Pattern:** @MainActor ObservableObject
- **Events:** `startRecording`, `stopRecording`, `beginTranscription`, `beginRouting`, `complete`, `cancel`, `error`, `forceReset`
- **Transition validation:** Only allows valid state transitions
- Callbacks: `onStateChange`, `onInvalidTransition`
- `forceSetState(_:)` for initialization/recovery
- `canTransition(_:)` to check without executing

**State Transition Rules:**
- idle → listening (startRecording)
- listening → transcribing (stopRecording, cancel)
- transcribing → routing (beginRouting)
- transcribing → idle (complete, cancel, error)
- routing → idle (complete, error)
- Any state → idle (forceReset)

---

### AudioLevelMonitor.swift
Audio level visualization.

**Discussion:**
- Singleton for cross-component access
- Publishes RMS level (0-1) for visualization
- Silence detection with configurable threshold
- Selected microphone name tracking
- Used by recording indicators and audio bars

---

## XPC

### XPCProtocols.swift (~150 lines)
XPC protocol definitions (single source of truth).

**Discussion:**
- Environment-aware service names via TalkieEnvironment
- TalkieLiveXPCServiceProtocol: state, recording, permissions
- TalkieLiveStateObserverProtocol: callbacks for state, dictations, audio level
- TalkieEngineProtocol: transcription, model management, downloads
- TranscriptionPriority enum with TaskPriority mapping

**Observations:**
- Clean @objc protocols for XPC
- Good priority system for scheduling

---

### TalkieEnvironment.swift
Environment configuration (prod/staging/dev).

**Discussion:**
- **Single source of truth** for all environment-specific config
- **Philosophy:** Dev and prod run simultaneously on same Mac
- Detects environment from bundle ID suffix (.dev, .staging, or none)

**Isolated Per-Environment:**
- Bundle IDs: `jdi.talkie.live` vs `jdi.talkie.live.dev`
- XPC Services: `jdi.talkie.live.xpc` vs `jdi.talkie.live.xpc.dev`
- Settings Storage: `com.jdi.talkie.shared` vs `.shared.dev`
- Database Paths: `~/...Talkie` vs `~/...Talkie.dev`
- Hotkey Signatures: TLIV vs DLIV
- URL Schemes: `talkie://` vs `talkie-dev://`

**Rule:** Never hardcode environment-specific values elsewhere.

---

### SharedSettings.swift
Settings shared across apps.

**Discussion:**
- User defaults shared between Talkie, TalkieLive, TalkieEngine
- Uses app group for cross-process access
- Environment-aware suite name
- Common settings: selected model, hotkey, audio device

---

## Audio Player

### AudioPlaybackManager.swift
Audio playback control.

**Discussion:**
- Manages AVAudioPlayer instances
- Play/pause/seek functionality
- Duration and current time tracking
- Handles audio session configuration

---

### AudioPlayerCard.swift
Player UI card.

**Discussion:**
- SwiftUI component for inline audio playback
- Play/pause button, progress bar, duration display
- Integrates with AudioPlaybackManager
- Theme-aware styling

---

### SeekableWaveform.swift
Waveform with seek.

**Discussion:**
- Visual waveform representation of audio
- Tap/drag to seek to position
- Playhead indicator
- Pre-computed waveform data for performance

---

## Console

### ConsoleView.swift
Log viewer UI.

**Discussion:**
- SwiftUI view for viewing app logs
- Filters by log level and category
- Search functionality
- Auto-scroll to latest entries
- Reads from TalkieLogFileWriter output

---

## TODO

- [ ] Review LiveStateMachine for edge cases
- [ ] Check SharedSettings sync mechanism

## Done

- [x] Initial review pass complete
- [x] Logging system is excellent
- [x] XPC protocols are well-defined
- [x] Design tokens are clean
- [x] TalkieLogFileWriter documented
- [x] LiveStateMachine documented
- [x] TalkieEnvironment documented
- [x] All UI components documented
