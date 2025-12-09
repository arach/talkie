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

// MARK: - Midnight Theme Surface Colors

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
                .foregroundColor(Design.foreground)
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
                .foregroundColor(Design.foregroundMuted)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(Design.fontXS)
                .foregroundColor(Design.foreground)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, 5)
        .background(Design.backgroundTertiary)
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
                    .foregroundColor(isSelected ? .accentColor : Color(white: 0.6))
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : Color(white: 0.8))

                Spacer()

                if let count = count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color(white: 0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(white: 0.15))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color(white: 0.12) : Color.clear))
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
