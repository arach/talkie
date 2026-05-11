# Services Module

`apps/macos/Talkie/Services/` - Core business logic (40 files)

---

## Structure

```
Services/
├── LLM/
│   ├── LLMProvider.swift       - Provider protocol
│   ├── AnthropicProvider.swift
│   ├── OpenAIProvider.swift
│   ├── GeminiService.swift
│   ├── GroqProvider.swift
│   └── ServerProvider.swift
├── Audio/
│   ├── AudioDeviceManager.swift
│   ├── AudioPlaybackManager.swift
│   └── SoundManager.swift
├── Migrations/
│   ├── MigrationRunner.swift
│   └── Migrations.swift
└── (30+ more files)
```

---

## Large Files (Need Attention)

| File | Lines | Notes |
|------|-------|-------|
| SettingsManager.swift | 1732 | **Very large** - god object? |
| DesignSystem.swift | 1067 | Large but may be intentional |
| ServiceManager.swift | 1038 | Service orchestration |

---

## Security

### KeychainManager.swift (~168 lines)
Secure storage for API keys.

**Discussion:**
- Uses kSecAttrAccessibleAfterFirstUnlock (correct security level)
- Proper update-or-add pattern
- Migration support from Core Data
- Enum-based key names (type-safe)

**Observations:**
- Clean implementation
- No logging of sensitive data
- Proper error handling

---

## LLM

### LLMProvider.swift
Protocol-based LLM architecture.

**Discussion:**
- Config loaded from LLMConfig.json
- Protocol: id, name, models, isAvailable, generate, streamGenerate
- Supports streaming via AsyncThrowingStream
- Good abstraction layer

---

### Provider Implementations

- **AnthropicProvider.swift** - Claude API
- **OpenAIProvider.swift** - GPT/Whisper API
- **GeminiService.swift** - Google AI
- **GroqProvider.swift** - Groq API
- **ServerProvider.swift** - Gateway-backed server inference

**Discussion:**
- Consistent interface across all providers
- API keys retrieved from KeychainManager
- Streaming support via AsyncThrowingStream
- Error handling with specific error types
- Model lists from LLMConfig.json

---

## Routing

### Router.swift
Central URL routing infrastructure.

**Discussion:**
- Clean route-based architecture
- Route metadata: path, description, isInternal
- Scopes: app (external), live (TalkieAgent sync), system (navigation)
- RouteGroup protocol for organized definitions
- Self-documenting (printAllRoutes())

---

### Route Groups

- **AppRoutes.swift** - External app shortcuts
- **LiveRoutes.swift** - TalkieAgent sync
- **SystemRoutes.swift** - Navigation, lifecycle

---

## Core Services

### SettingsManager.swift (1732 lines) 🔴 HIGH PRIORITY

App preferences - **needs refactoring**.

**Issue:** Monolithic god object managing 1700+ settings across all domains.

**Current Domains Mixed Together:**
- Appearance (theme, colors, fonts)
- Audio (device, levels, feedback sounds)
- Transcription models (Whisper, Parakeet)
- LLM configuration (providers, API keys)
- Workflow settings (auto-run, defaults)
- Integration settings (Quick Open targets)
- Debug/dev settings (feature flags)
- UI state (sidebar width, window positions)

**Recommended Split:**
```
Settings/
├── SettingsManager.swift       # Coordinator (~200 lines)
├── AppearanceSettings.swift    # Theme, colors, fonts (~300 lines)
├── AudioSettings.swift         # Device, levels, sounds (~250 lines)
├── ModelSettings.swift         # STT + LLM models (~300 lines)
├── IntegrationSettings.swift   # Quick Open, external apps (~200 lines)
├── WorkflowSettings.swift      # Auto-run, defaults (~200 lines)
├── DebugSettings.swift         # Feature flags, dev mode (~150 lines)
└── SettingsMigration.swift     # Version upgrades (~150 lines)
```

**Benefits of Split:**
- Faster compilation (smaller files)
- Easier testing (isolated domains)
- Clearer ownership (team assignments)
- Reduced merge conflicts

---

### ServiceManager.swift (1038 lines)
Service lifecycle orchestration.

**Discussion:**
- **Singleton:** `ServiceManager.shared`
- **Pattern:** @Observable for SwiftUI binding
- Manages `LiveServiceState` and `EngineServiceState`
- Multi-process discovery for DevControlPanel
- Environment-aware (`TalkieEnvironment`)
- Login item registration via ServiceManagement framework
- Process lifecycle: launch, terminate, restart
- HelperStatus enum for UI display

**Key Properties:**
- `live: LiveServiceState` - TalkieAgent process state
- `engine: EngineServiceState` - TalkieEngine process state
- `allLiveProcesses` / `allEngineProcesses` - Multi-process discovery

**Key Methods:**
- `launchLive()` / `launchEngine()` - Start helpers
- `registerEngineLoginItem()` / `registerLiveLoginItem()` - Login item setup

---

### XPCServiceManager.swift
XPC communication with TalkieAgent/Engine.

**Discussion:**
- Generic XPC manager (`XPCServiceManager<ServiceProtocol>`)
- Environment-aware connection (tries current → dev → staging → production)
- Connection states: `.disconnected`, `.connecting`, `.connected`, `.failed`
- Automatic retry with max 3 attempts
- Published state via Combine
- Support for exported interfaces (callbacks)

**Key Features:**
- `connect()` - Async connection with environment fallback
- `tryConnect(to:)` - Try specific environment
- Handles interruption and invalidation callbacks
- Thread-safe connection management

---

### EngineClient.swift
Client for TalkieEngine XPC.

**Discussion:**
- Wrapper around XPCServiceManager for TalkieEngine
- Implements EngineClient.shared singleton
- Provides transcribe(), preloadModel(), getStatus() APIs
- Auto-connects on first use
- Handles busy engine (waits up to 60s for model loading)

---

### PendingActionsManager.swift (~266 lines)
Manages pending AI actions queue.

**Discussion:**
- Queue of AI actions (summarize, extract tasks) waiting to be processed
- Persists to UserDefaults
- Processes in background
- Debouncing to avoid redundant work

---

## Audio

### AudioDeviceManager.swift
Audio device enumeration and selection.

**Discussion:**
- **Singleton:** `AudioDeviceManager.shared`
- Uses CoreAudio APIs for device discovery
- Tracks `inputDevices` and `defaultDeviceID`
- `selectedDeviceID` - Persisted in LiveSettings
- Device change listener for hot-plug support
- `selectDevice(_:)` - Sets default input for process

---

### SoundManager.swift
Sound effects and audio feedback.

**Discussion:**
- Plays system sounds for UI feedback
- Recording start/stop sounds
- Error and success audio cues
- Uses AVAudioPlayer for playback

---

## Context Capture

### ContextCaptureService.swift
App context capture using Accessibility APIs.

**Discussion:**
- **No screen recording** - Uses structured AX data only
- Configurable detail levels:
  - `.off` - No capture
  - `.metadataOnly` - App name and window title only
  - `.rich` - Full context including URLs and content

**Captured Data:**
- `appBundleID`, `appName`, `windowTitle`
- `documentURL` - File path or web URL
- `browserURL` - Full URL for browser tabs
- `focusedRole`, `focusedValue` - AX element info
- `terminalWorkingDir` - For terminal apps
- `isClaudeCodeSession` - Claude Code detection

**Options:**
- Timeout: 250-400ms (configurable)
- Session-based opt-out
- Per-capture options struct

---

## Transcription

### EphemeralTranscriber.swift
Quick transcription for voice guidance in Interstitial.

**Discussion:**
- **Singleton:** `EphemeralTranscriber.shared`
- **Pattern:** @Observable for SwiftUI binding
- Captures audio → transcribes via TalkieEngine → returns text
- **No persistence** - Audio deleted after transcription
- Uses AVAudioEngine for capture
- Lazy audio file creation (matches buffer format)

**States:**
- `isRecording` - Capture in progress
- `isTranscribing` - Engine processing
- `audioLevel` - RMS level for visualization

**Key Methods:**
- `startCapture()` - Begin microphone capture
- `stopAndTranscribe()` - Stop and get transcript
- `cancel()` - Abort without transcription

**Uses:**
- `EngineClient.shared` for transcription
- `parakeet:v3` model (fast)
- `.high` priority (real-time)

---

## Quick Open

### QuickOpenService.swift
Quick open content in external apps.

**Discussion:**
- Send content to Claude, ChatGPT, Notes, Obsidian, Bear
- Multiple open methods:
  - URL scheme (`obsidian://new?content=`)
  - Bundle ID (launch + clipboard)
  - AppleScript
  - Custom shell command

**QuickOpenTarget:**
- `id`, `name`, `bundleId`
- `openMethod` - How to open
- `keyboardShortcut` - 1-9 for ⌘1-⌘9
- `promptPrefix` - Optional prefix
- `autoPaste` - Use AX to paste automatically

**Built-in Targets:**
- Claude, ChatGPT, Notes, Obsidian, Bear

---

## TODO

- [ ] Split SettingsManager.swift (1732 lines) into smaller files
- [ ] Review ServiceManager.swift for potential simplification
- [ ] Verify LLM providers have consistent error handling
- [ ] Check API key handling in all providers

## Done

- [x] Initial structure review complete
- [x] KeychainManager is secure
- [x] LLM protocol architecture is clean
- [x] Router is well-designed
- [x] ServiceManager documented
- [x] XPCServiceManager documented
- [x] EphemeralTranscriber documented
- [x] ContextCaptureService documented
- [x] QuickOpenService documented
- [x] AudioDeviceManager documented
