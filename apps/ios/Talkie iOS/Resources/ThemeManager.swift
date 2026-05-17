//
//  ThemeManager.swift
//  Talkie iOS
//
//  Manages app themes with 5 configurable options
//

import SwiftUI

// MARK: - Appearance Mode

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Theme Definitions

enum AppTheme: String, CaseIterable, Identifiable {
    case scope = "scope"
    case midnight = "midnight"
    case tactical = "tactical"
    case ghost = "ghost"
    case lift = "lift"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .scope: return "Scope"
        case .midnight: return "Midnight"
        case .tactical: return "Tactical"
        case .ghost: return "Ghost"
        case .lift: return "Lift"
        }
    }

    var description: String {
        switch self {
        case .scope: return "Paper chassis with brass instrument chrome"
        case .midnight: return "Deep black with subtle highlights"
        case .tactical: return "High contrast, sharp edges"
        case .ghost: return "Soft, muted elegance"
        case .lift: return "Pure white surfaces with indigo lift"
        }
    }
}

// MARK: - Theme Colors

struct ThemeColors {
    // Table colors
    let tableHeaderBackground: Color
    let tableCellBackground: Color
    let tableDivider: Color
    let tableBorder: Color

    // General surfaces
    let background: Color
    let cardBackground: Color
    let searchBackground: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Accents
    let accent: Color
    let success: Color
}

// MARK: - Cached Theme Colors (parsed once at app launch, not on every access)

private let cachedMidnightColors = ThemeColors(
    tableHeaderBackground: Color(hex: "111111"),
    tableCellBackground: Color(hex: "000000"),
    tableDivider: Color(hex: "FFFFFF").opacity(0.08),
    tableBorder: Color(hex: "333333"),
    background: Color(hex: "0A0A0A"),
    cardBackground: Color(hex: "111111"),
    searchBackground: Color(hex: "151515"),
    textPrimary: Color(hex: "FAFAFA"),
    textSecondary: Color(hex: "9A9A9A"),
    textTertiary: Color(hex: "6A6A6A"),
    accent: Color(hex: "0084FF"),
    success: Color(hex: "22C55E")
)

private let cachedTacticalColors = ThemeColors(
    tableHeaderBackground: Color(hex: "1A1A1A"),
    tableCellBackground: Color(hex: "0F0F0F"),
    tableDivider: Color(hex: "3A3A3A"),
    tableBorder: Color(hex: "4A4A4A"),
    background: Color(hex: "0A0A0A"),
    cardBackground: Color(hex: "1A1A1A"),
    searchBackground: Color(hex: "181818"),
    textPrimary: Color(hex: "F0F0F0"),
    textSecondary: Color(hex: "A0A0A0"),
    textTertiary: Color(hex: "707070"),
    accent: Color(hex: "FF8800"),
    success: Color(hex: "00D26A")
)

private let cachedGhostColors = ThemeColors(
    tableHeaderBackground: Color(hex: "F0F0F0", darkHex: "1E1E1E"),
    tableCellBackground: Color(hex: "FAFAFA", darkHex: "141414"),
    tableDivider: Color(hex: "E5E5E5", darkHex: "2A2A2A"),
    tableBorder: Color(hex: "DDDDDD", darkHex: "333333"),
    background: Color(hex: "F5F5F5", darkHex: "0E0E0E"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    searchBackground: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    textPrimary: Color(hex: "2A2A2A", darkHex: "E5E5E5"),
    textSecondary: Color(hex: "7A7A7A", darkHex: "8A8A8A"),
    textTertiary: Color(hex: "A0A0A0", darkHex: "5A5A5A"),
    accent: Color(hex: "6366F1"),
    success: Color(hex: "10B981")
)

private let cachedLiftColors = ThemeColors(
    tableHeaderBackground: Color(hex: "FAFAFA", darkHex: "1A1A1A"),
    tableCellBackground: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    tableDivider: Color(hex: "000000", darkHex: "FFFFFF").opacity(0.04),
    tableBorder: Color(hex: "000000", darkHex: "FFFFFF").opacity(0.10),
    background: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    cardBackground: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
    searchBackground: Color(hex: "FAFAFA", darkHex: "181818"),
    textPrimary: Color(hex: "1A1A1A", darkHex: "FAFAFA"),
    textSecondary: Color(hex: "525252", darkHex: "A0A0A0"),
    textTertiary: Color(hex: "A0A0A0", darkHex: "707070"),
    accent: Color(hex: "6366F1"),
    success: Color(hex: "10B981")
)

// Scope: black-and-gold instrument chassis. Paper-white canvas, warm-graphite
// instrument panels, brass-amber accent. Mirrors the latest direction on
// `ui/instrument-bay-polish` — softer brass over emerald, paper over pure
// white. Dividers/borders derive from ink and auto-flip with mode.
private let cachedScopeColors = ThemeColors(
    tableHeaderBackground: Color(hex: "F5F3EE", darkHex: "1A1714"),
    tableCellBackground: Color(hex: "F8F6F1", darkHex: "13110E"),
    tableDivider: ScopeMobile.ink.opacity(0.06),
    tableBorder: ScopeMobile.ink.opacity(0.10),
    background: Color(hex: "FBFAF7", darkHex: "0A0907"),
    cardBackground: Color(hex: "F8F6F1", darkHex: "13110E"),
    searchBackground: Color(hex: "F2F0EA", darkHex: "151310"),
    textPrimary: Color(hex: "1A1612", darkHex: "F5F3EE"),
    textSecondary: Color(hex: "5A5045", darkHex: "A8A096"),
    textTertiary: Color(hex: "A39989", darkHex: "7D6E5E"),
    accent: Color(hex: "B5823A", darkHex: "E89A3C"),
    success: Color(hex: "6F7D3E", darkHex: "9CB35A")
)

// MARK: - Theme Color Access (O(1) lookup, no parsing)

extension AppTheme {
    var colors: ThemeColors {
        switch self {
        case .scope: return cachedScopeColors
        case .midnight: return cachedMidnightColors
        case .tactical: return cachedTacticalColors
        case .ghost: return cachedGhostColors
        case .lift: return cachedLiftColors
        }
    }

    var isScope: Bool {
        self == .scope
    }
}

// MARK: - Theme Manager

@MainActor
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    private let appSettings = TalkieAppSettings.shared

    @Published var currentTheme: AppTheme {
        didSet {
            appSettings.theme = currentTheme
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            appSettings.appearanceMode = appearanceMode
        }
    }

    var colors: ThemeColors {
        currentTheme.colors
    }

    private init() {
        let configuration = TalkieAppConfigurationStore.shared.configuration
        self.currentTheme = AppTheme(rawValue: configuration.appearance.theme) ?? .scope
        self.appearanceMode = AppearanceMode(rawValue: configuration.appearance.mode) ?? .system
    }

    func reloadFromDisk() {
        let configuration = TalkieAppConfigurationStore.shared.reload()
        currentTheme = AppTheme(rawValue: configuration.appearance.theme) ?? .scope
        appearanceMode = AppearanceMode(rawValue: configuration.appearance.mode) ?? .system
    }

    func apply(theme: AppTheme, appearanceMode: AppearanceMode? = nil) {
        currentTheme = theme
        if let appearanceMode {
            self.appearanceMode = appearanceMode
        }
    }
}
