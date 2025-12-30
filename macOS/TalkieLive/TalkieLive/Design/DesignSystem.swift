//
//  DesignSystem.swift
//  TalkieLive
//
//  Design tokens matching macOS Talkie for consistent cross-platform styling.
//

import SwiftUI

// MARK: - Spacing (Tighter, tactical feel)

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
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

// MARK: - Typography

extension Font {
    // Display
    static let displayLarge = Font.system(size: 32, weight: .bold, design: .default)
    static let displayMedium = Font.system(size: 26, weight: .bold, design: .default)
    static let displaySmall = Font.system(size: 22, weight: .semibold, design: .default)

    // Headline
    static let headlineLarge = Font.system(size: 18, weight: .semibold, design: .default)
    static let headlineMedium = Font.system(size: 16, weight: .semibold, design: .default)
    static let headlineSmall = Font.system(size: 14, weight: .semibold, design: .default)

    // Body (mono for tactical feel)
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .monospaced)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .monospaced)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .monospaced)

    // Label
    static let labelLarge = Font.system(size: 13, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 11, weight: .medium, design: .default)
    static let labelSmall = Font.system(size: 10, weight: .medium, design: .default)

    // Tech Labels (section headers)
    static let techLabel = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let techLabelSmall = Font.system(size: 9, weight: .bold, design: .monospaced)

    // Mono
    static let monoLarge = Font.system(size: 16, weight: .medium, design: .monospaced)
    static let monoMedium = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let monoSmall = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoXSmall = Font.system(size: 10, weight: .regular, design: .monospaced)
}

// MARK: - Tracking Presets

enum Tracking {
    static let tight: CGFloat = 0.5
    static let normal: CGFloat = 1.0
    static let medium: CGFloat = 1.5
    static let wide: CGFloat = 2.0
}

// MARK: - Opacity Presets

enum Opacity {
    static let subtle: Double = 0.03
    static let light: Double = 0.08
    static let medium: Double = 0.15
    static let strong: Double = 0.3
    static let half: Double = 0.5
    static let prominent: Double = 0.7
}

// MARK: - Animation Presets

enum TalkieAnimation {
    static let fast = Animation.easeInOut(duration: 0.15)
    static let normal = Animation.easeInOut(duration: 0.25)
    static let slow = Animation.easeInOut(duration: 0.4)
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
}

// MARK: - Semantic Colors

enum SemanticColor {
    static let success: Color = .green
    static let warning: Color = .orange
    static let error: Color = .red
    static let info: Color = .cyan
    static let pin: Color = .blue
    static let processing: Color = .purple
}

// MARK: - Theme Color Palette

/// Complete color palette for a visual theme
struct ThemeColorPalette {
    // Surfaces
    let surface: Color
    let surfaceElevated: Color
    let surfaceCard: Color

    // Text
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color
    let textMuted: Color

    // Borders
    let border: Color
    let divider: Color

    // Interactive
    let hover: Color
    let accent: Color

    // MARK: - Theme Definitions

    static func palette(for theme: VisualTheme, isDark: Bool) -> ThemeColorPalette {
        switch theme {
        case .live:
            return liveTheme(isDark: isDark)
        case .midnight:
            return midnightTheme(isDark: isDark)
        case .terminal:
            return terminalTheme(isDark: isDark)
        case .warm:
            return warmTheme(isDark: isDark)
        case .minimal:
            return minimalTheme(isDark: isDark)
        }
    }

    // MARK: - Live Theme (Default)
    private static func liveTheme(isDark: Bool) -> ThemeColorPalette {
        if isDark {
            return ThemeColorPalette(
                surface: Color(white: 0.06),
                surfaceElevated: Color(white: 0.10),
                surfaceCard: Color(white: 0.12),
                textPrimary: .white,
                textSecondary: Color(white: 0.7),
                textTertiary: Color(white: 0.5),
                textMuted: Color(white: 0.35),
                border: Color(white: 0.15),
                divider: Color(white: 0.1),
                hover: Color(white: 0.12),
                accent: .blue
            )
        } else {
            return ThemeColorPalette(
                surface: Color(white: 0.98),
                surfaceElevated: Color(white: 0.95),
                surfaceCard: .white,
                textPrimary: Color(white: 0.1),
                textSecondary: Color(white: 0.4),
                textTertiary: Color(white: 0.55),
                textMuted: Color(white: 0.7),
                border: Color(white: 0.88),
                divider: Color(white: 0.92),
                hover: Color(white: 0.94),
                accent: .blue
            )
        }
    }

    // MARK: - Midnight Theme (Deep black/pure white, high contrast)
    private static func midnightTheme(isDark: Bool) -> ThemeColorPalette {
        let midnightAccent = Color(red: 0.4, green: 0.7, blue: 1.0)
        if isDark {
            return ThemeColorPalette(
                surface: Color(red: 0.02, green: 0.02, blue: 0.03),
                surfaceElevated: Color(red: 0.06, green: 0.06, blue: 0.07),
                surfaceCard: Color(red: 0.08, green: 0.08, blue: 0.09),
                textPrimary: .white,
                textSecondary: Color(white: 0.75),
                textTertiary: Color(white: 0.55),
                textMuted: Color(white: 0.35),
                border: Color(white: 0.12),
                divider: Color(white: 0.08),
                hover: Color(white: 0.10),
                accent: midnightAccent
            )
        } else {
            // Light mode: Pure white, high contrast black text
            return ThemeColorPalette(
                surface: .white,
                surfaceElevated: Color(white: 0.97),
                surfaceCard: Color(white: 0.99),
                textPrimary: Color(red: 0.02, green: 0.02, blue: 0.03),
                textSecondary: Color(white: 0.3),
                textTertiary: Color(white: 0.45),
                textMuted: Color(white: 0.6),
                border: Color(white: 0.85),
                divider: Color(white: 0.9),
                hover: Color(white: 0.95),
                accent: midnightAccent
            )
        }
    }

    // MARK: - Terminal Theme (Green on black / dark green on paper)
    private static func terminalTheme(isDark: Bool) -> ThemeColorPalette {
        if isDark {
            let terminalGreen = Color(red: 0.2, green: 0.9, blue: 0.4)
            let dimGreen = Color(red: 0.15, green: 0.6, blue: 0.3)
            return ThemeColorPalette(
                surface: Color(red: 0.02, green: 0.03, blue: 0.02),
                surfaceElevated: Color(red: 0.04, green: 0.06, blue: 0.04),
                surfaceCard: Color(red: 0.06, green: 0.08, blue: 0.06),
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
            // Light mode: Paper-like background with dark green text (like a printout)
            let darkGreen = Color(red: 0.05, green: 0.35, blue: 0.15)
            let mediumGreen = Color(red: 0.1, green: 0.45, blue: 0.2)
            return ThemeColorPalette(
                surface: Color(red: 0.97, green: 0.98, blue: 0.96),
                surfaceElevated: Color(red: 0.94, green: 0.96, blue: 0.93),
                surfaceCard: Color(red: 0.99, green: 1.0, blue: 0.98),
                textPrimary: darkGreen,
                textSecondary: mediumGreen,
                textTertiary: mediumGreen.opacity(0.7),
                textMuted: mediumGreen.opacity(0.5),
                border: darkGreen.opacity(0.15),
                divider: darkGreen.opacity(0.08),
                hover: darkGreen.opacity(0.06),
                accent: darkGreen
            )
        }
    }

    // MARK: - Warm Theme (Cozy orange tones)
    private static func warmTheme(isDark: Bool) -> ThemeColorPalette {
        let warmAccent = Color(red: 1.0, green: 0.6, blue: 0.2)
        if isDark {
            return ThemeColorPalette(
                surface: Color(red: 0.08, green: 0.06, blue: 0.04),
                surfaceElevated: Color(red: 0.12, green: 0.09, blue: 0.06),
                surfaceCard: Color(red: 0.14, green: 0.11, blue: 0.08),
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
            return ThemeColorPalette(
                surface: Color(red: 0.98, green: 0.96, blue: 0.94),
                surfaceElevated: Color(red: 0.96, green: 0.93, blue: 0.90),
                surfaceCard: Color(red: 1.0, green: 0.98, blue: 0.96),
                textPrimary: Color(red: 0.2, green: 0.15, blue: 0.1),
                textSecondary: Color(red: 0.4, green: 0.35, blue: 0.3),
                textTertiary: Color(red: 0.55, green: 0.5, blue: 0.45),
                textMuted: Color(red: 0.7, green: 0.65, blue: 0.6),
                border: Color(red: 0.85, green: 0.8, blue: 0.75),
                divider: Color(red: 0.9, green: 0.87, blue: 0.84),
                hover: Color(red: 0.94, green: 0.91, blue: 0.88),
                accent: warmAccent
            )
        }
    }

    // MARK: - Minimal Theme (Clean and subtle)
    private static func minimalTheme(isDark: Bool) -> ThemeColorPalette {
        if isDark {
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
                surface: Color(white: 0.97),
                surfaceElevated: Color(white: 0.94),
                surfaceCard: .white,
                textPrimary: Color(white: 0.15),
                textSecondary: Color(white: 0.45),
                textTertiary: Color(white: 0.6),
                textMuted: Color(white: 0.75),
                border: Color(white: 0.85),
                divider: Color(white: 0.9),
                hover: Color(white: 0.92),
                accent: Color(white: 0.5)
            )
        }
    }
}

// MARK: - TalkieTheme (Dynamic Theme Provider)

/// Provides theme colors based on the current VisualTheme setting.
/// Colors are resolved dynamically based on current theme and appearance.
@MainActor
enum TalkieTheme {
    // System backgrounds (always follow system)
    static let background = Color(NSColor.windowBackgroundColor)
    static let secondaryBackground = Color(NSColor.controlBackgroundColor)
    static let tertiaryBackground = Color(NSColor.underPageBackgroundColor)

    /// Get the current palette based on theme and appearance
    private static func currentPalette() -> ThemeColorPalette {
        let theme = LiveSettings.shared.visualTheme
        let isDark: Bool
        switch LiveSettings.shared.appearanceMode {
        case .dark:
            isDark = true
        case .light:
            isDark = false
        case .system:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        return ThemeColorPalette.palette(for: theme, isDark: isDark)
    }

    static var surface: Color { currentPalette().surface }
    static var surfaceElevated: Color { currentPalette().surfaceElevated }
    static var surfaceCard: Color { currentPalette().surfaceCard }
    static var textPrimary: Color { currentPalette().textPrimary }
    static var textSecondary: Color { currentPalette().textSecondary }
    static var textTertiary: Color { currentPalette().textTertiary }
    static var textMuted: Color { currentPalette().textMuted }
    static var border: Color { currentPalette().border }
    static var divider: Color { currentPalette().divider }
    static var hover: Color { currentPalette().hover }
    static var accent: Color { currentPalette().accent }

    static var selected: Color {
        let palette = currentPalette()
        let isDark: Bool
        switch LiveSettings.shared.appearanceMode {
        case .dark: isDark = true
        case .light: isDark = false
        case .system: isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        return palette.accent.opacity(isDark ? 0.2 : 0.12)
    }
}

// MARK: - Theme Environment Key

/// Environment key for passing theme through SwiftUI view hierarchy
private struct ThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: VisualTheme = .live
}

extension EnvironmentValues {
    var visualTheme: VisualTheme {
        get { self[ThemeEnvironmentKey.self] }
        set { self[ThemeEnvironmentKey.self] = newValue }
    }
}

// MARK: - Theme-Aware View Modifier

/// View modifier that provides theme colors as a binding for reactive updates
struct ThemeColors {
    let theme: VisualTheme
    let isDark: Bool

    var palette: ThemeColorPalette {
        ThemeColorPalette.palette(for: theme, isDark: isDark)
    }

    var surface: Color { palette.surface }
    var surfaceElevated: Color { palette.surfaceElevated }
    var surfaceCard: Color { palette.surfaceCard }
    var textPrimary: Color { palette.textPrimary }
    var textSecondary: Color { palette.textSecondary }
    var textTertiary: Color { palette.textTertiary }
    var textMuted: Color { palette.textMuted }
    var border: Color { palette.border }
    var divider: Color { palette.divider }
    var hover: Color { palette.hover }
    var accent: Color { palette.accent }
    var selected: Color { palette.accent.opacity(isDark ? 0.2 : 0.12) }
}

/// View modifier that observes theme changes and triggers re-renders
struct ThemeObserver: ViewModifier {
    @ObservedObject private var settings = LiveSettings.shared
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .id("theme-\(settings.visualTheme.rawValue)-\(settings.appearanceMode.rawValue)-\(colorScheme)")
    }
}

extension View {
    /// Apply this modifier to views that need to react to theme changes
    func observeTheme() -> some View {
        modifier(ThemeObserver())
    }
}

// Helper for light/dark adaptive colors
extension Color {
    init(light: Color, dark: Color) {
        self.init(NSColor(name: nil, dynamicProvider: { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua:
                return NSColor(dark)
            default:
                return NSColor(light)
            }
        }))
    }
}

// MARK: - Midnight Theme Surface Colors (Legacy - for dark-only contexts)

enum MidnightSurface {
    static let content = Color(NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0))
    static let sidebar = Color(NSColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1.0))
    static let elevated = Color(NSColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1.0))
    static let card = Color(NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0))
    static let divider = Color.white.opacity(0.1)

    enum Text {
        static let primary = Color.white
        static let secondary = Color.white.opacity(0.7)
        static let tertiary = Color.white.opacity(0.5)
        static let quaternary = Color.white.opacity(0.3)
    }
}

// MARK: - Legacy Design Tokens (for compatibility)

struct Design {
    static let fontXS = Font.system(size: 10, weight: .regular)
    static let fontXSMedium = Font.system(size: 10, weight: .medium)
    static let fontXSBold = Font.system(size: 10, weight: .semibold)

    static let fontSM = Font.system(size: 11, weight: .regular)
    static let fontSMMedium = Font.system(size: 11, weight: .medium)
    static let fontSMBold = Font.system(size: 11, weight: .semibold)

    static let fontBody = Font.system(size: 13, weight: .regular)
    static let fontBodyMedium = Font.system(size: 13, weight: .medium)
    static let fontBodyBold = Font.system(size: 13, weight: .semibold)

    static let fontTitle = Font.system(size: 15, weight: .medium)
    static let fontTitleBold = Font.system(size: 15, weight: .bold)

    static let fontHeadline = Font.system(size: 18, weight: .medium)

    // Use MidnightSurface colors for consistent dark theme
    static var background: Color { MidnightSurface.content }
    static var backgroundSecondary: Color { MidnightSurface.sidebar }
    static var backgroundTertiary: Color { MidnightSurface.elevated }

    static var foreground: Color { Color.primary }
    static var foregroundSecondary: Color { Color.secondary }
    static var foregroundMuted: Color { Color.secondary.opacity(0.7) }

    static var divider: Color { Color(NSColor.separatorColor) }
    static var accent: Color { Color.accentColor }
}

// MARK: - Reusable Components

struct SidebarHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.techLabel)
                .tracking(Tracking.wide)
                .foregroundColor(TalkieTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

struct SidebarSearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(Design.fontXS)
                .foregroundColor(TalkieTheme.textMuted)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Design.fontXS)
                .foregroundColor(TalkieTheme.textPrimary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(TalkieTheme.surfaceElevated)
        .cornerRadius(CornerRadius.xs)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.techLabelSmall)
            .tracking(Tracking.normal)
            .foregroundColor(.secondary.opacity(0.6))
    }
}

struct SidebarRow: View {
    let icon: String
    let title: String
    var count: Int? = nil
    var isActive: Bool = false

    var body: some View {
        Label {
            HStack {
                Text(title)
                    .font(.labelMedium)
                Spacer()
                if let count = count {
                    Text("\(count)")
                        .font(.monoXSmall)
                        .foregroundColor(.secondary)
                }
            }
        } icon: {
            Image(systemName: icon)
                .font(Design.fontXS)
        }
    }
}

struct SidebarNavButton: View {
    let icon: String
    let title: String
    var count: Int? = nil
    var isSelected: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : TalkieTheme.textSecondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)

                Spacer()

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(TalkieTheme.surfaceElevated)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? TalkieTheme.selected : (isHovered ? TalkieTheme.hover : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Button Styles

struct IconButtonStyle: ButtonStyle {
    var hoverColor: Color = .primary
    var size: CGFloat = 24

    func makeBody(configuration: Configuration) -> some View {
        IconButtonView(configuration: configuration, hoverColor: hoverColor, size: size)
    }
}

private struct IconButtonView: View {
    let configuration: ButtonStyleConfiguration
    let hoverColor: Color
    let size: CGFloat
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(isHovered ? hoverColor.opacity(Opacity.light) : Color.clear)
            )
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(TalkieAnimation.fast, value: configuration.isPressed)
            .animation(TalkieAnimation.fast, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var icon: IconButtonStyle { IconButtonStyle() }
    static func icon(color: Color, size: CGFloat = 24) -> IconButtonStyle {
        IconButtonStyle(hoverColor: color, size: size)
    }
    static var iconDestructive: IconButtonStyle {
        IconButtonStyle(hoverColor: SemanticColor.error, size: 24)
    }
    static var iconSmall: IconButtonStyle { IconButtonStyle(size: 20) }
    static var iconTiny: IconButtonStyle { IconButtonStyle(size: 16) }
}

struct TinyButtonStyle: ButtonStyle {
    var foregroundColor: Color = .secondary
    var hoverForeground: Color? = nil
    var hoverBackground: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        TinyButtonView(
            configuration: configuration,
            foregroundColor: foregroundColor,
            hoverForeground: hoverForeground,
            hoverBackground: hoverBackground
        )
    }
}

private struct TinyButtonView: View {
    let configuration: ButtonStyleConfiguration
    let foregroundColor: Color
    let hoverForeground: Color?
    let hoverBackground: Color
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundColor(isHovered ? (hoverForeground ?? foregroundColor) : foregroundColor)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isHovered ? hoverBackground.opacity(Opacity.light) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(TalkieAnimation.fast, value: configuration.isPressed)
            .animation(TalkieAnimation.fast, value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension ButtonStyle where Self == TinyButtonStyle {
    static var tiny: TinyButtonStyle { TinyButtonStyle() }
    static var tinyDestructive: TinyButtonStyle {
        TinyButtonStyle(
            foregroundColor: .secondary,
            hoverForeground: SemanticColor.error,
            hoverBackground: SemanticColor.error
        )
    }
    static var tinyPrimary: TinyButtonStyle {
        TinyButtonStyle(foregroundColor: .primary, hoverBackground: .primary)
    }
}

// MARK: - Glass Design System

/// Glass intensity levels for different use cases
enum GlassIntensity {
    case subtle     // Light frosting, more transparency
    case regular    // Standard glass effect
    case prominent  // Heavier frosting, more opaque

    var material: Material {
        switch self {
        case .subtle: return .ultraThinMaterial
        case .regular: return .thinMaterial
        case .prominent: return .regularMaterial
        }
    }

    var highlightOpacity: Double {
        switch self {
        case .subtle: return 0.15
        case .regular: return 0.25
        case .prominent: return 0.35
        }
    }

    var borderOpacity: Double {
        switch self {
        case .subtle: return 0.08
        case .regular: return 0.12
        case .prominent: return 0.15
        }
    }
}

/// Glass background view modifier
struct GlassBackground: ViewModifier {
    var intensity: GlassIntensity = .regular
    var cornerRadius: CGFloat = CornerRadius.sm
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Base material
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(intensity.material)

                    // Optional color tint
                    if let tint = tint {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(tint.opacity(0.05))
                    }

                    // Inner glow (top-down radial)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.clear
                                ],
                                center: .top,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )

                    // Convex gradient (gives curved glass illusion)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(intensity.highlightOpacity * 0.5),
                                    Color.white.opacity(0.02),
                                    Color.black.opacity(0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Top edge highlight (light catching the edge)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(intensity.highlightOpacity),
                                    Color.white.opacity(intensity.highlightOpacity * 0.4),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 1
                        )

                    // Subtle border
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.white.opacity(intensity.borderOpacity), lineWidth: 0.5)
                }
            )
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
            .shadow(color: Color.white.opacity(0.03), radius: 1, x: 0, y: -1)
    }
}

extension View {
    /// Apply a glass background effect
    func glassBackground(
        intensity: GlassIntensity = .regular,
        cornerRadius: CGFloat = CornerRadius.sm,
        tint: Color? = nil
    ) -> some View {
        modifier(GlassBackground(intensity: intensity, cornerRadius: cornerRadius, tint: tint))
    }
}

/// A glass-styled card container
struct GlassCardView<Content: View>: View {
    var intensity: GlassIntensity = .regular
    var cornerRadius: CGFloat = CornerRadius.md
    var padding: CGFloat = Spacing.md
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .glassBackground(intensity: intensity, cornerRadius: cornerRadius)
    }
}

/// A glass-styled row for settings/list items
struct GlassRow<Content: View>: View {
    var isSelected: Bool = false
    var accentColor: Color = TalkieTheme.accent
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            content()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            ZStack {
                // Hover/selection state
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(
                        isSelected
                            ? accentColor.opacity(0.15)
                            : (isHovered ? Color.white.opacity(0.06) : Color.clear)
                    )

                // Subtle top highlight on hover
                if isHovered || isSelected {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isSelected ? 0.15 : 0.08),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.5
                        )
                }
            }
        )
        .animation(TalkieAnimation.fast, value: isHovered)
        .animation(TalkieAnimation.fast, value: isSelected)
        .onHover { isHovered = $0 }
    }
}

/// Glass-styled sidebar container
struct GlassSidebar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            ZStack {
                // Base frosted glass
                Rectangle()
                    .fill(.ultraThinMaterial)

                // Subtle gradient overlay
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.04),
                                Color.clear,
                                Color.black.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Right edge highlight (like light on glass edge)
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 1)
                }
            }
        )
    }
}

/// Glass-styled tab button
struct GlassTabButton: View {
    let icon: String
    let label: String?
    var isSelected: Bool
    var showWarning: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))

                if let label = label {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                }

                if showWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(isSelected ? .white : TalkieTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    if isSelected {
                        // Selected: accent color with glass overlay
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(TalkieTheme.accent)

                        // Glass highlight on top
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.25),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    } else if isHovered {
                        // Hovered: subtle glass
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Color.white.opacity(0.08))

                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    }
                }
            )
            .shadow(color: isSelected ? TalkieTheme.accent.opacity(0.3) : Color.clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .animation(TalkieAnimation.fast, value: isSelected)
        .animation(TalkieAnimation.fast, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

/// Glass-styled window/panel background
struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Deep glass effect for panels
                    VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

                    // Gradient overlay for depth
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.clear,
                            Color.black.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
    }
}

/// NSVisualEffectView wrapper for deeper blur effects
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

extension View {
    /// Apply a glass panel background (for windows/sheets)
    func glassPanel() -> some View {
        modifier(GlassPanel())
    }
}

// MARK: - Toggle Style

struct TalkieToggleStyle: ToggleStyle {
    var onColor: Color = SemanticColor.success

    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isOn ? onColor : Color.secondary.opacity(0.25))
                    .frame(width: 36, height: 20)

                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 1, x: 0, y: 1)
                    .frame(width: 16, height: 16)
                    .offset(x: configuration.isOn ? 8 : -8)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

extension ToggleStyle where Self == TalkieToggleStyle {
    static func talkie(_ color: Color) -> TalkieToggleStyle { TalkieToggleStyle(onColor: color) }
    static var talkieSuccess: TalkieToggleStyle { TalkieToggleStyle(onColor: SemanticColor.success) }
    static var talkieInfo: TalkieToggleStyle { TalkieToggleStyle(onColor: SemanticColor.info) }
    static var talkieWarning: TalkieToggleStyle { TalkieToggleStyle(onColor: SemanticColor.warning) }
}
