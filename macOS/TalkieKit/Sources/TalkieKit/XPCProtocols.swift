//
//  XPCProtocols.swift
//  TalkieKit
//
//  XPC protocol definitions shared between Talkie, TalkieLive, and TalkieEngine.
//  Single source of truth - all apps import from here.
//

import Foundation

// MARK: - XPC Service Names

/// XPC service name for TalkieLive (environment-aware)
public var kTalkieLiveXPCServiceName: String {
    TalkieEnvironment.current.liveXPCService
}

/// XPC service name for TalkieEngine (environment-aware)
public var kTalkieEngineXPCServiceName: String {
    TalkieEnvironment.current.engineXPCService
}

// MARK: - TalkieLive XPC Protocols

/// Protocol for TalkieLive's XPC service (Talkie → Live commands)
@objc public protocol TalkieLiveXPCServiceProtocol {
    /// Get current recording state, elapsed time, and process ID
    func getCurrentState(reply: @escaping (_ state: String, _ elapsedTime: TimeInterval, _ pid: Int32) -> Void)

    /// Register for state change notifications (returns success and PID)
    func registerStateObserver(reply: @escaping (_ success: Bool, _ pid: Int32) -> Void)

    /// Unregister from state change notifications
    func unregisterStateObserver(reply: @escaping (_ success: Bool) -> Void)

    /// Toggle recording (start if idle, stop if listening)
    func toggleRecording(reply: @escaping (_ success: Bool) -> Void)

    /// Get TalkieLive's permission status
    /// - Parameters:
    ///   - reply: Callback with microphone granted, accessibility granted, screen recording granted
    func getPermissions(reply: @escaping (_ microphone: Bool, _ accessibility: Bool, _ screenRecording: Bool) -> Void)

    /// Insert text into the target application
    ///
    /// Uses direct Accessibility API insertion when possible (no clipboard pollution),
    /// falls back to clipboard + simulated Cmd+V paste if direct insertion fails.
    ///
    /// - Parameters:
    ///   - text: The text to insert
    ///   - bundleID: Bundle identifier of the target app (nil = frontmost app)
    ///   - reply: Callback with success status
    func pasteText(_ text: String, toAppWithBundleID bundleID: String?, reply: @escaping (_ success: Bool) -> Void)

    /// Append a message to a Claude session's terminal (for iOS Bridge)
    ///
    /// Looks up the terminal context for the given session ID from BridgeContextMapper,
    /// then inserts the text using TextInserter.
    ///
    /// If text is empty and submit is true, just presses Enter without inserting anything.
    ///
    /// - Parameters:
    ///   - text: The text to append (empty = no text insertion)
    ///   - sessionId: Claude session UUID
    ///   - projectPath: Full project path (e.g., "/Users/arach/dev/talkie") for terminal matching
    ///   - submit: Whether to press Enter after inserting text (submits to Claude)
    ///   - reply: Callback with success status and optional error message
    func appendMessage(_ text: String, sessionId: String, projectPath: String?, submit: Bool, reply: @escaping (_ success: Bool, _ error: String?) -> Void)

    // MARK: - Screenshot Methods (for iOS Bridge)

    /// List terminal windows that might contain Claude sessions
    /// Returns JSON-encoded array of window info
    func listClaudeWindows(reply: @escaping (_ windowsJSON: Data?) -> Void)

    /// Capture a screenshot of a specific window
    /// Returns JPEG image data
    func captureWindow(windowID: UInt32, reply: @escaping (_ imageData: Data?, _ error: String?) -> Void)

    /// Capture screenshots of all terminal windows
    /// Returns JSON-encoded array with window info and base64 image data
    func captureTerminalWindows(reply: @escaping (_ screenshotsJSON: Data?, _ error: String?) -> Void)

    /// Check if screen recording permission is granted
    func hasScreenRecordingPermission(reply: @escaping (_ granted: Bool) -> Void)
}

/// Protocol for Talkie to receive callbacks from TalkieLive (Live → Talkie events)
@objc public protocol TalkieLiveStateObserverProtocol {
    /// Called when TalkieLive's state changes
    func stateDidChange(state: String, elapsedTime: TimeInterval)

    /// Called when TalkieLive adds a new dictation to the database
    func dictationWasAdded()

    /// Called when audio level changes (throttled to ~2Hz)
    func audioLevelDidChange(level: Float)

    /// Called when ambient mode captures a voice command
    /// TalkieLive handles wake phrase detection; this delivers the command text
    /// - Parameters:
    ///   - command: The voice command text (between wake and end phrases)
    ///   - duration: How long the command took to speak
    ///   - bufferContext: Optional recent transcript for context retrieval
    func ambientCommandReceived(command: String, duration: TimeInterval, bufferContext: String?)
}

// MARK: - TalkieEngine XPC Protocol

/// Post-processing options for transcription
/// Transcription is pure by default - processing is opt-in
@objc public enum PostProcessOption: Int, Sendable {
    case none = 0        // Raw transcription only (default)
    case dictionary = 1  // Apply dictionary replacements

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .dictionary: return "Dictionary"
        }
    }
}

/// Task priority for transcription requests
@objc public enum TranscriptionPriority: Int, Sendable {
    case background = 0       // Lowest - maintenance, cleanup
    case utility = 1          // Long-running tasks
    case low = 2             // Deferrable work
    case medium = 3          // Default - balanced priority
    case userInitiated = 4   // User-facing, should complete quickly
    case high = 5            // Highest - real-time, interactive (Live dictations)

    /// Convert to Swift TaskPriority
    public var taskPriority: TaskPriority {
        switch self {
        case .background: return .background
        case .utility: return .utility
        case .low: return .low
        case .medium: return .medium
        case .userInitiated: return .userInitiated
        case .high: return .high
        }
    }

    public var displayName: String {
        switch self {
        case .background: return "Background"
        case .utility: return "Utility"
        case .low: return "Low"
        case .medium: return "Medium"
        case .userInitiated: return "User Initiated"
        case .high: return "High (Real-time)"
        }
    }
}

/// Protocol for TalkieEngine's XPC service (Talkie/Live → Engine)
@objc public protocol TalkieEngineProtocol {
    /// Transcribe audio file to text
    ///
    /// Transcription is pure by default - just audio to text.
    /// Use `postProcess` to opt-in to additional processing steps.
    ///
    /// Priority Guidelines:
    /// - `.high` - Real-time dictation (TalkieLive) - user is waiting
    /// - `.medium` - Interactive features (scratch pad) - user-facing but can wait
    /// - `.low` - Batch/async operations - user isn't waiting
    ///
    /// - Parameters:
    ///   - audioPath: Path to audio file
    ///   - modelId: Model identifier (e.g., "whisper:openai_whisper-small" or "parakeet:v3")
    ///   - externalRefId: Optional trace ID for cross-app correlation
    ///   - priority: Task priority for scheduling
    ///   - postProcess: Optional processing to apply (default: .none = raw transcription)
    ///   - reply: Callback with transcript or error
    func transcribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption,
        reply: @escaping (_ transcript: String?, _ error: String?) -> Void
    )

    /// Preload a model into memory for faster transcription
    func preloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Unload the current model from memory
    func unloadModel(reply: @escaping () -> Void)

    /// Get engine status (returns JSON-encoded EngineStatus)
    func getStatus(reply: @escaping (_ statusJSON: Data?) -> Void)

    /// Ping to verify connection
    func ping(reply: @escaping (_ pong: Bool) -> Void)

    /// Request graceful shutdown
    func requestShutdown(waitForCompletion: Bool, reply: @escaping (_ accepted: Bool) -> Void)

    /// Start downloading a model
    func downloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Get current download progress (returns JSON-encoded DownloadProgress)
    func getDownloadProgress(reply: @escaping (_ progressJSON: Data?) -> Void)

    /// Cancel current download
    func cancelDownload(reply: @escaping () -> Void)

    /// Get list of available models (returns JSON-encoded [ModelInfo])
    func getAvailableModels(reply: @escaping (_ modelsJSON: Data?) -> Void)

    /// Update the dictionary for text post-processing
    /// Talkie pushes content, Engine persists to its own file
    /// - Parameters:
    ///   - entriesJSON: JSON-encoded [DictionaryEntry]
    ///   - reply: Callback with error message if failed
    func updateDictionary(
        entriesJSON: Data,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Enable or disable dictionary processing
    /// Engine persists this setting and loads dictionary on startup if enabled
    /// - Parameters:
    ///   - enabled: Whether dictionary should be active
    ///   - reply: Callback when done
    func setDictionaryEnabled(
        _ enabled: Bool,
        reply: @escaping () -> Void
    )

    // MARK: - Text-to-Speech

    /// Synthesize text to speech audio
    ///
    /// Generates audio file from text using the specified TTS provider.
    /// Returns path to generated WAV file in temporary directory.
    ///
    /// - Parameters:
    ///   - text: Text to synthesize
    ///   - voiceId: Voice identifier (provider-specific, e.g., "kokoro:default")
    ///   - reply: Callback with audio file path or error
    func synthesize(
        text: String,
        voiceId: String,
        reply: @escaping (_ audioPath: String?, _ error: String?) -> Void
    )

    /// Preload a TTS voice into memory for faster synthesis
    func preloadTTSVoice(
        _ voiceId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Get available TTS voices (returns JSON-encoded [TTSVoiceInfo])
    func getAvailableTTSVoices(reply: @escaping (_ voicesJSON: Data?) -> Void)

    /// Unload TTS model to free memory (auto-reloads on next synthesis)
    func unloadTTS(reply: @escaping (_ success: Bool) -> Void)

    /// Get TTS status (loaded, idle time since last use)
    func getTTSStatus(reply: @escaping (_ isLoaded: Bool, _ idleSeconds: Double) -> Void)

    // MARK: - Streaming ASR

    /// Start a streaming ASR session for real-time transcription
    ///
    /// Spawns the streaming-asr pod if not already running and begins a new session.
    /// Audio chunks can then be fed via `feedStreamingASR`.
    ///
    /// - Parameters:
    ///   - reply: Callback with session ID (UUID string) or error message
    func startStreamingASR(_ reply: @escaping (_ sessionId: String?, _ error: String?) -> Void)

    /// Feed audio data to an active streaming ASR session
    ///
    /// Sends a chunk of audio to the ASR engine for processing.
    /// The callback receives JSON-encoded transcript events that have occurred.
    ///
    /// Audio format: base64-encoded Float32 samples at 16kHz mono
    ///
    /// - Parameters:
    ///   - sessionId: The session ID from startStreamingASR
    ///   - audio: Base64-encoded Float32 16kHz mono audio samples
    ///   - reply: Callback with JSON-encoded events array (or nil if none) and error
    func feedStreamingASR(sessionId: String, audio: Data, _ reply: @escaping (_ eventsJSON: Data?, _ error: String?) -> Void)

    /// Stop a streaming ASR session and get the final transcript
    ///
    /// Ends the streaming session and returns the complete transcript.
    /// The pod remains running for future sessions.
    ///
    /// - Parameters:
    ///   - sessionId: The session ID from startStreamingASR
    ///   - reply: Callback with final transcript or error
    func stopStreamingASR(sessionId: String, _ reply: @escaping (_ transcript: String?, _ error: String?) -> Void)
}

// MARK: - TTS Types

/// TTS provider families
public enum TTSProvider: String, Codable, Sendable, CaseIterable {
    case kokoro = "kokoro"       // FluidAudio Kokoro (local)
    case elevenLabs = "elevenlabs" // ElevenLabs API (cloud)
    case system = "system"       // AVSpeechSynthesizer (fallback)

    public var displayName: String {
        switch self {
        case .kokoro: return "Kokoro"
        case .elevenLabs: return "ElevenLabs"
        case .system: return "System"
        }
    }

    public var isLocal: Bool {
        switch self {
        case .kokoro, .system: return true
        case .elevenLabs: return false
        }
    }
}

/// TTS voice metadata (Codable for JSON serialization over XPC)
public struct TTSVoiceInfo: Codable, Sendable, Identifiable {
    public let id: String              // Full ID including provider (e.g., "kokoro:default")
    public let provider: String        // Provider name ("kokoro", "elevenlabs", "system")
    public let voiceId: String         // Voice ID without provider prefix
    public let displayName: String
    public let description: String
    public let language: String        // e.g., "en-US"
    public let isDownloaded: Bool
    public let isLoaded: Bool

    public init(
        id: String,
        provider: String,
        voiceId: String,
        displayName: String,
        description: String,
        language: String,
        isDownloaded: Bool,
        isLoaded: Bool
    ) {
        self.id = id
        self.provider = provider
        self.voiceId = voiceId
        self.displayName = displayName
        self.description = description
        self.language = language
        self.isDownloaded = isDownloaded
        self.isLoaded = isLoaded
    }
}

// Note: LiveState enum is defined in UI/LiveState.swift
