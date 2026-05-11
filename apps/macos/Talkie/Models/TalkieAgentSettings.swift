//
//  AgentSettings.swift
//  TalkieAgent
//
//  Settings for Talkie Agent
//

import Foundation
import SwiftUI
import TalkieKit
import Carbon.HIToolbox
import Observation

// MARK: - Appearance Types (from TalkieKit)
// OverlayStyle, IndicatorPosition, PillPosition are now in TalkieKit

// Legacy compatibility alias
typealias OverlayPosition = IndicatorPosition

// MARK: - Appearance Mode (Light/Dark/System)
// NOTE: Using AppearanceMode from Talkie's SettingsManager to avoid duplication

// MARK: - Visual Theme (Color Schemes)

enum VisualTheme: String, CaseIterable, Codable {
    case live = "live"          // Maps to talkiePro
    case midnight = "midnight"  // Maps to talkiePro (legacy)
    case technical = "linear"
    case terminal = "terminal"
    case minimal = "minimal"
    case warm = "warm"          // Maps to warm theme

    var displayName: String {
        switch self {
        case .live: return "Pro"
        case .midnight: return "Pro"
        case .technical: return "Technical"
        case .terminal: return "Terminal"
        case .minimal: return "Minimal"
        case .warm: return "Warm"
        }
    }

    var description: String {
        switch self {
        case .live: return "Professional dark theme"
        case .midnight: return "Professional dark theme"
        case .technical: return "True black, Vercel-inspired"
        case .terminal: return "Clean monospace, sharp corners"
        case .minimal: return "Light and subtle"
        case .warm: return "Cozy dark mode with orange tones"
        }
    }

    /// Default accent color for this theme
    var accentColor: AccentColorOption {
        switch self {
        case .live: return .blue
        case .midnight: return .blue
        case .technical: return .blue
        case .terminal: return .gray    // No gimmicks
        case .minimal: return .gray
        case .warm: return .orange
        }
    }

    /// Suggested appearance mode for this theme (user can override)
    var suggestedAppearance: AppearanceMode {
        switch self {
        case .live: return .dark
        case .midnight: return .dark
        case .technical: return .dark
        case .terminal: return .dark
        case .minimal: return .system
        case .warm: return .dark
        }
    }

    /// Preview colors for theme selector
    var previewColors: (bg: Color, fg: Color, accent: Color) {
        switch self {
        case .live:
            return (Color(white: 0.08), Color.white.opacity(0.85), Color.blue)
        case .midnight:
            return (Color(white: 0.08), Color.white.opacity(0.85), Color(red: 0.4, green: 0.7, blue: 1.0))
        case .technical:
            return (Color.black, Color.white, Color(red: 0.0, green: 0.83, blue: 1.0))
        case .terminal:
            // Ghostty-style: black bg, light gray text, subtle gray accent
            return (Color.black, Color(white: 0.85), Color(white: 0.5))
        case .minimal:
            return (Color(white: 0.96), Color(white: 0.2), Color.gray)
        case .warm:
            return (Color(red: 0.1, green: 0.08, blue: 0.06), Color(white: 0.9), Color.orange)
        }
    }
}

// Legacy compatibility - maps to new system
@available(*, deprecated, message: "Use AppearanceMode and VisualTheme instead")
typealias AppTheme = AppearanceMode

/// Design system font sizes - canonical integer sizes, no fractional scaling
/// Each size tier defines proper integer point sizes for crisp rendering
enum FontSize: String, CaseIterable, Codable, CustomStringConvertible {
    case small = "small"
    case medium = "medium"
    case large = "large"

    var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var description: String {
        displayName
    }

    // MARK: - Design System Sizes (integers only, no scaling)

    /// Extra-small: metadata, timestamps, labels
    var xs: CGFloat {
        switch self {
        case .small: return 9
        case .medium: return 10
        case .large: return 11
        }
    }

    /// Small: secondary text, captions
    var sm: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 11
        case .large: return 12
        }
    }

    /// Body: primary transcription text
    var body: CGFloat {
        switch self {
        case .small: return 12
        case .medium: return 13
        case .large: return 15
        }
    }

    /// Detail: expanded view text
    var detail: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 14
        case .large: return 16
        }
    }

    /// Title: headings
    var title: CGFloat {
        switch self {
        case .small: return 14
        case .medium: return 15
        case .large: return 17
        }
    }

    // MARK: - Convenience Font Accessors

    var xsFont: Font { .system(size: xs) }
    var smFont: Font { .system(size: sm) }
    var bodyFont: Font { .system(size: body) }
    var detailFont: Font { .system(size: detail) }
    var titleFont: Font { .system(size: title, weight: .medium) }

    // Legacy compatibility
    var previewSize: CGFloat { body }
}

// NOTE: Using AccentColorOption from Talkie's SettingsManager to avoid duplication

// NOTE: ThemePreset defined in Talkie's SettingsManager

// MARK: - Context Preference

/// Which app context is considered "primary" for dictations
enum PrimaryContextSource: String, CaseIterable, Codable {
    case startApp = "startApp"
    case endApp = "endApp"

    var displayName: String {
        switch self {
        case .startApp: return "Where I Started"
        case .endApp: return "Where I Finished"
        }
    }

    var description: String {
        switch self {
        case .startApp: return "App where you pressed the hotkey"
        case .endApp: return "App where you were when recording stopped"
        }
    }
}

// MARK: - Hotkey Configuration

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// Toggle hotkey default: ⌥⌘L
    static let `default` = HotkeyConfig(
        keyCode: 37,  // L
        modifiers: UInt32(cmdKey | optionKey)  // ⌥⌘
    )

    /// Push-to-talk hotkey default: ⌥⌘; (semicolon, right next to L)
    static let defaultPTT = HotkeyConfig(
        keyCode: 41,  // ; (semicolon)
        modifiers: UInt32(cmdKey | optionKey)  // ⌥⌘
    )

    /// Quick selection action default: ⌥⌘Y
    static let defaultSelectionQuick = HotkeyConfig(
        keyCode: 16,  // Y
        modifiers: UInt32(cmdKey | optionKey)  // ⌥⌘
    )

    /// Capture chord default: Hyper+S (⌘⌥⌃⇧+S)
    static let defaultCaptureChord = HotkeyConfig(
        keyCode: 1,   // S
        modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey)  // Hyper
    )

    /// Screen record chord default: Hyper+R (⌘⌥⌃⇧+R)
    static let defaultScreenRecordChord = HotkeyConfig(
        keyCode: 15,  // R
        modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey)  // Hyper
    )

    /// Paste chord default: Hyper+V (⌘⌥⌃⇧+V)
    static let defaultPasteChord = HotkeyConfig(
        keyCode: 9,   // V
        modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey)  // Hyper
    )

    /// Load a hotkey config directly from TalkieSharedSettings (no actor isolation needed)
    static func fromSharedSettings(key: String, `default` fallback: HotkeyConfig) -> HotkeyConfig {
        guard let data = TalkieSharedSettings.data(forKey: key),
              let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) else {
            return fallback
        }
        return config
    }

    /// Convert Carbon modifiers to NSEvent.ModifierFlags for local event matching
    var nsModifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        return flags
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ code: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 41: ";", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
            49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc"
        ]
        return keyMap[code] ?? "?"
    }
}

// MARK: - Live Settings

@Observable
@MainActor
final class AgentSettings {
    static let shared = AgentSettings()

    // MARK: - Shared Settings Storage
    // Uses TalkieSharedSettings from TalkieKit for cross-app sync with TalkieAgent
    private var storage: UserDefaults { TalkieSharedSettings }
    @ObservationIgnored private var isSynchronizingPlacements = false

    // MARK: - Published Settings

    /// Toggle hotkey (press to start, press to stop)
    var hotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Push-to-talk hotkey (hold to record, release to stop)
    var pttHotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Whether push-to-talk hotkey is enabled
    var pttEnabled: Bool {
        didSet { save() }
    }

    /// Quick selection action hotkey (default: ⌥⌘Y)
    var selectionQuickHotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Capture chord hotkey (default: Hyper+S)
    var captureChordHotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Screen record chord hotkey (default: Hyper+R)
    var screenRecordChordHotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Selected model ID with family prefix (e.g., "whisper:openai_whisper-small" or "parakeet:v3")
    /// NOTE: This now delegates to SettingsManager for centralized model management
    var selectedModelId: String {
        get { SettingsManager.shared.liveTranscriptionModelId }
        set { SettingsManager.shared.liveTranscriptionModelId = newValue }
    }

    /// Legacy property for backwards compatibility - maps to selectedModelId
    @available(*, deprecated, message: "Use selectedModelId instead")
    var whisperModel: WhisperModel {
        get {
            // Extract model ID from selectedModelId and try to match
            let (_, modelId) = ModelInfo.parseModelId(selectedModelId)
            return WhisperModel(rawValue: modelId) ?? .small
        }
        set {
            selectedModelId = "whisper:\(newValue.rawValue)"
        }
    }

    var routingMode: RoutingMode {
        didSet { save() }
    }

    /// Selected microphone device ID (0 = system default)
    /// Legacy: kept for migration, prefer using selectedMicrophoneUID
    var selectedMicrophoneID: UInt32 {
        didSet { save() }
    }

    /// Microphone selection mode (system default vs fixed device)
    var selectedMicrophoneMode: MicrophoneSelectionMode {
        didSet { save() }
    }

    /// Persistent UID of selected microphone (survives reconnects)
    var selectedMicrophoneUID: String? {
        didSet { save() }
    }

    /// Display name of selected microphone (for UI when device is unavailable)
    var selectedMicrophoneName: String? {
        didSet { save() }
    }

    var utteranceTTLHours: Int {
        didSet {
            save()
            DictationStore.shared.ttlHours = utteranceTTLHours
        }
    }

    var overlayStyle: OverlayStyle {
        didSet { save() }
    }

    var overlayPosition: OverlayPosition {
        didSet {
            guard !isSynchronizingPlacements else { return }
            withPlacementSynchronization {
                overlayPlacement = NormalizedPlacement(indicatorPosition: overlayPosition)
            }
            save()
        }
    }

    var overlayPlacement: NormalizedPlacement {
        didSet {
            guard !isSynchronizingPlacements else { return }
            withPlacementSynchronization {
                overlayPosition = overlayPlacement.nearestIndicatorPosition
            }
            save()
        }
    }

    var pillEnabled: Bool {
        didSet { save() }
    }

    // Floating Pill Settings
    var pillPosition: PillPosition {
        didSet {
            guard !isSynchronizingPlacements else { return }
            withPlacementSynchronization {
                pillPlacement = NormalizedPlacement(pillPosition: pillPosition)
            }
            save()
        }
    }

    var pillPlacement: NormalizedPlacement {
        didSet {
            guard !isSynchronizingPlacements else { return }
            withPlacementSynchronization {
                pillPosition = pillPlacement.nearestPillPosition
            }
            save()
        }
    }

    var pillShowOnAllScreens: Bool {
        didSet { save() }
    }

    var pillExpandsDuringRecording: Bool {
        didSet { save() }
    }

    var startSound: TalkieSound {
        didSet { save() }
    }

    var finishSound: TalkieSound {
        didSet { save() }
    }

    var pastedSound: TalkieSound {
        didSet { save() }
    }

    // MARK: - Appearance (delegated to global SettingsManager)

    /// Appearance mode - delegates to global settings
    var appearanceMode: AppearanceMode {
        get { SettingsManager.shared.appearanceMode }
        set { SettingsManager.shared.appearanceMode = newValue }
    }

    /// Visual theme - maps to global ThemePreset
    var visualTheme: VisualTheme {
        get {
            guard let theme = SettingsManager.shared.currentTheme else { return .live }
            switch theme {
            case .talkiePro: return .midnight
            case .technical: return .technical
            case .terminal: return .terminal
            case .minimal: return .minimal
            case .classic: return .live
            case .warm: return .warm
            case .liquidGlass: return .midnight  // Deep dark for glass to pop
            }
        }
        set {
            let preset: ThemePreset
            switch newValue {
            case .live: preset = .talkiePro
            case .midnight: preset = .talkiePro
            case .technical: preset = .technical
            case .terminal: preset = .terminal
            case .minimal: preset = .minimal
            case .warm: preset = .warm
            }
            SettingsManager.shared.applyTheme(preset)
        }
    }

    /// Font size - delegates to global settings
    var fontSize: FontSize {
        get {
            switch SettingsManager.shared.uiFontSize {
            case .small: return .small
            case .medium: return .medium
            case .large: return .large
            }
        }
        set {
            switch newValue {
            case .small: SettingsManager.shared.uiFontSize = .small
            case .medium: SettingsManager.shared.uiFontSize = .medium
            case .large: SettingsManager.shared.uiFontSize = .large
            }
        }
    }

    /// Accent color - delegates to global settings
    var accentColor: AccentColorOption {
        get { SettingsManager.shared.accentColor }
        set { SettingsManager.shared.accentColor = newValue }
    }

    /// Which context (start or end app) is primary for dictations
    var primaryContextSource: PrimaryContextSource {
        didSet { save() }
    }

    /// How much context to capture from the Accessibility API
    var contextCaptureDetail: ContextCaptureDetail {
        didSet { save() }
    }

    /// Session-scoped permission for capturing context (resets on app restart)
    var contextCaptureSessionAllowed: Bool = true

    /// Whether to activate the start app after pasting
    var returnToOriginAfterPaste: Bool {
        didSet { save() }
    }

    /// Legacy setting kept for compatibility; selected text now pastes in place.
    var autoScratchpadOnSelection: Bool {
        didSet { save() }
    }

    // MARK: - Selection (Quick Selection / Reader)

    /// Master toggle for selection feature
    var selectionEnabled: Bool {
        didSet { save() }
    }

    /// Default processing mode
    var selectionDefaultMode: SelectionMode {
        didSet { save() }
    }

    /// Word count threshold for auto-verbatim in auto mode
    var selectionShortTextThreshold: Int {
        didSet { save() }
    }

    /// Dedicated TTS voice for selection (nil = use global)
    var selectionTTSVoiceId: String? {
        didSet { save() }
    }

    /// LLM timeout in seconds
    var selectionLLMTimeout: Double {
        didSet { save() }
    }

    /// Show feedback overlay HUD
    var selectionShowFeedbackOverlay: Bool {
        didSet { save() }
    }

    /// Per-app-category mode overrides
    var selectionAppOverrides: [SelectionAppCategoryOverride] {
        didSet { save() }
    }

    /// Capture a screenshot of the source window
    var selectionCaptureScreenshot: Bool {
        didSet { save() }
    }

    /// Keep readout history in the library
    var selectionKeepHistory: Bool {
        didSet { save() }
    }

    // Legacy compatibility - returns appearance mode
    @available(*, deprecated, message: "Use appearanceMode instead")
    var theme: AppearanceMode {
        get { appearanceMode }
        set { appearanceMode = newValue }
    }

    // MARK: - Init

    private init() {
        StartupProfiler.shared.mark("singleton.AgentSettings.start")
        // Use TalkieSharedSettings directly (can't use storage computed property before self is initialized)
        let store = TalkieSharedSettings

        // Load toggle hotkey (with migration from legacy UserDefaults.standard)
        if let data = migrateDataToSharedDefaults(key: AgentSettingsKey.hotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.hotkey = config
        } else {
            self.hotkey = .default
        }

        // Load push-to-talk hotkey
        if let data = migrateDataToSharedDefaults(key: AgentSettingsKey.pttHotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.pttHotkey = config
        } else {
            self.pttHotkey = .defaultPTT
        }

        // Load PTT enabled state (default: false)
        self.pttEnabled = migrateToSharedDefaults(key: AgentSettingsKey.pttEnabled, defaultValue: false)

        // Load quick selection hotkey
        if let data = store.data(forKey: AgentSettingsKey.selectionQuickHotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.selectionQuickHotkey = config
        } else {
            self.selectionQuickHotkey = .defaultSelectionQuick
        }

        // Load capture chord hotkeys
        if let data = store.data(forKey: AgentSettingsKey.captureChordHotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.captureChordHotkey = config
        } else {
            self.captureChordHotkey = .defaultCaptureChord
        }
        if let data = store.data(forKey: AgentSettingsKey.screenRecordChordHotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.screenRecordChordHotkey = config
        } else {
            self.screenRecordChordHotkey = .defaultScreenRecordChord
        }

        // Note: selectedModelId is now managed by SettingsManager, no need to load here

        // Load routing mode
        let routingRaw: String = migrateToSharedDefaults(key: AgentSettingsKey.routingMode, defaultValue: "paste")
        self.routingMode = routingRaw == "clipboardOnly" ? .clipboardOnly : .paste

        // Load selected microphone (0 = system default)
        let savedMicID = UInt32(migrateToSharedDefaults(key: AgentSettingsKey.selectedMicrophoneID, defaultValue: 0))
        self.selectedMicrophoneID = savedMicID

        // Load new UID-based microphone selection
        let savedUID = store.string(forKey: AgentSettingsKey.selectedMicrophoneUID)
        self.selectedMicrophoneUID = savedUID
        self.selectedMicrophoneName = store.string(forKey: AgentSettingsKey.selectedMicrophoneName)

        // Track if we need migration (mode key doesn't exist yet)
        let needsMigration = store.string(forKey: AgentSettingsKey.selectedMicrophoneMode) == nil

        if let modeRaw = store.string(forKey: AgentSettingsKey.selectedMicrophoneMode),
           let mode = MicrophoneSelectionMode(rawValue: modeRaw) {
            // Validate: if mode is fixedUID but no UID exists, reset to systemDefault
            if mode == .fixedUID && savedUID == nil {
                self.selectedMicrophoneMode = .systemDefault
                store.set(MicrophoneSelectionMode.systemDefault.rawValue, forKey: AgentSettingsKey.selectedMicrophoneMode)
                Log(.audio).info("Reset mic mode to systemDefault (fixedUID with no UID)")
            } else {
                self.selectedMicrophoneMode = mode
            }
        } else {
            // Migration: only use fixedUID mode if we have a UID, otherwise default to systemDefault
            // Legacy ID-based selection can't be migrated without UID, user will need to re-select
            let migratedMode: MicrophoneSelectionMode = (savedUID != nil) ? .fixedUID : .systemDefault
            self.selectedMicrophoneMode = migratedMode
            // Persist immediately so other processes see the correct value
            store.set(migratedMode.rawValue, forKey: AgentSettingsKey.selectedMicrophoneMode)
            if needsMigration {
                Log(.audio).info("Migrated mic mode to \(migratedMode.rawValue)")
            }
        }

        // Load TTL (default 48 hours)
        let ttl: Int = migrateToSharedDefaults(key: AgentSettingsKey.utteranceTTLHours, defaultValue: 48)
        self.utteranceTTLHours = ttl > 0 ? ttl : 48

        // Load overlay settings (direct access - migrateToSharedDefaults has type casting issues with enums)
        // Default to pillOnly for minimal visual footprint - users can enable particles/waveform in settings
        self.overlayStyle = store.string(forKey: AgentSettingsKey.overlayStyle).flatMap(OverlayStyle.init) ?? .pillOnly
        let overlayPosition = store.string(forKey: AgentSettingsKey.overlayPosition).flatMap(IndicatorPosition.init) ?? .topCenter
        self.overlayPosition = overlayPosition
        let overlayPlacement = Self.decodePlacement(
            forKey: AgentSettingsKey.overlayPlacement,
            from: store
        ) ?? NormalizedPlacement(indicatorPosition: overlayPosition)
        self.overlayPlacement = overlayPlacement
            .migratingLegacyIndicatorAnchor(for: overlayPosition)
            .snappedToNearestIndicatorAnchor()
        self.pillEnabled = store.object(forKey: AgentSettingsKey.pillEnabled) as? Bool ?? true
        let pillPosition = store.string(forKey: AgentSettingsKey.pillPosition).flatMap(PillPosition.init) ?? .bottomCenter
        self.pillPosition = pillPosition
        let pillPlacement = Self.decodePlacement(
            forKey: AgentSettingsKey.pillPlacement,
            from: store
        ) ?? NormalizedPlacement(pillPosition: pillPosition)
        self.pillPlacement = pillPlacement
            .migratingLegacyPillAnchor(for: pillPosition)
            .snappedToNearestPillAnchor()

        // Load pill settings
        // pillShowOnAllScreens: true by default - the floating pill is the primary visual indicator
        self.pillShowOnAllScreens = migrateToSharedDefaults(key: AgentSettingsKey.pillShowOnAllScreens, defaultValue: true)
        self.pillExpandsDuringRecording = migrateToSharedDefaults(key: AgentSettingsKey.pillExpandsDuringRecording, defaultValue: true)
        // Load sounds
        self.startSound = store.string(forKey: AgentSettingsKey.startSound).flatMap(TalkieSound.init) ?? .pop
        self.finishSound = store.string(forKey: AgentSettingsKey.finishSound).flatMap(TalkieSound.init) ?? .pop
        self.pastedSound = store.string(forKey: AgentSettingsKey.pastedSound).flatMap(TalkieSound.init) ?? .tink

        // Note: Appearance settings (appearanceMode, visualTheme, fontSize, accentColor)
        // are now computed properties delegating to SettingsManager, no loading needed

        // Load context settings
        self.primaryContextSource = store.string(forKey: AgentSettingsKey.primaryContextSource).flatMap(PrimaryContextSource.init) ?? .startApp
        self.contextCaptureDetail = store.string(forKey: AgentSettingsKey.contextCaptureDetail).flatMap(ContextCaptureDetail.init) ?? .rich

        // Load return to origin setting (default: false)
        self.returnToOriginAfterPaste = migrateToSharedDefaults(key: AgentSettingsKey.returnToOriginAfterPaste, defaultValue: false)

        // Load legacy selection-routing setting for migration compatibility.
        self.autoScratchpadOnSelection = store.bool(forKey: AgentSettingsKey.autoScratchpadOnSelection)

        // Load selection settings
        self.selectionEnabled = store.object(forKey: AgentSettingsKey.selectionEnabled) as? Bool ?? true
        self.selectionDefaultMode = store.string(forKey: AgentSettingsKey.selectionDefaultMode).flatMap(SelectionMode.init) ?? .auto
        let threshold = store.integer(forKey: AgentSettingsKey.selectionShortTextThreshold)
        self.selectionShortTextThreshold = threshold > 0 ? threshold : 45
        let storedSelectionVoiceId = store.string(forKey: AgentSettingsKey.selectionTTSVoiceId)
        self.selectionTTSVoiceId = storedSelectionVoiceId?.hasPrefix("kokoro:") == true ? nil : storedSelectionVoiceId
        let timeout = store.double(forKey: AgentSettingsKey.selectionLLMTimeout)
        self.selectionLLMTimeout = timeout > 0 ? timeout : 6.0
        self.selectionShowFeedbackOverlay = store.object(forKey: AgentSettingsKey.selectionShowFeedbackOverlay) as? Bool ?? true
        if let data = store.data(forKey: AgentSettingsKey.selectionAppOverrides),
           let overrides = try? JSONDecoder().decode([SelectionAppCategoryOverride].self, from: data) {
            self.selectionAppOverrides = overrides
        } else {
            self.selectionAppOverrides = SelectionAppCategoryOverride.defaults
        }
        self.selectionCaptureScreenshot = store.object(forKey: AgentSettingsKey.selectionCaptureScreenshot) as? Bool ?? false
        self.selectionKeepHistory = store.object(forKey: AgentSettingsKey.selectionKeepHistory) as? Bool ?? true

        // Apply TTL to store
        DictationStore.shared.ttlHours = utteranceTTLHours
        StartupProfiler.shared.mark("singleton.AgentSettings.done")

        #if DEBUG
        dumpSettingsToFile()
        #endif
    }

    // MARK: - Debug

    #if DEBUG
    private func dumpSettingsToFile() {
        let settings: [String: Any] = [
            "microphone": [
                "id": selectedMicrophoneID,
                "mode": selectedMicrophoneMode.rawValue,
                "uid": selectedMicrophoneUID ?? "(nil)",
                "name": selectedMicrophoneName ?? "(nil)"
            ],
            "model": selectedModelId,
            "routing": routingMode.rawValue,
            "hotkey": hotkey.displayString,
            "pttHotkey": pttHotkey.displayString,
            "pttEnabled": pttEnabled,
            "overlay": [
                "style": overlayStyle.rawValue,
                "position": overlayPosition.rawValue,
                "placement": ["x": overlayPlacement.x, "y": overlayPlacement.y],
                "pillEnabled": pillEnabled,
                "pillPosition": pillPosition.rawValue,
                "pillPlacement": ["x": pillPlacement.x, "y": pillPlacement.y],
                "pillShowOnAllScreens": pillShowOnAllScreens,
                "pillExpandsDuringRecording": pillExpandsDuringRecording,
            ],
            "sounds": [
                "start": startSound.rawValue,
                "finish": finishSound.rawValue,
                "pasted": pastedSound.rawValue
            ],
            "appearance": [
                "mode": appearanceMode.rawValue,
                "theme": visualTheme.rawValue,
                "fontSize": fontSize.rawValue,
                "accentColor": accentColor.rawValue
            ],
            "context": [
                "primarySource": primaryContextSource.rawValue,
                "captureDetail": contextCaptureDetail.rawValue
            ],
            "behavior": [
                "returnToOriginAfterPaste": returnToOriginAfterPaste,
                "autoScratchpadOnSelection": autoScratchpadOnSelection
            ],
            "utteranceTTLHours": utteranceTTLHours,
            "_dumpedAt": Date().iso8601
        ]

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("Talkie")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let file = tmpDir.appendingPathComponent("settings-dump.json")

        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file)
        }
    }
    #endif

    // MARK: - Persistence

    private func save() {
        // Save to shared storage for cross-app sync with TalkieAgent
        if let data = try? JSONEncoder().encode(hotkey) {
            storage.set(data, forKey: AgentSettingsKey.hotkey)
        }
        if let data = try? JSONEncoder().encode(pttHotkey) {
            storage.set(data, forKey: AgentSettingsKey.pttHotkey)
        }
        storage.set(pttEnabled, forKey: AgentSettingsKey.pttEnabled)
        if let data = try? JSONEncoder().encode(selectionQuickHotkey) {
            storage.set(data, forKey: AgentSettingsKey.selectionQuickHotkey)
        }
        if let data = try? JSONEncoder().encode(captureChordHotkey) {
            storage.set(data, forKey: AgentSettingsKey.captureChordHotkey)
        }
        if let data = try? JSONEncoder().encode(screenRecordChordHotkey) {
            storage.set(data, forKey: AgentSettingsKey.screenRecordChordHotkey)
        }
        // Note: selectedModelId is now managed by SettingsManager, no need to save here
        storage.set(routingMode == .clipboardOnly ? "clipboardOnly" : "paste", forKey: AgentSettingsKey.routingMode)
        storage.set(Int(selectedMicrophoneID), forKey: AgentSettingsKey.selectedMicrophoneID)
        storage.set(selectedMicrophoneMode.rawValue, forKey: AgentSettingsKey.selectedMicrophoneMode)
        storage.set(selectedMicrophoneUID, forKey: AgentSettingsKey.selectedMicrophoneUID)
        storage.set(selectedMicrophoneName, forKey: AgentSettingsKey.selectedMicrophoneName)
        storage.set(utteranceTTLHours, forKey: AgentSettingsKey.utteranceTTLHours)
        storage.set(overlayStyle.rawValue, forKey: AgentSettingsKey.overlayStyle)
        storage.set(overlayPosition.rawValue, forKey: AgentSettingsKey.overlayPosition)
        if let data = try? JSONEncoder().encode(overlayPlacement) {
            storage.set(data, forKey: AgentSettingsKey.overlayPlacement)
        }
        storage.set(pillEnabled, forKey: AgentSettingsKey.pillEnabled)
        storage.set(pillPosition.rawValue, forKey: AgentSettingsKey.pillPosition)
        if let data = try? JSONEncoder().encode(pillPlacement) {
            storage.set(data, forKey: AgentSettingsKey.pillPlacement)
        }
        storage.set(pillShowOnAllScreens, forKey: AgentSettingsKey.pillShowOnAllScreens)
        storage.set(pillExpandsDuringRecording, forKey: AgentSettingsKey.pillExpandsDuringRecording)
        storage.set(startSound.rawValue, forKey: AgentSettingsKey.startSound)
        storage.set(finishSound.rawValue, forKey: AgentSettingsKey.finishSound)
        storage.set(pastedSound.rawValue, forKey: AgentSettingsKey.pastedSound)
        // Note: appearance settings (appearanceMode, visualTheme, fontSize, accentColor)
        // are now delegated to SettingsManager and saved there
        storage.set(primaryContextSource.rawValue, forKey: AgentSettingsKey.primaryContextSource)
        storage.set(contextCaptureDetail.rawValue, forKey: AgentSettingsKey.contextCaptureDetail)
        storage.set(returnToOriginAfterPaste, forKey: AgentSettingsKey.returnToOriginAfterPaste)
        storage.set(autoScratchpadOnSelection, forKey: AgentSettingsKey.autoScratchpadOnSelection)

        // Selection settings
        storage.set(selectionEnabled, forKey: AgentSettingsKey.selectionEnabled)
        storage.set(selectionDefaultMode.rawValue, forKey: AgentSettingsKey.selectionDefaultMode)
        storage.set(selectionShortTextThreshold, forKey: AgentSettingsKey.selectionShortTextThreshold)
        storage.set(selectionTTSVoiceId, forKey: AgentSettingsKey.selectionTTSVoiceId)
        storage.set(selectionLLMTimeout, forKey: AgentSettingsKey.selectionLLMTimeout)
        storage.set(selectionShowFeedbackOverlay, forKey: AgentSettingsKey.selectionShowFeedbackOverlay)
        if let data = try? JSONEncoder().encode(selectionAppOverrides) {
            storage.set(data, forKey: AgentSettingsKey.selectionAppOverrides)
        }
        storage.set(selectionCaptureScreenshot, forKey: AgentSettingsKey.selectionCaptureScreenshot)
        storage.set(selectionKeepHistory, forKey: AgentSettingsKey.selectionKeepHistory)

        #if DEBUG
        dumpSettingsToFile()
        #endif
    }

    private func withPlacementSynchronization(_ updates: () -> Void) {
        isSynchronizingPlacements = true
        updates()
        isSynchronizingPlacements = false
    }

    private static func decodePlacement(forKey key: String, from store: UserDefaults) -> NormalizedPlacement? {
        guard let data = store.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NormalizedPlacement.self, from: data)
    }

    // MARK: - Appearance Application

    /// Apply appearance mode - delegates to SettingsManager
    func applyAppearance() {
        SettingsManager.shared.applyAppearanceMode()
    }

    /// Apply a visual theme preset - delegates to SettingsManager
    func applyVisualTheme(_ theme: VisualTheme) {
        self.visualTheme = theme  // Uses the computed property which delegates to SettingsManager
    }

    /// Effective accent color - delegates to SettingsManager
    var effectiveAccentColor: Color {
        SettingsManager.shared.resolvedAccentColor
    }
}

@available(*, deprecated, renamed: "AgentSettings")
typealias LiveSettings = AgentSettings

// MARK: - Stub types (simplified for Talkie integration)

// NOTE: RoutingMode is defined in RoutingMode.swift
// NOTE: TalkieSound is defined in SoundManager.swift
// NOTE: ContextCaptureDetail is defined in ContextCaptureService.swift
// NOTE: ModelInfo is defined in EngineClient.swift
