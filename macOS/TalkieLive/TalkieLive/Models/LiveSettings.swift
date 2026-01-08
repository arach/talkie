//
//  LiveSettings.swift
//  TalkieLive
//
//  Settings for Talkie Live
//

import Foundation
import SwiftUI
import Carbon.HIToolbox
import TalkieKit

private let log = Log(.system)

// MARK: - Appearance Types (from TalkieKit)
// OverlayStyle, IndicatorPosition, PillPosition are now in TalkieKit

// Legacy compatibility alias
typealias OverlayPosition = IndicatorPosition

// MARK: - Appearance Mode (Light/Dark/System)

enum AppearanceMode: String, CaseIterable, Codable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var description: String {
        switch self {
        case .system: return "Follow system appearance"
        case .light: return "Always light mode"
        case .dark: return "Always dark mode"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Visual Theme (Color Schemes)

enum VisualTheme: String, CaseIterable, Codable {
    case live = "live"          // Maps to talkiePro
    case midnight = "midnight"  // Maps to talkiePro (legacy)
    case terminal = "terminal"
    case minimal = "minimal"

    var displayName: String {
        switch self {
        case .live: return "Pro"
        case .midnight: return "Pro"
        case .terminal: return "Terminal"
        case .minimal: return "Minimal"
        }
    }

    var description: String {
        switch self {
        case .live: return "Professional dark theme"
        case .midnight: return "Professional dark theme"
        case .terminal: return "Clean monospace, sharp corners"
        case .minimal: return "Light and subtle"
        }
    }

    /// Default accent color for this theme
    var accentColor: AccentColorOption {
        switch self {
        case .live: return .blue
        case .midnight: return .blue
        case .terminal: return .gray    // No gimmicks
        case .minimal: return .gray
        }
    }

    /// Suggested appearance mode for this theme (user can override)
    var suggestedAppearance: AppearanceMode {
        switch self {
        case .live: return .dark
        case .midnight: return .dark
        case .terminal: return .dark
        case .minimal: return .system
        }
    }

    /// Preview colors for theme selector
    var previewColors: (bg: Color, fg: Color, accent: Color) {
        switch self {
        case .live:
            return (Color(white: 0.08), Color.white.opacity(0.85), Color.blue)
        case .midnight:
            return (Color(white: 0.08), Color.white.opacity(0.85), Color(red: 0.4, green: 0.7, blue: 1.0))
        case .terminal:
            // Ghostty-style: black bg, light gray text, subtle gray accent
            return (Color.black, Color(white: 0.85), Color(white: 0.5))
        case .minimal:
            return (Color(white: 0.96), Color(white: 0.2), Color.gray)
        }
    }
}

// Legacy compatibility - maps to new system
@available(*, deprecated, message: "Use AppearanceMode and VisualTheme instead")
typealias AppTheme = AppearanceMode

/// Design system font sizes - canonical integer sizes, no fractional scaling
/// Each size tier defines proper integer point sizes for crisp rendering
enum FontSize: String, CaseIterable, Codable {
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

enum AccentColorOption: String, CaseIterable, Codable {
    case system = "system"
    case blue = "blue"
    case purple = "purple"
    case pink = "pink"
    case red = "red"
    case orange = "orange"
    case yellow = "yellow"
    case green = "green"
    case teal = "teal"
    case gray = "gray"

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .system: return .accentColor
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .gray: return .gray
        }
    }
}

// Legacy compatibility for ThemePreset
@available(*, deprecated, message: "Use VisualTheme instead")
typealias ThemePreset = VisualTheme

// MARK: - Context Preference

/// Which app context is considered "primary" for utterances
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

    /// Toggle hotkey default - uses TalkieEnvironment for environment-specific modifiers
    /// Prod: ⌥⌘L, Staging: ⇧⌥⌘L, Dev: ⌃⌥⌘L
    static var `default`: HotkeyConfig {
        HotkeyConfig(keyCode: 37, modifiers: TalkieEnvironment.current.defaultHotkeyModifiers)  // L
    }

    /// Push-to-talk hotkey default - uses TalkieEnvironment for environment-specific modifiers
    /// Prod: ⌥⌘;, Staging: ⇧⌥⌘;, Dev: ⌃⌥⌘;
    static var defaultPTT: HotkeyConfig {
        HotkeyConfig(keyCode: 41, modifiers: TalkieEnvironment.current.defaultHotkeyModifiers)  // ;
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

@MainActor
final class LiveSettings: ObservableObject {
    static let shared = LiveSettings()

    // MARK: - Shared Settings Storage
    // Uses TalkieSharedSettings from TalkieKit for cross-app sync with Talkie
    private var storage: UserDefaults { TalkieSharedSettings }

    // MARK: - Published Settings

    /// Toggle hotkey (press to start, press to stop)
    @Published var hotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Push-to-talk hotkey (hold to record, release to stop)
    @Published var pttHotkey: HotkeyConfig {
        didSet { save() }
    }

    /// Whether push-to-talk hotkey is enabled
    @Published var pttEnabled: Bool {
        didSet { save() }
    }

    /// Selected model ID with family prefix (e.g., "whisper:openai_whisper-small" or "parakeet:v3")
    @Published var selectedModelId: String {
        didSet { save() }
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

    @Published var routingMode: RoutingMode {
        didSet { save() }
    }

    /// Selected microphone device ID (0 = system default)
    @Published var selectedMicrophoneID: UInt32 {
        didSet { save() }
    }

    @Published var dictationTTLHours: Int {
        didSet {
            save()
            DictationStore.shared.ttlHours = dictationTTLHours
        }
    }

    @Published var overlayStyle: OverlayStyle {
        didSet { save() }
    }

    @Published var overlayPosition: OverlayPosition {
        didSet { save() }
    }

    // Floating Pill Settings
    @Published var pillPosition: PillPosition {
        didSet { save() }
    }

    @Published var pillShowOnAllScreens: Bool {
        didSet { save() }
    }

    @Published var pillExpandsDuringRecording: Bool {
        didSet { save() }
    }

    /// Show "On Air" indicator while recording
    @Published var showOnAir: Bool {
        didSet { save() }
    }

    @Published var startSound: TalkieSound {
        didSet { save() }
    }

    @Published var finishSound: TalkieSound {
        didSet { save() }
    }

    @Published var pastedSound: TalkieSound {
        didSet { save() }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            save()
            applyAppearance()
        }
    }

    @Published var visualTheme: VisualTheme {
        didSet {
            save()
            // Optionally update accent color to match theme default
            if accentColor == .system {
                // Trigger UI update without changing setting
            }
        }
    }

    @Published var fontSize: FontSize {
        didSet { save() }
    }

    @Published var accentColor: AccentColorOption {
        didSet { save() }
    }

    /// Glass mode enabled via launch argument: --glass-mode
    /// Not a runtime toggle - set at startup only (simpler, no view rebuild issues)
    var glassMode: Bool {
        ProcessInfo.processInfo.arguments.contains("--glass-mode")
    }

    /// Which context (start or end app) is primary for utterances
    @Published var primaryContextSource: PrimaryContextSource {
        didSet { save() }
    }

    /// How much context to capture from the Accessibility API
    @Published var contextCaptureDetail: ContextCaptureDetail {
        didSet { save() }
    }

    /// Session-scoped permission for capturing context (resets on app restart)
    @Published var contextCaptureSessionAllowed: Bool = true

    /// Whether to activate the start app after pasting
    @Published var returnToOriginAfterPaste: Bool {
        didSet { save() }
    }

    /// Press Enter/Return after pasting (useful for chat apps, terminals)
    @Published var pressEnterAfterPaste: Bool {
        didSet { save() }
    }

    /// Auto-open scratchpad when text is selected at recording start
    @Published var autoScratchpadOnSelection: Bool = false {
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
        // Read from shared storage (Talkie is the owner, we're just reading)
        // Note: Use TalkieSharedSettings directly since storage property requires self
        let store = TalkieSharedSettings
        let suiteName = TalkieEnvironment.current.sharedSettingsSuite
        log.info("LiveSettings.init() loading from suite: \(suiteName)")

        // Load toggle hotkey
        if let data = store.data(forKey: LiveSettingsKey.hotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.hotkey = config
            log.debug("Loaded hotkey: \(config.displayString)")
        } else {
            self.hotkey = .default
            log.debug("No saved hotkey, using default: \(HotkeyConfig.default.displayString)")
        }

        // Load push-to-talk hotkey
        if let data = store.data(forKey: LiveSettingsKey.pttHotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.pttHotkey = config
        } else {
            self.pttHotkey = .defaultPTT
        }

        // Load PTT enabled state (default: false)
        self.pttEnabled = store.bool(forKey: LiveSettingsKey.pttEnabled)

        // Load selected model ID
        if let modelId = store.string(forKey: LiveSettingsKey.selectedModelId) {
            self.selectedModelId = modelId
        } else {
            // Default to parakeet v3 (fast, accurate, always available)
            self.selectedModelId = "parakeet:v3"
        }

        // Load routing mode
        let routingRaw = store.string(forKey: LiveSettingsKey.routingMode) ?? "paste"
        self.routingMode = routingRaw == "clipboardOnly" ? .clipboardOnly : .paste

        // Load selected microphone (0 = system default)
        self.selectedMicrophoneID = UInt32(store.integer(forKey: LiveSettingsKey.selectedMicrophoneID))

        // Load TTL (default 48 hours)
        let ttl = store.integer(forKey: LiveSettingsKey.utteranceTTLHours)
        self.dictationTTLHours = ttl > 0 ? ttl : 48

        // Load overlay style
        if let rawValue = store.string(forKey: LiveSettingsKey.overlayStyle),
           let style = OverlayStyle(rawValue: rawValue) {
            self.overlayStyle = style
        } else {
            self.overlayStyle = .particles
        }

        // Load overlay position
        if let rawValue = store.string(forKey: LiveSettingsKey.overlayPosition),
           let position = OverlayPosition(rawValue: rawValue) {
            self.overlayPosition = position
        } else {
            self.overlayPosition = .topCenter
        }

        // Load pill position
        if let rawValue = store.string(forKey: LiveSettingsKey.pillPosition),
           let position = PillPosition(rawValue: rawValue) {
            self.pillPosition = position
        } else {
            self.pillPosition = .bottomCenter
        }

        // Load pill settings
        self.pillShowOnAllScreens = store.object(forKey: LiveSettingsKey.pillShowOnAllScreens) as? Bool ?? true
        self.pillExpandsDuringRecording = store.object(forKey: LiveSettingsKey.pillExpandsDuringRecording) as? Bool ?? true
        self.showOnAir = store.object(forKey: LiveSettingsKey.showOnAir) as? Bool ?? true

        // Load sounds (default to pop for start/finish, tink for pasted)
        if let rawValue = store.string(forKey: LiveSettingsKey.startSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.startSound = sound
        } else {
            self.startSound = .pop
        }

        if let rawValue = store.string(forKey: LiveSettingsKey.finishSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.finishSound = sound
        } else {
            self.finishSound = .pop
        }

        if let rawValue = store.string(forKey: LiveSettingsKey.pastedSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.pastedSound = sound
        } else {
            self.pastedSound = .tink
        }

        // Load appearance mode
        if let rawValue = store.string(forKey: LiveSettingsKey.appearanceMode),
           let mode = AppearanceMode(rawValue: rawValue) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        // Load visual theme
        if let rawValue = store.string(forKey: LiveSettingsKey.visualTheme),
           let theme = VisualTheme(rawValue: rawValue) {
            self.visualTheme = theme
        } else {
            self.visualTheme = .live
        }

        // Load font size
        if let rawValue = store.string(forKey: LiveSettingsKey.fontSize),
           let size = FontSize(rawValue: rawValue) {
            self.fontSize = size
        } else {
            self.fontSize = .medium
        }

        // Load accent color
        if let rawValue = store.string(forKey: LiveSettingsKey.accentColor),
           let color = AccentColorOption(rawValue: rawValue) {
            self.accentColor = color
        } else {
            self.accentColor = .system
        }

        // Note: glassMode is now a computed property checking launch arg --glass-mode

        // Load primary context source (default: start app)
        if let rawValue = store.string(forKey: LiveSettingsKey.primaryContextSource),
           let source = PrimaryContextSource(rawValue: rawValue) {
            self.primaryContextSource = source
        } else {
            self.primaryContextSource = .startApp
        }

        // Load context capture detail (default: rich)
        if let rawValue = store.string(forKey: LiveSettingsKey.contextCaptureDetail),
           let detail = ContextCaptureDetail(rawValue: rawValue) {
            self.contextCaptureDetail = detail
        } else {
            self.contextCaptureDetail = .rich
        }

        // Load return to origin setting (default: false)
        self.returnToOriginAfterPaste = store.bool(forKey: LiveSettingsKey.returnToOriginAfterPaste)
        self.pressEnterAfterPaste = store.bool(forKey: LiveSettingsKey.pressEnterAfterPaste)
        self.autoScratchpadOnSelection = store.bool(forKey: LiveSettingsKey.autoScratchpadOnSelection)

        // Apply TTL to store
        DictationStore.shared.ttlHours = dictationTTLHours
    }

    // MARK: - Persistence
    // Writes to shared storage so Talkie sees changes (though Talkie is the primary owner)

    private func save() {
        let store = storage
        let suiteName = TalkieEnvironment.current.sharedSettingsSuite
        log.debug("LiveSettings.save() to suite: \(suiteName)")

        if let data = try? JSONEncoder().encode(hotkey) {
            store.set(data, forKey: LiveSettingsKey.hotkey)
            log.debug("Saved hotkey: \(hotkey.displayString)")
        }
        if let data = try? JSONEncoder().encode(pttHotkey) {
            store.set(data, forKey: LiveSettingsKey.pttHotkey)
        }
        store.set(pttEnabled, forKey: LiveSettingsKey.pttEnabled)
        store.set(selectedModelId, forKey: LiveSettingsKey.selectedModelId)
        store.set(routingMode == .clipboardOnly ? "clipboardOnly" : "paste", forKey: LiveSettingsKey.routingMode)
        store.set(Int(selectedMicrophoneID), forKey: LiveSettingsKey.selectedMicrophoneID)
        store.set(dictationTTLHours, forKey: LiveSettingsKey.utteranceTTLHours)
        store.set(overlayStyle.rawValue, forKey: LiveSettingsKey.overlayStyle)
        store.set(overlayPosition.rawValue, forKey: LiveSettingsKey.overlayPosition)
        store.set(pillPosition.rawValue, forKey: LiveSettingsKey.pillPosition)
        store.set(pillShowOnAllScreens, forKey: LiveSettingsKey.pillShowOnAllScreens)
        store.set(pillExpandsDuringRecording, forKey: LiveSettingsKey.pillExpandsDuringRecording)
        store.set(showOnAir, forKey: LiveSettingsKey.showOnAir)
        store.set(startSound.rawValue, forKey: LiveSettingsKey.startSound)
        store.set(finishSound.rawValue, forKey: LiveSettingsKey.finishSound)
        store.set(pastedSound.rawValue, forKey: LiveSettingsKey.pastedSound)
        store.set(appearanceMode.rawValue, forKey: LiveSettingsKey.appearanceMode)
        store.set(visualTheme.rawValue, forKey: LiveSettingsKey.visualTheme)
        store.set(fontSize.rawValue, forKey: LiveSettingsKey.fontSize)
        store.set(accentColor.rawValue, forKey: LiveSettingsKey.accentColor)
        // glassMode is now a launch arg, not persisted
        store.set(primaryContextSource.rawValue, forKey: LiveSettingsKey.primaryContextSource)
        store.set(contextCaptureDetail.rawValue, forKey: LiveSettingsKey.contextCaptureDetail)
        store.set(returnToOriginAfterPaste, forKey: LiveSettingsKey.returnToOriginAfterPaste)
        store.set(pressEnterAfterPaste, forKey: LiveSettingsKey.pressEnterAfterPaste)
        store.set(autoScratchpadOnSelection, forKey: LiveSettingsKey.autoScratchpadOnSelection)

        // Force immediate write to disk (important for dev builds that may be killed by Xcode)
        store.synchronize()
    }

    // MARK: - Appearance Application

    func applyAppearance() {
        switch appearanceMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Apply a visual theme preset (updates theme + accent color)
    func applyVisualTheme(_ theme: VisualTheme) {
        self.visualTheme = theme
        self.accentColor = theme.accentColor
        // Optionally also set appearance to suggested mode
        // self.appearanceMode = theme.suggestedAppearance
    }

    /// Effective accent color considering theme defaults
    var effectiveAccentColor: Color {
        if accentColor == .system {
            return visualTheme.accentColor.color
        }
        return accentColor.color
    }
}
