//
//  AppearanceSettingsSection.swift
//  TalkieLive
//
//  Appearance settings: theme, colors, fonts, overlay position/style
//

import SwiftUI
import TalkieKit

// MARK: - Appearance Settings Section

struct AppearanceSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "paintbrush",
                title: "APPEARANCE",
                subtitle: "Customize how Talkie Live looks."
            )
        } content: {
            // Appearance Mode
            SettingsCard(title: "APPEARANCE") {
                HStack(alignment: .top, spacing: Spacing.md) {
                    // Appearance mode list (left)
                    VStack(spacing: Spacing.xs) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                            CompactThemeRow(
                                theme: mode,
                                isSelected: settings.appearanceMode == mode
                            ) {
                                settings.appearanceMode = mode
                            }
                        }
                    }
                    .frame(width: 100)

                    // Preview table (right)
                    ThemePreviewTable(theme: settings.appearanceMode)
                        .frame(maxWidth: .infinity)
                }
            }

            // Visual Theme
            SettingsCard(title: "COLOR THEME") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: Spacing.sm) {
                    ForEach(VisualTheme.allCases, id: \.rawValue) { theme in
                        VisualThemeButton(
                            theme: theme,
                            isSelected: settings.visualTheme == theme
                        ) {
                            settings.applyVisualTheme(theme)
                        }
                    }
                }
            }

            // Accent Color
            SettingsCard(title: "ACCENT COLOR") {
                HStack(spacing: Spacing.sm) {
                    ForEach(AccentColorOption.allCases, id: \.rawValue) { color in
                        AccentColorButton(
                            option: color,
                            isSelected: settings.accentColor == color
                        ) {
                            settings.accentColor = color
                        }
                    }
                }
            }

            // Font Size with preview
            SettingsCard(title: "FONT SIZE") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(FontSize.allCases, id: \.rawValue) { size in
                            FontSizeButton(
                                size: size,
                                isSelected: settings.fontSize == size
                            ) {
                                settings.fontSize = size
                            }
                        }
                    }

                    // Preview text
                    Text("The quick brown fox jumps over the lazy dog.")
                        .font(.system(size: settings.fontSize.previewSize))
                        .foregroundColor(TalkieTheme.textSecondary)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(TalkieTheme.hover)
                        )
                }
            }

            // Overlay Position with visual selector
            SettingsCard(title: "OVERLAY POSITION") {
                OverlayPositionSelector(selection: $settings.overlayPosition)
            }

            // Overlay Style with previews
            SettingsCard(title: "OVERLAY STYLE") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: Spacing.sm) {
                    ForEach(OverlayStyle.allCases, id: \.rawValue) { style in
                        OverlayStylePreview(
                            style: style,
                            isSelected: settings.overlayStyle == style
                        ) {
                            settings.overlayStyle = style
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Compact Theme Row

struct CompactThemeRow: View {
    let theme: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(isSelected ? Color.accentColor : TalkieTheme.textMuted)
                .frame(width: 6, height: 6)

            Text(theme.displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : TalkieTheme.textSecondary)

            Spacer()
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Theme Preview Table

struct ThemePreviewTable: View {
    let theme: AppearanceMode

    private var bgColor: Color {
        switch theme {
        case .system, .dark: return Color(white: 0.1)
        case .light: return Color(white: 0.95)
        }
    }

    private var fgColor: Color {
        switch theme {
        case .system, .dark: return .white
        case .light: return .black
        }
    }

    private var mutedColor: Color {
        fgColor.opacity(0.5)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("RECENT")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1)
                    .foregroundColor(mutedColor)
                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(fgColor.opacity(0.05))

            // Rows
            ForEach(0..<3) { i in
                HStack {
                    Circle()
                        .fill(i == 0 ? Color.accentColor : mutedColor)
                        .frame(width: 4, height: 4)

                    Text(["Meeting notes", "Quick memo", "Project idea"][i])
                        .font(.system(size: 9))
                        .foregroundColor(fgColor.opacity(0.8))

                    Spacer()

                    Text(["2m", "15m", "1h"][i])
                        .font(.system(size: 8))
                        .foregroundColor(mutedColor)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)

                if i < 2 {
                    Rectangle()
                        .fill(fgColor.opacity(0.1))
                        .frame(height: 0.5)
                }
            }
        }
        .background(bgColor)
        .cornerRadius(CornerRadius.xs)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .stroke(fgColor.opacity(0.1), lineWidth: 0.5)
        )
    }
}

// MARK: - Font Size Button

struct FontSizeButton: View {
    let size: FontSize
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(size.displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : TalkieTheme.textTertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(isSelected ? Color.accentColor : (isHovered ? TalkieTheme.surfaceElevated : TalkieTheme.hover))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Overlay Position Selector

struct OverlayPositionSelector: View {
    @Binding var selection: OverlayPosition

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Visual screen representation with glass effect
            ZStack {
                // Screen background with glass effect
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.03))
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)

                // Position indicators
                VStack {
                    HStack {
                        PositionDot(position: .topLeft, selection: $selection)
                        Spacer()
                        PositionDot(position: .topCenter, selection: $selection)
                        Spacer()
                        PositionDot(position: .topRight, selection: $selection)
                    }
                    Spacer()
                }
                .padding(8)
            }
            .frame(width: 120, height: 75)

            // Position name
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text("Click a position on the screen")
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }
        }
    }
}

struct PositionDot: View {
    let position: OverlayPosition
    @Binding var selection: OverlayPosition

    @State private var isHovered = false

    private var isSelected: Bool { selection == position }

    var body: some View {
        Button(action: { selection = position }) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? Color.accentColor : (isHovered ? TalkieTheme.textMuted : TalkieTheme.border))
                .frame(width: isSelected ? 24 : 16, height: 6)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Overlay Style Preview

struct OverlayStylePreview: View {
    let style: OverlayStyle
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                // Animated preview with glass background
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(Color.white.opacity(isHovered ? 0.06 : 0.03))
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.1 : 0.06),
                                    Color.black.opacity(0.2)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Blur on hover
                    if isHovered {
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(.ultraThinMaterial)
                            .opacity(0.3)
                    }

                    OverlayPreviewAnimation(style: style)
                }
                .frame(width: 80, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .stroke(
                            isSelected ? Color.accentColor : (isHovered ? Color.white.opacity(0.2) : Color.white.opacity(0.1)),
                            lineWidth: isSelected ? 1.5 : (isHovered ? 1 : 0.5)
                        )
                )
                .shadow(
                    color: Color.black.opacity(isHovered ? 0.2 : 0.1),
                    radius: isHovered ? 6 : 2,
                    y: isHovered ? 3 : 1
                )

                Text(style.displayName)
                    .font(.system(size: 8, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : (isHovered ? TalkieTheme.textPrimary : TalkieTheme.textSecondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(Spacing.xs)
            .glassHover(
                isHovered: isHovered,
                isSelected: isSelected,
                cornerRadius: CornerRadius.sm,
                baseOpacity: 0.0,
                hoverOpacity: 0.08,
                accentColor: isSelected ? .accentColor : nil
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(TalkieAnimation.fast, value: isHovered)
    }
}

// MARK: - Overlay Preview Animation

struct OverlayPreviewAnimation: View {
    let style: OverlayStyle

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.033)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerY = size.height / 2

                switch style {
                case .particles:
                    // Fast reactive particles
                    for i in 0..<20 {
                        let seed = Double(i) * 1.618
                        let xProgress = (time * 0.18 + seed).truncatingRemainder(dividingBy: 1.0)
                        let x = CGFloat(xProgress) * size.width
                        let wave = sin(time * 3.0 + seed * 4) * 0.6
                        let baseY = (Double(i % 5) / 5.0 - 0.5) * 0.3
                        let y = centerY + CGFloat((baseY + wave) * Double(centerY) * 0.7)
                        let opacity = 0.5 + sin(seed) * 0.3
                        let rect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                        context.fill(Circle().path(in: rect), with: .color(.white.opacity(opacity)))
                    }

                case .particlesCalm:
                    // Slow calm particles
                    for i in 0..<18 {
                        let seed = Double(i) * 1.618
                        let xProgress = (time * 0.08 + seed).truncatingRemainder(dividingBy: 1.0)
                        let x = CGFloat(xProgress) * size.width
                        let wave = sin(time * 1.5 + seed * 4) * 0.4
                        let baseY = (Double(i % 6) / 6.0 - 0.5) * 0.35
                        let y = centerY + CGFloat((baseY + wave) * Double(centerY) * 0.7)
                        let opacity = 0.45 + sin(seed) * 0.25
                        let rect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
                        context.fill(Circle().path(in: rect), with: .color(.white.opacity(opacity)))
                    }

                case .waveform:
                    // Standard waveform bars
                    let barCount = 16
                    let barWidth = size.width / CGFloat(barCount) - 1
                    for i in 0..<barCount {
                        let x = CGFloat(i) * (barWidth + 1)
                        let seed = Double(i) * 1.618
                        let level = 0.25 + sin(time * 2.5 + seed * 2) * 0.25
                        let barHeight = max(2, CGFloat(level) * size.height * 0.8)
                        let barRect = CGRect(x: x, y: centerY - barHeight / 2, width: barWidth, height: barHeight)
                        context.fill(RoundedRectangle(cornerRadius: 1).path(in: barRect), with: .color(.white.opacity(0.5 + level * 0.3)))
                    }

                case .waveformSensitive:
                    // More active waveform bars
                    let barCount = 16
                    let barWidth = size.width / CGFloat(barCount) - 1
                    for i in 0..<barCount {
                        let x = CGFloat(i) * (barWidth + 1)
                        let seed = Double(i) * 1.618
                        let level = 0.4 + sin(time * 3.5 + seed * 2) * 0.35
                        let barHeight = max(4, CGFloat(level) * size.height * 0.85)
                        let barRect = CGRect(x: x, y: centerY - barHeight / 2, width: barWidth, height: barHeight)
                        context.fill(RoundedRectangle(cornerRadius: 1).path(in: barRect), with: .color(.white.opacity(0.55 + level * 0.35)))
                    }

                case .pillOnly:
                    // Just show a small pill indicator at bottom
                    let pillWidth: CGFloat = 24
                    let pillHeight: CGFloat = 4
                    let pillRect = CGRect(
                        x: (size.width - pillWidth) / 2,
                        y: size.height - pillHeight - 4,
                        width: pillWidth,
                        height: pillHeight
                    )
                    context.fill(RoundedRectangle(cornerRadius: 2).path(in: pillRect), with: .color(TalkieTheme.textMuted))
                }
            }
        }
    }
}

// MARK: - Theme Option Row

struct ThemeOptionRow: View {
    let theme: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(theme.description)
                    .font(.system(size: 10))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Visual Theme Button

struct VisualThemeButton: View {
    let theme: VisualTheme
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // Preview swatch
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(theme.previewColors.bg)
                .overlay(
                    Circle()
                        .fill(theme.previewColors.accent)
                        .frame(width: 12, height: 12)
                )
                .frame(width: 50, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            Text(theme.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isSelected ? .accentColor : TalkieTheme.textSecondary)
        }
        .padding(Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(isHovered ? TalkieTheme.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Accent Color Button

struct AccentColorButton: View {
    let option: AccentColorOption
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(option.color)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                )

            Text(option.displayName)
                .font(.system(size: 8))
                .foregroundColor(TalkieTheme.textTertiary)
        }
        .padding(Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isHovered ? TalkieTheme.hover : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Overlay Position Row

struct OverlayPositionRow: View {
    let position: OverlayPosition
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(position.displayName)
                .font(.system(size: 11))
                .foregroundColor(TalkieTheme.textPrimary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Overlay Style Row

struct OverlayStyleRow: View {
    let style: OverlayStyle
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(style.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(style.description)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}
