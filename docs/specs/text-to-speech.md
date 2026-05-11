# Text-to-Speech Feature Spec

## Overview

Add text-to-speech capabilities to Talkie, allowing the app to "talk back" to users. This complements the existing speech-to-text functionality, creating a complete voice-first experience.

**Guiding Principle**: Start simple with cloud APIs, then optionally add local TTS via TalkieEngine.

---

## Architecture Options

### Option A: Local-First (Recommended MVP)

Leverage macOS native speech synthesis (`NSSpeechSynthesizer` / `AVSpeechSynthesizer`).
*   **Pros**: Zero cost, zero latency, offline, privacy-first.
*   **Quality**: Modern macOS "Premium" voices (e.g., Siri voices, "Zoe", "Evan") are high quality.
*   **Strategy**: Prompt users to download enhanced voices in System Settings if they want better quality.

```
┌─────────────────────────────────────────────────────────┐
│                    Talkie App                            │
│  ┌─────────────────────────────────────────────────────┐│
│  │              TTSManager (singleton)                  ││
│  │  - AVSpeechSynthesizer (System Voices)              ││
│  │  - Cloud fallback (optional/future)                 ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### Option B: Cloud-Enhanced (Secondary)

Add OpenAI/ElevenLabs as optional "Pro" features for users demanding specific celebrity voices or higher emotional range.

```
┌─────────────────────────────────────────────────────────┐
│                    Talkie App                            │
│  ┌─────────────────────────────────────────────────────┐│
│  │              TTSManager                              ││
│  │  - Local (Default)                                  ││
│  │  - OpenAI/ElevenLabs (API Key required)             ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

---

## TTS Providers

### Primary: macOS System Voices
- **Framework**: `AVSpeechSynthesizer` (AVFoundation) is preferred over the older `NSSpeechSynthesizer`.
- **Quality**: "Premium" voices (downloadable via System Settings) offer near-neural quality.
- **Cost**: Free.
- **Latency**: Instant.

### Secondary: Cloud APIs (Optional)
For users who provide their own API keys.

| Provider | Latency | Quality | Cost | Voices |
|----------|---------|---------|------|--------|
| **OpenAI** | ~200ms | Excellent | $15/1M chars | 6 |
| **ElevenLabs** | ~300ms | Best | $5/30K chars | 100s |
| **Groq** | ~100ms | Good | Free tier | Limited |


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

### macOS System Provider (Primary)

```swift
import AVFoundation

@MainActor
class SystemTTSProvider: NSObject, TTSProvider, AVSpeechSynthesizerDelegate {
    let id = "system"
    let name = "macOS System"

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<TTSAudioResult, Error>?
    private var currentText: String = ""

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var isAvailable: Bool { get async { true } }

    func synthesize(
        text: String,
        voice: String?,
        options: TTSSynthesisOptions
    ) async throws -> TTSAudioResult {
        // AVSpeechSynthesizer plays directly, so "synthesize" here acts as "play"
        // For actual audio data extraction, we'd use write(_:toBufferCallback:) in newer OS versions
        // or just let AVSpeechSynthesizer handle the playback directly.

        // For this architecture, we might treat 'System' as a player+synthesizer combo.

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Float(options.speed * 0.5) // AVSpeechUtterance rate is 0.0-1.0
        utterance.volume = 1.0

        if let voiceId = voice {
            utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
        } else {
            // Prefer premium voices if available
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        // Return a dummy result since we play directly, OR implement write to file
        // For MVP, we let AVSpeechSynthesizer play.
        synthesizer.speak(utterance)

        return TTSAudioResult(
            audioData: Data(), // Empty for system playback
            format: .wav,
            duration: nil,
            characterCount: text.count
        )
    }

    func availableVoices() async throws -> [TTSVoice] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            TTSVoice(
                id: voice.identifier,
                name: voice.name,
                language: voice.language,
                gender: .neutral, // AVFoundation doesn't expose gender easily
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
- `apps/macos/Talkie/Services/TTS/TTSProvider.swift` - Protocol definition
- `apps/macos/Talkie/Services/TTS/TTSManager.swift` - Core manager
- `apps/macos/Talkie/Services/TTS/OpenAITTSProvider.swift` - OpenAI implementation
- `apps/macos/Talkie/Services/TTS/SystemTTSProvider.swift` - macOS fallback
- `apps/macos/Talkie/Views/Settings/TTSSettings.swift` - Settings UI

### Modify
- `apps/macos/Talkie/Views/MemoDetail/MemoDetailView.swift` - Add Listen button
- `apps/macos/Talkie/Views/ScratchPadView.swift` - Add Listen button
- `apps/macos/Talkie/Views/Settings/SettingsView.swift` - Add TTS section

### Future (Embedded Runtime Extension)
- `apps/macos/TalkieEngineCore/Sources/TalkieEngineCore/EmbeddedEngineRuntime.swift` - Extend only if we need more in-process engine capabilities later
- `apps/macos/TalkieAgent/TalkieAgent/Services/EmbeddedEngineCoordinator.swift` - Current embedded runtime entry point

---

## Open Questions

1. Should TTS share API keys with existing LLM providers, or have separate config?
2. Audio caching: cache by text hash, or ephemeral only?
3. Maximum text length before chunking/streaming?
4. If we revisit local speech later, should it live in the embedded runtime or stay cloud/system-only?
5. Priority: keep cloud/system TTS simple, or add a new local runtime again later?

---

## References

- speakeasy CLI config: `~/.config/speakeasy/settings.json`
- OpenAI TTS API: https://platform.openai.com/docs/guides/text-to-speech
- ElevenLabs API: https://docs.elevenlabs.io/api-reference/text-to-speech
- Parler TTS MLX: https://github.com/huggingface/parler-tts
