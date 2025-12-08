//
//  SettingsView.swift
//  TalkieLive
//
//  Settings UI with sidebar navigation
//

import SwiftUI
import TalkieServices

// MARK: - Embedded Settings View (for main app navigation)

struct EmbeddedSettingsView: View {
    @ObservedObject private var settings = LiveSettings.shared
    @State private var selectedSection: SettingsSection = .appearance

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Settings Sections Navigation (middle column)
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("SETTINGS")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(Design.foreground)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                Rectangle()
                    .fill(Design.divider)
                    .frame(height: 0.5)

                // Sections List
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.sm) {
                        // APPEARANCE
                        EmbeddedSettingsSectionHeader(title: "APPEARANCE")
                        EmbeddedSettingsRow(
                            icon: "paintbrush",
                            title: "Theme & Colors",
                            isSelected: selectedSection == .appearance
                        ) {
                            selectedSection = .appearance
                        }

                        // BEHAVIOR
                        EmbeddedSettingsSectionHeader(title: "BEHAVIOR")
                        EmbeddedSettingsRow(
                            icon: "speaker.wave.2",
                            title: "Sounds",
                            isSelected: selectedSection == .sounds
                        ) {
                            selectedSection = .sounds
                        }
                        EmbeddedSettingsRow(
                            icon: "arrow.right.doc.on.clipboard",
                            title: "Auto-Paste",
                            isSelected: selectedSection == .output
                        ) {
                            selectedSection = .output
                        }
                        EmbeddedSettingsRow(
                            icon: "rectangle.inset.topright.filled",
                            title: "Overlay",
                            isSelected: selectedSection == .overlay
                        ) {
                            selectedSection = .overlay
                        }

                        // STORAGE
                        EmbeddedSettingsSectionHeader(title: "STORAGE")
                        EmbeddedSettingsRow(
                            icon: "folder",
                            title: "Files & Data",
                            isSelected: selectedSection == .storage
                        ) {
                            selectedSection = .storage
                        }
                    }
                    .padding(Spacing.sm)
                }
            }
            .frame(width: 180)
            .background(Design.backgroundSecondary)

            Rectangle()
                .fill(Design.divider)
                .frame(width: 0.5)

            // MARK: - Settings Content (right column)
            VStack(spacing: 0) {
                switch selectedSection {
                case .appearance:
                    AppearanceSettingsSection()
                case .sounds:
                    SoundsSettingsSection()
                case .output:
                    OutputSettingsSection()
                case .overlay:
                    OverlaySettingsSection()
                case .storage:
                    StorageSettingsSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Design.background)
        }
    }
}

// MARK: - Embedded Settings Components

struct EmbeddedSettingsSectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.techLabelSmall)
                .tracking(Tracking.normal)
                .foregroundColor(Design.foregroundMuted)
            Spacer()
        }
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xxs)
        .padding(.horizontal, Spacing.xs)
    }
}

struct EmbeddedSettingsRow: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(Design.fontXS)
                    .foregroundColor(isSelected ? Design.accent : Design.foregroundSecondary)
                    .frame(width: 16)

                Text(title)
                    .font(Design.fontSM)
                    .foregroundColor(isSelected ? Design.foreground : Design.foregroundSecondary)

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isSelected ? Design.accent.opacity(0.15) : (isHovered ? Design.foreground.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Settings Section Enum

enum SettingsSection: String, Hashable, CaseIterable {
    // Appearance
    case appearance
    // Behavior
    case sounds
    case output
    case overlay
    // Storage
    case storage

    var title: String {
        switch self {
        case .appearance: return "APPEARANCE"
        case .sounds: return "SOUNDS"
        case .output: return "OUTPUT"
        case .overlay: return "OVERLAY"
        case .storage: return "STORAGE"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .sounds: return "speaker.wave.2"
        case .output: return "arrow.right.doc.on.clipboard"
        case .overlay: return "rectangle.inset.topright.filled"
        case .storage: return "folder"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = LiveSettings.shared
    @State private var selectedSection: SettingsSection = .appearance

    private let sidebarBackground = MidnightSurface.elevated
    private let contentBackground = MidnightSurface.content
    private let bottomBarBackground = MidnightSurface.sidebar

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                // Settings Header
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .tracking(Tracking.wide)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // Menu Sections
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // APPEARANCE
                        SettingsSidebarSection(
                            title: "APPEARANCE",
                            isActive: selectedSection == .appearance
                        ) {
                            SettingsSidebarItem(
                                icon: "paintbrush",
                                title: "THEME & COLORS",
                                isSelected: selectedSection == .appearance
                            ) {
                                selectedSection = .appearance
                            }
                        }

                        // BEHAVIOR
                        SettingsSidebarSection(
                            title: "BEHAVIOR",
                            isActive: selectedSection == .sounds || selectedSection == .output || selectedSection == .overlay
                        ) {
                            SettingsSidebarItem(
                                icon: "speaker.wave.2",
                                title: "SOUNDS",
                                isSelected: selectedSection == .sounds
                            ) {
                                selectedSection = .sounds
                            }
                            SettingsSidebarItem(
                                icon: "arrow.right.doc.on.clipboard",
                                title: "AUTO-PASTE",
                                isSelected: selectedSection == .output
                            ) {
                                selectedSection = .output
                            }
                            SettingsSidebarItem(
                                icon: "rectangle.inset.topright.filled",
                                title: "OVERLAY",
                                isSelected: selectedSection == .overlay
                            ) {
                                selectedSection = .overlay
                            }
                        }

                        // STORAGE
                        SettingsSidebarSection(
                            title: "STORAGE",
                            isActive: selectedSection == .storage
                        ) {
                            SettingsSidebarItem(
                                icon: "folder",
                                title: "FILES & DATA",
                                isSelected: selectedSection == .storage
                            ) {
                                selectedSection = .storage
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: 180)
            .background(sidebarBackground)

            // Divider
            Rectangle()
                .fill(MidnightSurface.divider)
                .frame(width: 1)

            // MARK: - Content Area
            VStack(spacing: 0) {
                // Content based on selection
                Group {
                    switch selectedSection {
                    case .appearance:
                        AppearanceSettingsSection()
                    case .sounds:
                        SoundsSettingsSection()
                    case .output:
                        OutputSettingsSection()
                    case .overlay:
                        OverlaySettingsSection()
                    case .storage:
                        StorageSettingsSection()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom bar with Done button
                HStack {
                    Spacer()
                    Button("DONE") {
                        dismiss()
                    }
                    .buttonStyle(SettingsDoneButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(bottomBarBackground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(contentBackground)
        }
        .frame(minWidth: 600, minHeight: 450)
    }
}

// MARK: - Sidebar Components

struct SettingsSidebarSection<Content: View>: View {
    let title: String
    var isActive: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(Tracking.normal)
                .foregroundColor(isActive ? .white.opacity(0.7) : .white.opacity(0.4))
                .padding(.leading, 6)
                .padding(.bottom, 2)

            content
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsSidebarItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                .frame(width: 14)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct SettingsDoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .tracking(Tracking.normal)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.accentColor)
            .cornerRadius(CornerRadius.xs)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(TalkieAnimation.fast, value: configuration.isPressed)
    }
}

// MARK: - Settings Page Container

struct SettingsPageContainer<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                content
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(Tracking.normal)
                    .foregroundColor(.white)
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let title = title {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(Tracking.normal)
                    .foregroundColor(.white.opacity(0.5))
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                content
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MidnightSurface.card)
            .cornerRadius(CornerRadius.sm)
        }
    }
}

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
            // Theme with preview
            SettingsCard(title: "THEME") {
                HStack(alignment: .top, spacing: Spacing.md) {
                    // Theme list (left)
                    VStack(spacing: Spacing.xs) {
                        ForEach(AppTheme.allCases, id: \.rawValue) { theme in
                            CompactThemeRow(
                                theme: theme,
                                isSelected: settings.theme == theme
                            ) {
                                settings.theme = theme
                            }
                        }
                    }
                    .frame(width: 100)

                    // Preview table (right)
                    ThemePreviewTable(theme: settings.theme)
                        .frame(maxWidth: .infinity)
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
                        .foregroundColor(.white.opacity(0.8))
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(Color.white.opacity(0.05))
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
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.white.opacity(0.3))
                .frame(width: 6, height: 6)

            Text(theme.displayName)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Theme Preview Table

struct ThemePreviewTable: View {
    let theme: AppTheme

    private var bgColor: Color {
        switch theme {
        case .system, .dark, .midnight: return Color(white: 0.1)
        case .light: return Color(white: 0.95)
        }
    }

    private var fgColor: Color {
        switch theme {
        case .system, .dark, .midnight: return .white
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
                .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(isSelected ? Color.accentColor : (isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05)))
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
            // Visual screen representation
            ZStack {
                // Screen outline
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 120, height: 75)

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
                    HStack {
                        Spacer()
                        PositionDot(position: .bottomCenter, selection: $selection)
                        Spacer()
                    }
                }
                .padding(8)
                .frame(width: 120, height: 75)
            }

            // Position name
            VStack(alignment: .leading, spacing: 4) {
                Text(selection.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)

                Text("Click a position on the screen")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
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
                .fill(isSelected ? Color.accentColor : (isHovered ? Color.white.opacity(0.4) : Color.white.opacity(0.2)))
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
                // Animated preview
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(Color.black.opacity(0.4))

                    OverlayPreviewAnimation(style: style)
                }
                .frame(width: 80, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                )

                Text(style.displayName)
                    .font(.system(size: 8, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
                    context.fill(RoundedRectangle(cornerRadius: 2).path(in: pillRect), with: .color(.white.opacity(0.4)))
                }
            }
        }
    }
}

struct ThemeOptionRow: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(theme.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)

                Text(theme.description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
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
                .fill(isSelected ? Color.accentColor.opacity(0.2) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

struct ThemePresetButton: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // Preview swatch
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(preset.previewColors.bg)
                .overlay(
                    Circle()
                        .fill(preset.previewColors.accent)
                        .frame(width: 12, height: 12)
                )
                .frame(width: 50, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )

            Text(preset.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isSelected ? .accentColor : .white.opacity(0.7))
        }
        .padding(Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

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
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

struct OverlayPositionRow: View {
    let position: OverlayPosition
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(position.displayName)
                .font(.system(size: 11))
                .foregroundColor(.white)

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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

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
                    .foregroundColor(.white)

                Text(style.description)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Sounds Settings Section

struct SoundsSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "speaker.wave.2",
                title: "SOUNDS",
                subtitle: "Configure audio feedback for different events."
            )
        } content: {
            SettingsCard(title: "RECORDING SOUNDS") {
                VStack(spacing: Spacing.md) {
                    SoundPickerRow(
                        label: "Start Recording",
                        sound: $settings.startSound
                    )

                    Divider()
                        .background(Color.white.opacity(0.1))

                    SoundPickerRow(
                        label: "Finish Recording",
                        sound: $settings.finishSound
                    )

                    Divider()
                        .background(Color.white.opacity(0.1))

                    SoundPickerRow(
                        label: "Text Pasted",
                        sound: $settings.pastedSound
                    )
                }
            }
        }
    }
}

// MARK: - Output Settings Section

struct OutputSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.right.doc.on.clipboard",
                title: "OUTPUT",
                subtitle: "Configure how transcribed text is delivered."
            )
        } content: {
            SettingsCard(title: "ROUTING MODE") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(RoutingMode.allCases, id: \.rawValue) { mode in
                        RoutingModeRow(
                            mode: mode,
                            isSelected: settings.routingMode == mode
                        ) {
                            settings.routingMode = mode
                        }
                    }
                }
            }
        }
    }
}

struct RoutingModeRow: View {
    let mode: RoutingMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)

                Text(mode.description)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Overlay Settings Section

struct OverlaySettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "rectangle.inset.topright.filled",
                title: "OVERLAY",
                subtitle: "Configure the recording overlay and transcription."
            )
        } content: {
            // Hotkey
            SettingsCard(title: "GLOBAL SHORTCUT") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Current hotkey:")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        Text(settings.hotkey.displayString)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                    .fill(Color.accentColor.opacity(0.15))
                            )
                    }

                    Text("Press and hold to record. Release to transcribe.")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Overlay Position
            SettingsCard(title: "OVERLAY POSITION") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(OverlayPosition.allCases, id: \.rawValue) { position in
                        OverlayPositionRow(
                            position: position,
                            isSelected: settings.overlayPosition == position
                        ) {
                            settings.overlayPosition = position
                        }
                    }
                }
            }

            // Overlay Style
            SettingsCard(title: "OVERLAY STYLE") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(OverlayStyle.allCases, id: \.rawValue) { style in
                        OverlayStyleRow(
                            style: style,
                            isSelected: settings.overlayStyle == style
                        ) {
                            settings.overlayStyle = style
                        }
                    }
                }
            }

            // Whisper Model
            SettingsCard(title: "WHISPER MODEL") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(WhisperModel.allCases, id: \.rawValue) { model in
                        WhisperModelRow(
                            model: model,
                            isSelected: settings.whisperModel == model
                        ) {
                            settings.whisperModel = model
                        }
                    }
                }
            }
        }
    }
}

struct WhisperModelRow: View {
    let model: WhisperModel
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)

                Text(model.description)
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.white.opacity(0.05) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Storage Settings Section

struct StorageSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @State private var storageStats = StorageStats()
    @State private var isRefreshing = false
    @State private var showDeleteConfirmation = false

    private let ttlOptions = [1, 6, 12, 24, 48, 72, 168] // hours, 168 = 1 week

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "folder",
                title: "STORAGE",
                subtitle: "Manage transcription history and storage."
            )
        } content: {
            // Live Stats Overview
            SettingsCard(title: "LIVE STORAGE") {
                VStack(spacing: Spacing.md) {
                    // Main stats row
                    HStack(spacing: Spacing.lg) {
                        StorageStatBox(
                            icon: "text.bubble.fill",
                            value: "\(storageStats.totalUtterances)",
                            label: "Transcriptions",
                            color: .accentColor
                        )

                        StorageStatBox(
                            icon: "waveform",
                            value: storageStats.audioStorageFormatted,
                            label: "Audio Files",
                            color: .purple
                        )

                        StorageStatBox(
                            icon: "cylinder.fill",
                            value: storageStats.databaseSizeFormatted,
                            label: "Database",
                            color: .orange
                        )

                        StorageStatBox(
                            icon: "sum",
                            value: storageStats.totalStorageFormatted,
                            label: "Total",
                            color: .green
                        )
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Secondary stats
                    HStack(spacing: Spacing.lg) {
                        // Time range
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TIME RANGE")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(.white.opacity(0.4))

                            if let oldest = storageStats.oldestDate, let newest = storageStats.newestDate {
                                Text("\(formatDate(oldest)) → \(formatDate(newest))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                            } else {
                                Text("No data")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }

                        Spacer()

                        // Total words
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TOTAL WORDS")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(.white.opacity(0.4))

                            Text(formatNumber(storageStats.totalWords))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        // Total duration
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TOTAL DURATION")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(.white.opacity(0.4))

                            Text(formatDuration(storageStats.totalDurationSeconds))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    // Refresh button
                    HStack {
                        Button(action: refreshStats) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9))
                                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                    .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                                Text("Refresh")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("Last updated: \(formatTime(storageStats.lastUpdated))")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }

            // Top Apps
            if !storageStats.topApps.isEmpty {
                SettingsCard(title: "TOP APPS") {
                    VStack(spacing: Spacing.xs) {
                        ForEach(storageStats.topApps.prefix(5), id: \.bundleID) { app in
                            HStack {
                                Text(app.name)
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.8))
                                    .lineLimit(1)

                                Spacer()

                                Text("\(app.count)")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.accentColor)

                                // Progress bar
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.accentColor.opacity(0.3))
                                        .frame(width: geo.size.width * CGFloat(app.count) / CGFloat(max(storageStats.topApps.first?.count ?? 1, 1)))
                                }
                                .frame(width: 60, height: 4)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // Retention
            SettingsCard(title: "RETENTION") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Keep transcriptions for:")
                            .font(.system(size: 11))
                            .foregroundColor(.white)

                        Spacer()

                        Picker("", selection: $settings.utteranceTTLHours) {
                            ForEach(ttlOptions, id: \.self) { hours in
                                Text(formatTTL(hours)).tag(hours)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }

                    Text("Older transcriptions will be automatically deleted.")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            // Storage Location & Actions
            SettingsCard(title: "DATA MANAGEMENT") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Location row
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.5))

                        Text("~/Library/Application Support/TalkieLive")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Open") {
                            if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("TalkieLive") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.system(size: 9, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Action buttons
                    HStack(spacing: Spacing.sm) {
                        StorageActionButton(
                            icon: "trash",
                            label: "Prune Old",
                            color: .orange
                        ) {
                            PastLivesDatabase.prune(olderThanHours: settings.utteranceTTLHours)
                            refreshStats()
                        }

                        StorageActionButton(
                            icon: "doc.badge.gearshape",
                            label: "Clean Orphans",
                            color: .purple
                        ) {
                            cleanOrphanedAudio()
                            refreshStats()
                        }

                        Spacer()

                        StorageActionButton(
                            icon: "trash.fill",
                            label: "Delete All",
                            color: .red
                        ) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
        }
        .onAppear {
            refreshStats()
        }
        .alert("Delete All Data?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                PastLivesDatabase.deleteAll()
                refreshStats()
            }
        } message: {
            Text("This will permanently delete all \(storageStats.totalUtterances) transcriptions and \(storageStats.audioStorageFormatted) of audio files. This cannot be undone.")
        }
    }

    private func refreshStats() {
        isRefreshing = true
        Task {
            let stats = await StorageStats.calculate()
            await MainActor.run {
                storageStats = stats
                isRefreshing = false
            }
        }
    }

    private func cleanOrphanedAudio() {
        let utterances = PastLivesDatabase.all()
        let referencedFilenames = Set(utterances.compactMap { $0.audioFilename })
        AudioStorage.pruneOrphanedFiles(referencedFilenames: referencedFilenames)
    }

    private func formatTTL(_ hours: Int) -> String {
        if hours < 24 {
            return "\(hours) hour\(hours == 1 ? "" : "s")"
        } else if hours == 168 {
            return "1 week"
        } else {
            let days = hours / 24
            return "\(days) day\(days == 1 ? "" : "s")"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

// MARK: - Storage Stats

struct StorageStats {
    var totalUtterances: Int = 0
    var totalWords: Int = 0
    var totalDurationSeconds: Double = 0
    var audioStorageBytes: Int64 = 0
    var databaseSizeBytes: Int64 = 0
    var oldestDate: Date?
    var newestDate: Date?
    var topApps: [AppUsage] = []
    var lastUpdated: Date = Date()

    var audioStorageFormatted: String {
        ByteCountFormatter.string(fromByteCount: audioStorageBytes, countStyle: .file)
    }

    var databaseSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: databaseSizeBytes, countStyle: .file)
    }

    var totalStorageFormatted: String {
        ByteCountFormatter.string(fromByteCount: audioStorageBytes + databaseSizeBytes, countStyle: .file)
    }

    struct AppUsage: Identifiable {
        let bundleID: String
        let name: String
        let count: Int
        var id: String { bundleID }
    }

    static func calculate() async -> StorageStats {
        let utterances = PastLivesDatabase.all()
        var stats = StorageStats()

        stats.totalUtterances = utterances.count
        stats.totalWords = utterances.compactMap { $0.wordCount }.reduce(0, +)
        stats.totalDurationSeconds = utterances.compactMap { $0.durationSeconds }.reduce(0, +)
        stats.audioStorageBytes = AudioStorage.totalStorageBytes()

        // Database size
        if let dbPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TalkieLive/PastLives.sqlite").path {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: dbPath),
               let size = attrs[.size] as? Int64 {
                stats.databaseSizeBytes = size
            }
        }

        // Date range
        if let oldest = utterances.last {
            stats.oldestDate = oldest.createdAt
        }
        if let newest = utterances.first {
            stats.newestDate = newest.createdAt
        }

        // Top apps
        var appCounts: [String: (name: String, count: Int)] = [:]
        for u in utterances {
            if let bundleID = u.appBundleID {
                let name = u.appName ?? bundleID
                let existing = appCounts[bundleID]
                appCounts[bundleID] = (name: name, count: (existing?.count ?? 0) + 1)
            }
        }
        stats.topApps = appCounts.map { AppUsage(bundleID: $0.key, name: $0.value.name, count: $0.value.count) }
            .sorted { $0.count > $1.count }

        stats.lastUpdated = Date()
        return stats
    }
}

// MARK: - Storage Stat Box

struct StorageStatBox: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)

            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Storage Action Button

struct StorageActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(isHovered ? color : .white.opacity(0.6))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isHovered ? color.opacity(0.15) : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .frame(width: 650, height: 500)
        .preferredColorScheme(.dark)
}
