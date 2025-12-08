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

enum OverlayPosition: String, CaseIterable, Codable {
    case topCenter = "topCenter"
    case topLeft = "topLeft"
    case topRight = "topRight"
    case bottomCenter = "bottomCenter"

    var displayName: String {
        switch self {
        case .topCenter: return "Top Center"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomCenter: return "Bottom Center"
        }
    }
}

enum AppTheme: String, CaseIterable, Codable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case midnight = "midnight"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .midnight: return "Midnight"
        }
    }

    var description: String {
        switch self {
        case .system: return "Follow system appearance"
        case .light: return "Always light mode"
        case .dark: return "Always dark mode"
        case .midnight: return "Deep black tactical theme"
        }
    }
}

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

// MARK: - Theme Presets

enum ThemePreset: String, CaseIterable {
    case liveDefault = "liveDefault"
    case terminal = "terminal"
    case minimal = "minimal"
    case warm = "warm"

    var displayName: String {
        switch self {
        case .liveDefault: return "Live"
        case .terminal: return "Terminal"
        case .minimal: return "Minimal"
        case .warm: return "Warm"
        }
    }

    var description: String {
        switch self {
        case .liveDefault: return "Sharp, high contrast"
        case .terminal: return "Green accents"
        case .minimal: return "Clean, adaptive"
        case .warm: return "Cozy orange tones"
        }
    }

    var previewColors: (bg: Color, fg: Color, accent: Color) {
        switch self {
        case .liveDefault:
            return (Color(white: 0.08), Color.white.opacity(0.85), Color(red: 0.4, green: 0.7, blue: 1.0))
        case .terminal:
            return (Color.black, Color.green.opacity(0.9), Color.green)
        case .minimal:
            return (Color(white: 0.96), Color.black.opacity(0.8), Color.gray)
        case .warm:
            return (Color(red: 0.1, green: 0.08, blue: 0.06), Color.white.opacity(0.9), Color.orange)
        }
    }

    var theme: AppTheme {
        switch self {
        case .liveDefault: return .midnight
        case .terminal: return .dark
        case .minimal: return .system
        case .warm: return .dark
        }
    }

    var accentColor: AccentColorOption {
        switch self {
        case .liveDefault: return .blue
        case .terminal: return .green
        case .minimal: return .gray
        case .warm: return .orange
        }
    }

    var fontSize: FontSize {
        switch self {
        case .liveDefault: return .medium
        case .terminal: return .small
        case .minimal: return .medium
        case .warm: return .large
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
    private let startSoundKey = "startSound"
    private let finishSoundKey = "finishSound"
    private let pastedSoundKey = "pastedSound"
    private let themeKey = "theme"
    private let fontSizeKey = "fontSize"
    private let accentColorKey = "accentColor"

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

    @Published var startSound: TalkieSound {
        didSet { save() }
    }

    @Published var finishSound: TalkieSound {
        didSet { save() }
    }

    @Published var pastedSound: TalkieSound {
        didSet { save() }
    }

    @Published var theme: AppTheme {
        didSet {
            save()
            applyTheme()
        }
    }

    @Published var fontSize: FontSize {
        didSet { save() }
    }

    @Published var accentColor: AccentColorOption {
        didSet { save() }
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

        // Load theme
        if let rawValue = UserDefaults.standard.string(forKey: themeKey),
           let loadedTheme = AppTheme(rawValue: rawValue) {
            self.theme = loadedTheme
        } else {
            self.theme = .system
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
        UserDefaults.standard.set(utteranceTTLHours, forKey: utteranceTTLKey)
        UserDefaults.standard.set(overlayStyle.rawValue, forKey: overlayStyleKey)
        UserDefaults.standard.set(overlayPosition.rawValue, forKey: overlayPositionKey)
        UserDefaults.standard.set(startSound.rawValue, forKey: startSoundKey)
        UserDefaults.standard.set(finishSound.rawValue, forKey: finishSoundKey)
        UserDefaults.standard.set(pastedSound.rawValue, forKey: pastedSoundKey)
        UserDefaults.standard.set(theme.rawValue, forKey: themeKey)
        UserDefaults.standard.set(fontSize.rawValue, forKey: fontSizeKey)
        UserDefaults.standard.set(accentColor.rawValue, forKey: accentColorKey)
    }

    // MARK: - Theme Application

    func applyTheme() {
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case .midnight:
            // Midnight uses dark as base with custom colors
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func applyPreset(_ preset: ThemePreset) {
        theme = preset.theme
        accentColor = preset.accentColor
        fontSize = preset.fontSize
    }

    var currentPreset: ThemePreset? {
        ThemePreset.allCases.first {
            $0.theme == theme && $0.accentColor == accentColor && $0.fontSize == fontSize
        }
    }
}
