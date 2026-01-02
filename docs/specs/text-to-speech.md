# Text-to-Speech Feature Spec

## Overview

Add text-to-speech capabilities to Talkie, allowing the app to "talk back" to users. This complements the existing speech-to-text functionality, creating a complete voice-first experience.

**Guiding Principle**: Start simple with cloud APIs, then optionally add local TTS via TalkieEngine.

---

## Architecture Options

### Option A: Cloud-First (Recommended MVP)

```
┌─────────────────────────────────────────────────────────┐
│                    Talkie App                            │
│  ┌─────────────────────────────────────────────────────┐│
│  │              TTSManager (singleton)                  ││
│  │  - Provider registry (OpenAI, ElevenLabs, etc.)     ││
│  │  - Audio playback via AVAudioPlayer                 ││
│  │  - Caching layer (optional)                         ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### Option B: Engine-Based (Future)

```
┌──────────────────────┐        ┌──────────────────────────┐
│      Talkie App      │        │     TalkieEngine         │
│  ┌────────────────┐  │  XPC   │  ┌────────────────────┐  │
│  │  TTSManager    │◄─┼────────┼─►│  TTSService        │  │
│  │  (client)      │  │        │  │  - Local models    │  │
│  └────────────────┘  │        │  │  - MLX inference   │  │
└──────────────────────┘        │  │  - Cloud fallback  │  │
                                │  └────────────────────┘  │
                                └──────────────────────────┘
```

---

## Cloud TTS Providers

### Provider Comparison

| Provider | Latency | Quality | Cost | Voices | Notes |
|----------|---------|---------|------|--------|-------|
| **OpenAI** | ~200ms | Excellent | $15/1M chars | 6 | Best balance, already have API key |
| **ElevenLabs** | ~300ms | Best | $5/30K chars | 100s | Cloning, emotions |
| **Groq** | ~100ms | Good | Free tier | Limited | Fastest, PlayAI voices |
| **Gemini** | ~250ms | Good | Free tier | Multiple | New TTS model |
| **macOS System** | ~50ms | OK | Free | Many | Offline, robotic |

### Recommended Default: OpenAI

- User likely already has API key configured for LLM polish
- Good quality/latency/cost balance
- Simple API with consistent output

### Existing Reference: speakeasy CLI

Your `speakeasy` CLI already implements all providers. Configuration at:
`~/.config/speakeasy/settings.json`

Consider sharing API key storage or importing speakeasy config.

---

## Data Model

```swift
// MARK: - TTS Provider Protocol

protocol TTSProvider {
    var id: String { get }
    var name: String { get }
    var isAvailable: Bool { get async }

    /// Generate speech audio from text
    func synthesize(
        text: String,
        voice: String?,
        options: TTSSynthesisOptions
    ) async throws -> TTSAudioResult

    /// List available voices
    func availableVoices() async throws -> [TTSVoice]
}

// MARK: - Options & Results

struct TTSSynthesisOptions {
    var speed: Double = 1.0          // 0.25 to 4.0
    var format: AudioFormat = .mp3   // mp3, wav, opus
    var streaming: Bool = false      // Stream chunks for long text
}

struct TTSAudioResult {
    let audioData: Data
    let format: AudioFormat
    let duration: TimeInterval?      // Estimated duration
    let characterCount: Int
}

struct TTSVoice: Identifiable, Codable {
    let id: String
    let name: String
    let language: String
    let gender: VoiceGender?
    let preview: URL?               // Sample audio URL

    enum VoiceGender: String, Codable {
        case male, female, neutral
    }
}

enum AudioFormat: String, Codable {
    case mp3 = "mp3"
    case wav = "wav"
    case opus = "opus"
    case aac = "aac"
}
```

---

## Core Manager

```swift
@MainActor
@Observable
final class TTSManager {
    static let shared = TTSManager()

    // State
    private(set) var isSpeaking: Bool = false
    private(set) var currentText: String?
    private(set) var progress: Double = 0  // 0-1 for long text

    // Settings
    var preferredProviderId: String?
    var preferredVoiceId: String?
    var defaultSpeed: Double = 1.0
    var defaultVolume: Double = 0.7

    // Providers
    private var providers: [String: TTSProvider] = [:]
    private var audioPlayer: AVAudioPlayer?

    // MARK: - Public API

    /// Speak text aloud
    func speak(_ text: String, interrupt: Bool = true) async throws {
        if interrupt { stop() }

        guard !text.isEmpty else { return }

        isSpeaking = true
        currentText = text

        defer {
            isSpeaking = false
            currentText = nil
        }

        let provider = resolveProvider()
        let voice = preferredVoiceId ?? provider.defaultVoice

        let result = try await provider.synthesize(
            text: text,
            voice: voice,
            options: TTSSynthesisOptions(speed: defaultSpeed)
        )

        try await playAudio(result.audioData, format: result.format)
    }

    /// Stop current speech
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isSpeaking = false
    }

    /// Preview a voice with sample text
    func previewVoice(_ voice: TTSVoice, provider: TTSProvider) async throws {
        let sample = "Hello! This is how I sound when reading your text."
        try await speak(sample)
    }
}
```

---

## Provider Implementations

### OpenAI Provider

```swift
class OpenAITTSProvider: TTSProvider {
    let id = "openai"
    let name = "OpenAI"

    // Available voices
    static let voices = ["alloy", "echo", "fable", "onyx", "nova", "shimmer"]
    var defaultVoice = "nova"

    var isAvailable: Bool {
        get async {
            guard let key = SettingsManager.shared.openaiApiKey else { return false }
            return !key.isEmpty
        }
    }

    func synthesize(
        text: String,
        voice: String?,
        options: TTSSynthesisOptions
    ) async throws -> TTSAudioResult {
        guard let apiKey = SettingsManager.shared.openaiApiKey else {
            throw TTSError.notConfigured("OpenAI API key not set")
        }

        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "tts-1",  // or "tts-1-hd" for higher quality
            "input": text,
            "voice": voice ?? defaultVoice,
            "speed": options.speed,
            "response_format": options.format.rawValue
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TTSError.apiError("OpenAI TTS request failed")
        }

        return TTSAudioResult(
            audioData: data,
            format: options.format,
            duration: nil,
            characterCount: text.count
        )
    }

    func availableVoices() async throws -> [TTSVoice] {
        Self.voices.map { voiceId in
            TTSVoice(
                id: voiceId,
                name: voiceId.capitalized,
                language: "en",
                gender: ["nova", "shimmer"].contains(voiceId) ? .female : .male,
                preview: nil
            )
        }
    }
}
```

### macOS System Provider (Offline Fallback)

```swift
class SystemTTSProvider: TTSProvider {
    let id = "system"
    let name = "macOS System"

    private let synthesizer = NSSpeechSynthesizer()

    var isAvailable: Bool { get async { true } }  // Always available

    func synthesize(
        text: String,
        voice: String?,
        options: TTSSynthesisOptions
    ) async throws -> TTSAudioResult {
        // Use NSSpeechSynthesizer.startSpeaking(to:) to write to file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("aiff")

        if let voiceId = voice {
            synthesizer.setVoice(NSSpeechSynthesizer.VoiceName(voiceId))
        }

        synthesizer.rate = Float(options.speed * 180)  // 180 WPM default

        return try await withCheckedThrowingContinuation { continuation in
            synthesizer.startSpeaking(text, to: tempURL)

            // Poll for completion (NSSpeechSynthesizer is old API)
            Task {
                while synthesizer.isSpeaking {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }

                do {
                    let data = try Data(contentsOf: tempURL)
                    try FileManager.default.removeItem(at: tempURL)

                    continuation.resume(returning: TTSAudioResult(
                        audioData: data,
                        format: .wav,
                        duration: nil,
                        characterCount: text.count
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func availableVoices() async throws -> [TTSVoice] {
        NSSpeechSynthesizer.availableVoices.map { voiceName in
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voiceName)
            return TTSVoice(
                id: voiceName.rawValue,
                name: attrs[.name] as? String ?? voiceName.rawValue,
                language: attrs[.localeIdentifier] as? String ?? "en",
                gender: nil,
                preview: nil
            )
        }
    }
}
```

---

## Use Cases

### 1. Read Transcription Aloud

After transcription, user can tap "Listen" to hear polished text.

```swift
// In MemoDetailView or ScratchPadView
Button {
    Task {
        try? await TTSManager.shared.speak(memo.transcript)
    }
} label: {
    Label("Listen", systemImage: "speaker.wave.2")
}
```

### 2. Voice Feedback for Actions

Confirm actions audibly (accessibility, hands-free).

```swift
// After successful paste
TTSManager.shared.speak("Text copied to clipboard", interrupt: true)

// After dictation complete
TTSManager.shared.speak("Recording saved", interrupt: true)
```

### 3. Read LLM Responses

For AI assistant features, speak the response.

```swift
let response = try await llm.generate(prompt: userQuery)
try await TTSManager.shared.speak(response)
```

### 4. Pronunciation Check

User can hear how their dictation sounds to verify accuracy.

---

## Settings UI

```
┌─────────────────────────────────────────────────────────┐
│ TEXT-TO-SPEECH                                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│ Provider:    [OpenAI           ▼]                       │
│                                                         │
│ Voice:       [Nova             ▼]  [▶ Preview]          │
│                                                         │
│ Speed:       [━━━━━━━●━━━━━━━━━━]  1.0x                 │
│                                                         │
│ Volume:      [━━━━━━━━━━●━━━━━━━]  70%                  │
│                                                         │
│ ─────────────────────────────────────────────────────── │
│                                                         │
│ QUICK ACTIONS                                           │
│                                                         │
│ ☑️ Read transcription aloud after memo creation         │
│ ☐ Voice feedback for clipboard actions                  │
│ ☐ Read LLM polish results aloud                         │
│                                                         │
│ ─────────────────────────────────────────────────────── │
│                                                         │
│ FALLBACK                                                │
│                                                         │
│ If primary provider unavailable:                        │
│ ☑️ Use macOS System voice (offline)                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Future: TalkieEngine TTS Extension

### Why Add TTS to Engine?

1. **Local inference** - MLX-based TTS models (Parler, XTTS, etc.)
2. **Shared process** - Reuse Engine's GPU/memory management
3. **Unified XPC** - Same communication pattern as transcription
4. **Voice cloning** - Local models can clone user's voice

### Proposed XPC Protocol Extension

```swift
// Add to TalkieEngineProtocol
@objc public protocol TalkieEngineProtocol {
    // ... existing transcription methods ...

    // MARK: - TTS (Future)

    /// Synthesize speech from text
    func synthesize(
        text: String,
        modelId: String,
        voiceId: String?,
        speed: Double,
        reply: @escaping (_ audioPath: String?, _ error: String?) -> Void
    )

    /// Preload TTS model
    func preloadTTSModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Get available TTS voices for a model
    func getTTSVoices(
        modelId: String,
        reply: @escaping (_ voicesJSON: Data?) -> Void
    )
}
```

### Local TTS Models (Research)

| Model | Size | Quality | Speed | Notes |
|-------|------|---------|-------|-------|
| **Parler TTS** | ~1GB | Good | Fast | MLX port available |
| **XTTS v2** | ~2GB | Excellent | Medium | Voice cloning |
| **Piper** | ~50MB | OK | Very fast | Lightweight |
| **Coqui** | ~500MB | Good | Medium | Multiple voices |

### Integration with speakeasy

Could shell out to speakeasy as temporary solution:

```swift
func speakViaCLI(_ text: String) async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/speakeasy")
    process.arguments = ["--text", text, "--provider", "openai"]
    try process.run()
    process.waitUntilExit()
}
```

---

## Implementation Priority

### MVP (Phase 1)
- [ ] TTSProvider protocol and TTSManager
- [ ] OpenAI provider implementation
- [ ] macOS System provider (offline fallback)
- [ ] Basic settings UI (provider, voice, speed)
- [ ] "Listen" button on MemoDetailView

### Phase 2
- [ ] ElevenLabs provider
- [ ] Groq provider
- [ ] Audio caching (hash text → cached audio file)
- [ ] Voice preview in settings
- [ ] Keyboard shortcut to read selection

### Phase 3 (Future)
- [ ] TalkieEngine TTS extension
- [ ] Local MLX models (Parler TTS)
- [ ] Voice cloning support
- [ ] Streaming for long text

---

## Files to Create/Modify

### New Files
- `macOS/Talkie/Services/TTS/TTSProvider.swift` - Protocol definition
- `macOS/Talkie/Services/TTS/TTSManager.swift` - Core manager
- `macOS/Talkie/Services/TTS/OpenAITTSProvider.swift` - OpenAI implementation
- `macOS/Talkie/Services/TTS/SystemTTSProvider.swift` - macOS fallback
- `macOS/Talkie/Views/Settings/TTSSettings.swift` - Settings UI

### Modify
- `macOS/Talkie/Views/MemoDetail/MemoDetailView.swift` - Add Listen button
- `macOS/Talkie/Views/ScratchPadView.swift` - Add Listen button
- `macOS/Talkie/Views/Settings/SettingsView.swift` - Add TTS section

### Future (Engine Extension)
- `macOS/TalkieEngine/TalkieEngine/EngineProtocol.swift` - Add TTS methods
- `macOS/TalkieEngine/TalkieEngine/TTSService.swift` - Local TTS implementation

---

## Open Questions

1. Should TTS share API keys with existing LLM providers, or have separate config?
2. Audio caching: cache by text hash, or ephemeral only?
3. Maximum text length before chunking/streaming?
4. Should engine TTS be a separate XPC service or extend existing?
5. Priority: cloud-first MVP, or jump straight to engine-based?

---

## References

- speakeasy CLI config: `~/.config/speakeasy/settings.json`
- OpenAI TTS API: https://platform.openai.com/docs/guides/text-to-speech
- ElevenLabs API: https://docs.elevenlabs.io/api-reference/text-to-speech
- Parler TTS MLX: https://github.com/huggingface/parler-tts
