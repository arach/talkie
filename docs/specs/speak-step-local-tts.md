# Speak Step: Local TTS Integration

> **Status**: Ready to implement. This is the handoff spec for wiring up local TTS in the workflow engine.

## Goal

Add a `.local` TTS provider to the `.speak` workflow step that uses the TalkieEnginePod (FluidAudio/Kokoro) for free, on-device speech synthesis.

## Why

- Users without API budget can still use TTS workflows
- No external dependencies (ElevenLabs, OpenAI keys)
- ~800MB memory, reclaimable by killing the pod

## What Exists (Already Built)

### Full TTS Pipeline
```
EngineClient.synthesize(text:voiceId:)     ← Talkie app
    ↓ XPC
TalkieEngine/EngineService.doSynthesize()  ← XPC service
    ↓
TTSService.shared.synthesize()             ← TTS coordinator
    ↓
PodManager.shared.request("tts")           ← Subprocess IPC
    ↓
TalkieEnginePod                            ← FluidAudio/Kokoro
    ↓
Returns: /path/to/audio.wav
```

### Key Files
| File | What It Does |
|------|--------------|
| `macOS/Talkie/Services/EngineClient.swift` | XPC client, has `synthesize(text:voiceId:)` |
| `macOS/TalkieKit/.../XPCProtocols.swift` | Defines `TalkieEngineProtocol.synthesize()` |
| `macOS/TalkieEngine/.../EngineService.swift` | XPC server, delegates to TTSService |
| `macOS/TalkieEngine/.../TTSService.swift` | Manages pod lifecycle, calls PodManager |
| `macOS/TalkieEngine/.../PodManager.swift` | Spawns/kills TalkieEnginePod subprocess |
| `macOS/TalkieEnginePod/` | FluidAudio TTS, shows as "Talkie Speech Engine" in Activity Monitor |

### Workflow Engine
| File | What It Does |
|------|--------------|
| `macOS/Talkie/Workflow/WorkflowDefinition.swift` | Defines `TTSProvider` enum, `SpeakStepConfig` |
| `macOS/Talkie/Workflow/WorkflowExecutor.swift` | `executeSpeakStep()` - currently has system + SpeakEasy |

## What Needs to Be Built

### 1. Add `.local` to TTSProvider enum

**File**: `WorkflowDefinition.swift`

```swift
enum TTSProvider: String, Codable, CaseIterable {
    case system = "system"
    case speakeasy = "speakeasy"
    case openai = "openai"
    case elevenlabs = "elevenlabs"
    case local = "local"  // ← ADD THIS
}
```

### 2. Handle `.local` in executeSpeakStep()

**File**: `WorkflowExecutor.swift`

Add a case in the switch:

```swift
case .local:
    audioFileURL = try await generateWithLocalTTS(
        text: textToSpeak,
        voice: config.voice ?? "default"
    )
```

### 3. Implement generateWithLocalTTS()

**File**: `WorkflowExecutor.swift`

```swift
private func generateWithLocalTTS(text: String, voice: String) async throws -> URL? {
    let voiceId = "kokoro:\(voice)"
    let audioPath = try await EngineClient.shared.synthesize(
        text: text,
        voiceId: voiceId
    )
    return URL(fileURLWithPath: audioPath)
}
```

### 4. Add "Keep TTS Engine Warm" setting

**Location**: Settings → Helper Apps or Dev Controls (system-level, not model-level)

**Setting**: Global toggle
- **ON**: Keep TalkieEnginePod running after TTS (fast subsequent calls)
- **OFF**: Kill pod after TTS completes (reclaim ~800MB)

**Implementation**:
- Add `keepTTSEngineWarm: Bool` to SettingsManager
- After `executeSpeakStep()` completes, check setting
- If OFF, call `EngineClient.shared.unloadTTS()`

## Proof of Concept Workflow

Once wired up, create a test workflow:

```
Memo
  → LLM Step (prompt: "Summarize this as a dramatic movie trailer narrator")
  → Speak Step (provider: .local, text: "{{OUTPUT}}")
```

This validates the full chain: Memo → LLM → TTS → Audio playback.

## Future (Not Now)

- Provider fallback: try cloud, fall back to local if no API key
- Heuristics: use local for short text, cloud for long/important
- Per-step override of warm/ephemeral setting

## Branch

Work on: `feature/specs-dictionary-tts` (current branch)

The TTS pod architecture is already committed. This is additive work.
