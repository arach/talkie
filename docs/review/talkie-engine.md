# TalkieEngine

`macOS/TalkieEngine/` - XPC transcription service

Isolated XPC service process hosting WhisperKit and FluidAudio (Parakeet) for transcription.

---

## Architecture Overview

TalkieEngine is a standalone XPC service that:
- Hosts ML models (Whisper via WhisperKit, Parakeet via FluidAudio)
- Provides transcription API via XPC protocol
- Manages model lifecycle (download, preload, unload)
- Runs as launchd service for on-demand startup
- Environment-aware (production/staging/dev) for parallel testing

**Flow:** Audio path → Model load (if needed) → Inference → Transcript

---

## Files

### main.swift
XPC service entry point.

**Discussion:**
- Sets up `NSXPCListener` with mach service name
- Registers `EngineService` as the exported object
- Configures listener delegate for connection handling
- Uses TalkieLogger for startup logging

---

### EngineService.swift (~1000 lines)
Core transcription implementation.

**Discussion:**
- **Multi-Model Support:**
  - Whisper family: tiny, base, small, distil-large-v3 (via WhisperKit)
  - Parakeet family: v2, v3 (via FluidAudio/NVIDIA)
- **Model ID Format:** `family:modelId` (e.g., `parakeet:v3`, `whisper:openai_whisper-small`)
- **Lazy Loading:** Models loaded on first transcription, cached for subsequent use
- **Model Storage:**
  - Whisper: `~/Library/Application Support/Talkie/WhisperModels/`
  - Parakeet: `~/Library/Application Support/Talkie/ParakeetModels/`
- **Priority Support:** Maps `TranscriptionPriority` to Swift `TaskPriority`
- **Warmup:** Silent audio inference after model load to JIT compile

**Key Methods:**
- `transcribe(audioPath:modelId:externalRefId:priority:reply:)` - Main entry point
- `transcribeWithWhisper(audioPath:modelId:trace:)` - Whisper-specific transcription
- `transcribeWithParakeet(audioPath:modelId:trace:)` - Parakeet-specific transcription
- `preloadModel(_:reply:)` - Preload model into memory
- `unloadModel(reply:)` - Release model memory
- `downloadModel(_:reply:)` - Download model from HuggingFace
- `getAvailableModels(reply:)` - List all known models with download status

**Parakeet Audio Processing:**
- Loads audio file via AVAudioFile
- Converts to 16kHz mono Float32 samples
- Appends pink noise padding (300ms) to help decoder flush final tokens

**Performance:**
- Uses `TranscriptionTrace` for step-level timing (visible in Instruments via os_signpost)
- Logs RTF (realtime factor) for performance insight
- Alerts on slow transcriptions (>5s inference)

**Graceful Shutdown:**
- `requestShutdown(waitForCompletion:reply:)` - Stop accepting work, optionally wait for completion
- Sets `isShuttingDown` flag to reject new requests
- Grace period of 2 minutes for in-flight transcriptions

---

### EngineProtocol.swift (~317 lines)
XPC protocol definitions.

**Discussion:**
- **TalkieEngineProtocol:** @objc protocol for XPC interface
  - `transcribe()` - Transcribe audio with priority
  - `preloadModel()` / `unloadModel()` - Model lifecycle
  - `getStatus()` - JSON-encoded status
  - `ping()` - Connection test
  - `requestShutdown()` - Graceful shutdown
  - `downloadModel()` / `cancelDownload()` / `getDownloadProgress()` - Download management
  - `getAvailableModels()` - Model listing

- **TranscriptionPriority:** XPC-compatible enum mapping to Swift TaskPriority
  - `.high` - Real-time dictation (TalkieLive)
  - `.medium` - Interactive features
  - `.low` - Batch operations
  - `.background` - Maintenance

- **EngineServiceMode:** Environment-based service names
  - `.production` → `jdi.talkie.engine.xpc`
  - `.staging` → `jdi.talkie.engine.xpc.staging`
  - `.dev` → `jdi.talkie.engine.xpc.dev`

- **Data Types (Codable for JSON over XPC):**
  - `EngineStatus` - PID, version, model state, memory usage
  - `DownloadProgress` - Model download progress
  - `ModelInfo` - Model metadata for UI
  - `ModelFamily` - whisper/parakeet enum

---

### XPCServiceWrapper.swift
Connection handling.

**Discussion:**
- Implements `NSXPCListenerDelegate`
- Creates new `EngineService` instance per connection
- Sets up `remoteObjectInterface` and `exportedInterface`

---

### AppDelegate.swift
Application lifecycle.

**Discussion:**
- Status window management
- `EngineStatusManager` integration for UI
- Debug menu items

---

## Model Families

### Whisper (WhisperKit)
OpenAI's Whisper model family:
- `openai_whisper-tiny` (~75 MB) - Fastest, basic quality
- `openai_whisper-base` (~150 MB) - Fast, good quality
- `openai_whisper-small` (~500 MB) - Balanced
- `distil-whisper_distil-large-v3` (~1.5 GB) - Best quality, slower

### Parakeet (FluidAudio/NVIDIA)
NVIDIA's Parakeet model family:
- `v2` (~200 MB) - English only, highest accuracy
- `v3` (~250 MB) - 25 languages, fast

---

## Performance Notes

- **Pink Noise Padding:** 300ms of low-level pink noise appended to audio helps ASR models flush final tokens without echo artifacts
- **RTF (Realtime Factor):** Logged as `Nx realtime` (e.g., 5.2x = 5.2x faster than audio duration)
- **Slow Inference Alert:** Logged as warning when inference >5s

---

## Logging

Uses `AppLogger` which routes to:
- Console (NSLog for Xcode/Console.app visibility)
- `TalkieLogFileWriter` for cross-app viewing in Talkie

Categories: `.system`, `.audio`, `.transcription`, `.model`, `.xpc`, `.performance`, `.error`

---

## TODO

- [ ] Consider model prewarming strategy on app launch
- [ ] Add memory pressure monitoring for model unloading
- [ ] Review download progress tracking (currently incomplete for Parakeet)

## Done

- [x] Complete documentation of EngineService
- [x] Document multi-model architecture
- [x] Document XPC protocol
- [x] Document model families and storage
