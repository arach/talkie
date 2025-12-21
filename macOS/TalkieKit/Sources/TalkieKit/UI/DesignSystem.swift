//
//  DesignSystem.swift
//  TalkieKit
//
//  Shared design tokens for Talkie apps
//

import SwiftUI

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

    private static func currentPalette() -> ThemeColorPalette {
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
}
