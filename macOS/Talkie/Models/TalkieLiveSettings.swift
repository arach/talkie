//
//  LiveSettings.swift
//  TalkieLive
//
//  Settings for Talkie Live
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
    case live = "live"
    case midnight = "midnight"
    case linear = "linear"
    case terminal = "terminal"
    case warm = "warm"
    case minimal = "minimal"

    var displayName: String {
        switch self {
        case .live: return "Live"
        case .midnight: return "Midnight"
        case .linear: return "Linear"
        case .terminal: return "Terminal"
        case .warm: return "Warm"
        case .minimal: return "Minimal"
        }
    }

    var description: String {
        switch self {
        case .live: return "Default blue accent"
        case .midnight: return "Deep black, high contrast"
        case .linear: return "True black, Vercel-inspired"
        case .terminal: return "Green on black"
        case .warm: return "Cozy orange tones"
        case .minimal: return "Clean and subtle"
        }
    }

    /// Default accent color for this theme
    var accentColor: AccentColorOption {
        switch self {
        case .live: return .blue
        case .midnight: return .blue
        case .linear: return .blue
        case .terminal: return .green
        case .warm: return .orange
        case .minimal: return .gray
        }
    }

    /// Suggested appearance mode for this theme (user can override)
    var suggestedAppearance: AppearanceMode {
        switch self {
        case .live: return .dark
        case .midnight: return .dark
        case .linear: return .dark
        case .terminal: return .dark
        case .warm: return .dark
        case .minimal: return .system
        }
    }

    /// Preview colors for theme selector
    var previewColors: (bg: Color, fg: Color, accent: Color) {
        switch self {
        case .live:
            return (Color(white: 0.1), Color.white.opacity(0.9), Color.blue)
        case .midnight:
            return (Color.black, Color.white.opacity(0.85), Color(red: 0.4, green: 0.7, blue: 1.0))
        case .linear:
            return (Color.black, Color.white, Color(red: 0.0, green: 0.83, blue: 1.0))
        case .terminal:
            return (Color.black, Color.green.opacity(0.9), Color.green)
        case .warm:
            return (Color(red: 0.1, green: 0.08, blue: 0.06), Color.white.opacity(0.9), Color.orange)
        case .minimal:
            return (Color(white: 0.95), Color.black.opacity(0.8), Color.gray)
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
final class LiveSettings {
    static let shared = LiveSettings()

    // MARK: - Shared Settings Storage
    // Uses TalkieSharedSettings from TalkieKit for cross-app sync with TalkieLive
    private var storage: UserDefaults { TalkieSharedSettings }

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
    var selectedMicrophoneID: UInt32 {
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
        didSet { save() }
    }

    // Floating Pill Settings
    var pillPosition: PillPosition {
        didSet { save() }
    }

    var pillShowOnAllScreens: Bool {
        didSet { save() }
    }

    var pillExpandsDuringRecording: Bool {
        didSet { save() }
    }

    var showOnAir: Bool {
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
            case .linear: return .linear
            case .terminal: return .terminal
            case .minimal: return .minimal
            case .warm: return .warm
            case .classic: return .live
            case .liquidGlass: return .midnight  // Deep dark for glass to pop
            }
        }
        set {
            let preset: ThemePreset
            switch newValue {
            case .live: preset = .classic
            case .midnight: preset = .talkiePro
            case .linear: preset = .linear
            case .terminal: preset = .terminal
            case .warm: preset = .warm
            case .minimal: preset = .minimal
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

    /// Auto-open scratchpad when text is selected at recording start
    var autoScratchpadOnSelection: Bool {
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
        StartupProfiler.shared.mark("singleton.LiveSettings.start")
        // Use TalkieSharedSettings directly (can't use storage computed property before self is initialized)
        let store = TalkieSharedSettings

        // Load toggle hotkey (with migration from legacy UserDefaults.standard)
        if let data = migrateDataToSharedDefaults(key: LiveSettingsKey.hotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.hotkey = config
        } else {
            self.hotkey = .default
        }

        // Load push-to-talk hotkey
        if let data = migrateDataToSharedDefaults(key: LiveSettingsKey.pttHotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.pttHotkey = config
        } else {
            self.pttHotkey = .defaultPTT
        }

        // Load PTT enabled state (default: false)
        self.pttEnabled = migrateToSharedDefaults(key: LiveSettingsKey.pttEnabled, defaultValue: false)

        // Note: selectedModelId is now managed by SettingsManager, no need to load here

        // Load routing mode
        let routingRaw: String = migrateToSharedDefaults(key: LiveSettingsKey.routingMode, defaultValue: "paste")
        self.routingMode = routingRaw == "clipboardOnly" ? .clipboardOnly : .paste

        // Load selected microphone (0 = system default)
        self.selectedMicrophoneID = UInt32(migrateToSharedDefaults(key: LiveSettingsKey.selectedMicrophoneID, defaultValue: 0))

        // Load TTL (default 48 hours)
        let ttl: Int = migrateToSharedDefaults(key: LiveSettingsKey.utteranceTTLHours, defaultValue: 48)
        self.utteranceTTLHours = ttl > 0 ? ttl : 48

        // Load overlay settings (direct access - migrateToSharedDefaults has type casting issues with enums)
        self.overlayStyle = store.string(forKey: LiveSettingsKey.overlayStyle).flatMap(OverlayStyle.init) ?? .particles
        self.overlayPosition = store.string(forKey: LiveSettingsKey.overlayPosition).flatMap(IndicatorPosition.init) ?? .topCenter
        self.pillPosition = store.string(forKey: LiveSettingsKey.pillPosition).flatMap(PillPosition.init) ?? .bottomCenter

        // Load pill settings
        self.pillShowOnAllScreens = migrateToSharedDefaults(key: LiveSettingsKey.pillShowOnAllScreens, defaultValue: true)
        self.pillExpandsDuringRecording = migrateToSharedDefaults(key: LiveSettingsKey.pillExpandsDuringRecording, defaultValue: true)
        self.showOnAir = migrateToSharedDefaults(key: LiveSettingsKey.showOnAir, defaultValue: true)

        // Load sounds
        self.startSound = store.string(forKey: LiveSettingsKey.startSound).flatMap(TalkieSound.init) ?? .pop
        self.finishSound = store.string(forKey: LiveSettingsKey.finishSound).flatMap(TalkieSound.init) ?? .pop
        self.pastedSound = store.string(forKey: LiveSettingsKey.pastedSound).flatMap(TalkieSound.init) ?? .tink

        // Note: Appearance settings (appearanceMode, visualTheme, fontSize, accentColor)
        // are now computed properties delegating to SettingsManager, no loading needed

        // Load context settings
        self.primaryContextSource = store.string(forKey: LiveSettingsKey.primaryContextSource).flatMap(PrimaryContextSource.init) ?? .startApp
        self.contextCaptureDetail = store.string(forKey: LiveSettingsKey.contextCaptureDetail).flatMap(ContextCaptureDetail.init) ?? .rich

        // Load return to origin setting (default: false)
        self.returnToOriginAfterPaste = migrateToSharedDefaults(key: LiveSettingsKey.returnToOriginAfterPaste, defaultValue: false)

        // Load auto-scratchpad setting (default: false)
        self.autoScratchpadOnSelection = store.bool(forKey: LiveSettingsKey.autoScratchpadOnSelection)

        // Apply TTL to store
        DictationStore.shared.ttlHours = utteranceTTLHours
        StartupProfiler.shared.mark("singleton.LiveSettings.done")
    }

    // MARK: - Persistence

    private func save() {
        // Save to shared storage for cross-app sync with TalkieLive
        if let data = try? JSONEncoder().encode(hotkey) {
            storage.set(data, forKey: LiveSettingsKey.hotkey)
        }
        if let data = try? JSONEncoder().encode(pttHotkey) {
            storage.set(data, forKey: LiveSettingsKey.pttHotkey)
        }
        storage.set(pttEnabled, forKey: LiveSettingsKey.pttEnabled)
        // Note: selectedModelId is now managed by SettingsManager, no need to save here
        storage.set(routingMode == .clipboardOnly ? "clipboardOnly" : "paste", forKey: LiveSettingsKey.routingMode)
        storage.set(Int(selectedMicrophoneID), forKey: LiveSettingsKey.selectedMicrophoneID)
        storage.set(utteranceTTLHours, forKey: LiveSettingsKey.utteranceTTLHours)
        storage.set(overlayStyle.rawValue, forKey: LiveSettingsKey.overlayStyle)
        storage.set(overlayPosition.rawValue, forKey: LiveSettingsKey.overlayPosition)
        storage.set(pillPosition.rawValue, forKey: LiveSettingsKey.pillPosition)
        storage.set(pillShowOnAllScreens, forKey: LiveSettingsKey.pillShowOnAllScreens)
        storage.set(pillExpandsDuringRecording, forKey: LiveSettingsKey.pillExpandsDuringRecording)
        storage.set(showOnAir, forKey: LiveSettingsKey.showOnAir)
        storage.set(startSound.rawValue, forKey: LiveSettingsKey.startSound)
        storage.set(finishSound.rawValue, forKey: LiveSettingsKey.finishSound)
        storage.set(pastedSound.rawValue, forKey: LiveSettingsKey.pastedSound)
        // Note: appearance settings (appearanceMode, visualTheme, fontSize, accentColor)
        // are now delegated to SettingsManager and saved there
        storage.set(primaryContextSource.rawValue, forKey: LiveSettingsKey.primaryContextSource)
        storage.set(contextCaptureDetail.rawValue, forKey: LiveSettingsKey.contextCaptureDetail)
        storage.set(returnToOriginAfterPaste, forKey: LiveSettingsKey.returnToOriginAfterPaste)
        storage.set(autoScratchpadOnSelection, forKey: LiveSettingsKey.autoScratchpadOnSelection)
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

// MARK: - Stub types (simplified for Talkie integration)

// NOTE: RoutingMode is defined in RoutingMode.swift
// NOTE: TalkieSound is defined in SoundManager.swift
// NOTE: ContextCaptureDetail is defined in ContextCaptureService.swift
// NOTE: ModelInfo is defined in EngineClient.swift
