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

// MARK: - Appearance Options

enum OverlayStyle: String, CaseIterable, Codable {
    case particles = "particles"
    case particlesCalm = "particlesCalm"
    case waveform = "waveform"
    case waveformSensitive = "waveformSensitive"
    case pillOnly = "pillOnly"

    var displayName: String {
        switch self {
        case .particles: return "Particles"
        case .particlesCalm: return "Particles (Calm)"
        case .waveform: return "Waveform"
        case .waveformSensitive: return "Waveform (Sensitive)"
        case .pillOnly: return "Pill Only"
        }
    }

    var description: String {
        switch self {
        case .particles: return "Responsive particles that react to your voice"
        case .particlesCalm: return "Smooth, relaxed particle flow"
        case .waveform: return "Scrolling audio bars"
        case .waveformSensitive: return "Waveform with enhanced low-level response"
        case .pillOnly: return "No top overlay, just the bottom pill"
        }
    }

    var showsTopOverlay: Bool {
        switch self {
        case .particles, .particlesCalm, .waveform, .waveformSensitive: return true
        case .pillOnly: return false
        }
    }
}

/// Position for the recording indicator (particles/waveform overlay)
enum IndicatorPosition: String, CaseIterable, Codable {
    case topCenter = "topCenter"
    case topLeft = "topLeft"
    case topRight = "topRight"

    var displayName: String {
        switch self {
        case .topCenter: return "Top Center"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        }
    }

    var description: String {
        switch self {
        case .topCenter: return "Centered at top of screen"
        case .topLeft: return "Upper left corner"
        case .topRight: return "Upper right corner"
        }
    }
}

/// Position for the floating pill widget
enum PillPosition: String, CaseIterable, Codable {
    case bottomCenter = "bottomCenter"
    case bottomLeft = "bottomLeft"
    case bottomRight = "bottomRight"
    case topCenter = "topCenter"

    var displayName: String {
        switch self {
        case .bottomCenter: return "Bottom Center"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .topCenter: return "Top Center"
        }
    }

    var description: String {
        switch self {
        case .bottomCenter: return "Centered at bottom edge"
        case .bottomLeft: return "Lower left corner"
        case .bottomRight: return "Lower right corner"
        case .topCenter: return "Centered at top edge"
        }
    }
}

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
    case live = "live"
    case midnight = "midnight"
    case terminal = "terminal"
    case warm = "warm"
    case minimal = "minimal"

    var displayName: String {
        switch self {
        case .live: return "Live"
        case .midnight: return "Midnight"
        case .terminal: return "Terminal"
        case .warm: return "Warm"
        case .minimal: return "Minimal"
        }
    }

    var description: String {
        switch self {
        case .live: return "Default blue accent"
        case .midnight: return "Deep black, high contrast"
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

        // Load toggle hotkey
        if let data = store.data(forKey: LiveSettingsKey.hotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.hotkey = config
        } else {
            self.hotkey = .default
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

        // Apply TTL to store
        DictationStore.shared.ttlHours = dictationTTLHours
    }

    // MARK: - Reload

    /// Reload all settings from shared storage (call when notified of cross-process changes)
    func reload() {
        let store = TalkieSharedSettings

        // Reload hotkeys
        if let data = store.data(forKey: LiveSettingsKey.hotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.hotkey = config
        }

        if let data = store.data(forKey: LiveSettingsKey.pttHotkey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.pttHotkey = config
        }

        self.pttEnabled = store.bool(forKey: LiveSettingsKey.pttEnabled)

        // Reload model
        if let modelId = store.string(forKey: LiveSettingsKey.selectedModelId) {
            self.selectedModelId = modelId
        }

        // Reload routing
        let routingRaw = store.string(forKey: LiveSettingsKey.routingMode) ?? "paste"
        self.routingMode = routingRaw == "clipboardOnly" ? .clipboardOnly : .paste

        // Reload audio
        self.selectedMicrophoneID = UInt32(store.integer(forKey: LiveSettingsKey.selectedMicrophoneID))

        // Reload TTL
        let ttl = store.integer(forKey: LiveSettingsKey.utteranceTTLHours)
        self.dictationTTLHours = ttl > 0 ? ttl : 48
        DictationStore.shared.ttlHours = dictationTTLHours

        // Reload overlay/pill
        if let rawValue = store.string(forKey: LiveSettingsKey.overlayStyle),
           let style = OverlayStyle(rawValue: rawValue) {
            self.overlayStyle = style
        }

        if let rawValue = store.string(forKey: LiveSettingsKey.overlayPosition),
           let position = OverlayPosition(rawValue: rawValue) {
            self.overlayPosition = position
        }

        if let rawValue = store.string(forKey: LiveSettingsKey.pillPosition),
           let position = PillPosition(rawValue: rawValue) {
            self.pillPosition = position
        }

        self.pillShowOnAllScreens = store.object(forKey: LiveSettingsKey.pillShowOnAllScreens) as? Bool ?? true
        self.pillExpandsDuringRecording = store.object(forKey: LiveSettingsKey.pillExpandsDuringRecording) as? Bool ?? true

        // Reload sounds
        if let rawValue = store.string(forKey: LiveSettingsKey.startSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.startSound = sound
        }

        if let rawValue = store.string(forKey: LiveSettingsKey.finishSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.finishSound = sound
        }

        if let rawValue = store.string(forKey: LiveSettingsKey.pastedSound),
           let sound = TalkieSound(rawValue: rawValue) {
            self.pastedSound = sound
        }

        // Reload context settings
        if let rawValue = store.string(forKey: LiveSettingsKey.primaryContextSource),
           let source = PrimaryContextSource(rawValue: rawValue) {
            self.primaryContextSource = source
        }

        if let rawValue = store.string(forKey: LiveSettingsKey.contextCaptureDetail),
           let detail = ContextCaptureDetail(rawValue: rawValue) {
            self.contextCaptureDetail = detail
        }

        self.returnToOriginAfterPaste = store.bool(forKey: LiveSettingsKey.returnToOriginAfterPaste)

        NSLog("[LiveSettings] ✓ Reloaded from shared storage")
    }

    // MARK: - Persistence
    // Writes to shared storage so Talkie sees changes (though Talkie is the primary owner)

    private func save() {
        let store = storage

        if let data = try? JSONEncoder().encode(hotkey) {
            store.set(data, forKey: LiveSettingsKey.hotkey)
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
        store.set(startSound.rawValue, forKey: LiveSettingsKey.startSound)
        store.set(finishSound.rawValue, forKey: LiveSettingsKey.finishSound)
        store.set(pastedSound.rawValue, forKey: LiveSettingsKey.pastedSound)
        store.set(appearanceMode.rawValue, forKey: LiveSettingsKey.appearanceMode)
        store.set(visualTheme.rawValue, forKey: LiveSettingsKey.visualTheme)
        store.set(fontSize.rawValue, forKey: LiveSettingsKey.fontSize)
        store.set(accentColor.rawValue, forKey: LiveSettingsKey.accentColor)
        store.set(primaryContextSource.rawValue, forKey: LiveSettingsKey.primaryContextSource)
        store.set(contextCaptureDetail.rawValue, forKey: LiveSettingsKey.contextCaptureDetail)
        store.set(returnToOriginAfterPaste, forKey: LiveSettingsKey.returnToOriginAfterPaste)
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
