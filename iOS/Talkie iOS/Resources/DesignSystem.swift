//
//  DesignSystem.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI

// MARK: - Color Palette
// Inspired by Apple's precision, Vercel's boldness, Palantir's tactical UI, and Anduril's edge

extension Color {
    // Primary Brand Colors
    static let brandPrimary = Color(hex: "0A0A0A")        // Deep black
    static let brandSecondary = Color(hex: "FAFAFA")      // Pure white
    static let brandAccent = Color(hex: "0070F3")         // Vercel blue

    // Tactical Grays (Palantir/Anduril inspired)
    static let tactical900 = Color(hex: "0A0A0A")
    static let tactical800 = Color(hex: "1A1A1A")
    static let tactical700 = Color(hex: "2A2A2A")
    static let tactical600 = Color(hex: "3A3A3A")
    static let tactical500 = Color(hex: "6A6A6A")
    static let tactical400 = Color(hex: "9A9A9A")
    static let tactical300 = Color(hex: "CACACA")
    static let tactical200 = Color(hex: "E5E5E5")
    static let tactical100 = Color(hex: "F5F5F5")

    // Semantic Colors
    static let recording = Color(hex: "FF3B30")           // Apple red
    static let recordingGlow = Color(hex: "FF453A")
    static let active = Color(hex: "0070F3")              // Active blue
    static let activeGlow = Color(hex: "0084FF")
    static let success = Color(hex: "34C759")             // Apple green
    static let warning = Color(hex: "FF9F0A")             // Apple orange
    static let transcribing = Color(hex: "5E5CE6")        // Apple purple

    // Surface Colors (adapts to light/dark mode)
    static let surfacePrimary = Color(hex: "FFFFFF", darkHex: "0A0A0A")
    static let surfaceSecondary = Color(hex: "F5F5F5", darkHex: "1A1A1A")
    static let surfaceTertiary = Color(hex: "E5E5E5", darkHex: "2A2A2A")

    // Text Colors
    static let textPrimary = Color(hex: "0A0A0A", darkHex: "FAFAFA")
    static let textSecondary = Color(hex: "6A6A6A", darkHex: "9A9A9A")
    static let textTertiary = Color(hex: "9A9A9A", darkHex: "6A6A6A")

    // Border Colors
    static let borderPrimary = Color(hex: "E5E5E5", darkHex: "2A2A2A")
    static let borderSecondary = Color(hex: "F5F5F5", darkHex: "1A1A1A")
}

// MARK: - Color Hex Initializer
extension Color {
    init(hex: String, darkHex: String? = nil) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        let lightColor = UIColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )

        if let darkHex = darkHex {
            let darkHexTrimmed = darkHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            var darkInt: UInt64 = 0
            Scanner(string: darkHexTrimmed).scanHexInt64(&darkInt)
            let da, dr, dg, db: UInt64
            switch darkHexTrimmed.count {
            case 6:
                (da, dr, dg, db) = (255, darkInt >> 16, darkInt >> 8 & 0xFF, darkInt & 0xFF)
            case 8:
                (da, dr, dg, db) = (darkInt >> 24, darkInt >> 16 & 0xFF, darkInt >> 8 & 0xFF, darkInt & 0xFF)
            default:
                (da, dr, dg, db) = (255, 0, 0, 0)
            }

            let darkColor = UIColor(
                red: CGFloat(dr) / 255,
                green: CGFloat(dg) / 255,
                blue: CGFloat(db) / 255,
                alpha: CGFloat(da) / 255
            )

            self.init(uiColor: UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? darkColor : lightColor
            })
        } else {
            self.init(uiColor: lightColor)
        }
    }
}

// MARK: - Typography (Tactical/Dev-Tool Oriented)
extension Font {
    // Display - More technical, less rounded
    static let displayLarge = Font.system(size: 32, weight: .bold, design: .default)
    static let displayMedium = Font.system(size: 26, weight: .bold, design: .default)
    static let displaySmall = Font.system(size: 22, weight: .semibold, design: .default)

    // Headline - Tactical
    static let headlineLarge = Font.system(size: 18, weight: .semibold, design: .default)
    static let headlineMedium = Font.system(size: 16, weight: .semibold, design: .default)
    static let headlineSmall = Font.system(size: 14, weight: .semibold, design: .default)

    // Body - Prefer monospace for dev tool feel
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .monospaced)

    // Label - Compact and precise
    static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 11, weight: .medium, design: .default)
    static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)

    // Monospace (for durations, technical data) - primary choice
    static let monoLarge = Font.system(size: 16, weight: .medium, design: .monospaced)
    static let monoMedium = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)

    // Technical labels - uppercase, tracked
    static let techLabel = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let techLabelSmall = Font.system(size: 9, weight: .bold, design: .monospaced)
}

// MARK: - Spacing (Tighter, more tactical)
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let xxl: CGFloat = 40
}

// MARK: - Corner Radius
enum CornerRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let full: CGFloat = 9999
}

// MARK: - Shadow
struct TalkieShadow {
    static let small = (color: Color.black.opacity(0.05), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
    static let medium = (color: Color.black.opacity(0.08), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
    static let large = (color: Color.black.opacity(0.12), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(8))
}

// MARK: - Animations
enum TalkieAnimation {
    static let fast = Animation.easeInOut(duration: 0.2)
    static let medium = Animation.easeInOut(duration: 0.3)
    static let slow = Animation.easeInOut(duration: 0.5)
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
}
