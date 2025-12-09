//
//  LiveSettings.swift
//  TalkieLive
//
//  Settings for Talkie Live
//

import Foundation
import SwiftUI
import Carbon.HIToolbox
import TalkieServices

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

    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.15
        }
    }

    var previewSize: CGFloat {
        switch self {
        case .small: return 11
        case .medium: return 13
        case .large: return 15
        }
    }
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

    static let `default` = HotkeyConfig(
        keyCode: 37,  // L
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
            38: "J", 40: "K", 45: "N", 46: "M",
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

    // MARK: - Keys
    private let hotkeyKey = "hotkey"
    private let whisperModelKey = "whisperModel"
    private let routingModeKey = "routingMode"
    private let utteranceTTLKey = "utteranceTTLHours"
    private let overlayStyleKey = "overlayStyle"
    private let overlayPositionKey = "overlayPosition"
    private let pillPositionKey = "pillPosition"
    private let pillShowOnAllScreensKey = "pillShowOnAllScreens"
    private let pillExpandsDuringRecordingKey = "pillExpandsDuringRecording"
    private let startSoundKey = "startSound"
    private let finishSoundKey = "finishSound"
    private let pastedSoundKey = "pastedSound"
    private let appearanceModeKey = "appearanceMode"
    private let visualThemeKey = "visualTheme"
    private let fontSizeKey = "fontSize"
    private let accentColorKey = "accentColor"
    private let primaryContextSourceKey = "primaryContextSource"
    private let returnToOriginAfterPasteKey = "returnToOriginAfterPaste"
    private let selectedMicrophoneIDKey = "selectedMicrophoneID"
    // Legacy key for migration
    private let legacyThemeKey = "theme"

    // MARK: - Published Settings

    @Published var hotkey: HotkeyConfig {
        didSet { save() }
    }

    @Published var whisperModel: WhisperModel {
        didSet { save() }
    }

    @Published var routingMode: RoutingMode {
        didSet { save() }
    }

    /// Selected microphone device ID (0 = system default)
    @Published var selectedMicrophoneID: UInt32 {
        didSet { save() }
    }

    @Published var utteranceTTLHours: Int {
        didSet {
            save()
            UtteranceStore.shared.ttlSeconds = TimeInterval(utteranceTTLHours * 3600)
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
        // Load hotkey
        if let data = UserDefaults.standard.data(forKey: hotkeyKey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.hotkey = config
        } else {
            self.hotkey = .default
        }

        // Load whisper model
        if let rawValue = UserDefaults.standard.string(forKey: whisperModelKey),
           let model = WhisperModel(rawValue: rawValue) {
            self.whisperModel = model
        } else {
            self.whisperModel = .small
        }

        // Load routing mode
        let routingRaw = UserDefaults.standard.string(forKey: routingModeKey) ?? "paste"
        self.routingMode = routingRaw == "clipboardOnly" ? .clipboardOnly : .paste

        // Load selected microphone (0 = system default)
        self.selectedMicrophoneID = UInt32(UserDefaults.standard.integer(forKey: selectedMicrophoneIDKey))

        // Load TTL (default 48 hours)
        let ttl = UserDefaults.standard.integer(forKey: utteranceTTLKey)
        self.utteranceTTLHours = ttl > 0 ? ttl : 48

        // Load overlay style
        if let rawValue = UserDefaults.standard.string(forKey: overlayStyleKey),
           let style = OverlayStyle(rawValue: rawValue) {
            self.overlayStyle = style
        } else {
            self.overlayStyle = .particles
        }

        // Load overlay position
        if let rawValue = UserDefaults.standard.string(forKey: overlayPositionKey),
           let position = OverlayPosition(rawValue: rawValue) {
            self.overlayPosition = position
        } else {
            self.overlayPosition = .topCenter
        }

        // Load pill position
        if let rawValue = UserDefaults.standard.string(forKey: pillPositionKey),
           let position = PillPosition(rawValue: rawValue) {
            self.pillPosition = position
        } else {
            self.pillPosition = .bottomCenter
        }

        // Load pill settings
        self.pillShowOnAllScreens = UserDefaults.standard.object(forKey: pillShowOnAllScreensKey) as? Bool ?? true
        self.pillExpandsDuringRecording = UserDefaults.standard.object(forKey: pillExpandsDuringRecordingKey) as? Bool ?? true

        // Load sounds (default to pop for start/finish, tink for pasted)
        if let rawValue = UserDefaults.standard.string(forKey: startSoundKey),
           let sound = TalkieSound(rawValue: rawValue) {
            self.startSound = sound
        } else {
            self.startSound = .pop
        }

        if let rawValue = UserDefaults.standard.string(forKey: finishSoundKey),
           let sound = TalkieSound(rawValue: rawValue) {
            self.finishSound = sound
        } else {
            self.finishSound = .pop
        }

        if let rawValue = UserDefaults.standard.string(forKey: pastedSoundKey),
           let sound = TalkieSound(rawValue: rawValue) {
            self.pastedSound = sound
        } else {
            self.pastedSound = .tink
        }

        // Load appearance mode (with migration from legacy theme key)
        if let rawValue = UserDefaults.standard.string(forKey: appearanceModeKey),
           let mode = AppearanceMode(rawValue: rawValue) {
            self.appearanceMode = mode
        } else if let legacyTheme = UserDefaults.standard.string(forKey: legacyThemeKey) {
            // Migrate from legacy theme setting
            switch legacyTheme {
            case "system": self.appearanceMode = .system
            case "light": self.appearanceMode = .light
            case "dark", "midnight": self.appearanceMode = .dark
            default: self.appearanceMode = .system
            }
        } else {
            self.appearanceMode = .system
        }

        // Load visual theme
        if let rawValue = UserDefaults.standard.string(forKey: visualThemeKey),
           let theme = VisualTheme(rawValue: rawValue) {
            self.visualTheme = theme
        } else if let legacyTheme = UserDefaults.standard.string(forKey: legacyThemeKey) {
            // Migrate: midnight -> midnight theme, others -> live
            self.visualTheme = legacyTheme == "midnight" ? .midnight : .live
        } else {
            self.visualTheme = .live
        }

        // Load font size
        if let rawValue = UserDefaults.standard.string(forKey: fontSizeKey),
           let size = FontSize(rawValue: rawValue) {
            self.fontSize = size
        } else {
            self.fontSize = .medium
        }

        // Load accent color
        if let rawValue = UserDefaults.standard.string(forKey: accentColorKey),
           let color = AccentColorOption(rawValue: rawValue) {
            self.accentColor = color
        } else {
            self.accentColor = .system
        }

        // Load primary context source (default: start app)
        if let rawValue = UserDefaults.standard.string(forKey: primaryContextSourceKey),
           let source = PrimaryContextSource(rawValue: rawValue) {
            self.primaryContextSource = source
        } else {
            self.primaryContextSource = .startApp
        }

        // Load return to origin setting (default: false)
        self.returnToOriginAfterPaste = UserDefaults.standard.bool(forKey: returnToOriginAfterPasteKey)

        // Apply TTL to store
        UtteranceStore.shared.ttlSeconds = TimeInterval(utteranceTTLHours * 3600)
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: hotkeyKey)
        }
        UserDefaults.standard.set(whisperModel.rawValue, forKey: whisperModelKey)
        UserDefaults.standard.set(routingMode == .clipboardOnly ? "clipboardOnly" : "paste", forKey: routingModeKey)
        UserDefaults.standard.set(Int(selectedMicrophoneID), forKey: selectedMicrophoneIDKey)
        UserDefaults.standard.set(utteranceTTLHours, forKey: utteranceTTLKey)
        UserDefaults.standard.set(overlayStyle.rawValue, forKey: overlayStyleKey)
        UserDefaults.standard.set(overlayPosition.rawValue, forKey: overlayPositionKey)
        UserDefaults.standard.set(pillPosition.rawValue, forKey: pillPositionKey)
        UserDefaults.standard.set(pillShowOnAllScreens, forKey: pillShowOnAllScreensKey)
        UserDefaults.standard.set(pillExpandsDuringRecording, forKey: pillExpandsDuringRecordingKey)
        UserDefaults.standard.set(startSound.rawValue, forKey: startSoundKey)
        UserDefaults.standard.set(finishSound.rawValue, forKey: finishSoundKey)
        UserDefaults.standard.set(pastedSound.rawValue, forKey: pastedSoundKey)
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceModeKey)
        UserDefaults.standard.set(visualTheme.rawValue, forKey: visualThemeKey)
        UserDefaults.standard.set(fontSize.rawValue, forKey: fontSizeKey)
        UserDefaults.standard.set(accentColor.rawValue, forKey: accentColorKey)
        UserDefaults.standard.set(primaryContextSource.rawValue, forKey: primaryContextSourceKey)
        UserDefaults.standard.set(returnToOriginAfterPaste, forKey: returnToOriginAfterPasteKey)
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
