//
//  ThemeManager.swift
//  Talkie iOS
//
//  Manages app themes with 3 configurable options
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
    case midnight = "midnight"
    case tactical = "tactical"
    case ghost = "ghost"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .midnight: return "Midnight"
        case .tactical: return "Tactical"
        case .ghost: return "Ghost"
        }
    }

    var description: String {
        switch self {
        case .midnight: return "Deep black with subtle highlights"
        case .tactical: return "High contrast, sharp edges"
        case .ghost: return "Soft, muted elegance"
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

// MARK: - Theme Definitions

extension AppTheme {
    var colors: ThemeColors {
        switch self {
        case .midnight:
            return ThemeColors(
                tableHeaderBackground: Color(hex: "1A1A1A", darkHex: "1A1A1A"),
                tableCellBackground: Color(hex: "F5F5F5", darkHex: "000000"),
                tableDivider: Color(hex: "E0E0E0", darkHex: "FFFFFF").opacity(0.08),
                tableBorder: Color(hex: "D0D0D0", darkHex: "FFFFFF").opacity(0.12),
                background: Color(hex: "FFFFFF", darkHex: "0A0A0A"),
                cardBackground: Color(hex: "F8F8F8", darkHex: "111111"),
                searchBackground: Color(hex: "F0F0F0", darkHex: "0F0F0F"),
                textPrimary: Color(hex: "0A0A0A", darkHex: "FAFAFA"),
                textSecondary: Color(hex: "6A6A6A", darkHex: "9A9A9A"),
                textTertiary: Color(hex: "9A9A9A", darkHex: "6A6A6A"),
                accent: Color(hex: "0070F3"),
                success: Color(hex: "22C55E")
            )

        case .tactical:
            return ThemeColors(
                tableHeaderBackground: Color(hex: "E8E8E8", darkHex: "252525"),
                tableCellBackground: Color(hex: "FAFAFA", darkHex: "0F0F0F"),
                tableDivider: Color(hex: "CCCCCC", darkHex: "3A3A3A"),
                tableBorder: Color(hex: "BBBBBB", darkHex: "4A4A4A"),
                background: Color(hex: "F0F0F0", darkHex: "0A0A0A"),
                cardBackground: Color(hex: "FFFFFF", darkHex: "1A1A1A"),
                searchBackground: Color(hex: "FFFFFF", darkHex: "181818"),
                textPrimary: Color(hex: "1A1A1A", darkHex: "F0F0F0"),
                textSecondary: Color(hex: "5A5A5A", darkHex: "A0A0A0"),
                textTertiary: Color(hex: "8A8A8A", darkHex: "707070"),
                accent: Color(hex: "FF6B00"),
                success: Color(hex: "00D26A")
            )

        case .ghost:
            return ThemeColors(
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
        }
    }
}

// MARK: - Theme Manager

class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private let themeKey = "selectedTheme"
    private let appearanceKey = "appearanceMode"

    @Published var currentTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: themeKey)
        }
    }

    @Published var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceKey)
            // Also save to App Group for widget
            UserDefaults(suiteName: "group.com.jdi.talkie")?.set(appearanceMode.rawValue, forKey: appearanceKey)
        }
    }

    var colors: ThemeColors {
        currentTheme.colors
    }

    private init() {
        // Load theme
        if let savedTheme = UserDefaults.standard.string(forKey: themeKey),
           let theme = AppTheme(rawValue: savedTheme) {
            self.currentTheme = theme
        } else {
            self.currentTheme = .midnight
        }

        // Load appearance mode
        if let savedAppearance = UserDefaults.standard.string(forKey: appearanceKey),
           let appearance = AppearanceMode(rawValue: savedAppearance) {
            self.appearanceMode = appearance
        } else {
            self.appearanceMode = .system
        }
    }
}

// MARK: - Environment Key

struct ThemeKey: EnvironmentKey {
    static let defaultValue: ThemeManager = ThemeManager.shared
}

extension EnvironmentValues {
    var theme: ThemeManager {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
