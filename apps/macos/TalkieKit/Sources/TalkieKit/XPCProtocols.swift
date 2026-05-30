//
//  XPCProtocols.swift
//  TalkieKit
//
//  XPC protocol definitions shared between Talkie, TalkieAgent, and TalkieEngine.
//  Single source of truth - all apps import from here.
//

import Foundation

// MARK: - XPC Service Names

/// XPC service name for TalkieAgent (environment-aware)
public var kTalkieAgentXPCServiceName: String {
    TalkieEnvironment.current.liveXPCService
}

/// XPC service name for TalkieEngine (environment-aware)
public var kTalkieEngineXPCServiceName: String {
    TalkieEnvironment.current.engineXPCService
}

/// XPC service name for TalkieSync (environment-aware)
public var kTalkieSyncXPCServiceName: String {
    TalkieEnvironment.current.syncXPCService
}

// MARK: - Hotkey Status

/// Snapshot of a registered Carbon hotkey for diagnostic display
public struct HotKeyStatusInfo: Codable, Sendable, Identifiable {
    public let id: String       // signature (e.g., "DLIV")
    public let label: String    // human-readable name (e.g., "Toggle Recording")
    public let hotkeyID: UInt32
    public let isRegistered: Bool
    public let keyCode: UInt32?
    public let modifiers: UInt32?

    public init(id: String, label: String, hotkeyID: UInt32, isRegistered: Bool, keyCode: UInt32? = nil, modifiers: UInt32? = nil) {
        self.id = id
        self.label = label
        self.hotkeyID = hotkeyID
        self.isRegistered = isRegistered
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

// MARK: - TalkieAgent XPC Protocols

/// Protocol for TalkieAgent's XPC service (Talkie → Live commands)
@objc public protocol TalkieAgentXPCServiceProtocol {
    /// Get current recording state, elapsed time, and process ID
    func getCurrentState(reply: @escaping (_ state: String, _ elapsedTime: TimeInterval, _ pid: Int32) -> Void)

    /// Register for state change notifications (returns success and PID)
    func registerStateObserver(reply: @escaping (_ success: Bool, _ pid: Int32) -> Void)

    /// Unregister from state change notifications
    func unregisterStateObserver(reply: @escaping (_ success: Bool) -> Void)

    /// Toggle recording (start if idle, stop if listening)
    func toggleRecording(reply: @escaping (_ success: Bool) -> Void)

    /// Get TalkieAgent's permission status
    /// - Parameters:
    ///   - reply: Callback with microphone granted, accessibility granted, screen recording granted
    func getPermissions(reply: @escaping (_ microphone: Bool, _ accessibility: Bool, _ screenRecording: Bool) -> Void)

    /// Request microphone permission for TalkieAgent.
    /// Used when Talkie detects the agent is missing capture permission.
    func requestMicrophonePermission(reply: @escaping (_ granted: Bool) -> Void)

    /// Request Accessibility permission for TalkieAgent.
    /// Used when Talkie detects the agent is missing auto-paste permission.
    func requestAccessibilityPermission(reply: @escaping (_ granted: Bool) -> Void)

    /// Request Screen Recording permission for TalkieAgent.
    /// Used when enabling capture features from Talkie.
    func requestScreenRecordingPermission(reply: @escaping (_ granted: Bool) -> Void)

    /// Get TalkieAgent's Input Monitoring permission (needed for global hotkey).
    /// - Parameters:
    ///   - reply: Callback with granted flag (true if Input Monitoring is allowed)
    func getInputMonitoringPermission(reply: @escaping (_ granted: Bool) -> Void)

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
    ///   - projectPath: Full project path (e.g., "/Users/example/dev/talkie") for terminal matching
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

    /// Capture a screenshot of the main display for remote preview surfaces.
    /// - Parameters:
    ///   - maxDimension: Maximum pixel dimension for the longer edge (0 = native size)
    ///   - quality: JPEG compression quality from 0.0 to 1.0
    ///   - reply: Encoded JPEG data or an error message
    func captureMainDisplay(maxDimension: UInt32, quality: Double, reply: @escaping (_ imageData: Data?, _ error: String?) -> Void)

    /// Capture screenshots of all terminal windows
    /// Returns JSON-encoded array with window info and base64 image data
    func captureTerminalWindows(reply: @escaping (_ screenshotsJSON: Data?, _ error: String?) -> Void)

    /// Check if screen recording permission is granted
    func hasScreenRecordingPermission(reply: @escaping (_ granted: Bool) -> Void)

    /// Retranscribe a dictation with a different model
    ///
    /// TalkieAgent owns the unified database, so retranscription must go through XPC.
    /// TalkieAgent fetches audio, transcribes via Engine, and updates the database.
    ///
    /// - Parameters:
    ///   - dictationId: The UUID string of the dictation to retranscribe
    ///   - modelId: Model identifier (e.g., "whisper:openai_whisper-small" or "parakeet:v3")
    ///   - reply: Callback with new transcript text on success, or error message on failure
    func retranscribe(dictationId: String, modelId: String, reply: @escaping (_ newText: String?, _ error: String?) -> Void)

    // MARK: - Ephemeral Capture (for TalkieHeadless/Extensions)

    /// Start ephemeral audio capture (not saved to dictation history)
    ///
    /// Captures microphone audio for external use (e.g., extension transcription).
    /// The audio is not saved to LiveDatabase - it's temporary for the caller's use.
    ///
    /// - Parameters:
    ///   - reply: Callback with session ID on success, or error message on failure
    func startEphemeralCapture(reply: @escaping (_ sessionId: String?, _ error: String?) -> Void)

    /// Stop ephemeral audio capture and get the audio file
    ///
    /// Stops recording and returns the path to the captured audio file.
    /// The caller is responsible for deleting the file when done.
    ///
    /// - Parameters:
    ///   - sessionId: The session ID from startEphemeralCapture
    ///   - reply: Callback with audio file path on success, or error message on failure
    func stopEphemeralCapture(sessionId: String, reply: @escaping (_ audioPath: String?, _ error: String?) -> Void)

    // MARK: - UI Commands

    /// Show TalkieAgent's settings window
    ///
    /// Brings TalkieAgent to foreground and opens its settings.
    /// Use this instead of URL schemes to ensure the correct instance opens.
    func showSettings(reply: @escaping (_ success: Bool) -> Void)

    /// Simulate a Cmd+V paste keystroke
    ///
    /// Used by Talkie after loading images onto the clipboard to deliver
    /// tray items alongside dictation text.
    func simulatePaste(reply: @escaping (_ success: Bool) -> Void)

    /// Attach screenshots to an existing dictation record
    ///
    /// Called by Talkie after copying tray screenshots to ScreenshotStorage.
    /// Agent merges these into the dictation's screenshotsJSON in UnifiedDatabase.
    ///
    /// - Parameters:
    ///   - dictationId: Recording UUID string
    ///   - screenshotsJSON: JSON-encoded [RecordingScreenshot] to merge
    ///   - reply: Callback with success status
    func attachScreenshots(dictationId: String, screenshotsJSON: String, reply: @escaping (_ success: Bool) -> Void)

    /// Record a screenshot captured while a live dictation is actively listening.
    ///
    /// Talkie calls this at capture time so Agent can keep a per-recording
    /// side list. Delivery then uses Agent-local metadata instead of pulling
    /// from, mutating, or waiting on the tray after transcription.
    ///
    /// - Parameters:
    ///   - imageData: PNG image data for the screenshot.
    ///   - capturedAt: Unix timestamp for when Talkie captured the screenshot.
    ///   - captureMode: Capture mode string ("region", "fullscreen", "window").
    ///   - width: Pixel width.
    ///   - height: Pixel height.
    ///   - windowTitle: Optional source window title.
    ///   - appName: Optional source app name.
    ///   - displayName: Optional source display name.
    ///   - reply: Callback with success status.
    func recordLiveScreenshot(
        imageData: Data,
        capturedAt: TimeInterval,
        captureMode: String,
        width: Int,
        height: Int,
        windowTitle: String?,
        appName: String?,
        displayName: String?,
        reply: @escaping (_ success: Bool) -> Void
    )

    // MARK: - Embedded Engine

    /// Ping TalkieAgent's XPC service for transport liveness.
    /// This must stay fast and independent from embedded-engine readiness.
    func ping(reply: @escaping (_ pong: Bool) -> Void)

    /// Get embedded engine status (returns JSON-encoded EngineStatus)
    func getStatus(reply: @escaping (_ statusJSON: Data?) -> Void)

    /// Transcribe audio file to text.
    func transcribe(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption,
        reply: @escaping (_ transcript: String?, _ error: String?) -> Void
    )

    /// Transcribe audio file to text with word-level timestamps.
    func transcribeWithTimings(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption,
        reply: @escaping (_ transcript: String?, _ segmentsJSON: Data?, _ error: String?) -> Void
    )

    /// Preload a model into memory for faster transcription.
    func preloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Unload the current model from memory.
    func unloadModel(reply: @escaping () -> Void)

    /// Start downloading a model.
    func downloadModel(
        _ modelId: String,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Get current download progress (returns JSON-encoded DownloadProgress).
    func getDownloadProgress(reply: @escaping (_ progressJSON: Data?) -> Void)

    /// Cancel current download.
    func cancelDownload(reply: @escaping () -> Void)

    /// Get list of available models (returns JSON-encoded [ModelInfo]).
    func getAvailableModels(reply: @escaping (_ modelsJSON: Data?) -> Void)

    /// Update the dictionary for text post-processing.
    func updateDictionary(
        entriesJSON: Data,
        reply: @escaping (_ error: String?) -> Void
    )

    /// Enable or disable dictionary processing.
    func setDictionaryEnabled(
        _ enabled: Bool,
        reply: @escaping () -> Void
    )

    /// Enable or disable symbolic mapping.
    func setSymbolicMappingEnabled(
        _ enabled: Bool,
        reply: @escaping () -> Void
    )

    /// Enable or disable filler-word removal.
    func setFillerRemovalEnabled(
        _ enabled: Bool,
        reply: @escaping () -> Void
    )

    /// Reload symbolic mapping rules from disk.
    func reloadSymbolicMapping(
        reply: @escaping (_ error: String?) -> Void
    )

    /// Start a streaming ASR session.
    func startStreamingASR(_ reply: @escaping (_ sessionId: String?, _ error: String?) -> Void)

    /// Feed audio data to an active streaming ASR session.
    func feedStreamingASR(sessionId: String, audio: Data, _ reply: @escaping (_ eventsJSON: Data?, _ error: String?) -> Void)

    /// Stop a streaming ASR session and get the final transcript.
    func stopStreamingASR(sessionId: String, _ reply: @escaping (_ transcript: String?, _ error: String?) -> Void)

    // MARK: - TalkieServer Supervision

    /// Get TalkieServer (Bun sidecar) supervision status.
    /// Returns JSON-encoded `TalkieAgentServerStatus` with process state, health, backoff info.
    func getTalkieAgentServerStatus(reply: @escaping (_ statusJSON: Data?) -> Void)

    /// Control TalkieServer lifecycle. Action: "start", "stop", "restart".
    func controlTalkieAgentServer(action: String, reply: @escaping (_ success: Bool, _ error: String?) -> Void)

    // MARK: - Diagnostics

    /// Get status of all registered Carbon hotkeys
    ///
    /// Returns JSON-encoded `[HotKeyStatusInfo]` with registration state for each hotkey.
    /// Used by Talkie's dev settings UI to diagnose hotkey issues.
    func getHotkeyStatus(reply: @escaping (_ statusJSON: Data?) -> Void)
}

/// Protocol for Talkie to receive callbacks from TalkieAgent (Live → Talkie events)
@objc public protocol TalkieAgentStateObserverProtocol {
    /// Called when TalkieAgent's state changes
    func stateDidChange(state: String, elapsedTime: TimeInterval)

    /// Called when TalkieAgent adds a new dictation to the database
    func dictationWasAdded()

    /// Called when audio level changes (throttled to ~2Hz)
    func audioLevelDidChange(level: Float)

    /// Called when ambient mode captures a voice command
    /// TalkieAgent handles wake phrase detection; this delivers the command text
    /// - Parameters:
    ///   - command: The voice command text (between wake and end phrases)
    ///   - duration: How long the command took to speak
    ///   - bufferContext: Optional recent transcript for context retrieval
    func ambientCommandReceived(command: String, duration: TimeInterval, bufferContext: String?)

    /// Called when TalkieAgent detects a voice navigation intent
    /// - Parameters:
    ///   - intent: The recognized intent (e.g., "navigateHome", "openSearch")
    ///   - confidence: Confidence score from 0 to 1
    ///   - rawText: The original transcribed text
    func voiceNavigationReceived(intent: String, confidence: Float, rawText: String)

    /// Legacy paste callback retained for older agents. Dictation does not mutate tray items.
    /// - Parameter recordingId: The UUID string of the dictation recording
    func dictationWasPasted(recordingId: String)

    /// Pull tray screenshots from Talkie at transcription time.
    /// All unpinned items are included. Talkie saves them to ScreenshotStorage
    /// and returns their metadata as JSON. Agent includes this in the initial DB write.
    /// - Parameters:
    ///   - recordingId: The UUID string of the dictation recording
    ///   - reply: JSON-encoded [RecordingScreenshot], or nil if no tray items
    func fetchTrayScreenshots(recordingId: String, reply: @escaping (_ screenshotsJSON: String?) -> Void)

    /// Pull tray screenshots and video clips captured during the dictation window.
    /// Talkie saves eligible unpinned tray media to permanent storage and returns a
    /// JSON-encoded TalkieObjectAssets blob for Agent to merge after the DB write.
    /// - Parameters:
    ///   - recordingId: The UUID string of the dictation recording
    ///   - recordingStartedAt: Unix timestamp for the start of the dictation
    ///   - recordingEndedAt: Unix timestamp for the end of the dictation
    ///   - reply: JSON-encoded TalkieObjectAssets, or nil if no tray assets
    @objc optional func fetchTrayAssets(
        recordingId: String,
        recordingStartedAt: TimeInterval,
        recordingEndedAt: TimeInterval,
        includeScreenshots: Bool,
        reply: @escaping (_ assetsJSON: String?) -> Void
    )

    /// Called when TalkieServer supervision status changes (started, stopped, error, etc.)
    /// JSON-encoded `TalkieAgentServerStatus`. Optional so old builds don't crash.
    @objc optional func talkieAgentServerStatusDidChange(_ statusJSON: Data)
}

// MARK: - TalkieEngine XPC Protocol

/// Post-processing options for transcription
/// Transcription is pure by default - processing is opt-in
@objc public enum PostProcessOption: Int, Sendable {
    case none = 0              // Raw transcription only (default)
    case dictionary = 1        // Apply dictionary replacements
    case intentRecognition = 2 // Recognize voice intent (returns JSON-encoded IntentResult)
    case proceduralProcessor = 3 // Deterministic protocol dictation → syntax (no LLM)
    case inverseTextNormalization = 4 // Spoken-form → written-form text normalization

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .dictionary: return "Dictionary"
        case .intentRecognition: return "Intent Recognition"
        case .proceduralProcessor: return "Procedural Processor"
        case .inverseTextNormalization: return "Inverse Text Normalization"
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
    /// - `.high` - Real-time dictation (TalkieAgent) - user is waiting
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

    /// Transcribe audio file to text with word-level timestamps
    ///
    /// Same as transcribe() but returns structured timing data alongside the transcript.
    /// Falls back gracefully — segmentsJSON is nil if the engine doesn't produce word timings.
    ///
    /// - Parameters:
    ///   - audioPath: Path to audio file
    ///   - modelId: Model identifier (e.g., "whisper:openai_whisper-small" or "parakeet:v3")
    ///   - externalRefId: Optional trace ID for cross-app correlation
    ///   - priority: Task priority for scheduling
    ///   - postProcess: Optional processing to apply (default: .none = raw transcription)
    ///   - reply: Callback with transcript, JSON-encoded TimedTranscription data, or error
    func transcribeWithTimings(
        audioPath: String,
        modelId: String,
        externalRefId: String?,
        priority: TranscriptionPriority,
        postProcess: PostProcessOption,
        reply: @escaping (_ transcript: String?, _ segmentsJSON: Data?, _ error: String?) -> Void
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

    /// Enable or disable symbolic mapping (slash → /, dash → -, etc.)
    /// Engine persists this setting
    /// - Parameters:
    ///   - enabled: Whether symbolic mapping should be active
    ///   - reply: Callback when done
    func setSymbolicMappingEnabled(
        _ enabled: Bool,
        reply: @escaping () -> Void
    )

    /// Enable or disable filler-word removal (um/uh/uhm variants)
    /// Engine persists this setting
    /// - Parameters:
    ///   - enabled: Whether filler cleanup should be active
    ///   - reply: Callback when done
    func setFillerRemovalEnabled(
        _ enabled: Bool,
        reply: @escaping () -> Void
    )

    /// Reload symbolic mapping rules from the JSON file on disk
    /// - Parameter reply: Callback with optional error message
    func reloadSymbolicMapping(
        reply: @escaping (_ error: String?) -> Void
    )

    // MARK: - Streaming ASR

    /// Start a streaming ASR session for real-time transcription
    ///
    /// Starts an in-process streaming ASR session and begins a new stream.
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
    ///
    /// - Parameters:
    ///   - sessionId: The session ID from startStreamingASR
    ///   - reply: Callback with final transcript or error
    func stopStreamingASR(sessionId: String, _ reply: @escaping (_ transcript: String?, _ error: String?) -> Void)
}

// Note: LiveState enum is defined in UI/LiveState.swift

// MARK: - TalkieSync XPC Protocols

/// Status of a sync operation
@objc public enum SyncOperationStatus: Int, Sendable {
    case idle = 0
    case syncing = 1
    case completed = 2
    case failed = 3

    public var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .syncing: return "Syncing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

/// Protocol for TalkieSync's XPC service (Talkie → Sync commands)
///
/// TalkieSync handles all CloudKit and future sync providers out-of-process
/// so Talkie stays thin and UI-focused.
@objc public protocol TalkieSyncXPCProtocol {
    // MARK: - Sync Control

    /// Trigger an immediate sync operation
    /// - Parameters:
    ///   - reply: Callback with success status and optional error message
    func syncNow(reply: @escaping (_ success: Bool, _ error: String?) -> Void)

    /// Trigger a sync with options (limit, since date).
    /// - Parameters:
    ///   - limit: Max number of records to fetch (0 = unlimited)
    ///   - since: Only fetch records created after this date (nil = all)
    ///   - reply: Callback with success status and optional error message
    func syncNowWithOptions(_ limit: Int, since: Date?, reply: @escaping (_ success: Bool, _ error: String?) -> Void)

    /// Cancel any in-progress sync operation
    func cancelSync(reply: @escaping () -> Void)

    // MARK: - Status

    /// Get current sync status as JSON
    /// Returns SyncStatus struct encoded as JSON
    func getStatus(reply: @escaping (_ statusJSON: Data?) -> Void)

    /// Get the last successful sync date
    func getLastSyncDate(reply: @escaping (_ date: Date?) -> Void)

    /// Check if iCloud is available
    func checkiCloudAvailability(reply: @escaping (_ available: Bool, _ error: String?) -> Void)

    // MARK: - Provider Management

    /// Enable a sync provider with optional configuration
    /// - Parameters:
    ///   - providerId: Provider identifier (e.g., "icloud", "s3", "dropbox")
    ///   - config: JSON-encoded provider configuration
    ///   - reply: Callback with optional error message
    func enableProvider(_ providerId: String, config: Data?, reply: @escaping (_ error: String?) -> Void)

    /// Disable a sync provider
    func disableProvider(_ providerId: String, reply: @escaping () -> Void)

    /// List all registered sync providers and their status
    /// Returns JSON array of provider info
    func listProviders(reply: @escaping (_ providersJSON: Data?) -> Void)

    // MARK: - Data Bridge

    /// Get count of remote memos seen by TalkieSync.
    /// Returns -1 when unavailable (distinguishes "unavailable" from "0 records").
    func getRemoteMemoCount(reply: @escaping (_ count: Int) -> Void)

    /// Get latest remote memo trace observed by direct CloudKit sync.
    /// Returns "none" when no memo has been observed yet.
    func getLatestRemoteMemoTrace(reply: @escaping (_ trace: String) -> Void)

    /// Force an immediate sync pass.
    func runSyncPass(reply: @escaping (_ syncedCount: Int, _ error: String?) -> Void)

    /// Fetch audio for a specific memo from CloudKit.
    /// Targeted fetch — doesn't run a full sync.
    func fetchAudioForMemo(_ memoID: String, reply: @escaping (_ success: Bool, _ error: String?) -> Void)

    // MARK: - Lifecycle

    /// Ping to verify connection
    func ping(reply: @escaping (_ pong: Bool) -> Void)

    /// Request graceful shutdown
    func shutdown(reply: @escaping () -> Void)
}

/// Protocol for Talkie to receive callbacks from TalkieSync (Sync → Talkie events)
@objc public protocol TalkieSyncObserverProtocol {
    /// Called when sync operation starts
    func syncDidStart()

    /// Called when sync progress changes
    /// - Parameters:
    ///   - progress: Progress from 0.0 to 1.0
    ///   - message: Human-readable status message
    func syncProgressDidChange(_ progress: Double, _ message: String)

    /// Called when sync operation completes
    /// - Parameter error: Error message if sync failed, nil on success
    func syncDidComplete(_ error: String?)

    /// Called when sync completes with detailed stats (JSON-encoded SyncCompletionStats).
    /// Optional — old Talkie builds that don't implement this won't crash.
    /// - Parameters:
    ///   - statsJSON: JSON-encoded SyncCompletionStats
    ///   - error: Error message if sync failed, nil on success
    @objc optional func syncDidCompleteWithStats(_ statsJSON: Data, error: String?)

    /// Called when new data is available in GRDB after bridge sync
    /// Talkie should refresh its UI from GRDB when this is received
    func newDataAvailable()

    /// Called when iCloud availability changes
    func iCloudAvailabilityDidChange(_ available: Bool)
}

/// Sync completion stats (Codable for JSON over XPC)
/// Contains the real breakdown of what happened during a sync pass.
public struct SyncCompletionStats: Codable, Sendable {
    public let inserted: Int
    public let updated: Int
    public let deleted: Int
    public let skipped: Int
    public let remoteCount: Int
    public let localCount: Int
    public let fetchTimeMs: Int
    public let totalTimeMs: Int
    public let schema: String
    public let syncMode: String  // "full" or "incremental"

    public init(
        inserted: Int,
        updated: Int,
        deleted: Int,
        skipped: Int,
        remoteCount: Int,
        localCount: Int,
        fetchTimeMs: Int,
        totalTimeMs: Int,
        schema: String,
        syncMode: String = "full"
    ) {
        self.inserted = inserted
        self.updated = updated
        self.deleted = deleted
        self.skipped = skipped
        self.remoteCount = remoteCount
        self.localCount = localCount
        self.fetchTimeMs = fetchTimeMs
        self.totalTimeMs = totalTimeMs
        self.schema = schema
        self.syncMode = syncMode
    }

    /// Total items changed (inserted + updated + deleted)
    public var totalChanged: Int { inserted + updated + deleted }

    // Custom decoder: syncMode may be absent in JSON from older TalkieSync builds
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inserted = try container.decode(Int.self, forKey: .inserted)
        updated = try container.decode(Int.self, forKey: .updated)
        deleted = try container.decode(Int.self, forKey: .deleted)
        skipped = try container.decode(Int.self, forKey: .skipped)
        remoteCount = try container.decode(Int.self, forKey: .remoteCount)
        localCount = try container.decode(Int.self, forKey: .localCount)
        fetchTimeMs = try container.decode(Int.self, forKey: .fetchTimeMs)
        totalTimeMs = try container.decode(Int.self, forKey: .totalTimeMs)
        schema = try container.decode(String.self, forKey: .schema)
        syncMode = try container.decodeIfPresent(String.self, forKey: .syncMode) ?? "full"
    }
}

/// Sync status information (Codable for JSON over XPC)
public struct SyncStatusInfo: Codable, Sendable {
    public let status: String           // "idle", "syncing", "completed", "failed"
    public let lastSyncDate: Date?
    public let pendingChanges: Int
    public let iCloudAvailable: Bool
    public let errorMessage: String?
    public let activeProvider: String?  // Currently active provider ID

    public init(
        status: String,
        lastSyncDate: Date?,
        pendingChanges: Int,
        iCloudAvailable: Bool,
        errorMessage: String?,
        activeProvider: String?
    ) {
        self.status = status
        self.lastSyncDate = lastSyncDate
        self.pendingChanges = pendingChanges
        self.iCloudAvailable = iCloudAvailable
        self.errorMessage = errorMessage
        self.activeProvider = activeProvider
    }
}

/// Sync provider information (Codable for JSON over XPC)
public struct SyncProviderInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let isEnabled: Bool
    public let isConnected: Bool
    public let lastSyncDate: Date?
    public let errorMessage: String?

    public init(
        id: String,
        displayName: String,
        isEnabled: Bool,
        isConnected: Bool,
        lastSyncDate: Date?,
        errorMessage: String?
    ) {
        self.id = id
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.isConnected = isConnected
        self.lastSyncDate = lastSyncDate
        self.errorMessage = errorMessage
    }
}
