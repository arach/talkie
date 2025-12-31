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
    public let surface: Color
    public let surfaceElevated: Color
    public let surfaceCard: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let textMuted: Color
    public let border: Color
    public let divider: Color
    public let hover: Color
    public let accent: Color

    public init(
        surface: Color,
        surfaceElevated: Color,
        surfaceCard: Color,
        textPrimary: Color,
        textSecondary: Color,
        textTertiary: Color,
        textMuted: Color,
        border: Color,
        divider: Color,
        hover: Color,
        accent: Color
    ) {
        self.surface = surface
        self.surfaceElevated = surfaceElevated
        self.surfaceCard = surfaceCard
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.textMuted = textMuted
        self.border = border
        self.divider = divider
        self.hover = hover
        self.accent = accent
    }

    // MARK: - Adaptive Themes (support light/dark mode)

    /// Midnight/TalkiePro - Deep black in dark, clean white in light
    public static func midnight(for scheme: ColorScheme = .dark) -> ThemeColorPalette {
        if scheme == .dark {
            return ThemeColorPalette(
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
        } else {
            return ThemeColorPalette(
                surface: Color(white: 0.98),
                surfaceElevated: Color.white,
                surfaceCard: Color.white,
                textPrimary: Color(white: 0.1),
                textSecondary: Color(white: 0.4),
                textTertiary: Color(white: 0.55),
                textMuted: Color(white: 0.7),
                border: Color.black.opacity(0.1),
                divider: Color.black.opacity(0.08),
                hover: Color.black.opacity(0.04),
                accent: Color(red: 0.0, green: 0.6, blue: 0.8)  // Darker cyan for light mode
            )
        }
    }

    /// Warm - Cozy brown/orange tones (adapts to light mode)
    public static func warm(for scheme: ColorScheme = .dark) -> ThemeColorPalette {
        if scheme == .dark {
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
        } else {
            let warmAccentLight = Color(red: 0.9, green: 0.5, blue: 0.1)
            return ThemeColorPalette(
                surface: Color(red: 1.0, green: 0.98, blue: 0.95),
                surfaceElevated: Color(red: 0.99, green: 0.97, blue: 0.94),
                surfaceCard: Color.white,
                textPrimary: Color(red: 0.2, green: 0.15, blue: 0.1),
                textSecondary: Color(red: 0.45, green: 0.38, blue: 0.3),
                textTertiary: Color(red: 0.55, green: 0.48, blue: 0.4),
                textMuted: Color(red: 0.7, green: 0.63, blue: 0.55),
                border: Color(red: 0.85, green: 0.78, blue: 0.68),
                divider: Color(red: 0.9, green: 0.85, blue: 0.78),
                hover: Color(red: 0.95, green: 0.9, blue: 0.82),
                accent: warmAccentLight
            )
        }
    }

    /// Minimal - Clean and subtle (adapts to light mode)
    public static func minimal(for scheme: ColorScheme = .dark) -> ThemeColorPalette {
        if scheme == .dark {
            return ThemeColorPalette(
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
        } else {
            return ThemeColorPalette(
                surface: Color(white: 0.96),
                surfaceElevated: Color(white: 0.99),
                surfaceCard: Color.white,
                textPrimary: Color(white: 0.15),
                textSecondary: Color(white: 0.45),
                textTertiary: Color(white: 0.55),
                textMuted: Color(white: 0.7),
                border: Color(white: 0.85),
                divider: Color(white: 0.9),
                hover: Color(white: 0.92),
                accent: Color(white: 0.45)
            )
        }
    }

    /// Classic - Gray tones, blue accent (adapts to light mode)
    public static func classic(for scheme: ColorScheme = .dark) -> ThemeColorPalette {
        if scheme == .dark {
            return ThemeColorPalette(
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
        } else {
            return ThemeColorPalette(
                surface: Color(white: 0.94),
                surfaceElevated: Color(white: 0.98),
                surfaceCard: Color.white,
                textPrimary: Color(white: 0.1),
                textSecondary: Color(white: 0.4),
                textTertiary: Color(white: 0.55),
                textMuted: Color(white: 0.7),
                border: Color(white: 0.82),
                divider: Color(white: 0.88),
                hover: Color(white: 0.9),
                accent: Color(red: 0.0, green: 0.4, blue: 0.9)  // Darker blue for light mode
            )
        }
    }

    // MARK: - Tech Themes (adapt to light/dark)

    /// Terminal - Green terminal aesthetic (adapts to light/dark)
    public static func terminal(for scheme: ColorScheme = .dark) -> ThemeColorPalette {
        let terminalGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
        let darkGreen = Color(red: 0.1, green: 0.5, blue: 0.25)
        let dimGreen = Color(red: 0.15, green: 0.6, blue: 0.3)

        if scheme == .dark {
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
        } else {
            return ThemeColorPalette(
                surface: Color(red: 0.95, green: 0.99, blue: 0.95),
                surfaceElevated: Color(red: 0.96, green: 0.99, blue: 0.96),
                surfaceCard: Color.white,
                textPrimary: darkGreen,
                textSecondary: Color(red: 0.2, green: 0.5, blue: 0.3),
                textTertiary: Color(red: 0.3, green: 0.55, blue: 0.38),
                textMuted: Color(red: 0.5, green: 0.65, blue: 0.55),
                border: darkGreen.opacity(0.2),
                divider: darkGreen.opacity(0.1),
                hover: darkGreen.opacity(0.05),
                accent: darkGreen
            )
        }
    }

    /// Linear - Sharp, minimal, Vercel-inspired (adapts to light/dark)
    public static func linear(for scheme: ColorScheme = .dark) -> ThemeColorPalette {
        if scheme == .dark {
            return ThemeColorPalette(
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
        } else {
            return ThemeColorPalette(
                surface: Color.white,
                surfaceElevated: Color(white: 0.99),
                surfaceCard: Color.white,
                textPrimary: Color.black,
                textSecondary: Color(white: 0.35),
                textTertiary: Color(white: 0.5),
                textMuted: Color(white: 0.65),
                border: Color(white: 0.88),
                divider: Color(white: 0.92),
                hover: Color(white: 0.96),
                accent: Color(red: 0.0, green: 0.5, blue: 0.7)  // Darker cyan for light
            )
        }
    }

    // MARK: - Legacy (no colorScheme parameter for backward compatibility)

    /// @available(*, deprecated, message: "Use midnight(for:) instead")
    public static func midnight() -> ThemeColorPalette {
        midnight(for: .dark)
    }

    /// @available(*, deprecated, message: "Use terminal(for:) instead")
    public static func terminal() -> ThemeColorPalette {
        terminal(for: .dark)
    }

    /// @available(*, deprecated, message: "Use linear(for:) instead")
    public static func linear() -> ThemeColorPalette {
        linear(for: .dark)
    }

    /// @available(*, deprecated, message: "Use warm(for:) instead")
    public static func warm() -> ThemeColorPalette {
        warm(for: .dark)
    }

    /// @available(*, deprecated, message: "Use minimal(for:) instead")
    public static func minimal() -> ThemeColorPalette {
        minimal(for: .dark)
    }

    /// @available(*, deprecated, message: "Use classic(for:) instead")
    public static func classic() -> ThemeColorPalette {
        classic(for: .dark)
    }
}
