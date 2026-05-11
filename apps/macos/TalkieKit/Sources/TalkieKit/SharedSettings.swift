//
//  SharedSettings.swift
//  TalkieKit
//
//  Shared settings storage for Talkie + TalkieAgent
//  Both apps read/write to this shared location for settings sync
//

import Foundation

// MARK: - Shared Settings Storage

/// Shared UserDefaults suite name - derived from TalkieEnvironment
public var kTalkieSharedSuiteName: String {
    TalkieEnvironment.current.sharedSettingsSuite
}

/// Shared settings storage instance
/// Use this for all Agent-related settings that need to sync between apps
public var TalkieSharedSettings: UserDefaults {
    UserDefaults(suiteName: TalkieEnvironment.current.sharedSettingsSuite) ?? .standard
}

// MARK: - Default Values

/// Single source of truth for default models and settings
/// All apps (Talkie, TalkieAgent, TalkieEngine) should reference this
public enum TalkieDefaults {

    // MARK: - Transcription Models

    /// Primary dictation model - used for live recording transcription
    /// Fast, accurate, always preloaded by TalkieEngine
    public static let dictationModelId = "parakeet:v3"

    /// Ephemeral/compose model - used for quick voice commands, scratch recordings
    /// Prioritizes speed over accuracy for short utterances
    public static let ephemeralModelId = "parakeet:v3"

    /// Re-transcription model - used when user requests higher quality re-transcription
    /// Can be slower, prioritizes accuracy
    public static let retranscriptionModelId = "parakeet:v3"

    // MARK: - Legacy Aliases

    /// Alias for backwards compatibility - prefer dictationModelId
    public static var transcriptionModelId: String { dictationModelId }
}

// MARK: - Settings Keys

/// Sync-related settings keys
public enum SyncSettingsKey {
    public static let iCloudEnabled = "sync_icloud_enabled"
}

/// All settings keys used by Agent settings
/// Centralized here to ensure consistency between Talkie and Talkie Agent
public enum AgentSettingsKey {
    // MARK: Hotkeys
    public static let hotkey = "hotkey"
    public static let pttHotkey = "pttHotkey"
    public static let pttEnabled = "pttEnabled"
    public static let selectionQuickHotkey = "selectionQuickHotkey"
    public static let captureChordHotkey = "captureChordHotkey"
    public static let screenRecordChordHotkey = "screenRecordChordHotkey"
    public static let pasteChordHotkey = "pasteChordHotkey"
    public static let pasteLastScreenshotHotkey = "hotkeyCapture.pasteLastScreenshot"

    // MARK: Model Selection
    public static let selectedModelId = "selectedModelId"
    public static let selectedTTSVoiceId = "selectedTTSVoiceId"
    public static let whisperModel = "whisperModel"  // Legacy, for migration

    // MARK: Routing & Output
    public static let routingMode = "routingMode"
    public static let returnToOriginAfterPaste = "returnToOriginAfterPaste"
    public static let pressEnterAfterPaste = "pressEnterAfterPaste"
    public static let primaryContextSource = "primaryContextSource"
    public static let contextCaptureDetail = "contextCaptureDetail"
    public static let autoScratchpadOnSelection = "autoScratchpadOnSelection"

    // MARK: Storage
    public static let utteranceTTLHours = "utteranceTTLHours"

    // MARK: Overlay & Pill
    public static let overlayPlacement = "overlayPlacement"
    public static let overlayStyle = "overlayStyle"
    public static let overlayPosition = "overlayPosition"
    public static let pillEnabled = "pillEnabled"
    public static let pillPlacement = "pillPlacement"
    public static let pillPosition = "pillPosition"
    public static let pillShowOnAllScreens = "pillShowOnAllScreens"
    public static let pillExpandsDuringRecording = "pillExpandsDuringRecording"
    public static let notchOverlayEnabled = "notchOverlayEnabled"

    // MARK: Sounds
    public static let startSound = "startSound"
    public static let finishSound = "finishSound"
    public static let pastedSound = "pastedSound"
    public static let cancelledSound = "cancelledSound"  // Dev-only: plays on graceful cancel

    // MARK: Audio
    public static let segmentDuration = "segmentDuration"  // seconds, 0 = disabled
    public static let selectedMicrophoneID = "selectedMicrophoneID"  // Legacy, kept for migration
    public static let selectedMicrophoneUID = "selectedMicrophoneUID"
    public static let selectedMicrophoneName = "selectedMicrophoneName"
    public static let selectedMicrophoneMode = "selectedMicrophoneMode"

    // MARK: Appearance (for TalkieAgent standalone use)
    public static let appearanceMode = "appearanceMode"
    public static let visualTheme = "visualTheme"
    public static let fontSize = "fontSize"
    public static let accentColor = "accentColor"
    // glassMode removed - now a launch arg (--glass-mode)

    // MARK: Dictionary & Text Processing
    public static let dictionaryEnabled = "dictionaryEnabled"
    public static let symbolicMappingEnabled = "symbolicMappingEnabled"
    public static let fillerRemovalEnabled = "fillerRemovalEnabled"

    // MARK: Ambient Mode
    public static let ambientEnabled = "ambientEnabled"
    public static let ambientWakePhrase = "ambientWakePhrase"
    public static let ambientEndPhrase = "ambientEndPhrase"
    public static let ambientCancelPhrase = "ambientCancelPhrase"
    public static let ambientBufferDuration = "ambientBufferDuration"
    public static let ambientEnableChimes = "ambientEnableChimes"
    public static let ambientUseStreamingASR = "ambientUseStreamingASR"
    public static let ambientUseBatchASR = "ambientUseBatchASR"

    // MARK: LLM / Polish
    public static let polishProvider = "polishProvider"      // "anthropic" or "openai"
    public static let polishModel = "polishModel"            // e.g., "gpt-4o-mini", "claude-3-haiku-20240307"
    public static let polishAPIKey = "polishAPIKey"          // Only for explicit override (normally uses encrypted store)

    // MARK: Legacy
    public static let legacyTheme = "theme"

    // MARK: LLM Settings
    public static let llmProviderId = "llmProviderId"
    public static let llmModelId = "llmModelId"
    public static let llmTemperature = "llmTemperature"
    public static let llmMaxTokens = "llmMaxTokens"

    // MARK: API Keys (stored in Keychain, these are just for reference)
    // Actual keys are read via LLMAPIKeyStore
    public static let openaiApiKey = "openai_api_key"
    public static let anthropicApiKey = "anthropic_api_key"
    public static let geminiApiKey = "gemini_api_key"
    public static let groqApiKey = "groq_api_key"
    public static let elevenLabsApiKey = "elevenlabs_api_key"

    // MARK: Interstitial Settings
    public static let askOnInterstitialDismiss = "askOnInterstitialDismiss"

    // MARK: Feature Flags
    public static let featureAmbientModeEnabled = "feature_ambient_mode_enabled"
    public static let featureCaptureEnabled = "feature_capture_enabled"
    public static let featureNotchComposerEnabled = "feature_notch_composer_enabled"
    public static let featureVoiceForegroundingEnabled = "feature_voice_foregrounding_enabled"

    // MARK: Remote Engine
    public static let remoteEngineEnabled = "engine.remoteAccessEnabled"
    public static let remoteEngineHost = "engine.remoteHost"
    public static let remoteEnginePort = "engine.remotePort"  // default 19821

    // MARK: Context Rules
    public static let contextRules = "contextRules"              // JSON array of ContextRule
    public static let contextRulesEnabled = "contextRulesEnabled" // Master toggle

    // MARK: Selection (Quick Selection / Reader)
    public static let selectionEnabled = "selectionEnabled"                          // Bool, master toggle (default: true)
    public static let selectionDefaultMode = "selectionDefaultMode"                  // SelectionMode raw value
    public static let selectionShortTextThreshold = "selectionShortTextThreshold"    // Int: word count for auto verbatim (default: 45)
    public static let selectionTTSVoiceId = "selectionTTSVoiceId"                   // String: nil = use global TTS voice
    public static let selectionLLMTimeout = "selectionLLMTimeout"                    // Double: seconds (default: 6.0)
    public static let selectionShowFeedbackOverlay = "selectionShowFeedbackOverlay"  // Bool (default: true)
    public static let selectionAppOverrides = "selectionAppOverrides"                // JSON: per-category mode overrides
    public static let selectionCaptureScreenshot = "selectionCaptureScreenshot"      // Bool: capture source window screenshot
    public static let selectionKeepHistory = "selectionKeepHistory"                  // Bool: store readouts in library

    // MARK: Selection capture fallbacks
    /// Comma-separated bundle IDs where synthetic ⌘C is skipped. Default empty.
    public static let selectionClipboardFallbackBlocklist = "selectionClipboardFallbackBlocklist"
    /// Bool: if AX + clipboard both fail, offer OCR region picker. Default true.
    public static let selectionOCRFallbackEnabled = "selectionOCRFallbackEnabled"
}

// MARK: - Selection Mode

/// How selected text is processed before TTS readback
public enum SelectionMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto          // Decide based on source app and text length
    case verbatim      // Read the text exactly as selected
    case summary       // Condense into a brief spoken summary
    case explanation   // Explain what the text means

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .verbatim: return "Verbatim"
        case .summary: return "Summary"
        case .explanation: return "Explanation"
        }
    }

    public var description: String {
        switch self {
        case .auto: return "Decide based on source app and text length"
        case .verbatim: return "Read the text exactly as selected"
        case .summary: return "Condense into a brief spoken summary"
        case .explanation: return "Explain what the text means"
        }
    }
}

// MARK: - Selection App Category Overrides

/// Per-app-category mode override for selection processing
public struct SelectionAppCategoryOverride: Codable, Identifiable, Sendable {
    public let id: String           // Category key: "terminals", "browsers", "code", "documents"
    public var label: String        // Display name
    public var mode: SelectionMode
    public var enabled: Bool

    public init(id: String, label: String, mode: SelectionMode, enabled: Bool = true) {
        self.id = id
        self.label = label
        self.mode = mode
        self.enabled = enabled
    }

    /// Built-in defaults matching current hardcoded behavior
    public static let defaults: [SelectionAppCategoryOverride] = [
        .init(id: "terminals", label: "Terminals", mode: .explanation),
        .init(id: "code", label: "Code Editors", mode: .explanation),
        .init(id: "browsers", label: "Browsers", mode: .summary),
        .init(id: "documents", label: "Documents", mode: .summary),
    ]
}

@available(*, deprecated, renamed: "AgentSettingsKey")
public typealias LiveSettingsKey = AgentSettingsKey

// MARK: - Migration Helper

/// Migrate a value from legacy UserDefaults.standard to shared settings
/// Returns the value (from shared if exists, else migrated from legacy)
public func migrateToSharedDefaults<T>(key: String, defaultValue: T) -> T {
    let shared = TalkieSharedSettings
    let legacy = UserDefaults.standard

    // Already in shared storage?
    if let value = shared.object(forKey: key) as? T {
        return value
    }

    // Migrate from legacy
    if let legacyValue = legacy.object(forKey: key) as? T {
        shared.set(legacyValue, forKey: key)
        legacy.removeObject(forKey: key)
        return legacyValue
    }

    // Use default
    return defaultValue
}

/// Migrate Data values (for Codable types like HotkeyConfig)
public func migrateDataToSharedDefaults(key: String) -> Data? {
    let shared = TalkieSharedSettings
    let legacy = UserDefaults.standard

    // Already in shared storage?
    if let value = shared.data(forKey: key) {
        return value
    }

    // Migrate from legacy
    if let legacyValue = legacy.data(forKey: key) {
        shared.set(legacyValue, forKey: key)
        legacy.removeObject(forKey: key)
        return legacyValue
    }

    return nil
}
