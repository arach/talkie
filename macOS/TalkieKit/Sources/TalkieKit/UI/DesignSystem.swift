//
//  DesignSystem.swift
//  TalkieKit
//
//  Shared design tokens for Talkie apps
//

import SwiftUI

// MARK: - Spacing

public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

public enum CornerRadius {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
}

// MARK: - Semantic Colors

public enum SemanticColor {
    /// Success/enabled state
    public static let success: Color = .green

    /// Warning state
    public static let warning: Color = .orange

    /// Error state
    public static let error: Color = .red

    /// Info/highlight state
    public static let info: Color = .cyan

    /// Pin/favorite accent
    public static let pin: Color = .blue

    /// Processing/activity state
    public static let processing: Color = .purple
}

// MARK: - TalkieTheme

public enum TalkieTheme {
    // System backgrounds
    public static let background = Color(NSColor.windowBackgroundColor)
    public static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
    public static let backgroundTertiary = Color(NSColor.underPageBackgroundColor)

    // Configurable palette - set at app launch via configure()
    private static var _configuredPalette: ThemeColorPalette?

    /// Configure the theme palette. Call once at app launch.
    /// If not called, reads from SharedSettings or defaults to midnight.
    public static func configure(palette: ThemeColorPalette) {
        _configuredPalette = palette
    }

    private static func currentPalette() -> ThemeColorPalette {
        // 1. Use explicitly configured palette
        if let configured = _configuredPalette {
            return configured
        }

        // 2. Read from SharedSettings
        if let themeString = TalkieSharedSettings.string(forKey: LiveSettingsKey.visualTheme) {
            switch themeString {
            case "terminal": return ThemeColorPalette.terminal()
            case "linear": return ThemeColorPalette.linear()
            case "warm": return ThemeColorPalette.warm()
            case "minimal": return ThemeColorPalette.minimal()
            case "classic": return ThemeColorPalette.classic()
            default: return ThemeColorPalette.midnight()  // talkiePro or unknown
            }
        }

        // 3. Default to midnight
        return ThemeColorPalette.midnight()
    }

    public static var surface: Color { currentPalette().surface }
    public static var surfaceElevated: Color { currentPalette().surfaceElevated }
    public static var surfaceCard: Color { currentPalette().surfaceCard }
    public static var textPrimary: Color { currentPalette().textPrimary }
    public static var textSecondary: Color { currentPalette().textSecondary }
    public static var textTertiary: Color { currentPalette().textTertiary }
    public static var textMuted: Color { currentPalette().textMuted }
    public static var border: Color { currentPalette().border }
    public static var divider: Color { currentPalette().divider }
    public static var hover: Color { currentPalette().hover }
    public static var accent: Color { currentPalette().accent }
    public static var selected: Color { accent.opacity(0.2) }

    // Foreground aliases (for backwards compatibility)
    public static var foreground: Color { textPrimary }
    public static var foregroundSecondary: Color { textSecondary }
    public static var foregroundMuted: Color { textMuted }
}

public struct ThemeColorPalette {
    let surface: Color
    let surfaceElevated: Color
    let surfaceCard: Color
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textMuted: Color
    let border: Color
    let divider: Color
    let hover: Color
    let accent: Color

    /// Midnight/TalkiePro - Deep black, high contrast, cyan accent
    static func midnight() -> ThemeColorPalette {
        ThemeColorPalette(
            surface: Color(NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0)),
            surfaceElevated: Color(NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0)),
            surfaceCard: Color(NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0)),
            textPrimary: Color.white,
            textSecondary: Color.white.opacity(0.7),
            textTertiary: Color.white.opacity(0.5),
            textMuted: Color.white.opacity(0.3),
            border: Color.white.opacity(0.1),
            divider: Color.white.opacity(0.1),
            hover: Color.white.opacity(0.05),
            accent: Color.cyan
        )
    }

    /// Terminal - Green on black, retro terminal aesthetic
    static func terminal() -> ThemeColorPalette {
        let terminalGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
        let dimGreen = Color(red: 0.15, green: 0.6, blue: 0.3)
        return ThemeColorPalette(
            surface: Color(NSColor(red: 0.02, green: 0.03, blue: 0.02, alpha: 1.0)),
            surfaceElevated: Color(NSColor(red: 0.04, green: 0.06, blue: 0.04, alpha: 1.0)),
            surfaceCard: Color(NSColor(red: 0.06, green: 0.08, blue: 0.06, alpha: 1.0)),
            textPrimary: terminalGreen,
            textSecondary: dimGreen,
            textTertiary: dimGreen.opacity(0.7),
            textMuted: dimGreen.opacity(0.5),
            border: terminalGreen.opacity(0.2),
            divider: terminalGreen.opacity(0.1),
            hover: terminalGreen.opacity(0.08),
            accent: terminalGreen
        )
    }

    /// Linear - True black, minimal, Vercel-inspired
    static func linear() -> ThemeColorPalette {
        ThemeColorPalette(
            surface: Color.black,
            surfaceElevated: Color(white: 0.06),
            surfaceCard: Color(white: 0.08),
            textPrimary: Color.white,
            textSecondary: Color(white: 0.7),
            textTertiary: Color(white: 0.5),
            textMuted: Color(white: 0.35),
            border: Color(white: 0.12),
            divider: Color(white: 0.08),
            hover: Color(white: 0.10),
            accent: Color.cyan
        )
    }

    /// Warm - Cozy brown/orange tones
    static func warm() -> ThemeColorPalette {
        let warmAccent = Color(red: 1.0, green: 0.6, blue: 0.2)
        return ThemeColorPalette(
            surface: Color(NSColor(red: 0.08, green: 0.06, blue: 0.04, alpha: 1.0)),
            surfaceElevated: Color(NSColor(red: 0.12, green: 0.09, blue: 0.06, alpha: 1.0)),
            surfaceCard: Color(NSColor(red: 0.14, green: 0.11, blue: 0.08, alpha: 1.0)),
            textPrimary: Color(red: 1.0, green: 0.95, blue: 0.9),
            textSecondary: Color(red: 0.85, green: 0.75, blue: 0.65),
            textTertiary: Color(red: 0.7, green: 0.6, blue: 0.5),
            textMuted: Color(red: 0.5, green: 0.4, blue: 0.35),
            border: Color(red: 0.25, green: 0.2, blue: 0.15),
            divider: Color(red: 0.18, green: 0.14, blue: 0.1),
            hover: Color(red: 0.16, green: 0.12, blue: 0.08),
            accent: warmAccent
        )
    }

    /// Minimal - Clean and subtle, gray accent
    static func minimal() -> ThemeColorPalette {
        ThemeColorPalette(
            surface: Color(white: 0.08),
            surfaceElevated: Color(white: 0.11),
            surfaceCard: Color(white: 0.13),
            textPrimary: Color(white: 0.9),
            textSecondary: Color(white: 0.6),
            textTertiary: Color(white: 0.45),
            textMuted: Color(white: 0.3),
            border: Color(white: 0.18),
            divider: Color(white: 0.12),
            hover: Color(white: 0.14),
            accent: Color(white: 0.6)
        )
    }

    /// Classic - Dark gray, blue accent
    static func classic() -> ThemeColorPalette {
        ThemeColorPalette(
            surface: Color(white: 0.12),
            surfaceElevated: Color(white: 0.15),
            surfaceCard: Color(white: 0.17),
            textPrimary: Color.white,
            textSecondary: Color(white: 0.7),
            textTertiary: Color(white: 0.5),
            textMuted: Color(white: 0.35),
            border: Color(white: 0.2),
            divider: Color(white: 0.15),
            hover: Color(white: 0.18),
            accent: Color.blue
        )
    }
}
