//
//  SettingsView.swift
//  TalkieLive
//
//  Settings UI with sidebar navigation
//

import SwiftUI
import AppKit
import Carbon.HIToolbox
import TalkieKit

// MARK: - Embedded Settings View (for main app navigation)

struct EmbeddedSettingsView: View {
    @Binding var initialSection: SettingsSection?
    @ObservedObject private var settings = LiveSettings.shared
    @State private var selectedSection: SettingsSection = .appearance

    init(initialSection: Binding<SettingsSection?> = .constant(nil)) {
        self._initialSection = initialSection
    }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Settings Sections Navigation (middle column)
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("SETTINGS")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(TalkieTheme.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                Rectangle()
                    .fill(TalkieTheme.divider)
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
                            icon: "command",
                            title: "Shortcuts",
                            isSelected: selectedSection == .shortcuts
                        ) {
                            selectedSection = .shortcuts
                        }
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
                        EmbeddedSettingsRow(
                            icon: "mic",
                            title: "Audio",
                            isSelected: selectedSection == .audio
                        ) {
                            selectedSection = .audio
                        }

                        // SYSTEM
                        EmbeddedSettingsSectionHeader(title: "SYSTEM")
                        EmbeddedSettingsRow(
                            icon: "waveform",
                            title: "Transcription",
                            isSelected: selectedSection == .engine
                        ) {
                            selectedSection = .engine
                        }
                        EmbeddedSettingsRow(
                            icon: "folder",
                            title: "Files & Data",
                            isSelected: selectedSection == .storage
                        ) {
                            selectedSection = .storage
                        }
                        EmbeddedSettingsRow(
                            icon: "lock.shield",
                            title: "Permissions",
                            isSelected: selectedSection == .permissions
                        ) {
                            selectedSection = .permissions
                        }
                        EmbeddedSettingsRow(
                            icon: "info.circle",
                            title: "About",
                            isSelected: selectedSection == .about
                        ) {
                            selectedSection = .about
                        }
                    }
                    .padding(Spacing.sm)
                }
            }
            .frame(width: 180)
            .background(TalkieTheme.secondaryBackground)

            Rectangle()
                .fill(TalkieTheme.divider)
                .frame(width: 0.5)

            // MARK: - Settings Content (right column)
            VStack(spacing: 0) {
                switch selectedSection {
                case .appearance:
                    AppearanceSettingsSection()
                case .shortcuts:
                    ShortcutsSettingsSection()
                case .sounds:
                    SoundsSettingsSection()
                case .output:
                    OutputSettingsSection()
                case .overlay:
                    OverlaySettingsSection()
                case .audio:
                    AudioSettingsSection()
                case .engine:
                    EngineSettingsSection()
                case .storage:
                    StorageSettingsSection()
                case .permissions:
                    PermissionsSettingsSection()
                case .about:
                    AboutSettingsSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TalkieTheme.surface)
        }
        .background(TalkieTheme.surface)
        .ignoresSafeArea(.all, edges: .all)
        .onChange(of: initialSection) { _, newSection in
            if let section = newSection {
                selectedSection = section
                // Clear the initial section after applying it
                initialSection = nil
            }
        }
        .onAppear {
            // Apply initial section on appear if set
            if let section = initialSection {
                selectedSection = section
                initialSection = nil
            }
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
                .foregroundColor(TalkieTheme.textMuted)
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
                    .foregroundColor(isSelected ? TalkieTheme.accent : TalkieTheme.textSecondary)
                    .frame(width: 16)

                Text(title)
                    .font(Design.fontSM)
                    .foregroundColor(isSelected ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isSelected ? TalkieTheme.accent.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
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
    case shortcuts
    case sounds
    case output
    case overlay
    case audio  // Microphone & audio troubleshooting
    // System
    case engine  // Now "Transcription" - AI models
    case storage
    case permissions  // Permission Center
    case about

    var title: String {
        switch self {
        case .appearance: return "APPEARANCE"
        case .shortcuts: return "SHORTCUTS"
        case .sounds: return "SOUNDS"
        case .output: return "OUTPUT"
        case .overlay: return "OVERLAY"
        case .audio: return "AUDIO"
        case .engine: return "TRANSCRIPTION"
        case .storage: return "STORAGE"
        case .permissions: return "PERMISSIONS"
        case .about: return "ABOUT"
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .shortcuts: return "command"
        case .sounds: return "speaker.wave.2"
        case .output: return "arrow.right.doc.on.clipboard"
        case .overlay: return "rectangle.inset.topright.filled"
        case .audio: return "mic"
        case .engine: return "waveform"
        case .storage: return "folder"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = LiveSettings.shared
    @State private var selectedSection: SettingsSection = .appearance

    private var sidebarBackground: Color { TalkieTheme.surfaceElevated }
    private var contentBackground: Color { TalkieTheme.surface }
    private var bottomBarBackground: Color { TalkieTheme.secondaryBackground }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                // Settings Header
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .tracking(Tracking.wide)
                    .foregroundColor(TalkieTheme.textPrimary)
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
                            isActive: selectedSection == .shortcuts || selectedSection == .sounds || selectedSection == .output || selectedSection == .overlay
                        ) {
                            SettingsSidebarItem(
                                icon: "command",
                                title: "SHORTCUTS",
                                isSelected: selectedSection == .shortcuts
                            ) {
                                selectedSection = .shortcuts
                            }
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
                            SettingsSidebarItem(
                                icon: "mic",
                                title: "AUDIO",
                                isSelected: selectedSection == .audio
                            ) {
                                selectedSection = .audio
                            }
                        }

                        // SYSTEM
                        SettingsSidebarSection(
                            title: "SYSTEM",
                            isActive: selectedSection == .engine || selectedSection == .storage || selectedSection == .permissions || selectedSection == .about
                        ) {
                            SettingsSidebarItem(
                                icon: "waveform",
                                title: "TRANSCRIPTION",
                                isSelected: selectedSection == .engine
                            ) {
                                selectedSection = .engine
                            }
                            SettingsSidebarItem(
                                icon: "folder",
                                title: "FILES & DATA",
                                isSelected: selectedSection == .storage
                            ) {
                                selectedSection = .storage
                            }
                            SettingsSidebarItem(
                                icon: "lock.shield",
                                title: "PERMISSIONS",
                                isSelected: selectedSection == .permissions
                            ) {
                                selectedSection = .permissions
                            }
                            SettingsSidebarItem(
                                icon: "info.circle",
                                title: "ABOUT",
                                isSelected: selectedSection == .about
                            ) {
                                selectedSection = .about
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
                .fill(TalkieTheme.divider)
                .frame(width: 1)

            // MARK: - Content Area
            VStack(spacing: 0) {
                // Content based on selection
                Group {
                    switch selectedSection {
                    case .appearance:
                        AppearanceSettingsSection()
                    case .shortcuts:
                        ShortcutsSettingsSection()
                    case .sounds:
                        SoundsSettingsSection()
                    case .output:
                        OutputSettingsSection()
                    case .overlay:
                        OverlaySettingsSection()
                    case .audio:
                        AudioSettingsSection()
                    case .engine:
                        EngineSettingsSection()
                    case .storage:
                        StorageSettingsSection()
                    case .permissions:
                        PermissionsSettingsSection()
                    case .about:
                        AboutSettingsSection()
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
                .foregroundColor(isActive ? TalkieTheme.textSecondary : TalkieTheme.textMuted)
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
                .foregroundColor(isSelected ? .white : TalkieTheme.textTertiary)
                .frame(width: 14)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isSelected ? .white : TalkieTheme.textSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor : (isHovered ? TalkieTheme.hover : Color.clear))
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
            .foregroundColor(TalkieTheme.textPrimary)
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
                    .foregroundColor(TalkieTheme.textPrimary)
            }

            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(TalkieTheme.textTertiary)
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
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                content
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TalkieTheme.surfaceCard)
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
            // Visual screen representation
            ZStack {
                // Screen outline
                RoundedRectangle(cornerRadius: 4)
                    .stroke(TalkieTheme.textMuted, lineWidth: 1)
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
                }
                .padding(8)
                .frame(width: 120, height: 75)
            }

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
                        .stroke(isSelected ? Color.accentColor : TalkieTheme.border, lineWidth: isSelected ? 2 : 1)
                )

                Text(style.displayName)
                    .font(.system(size: 8, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : TalkieTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isHovered ? TalkieTheme.hover : Color.clear)
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
                    context.fill(RoundedRectangle(cornerRadius: 2).path(in: pillRect), with: .color(TalkieTheme.textMuted))
                }
            }
        }
    }
}

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

// MARK: - Shortcuts Settings Section

struct ShortcutsSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @State private var isRecordingHotkey = false
    @State private var isRecordingPTTHotkey = false
    @State private var isRestoreHovered = false

    /// Check if any shortcuts have been modified from defaults
    private var hasModifiedShortcuts: Bool {
        settings.hotkey != .default || settings.pttHotkey != .defaultPTT
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "command",
                title: "SHORTCUTS",
                subtitle: "Configure global keyboard shortcuts."
            )
        } content: {
            // Toggle mode shortcut
            SettingsCard(title: "TOGGLE RECORD") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Toggle Recording")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Press to start, press again to stop and transcribe")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        HotkeyRecorderButton(
                            hotkey: $settings.hotkey,
                            isRecording: $isRecordingHotkey,
                            showReset: false
                        )
                    }

                    if isRecordingHotkey {
                        Text("Press any key combination with ⌘, ⌥, ⌃, or ⇧")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor.opacity(0.8))
                    }
                }
            }

            // Push-to-talk shortcut
            SettingsCard(title: "PUSH-TO-TALK") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Enable toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Push-to-Talk")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Hold to record, release to stop and transcribe")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Toggle("", isOn: $settings.pttEnabled)
                            .toggleStyle(.switch)
                            .tint(.accentColor)
                            .labelsHidden()
                    }

                    if settings.pttEnabled {
                        Divider()
                            .background(TalkieTheme.surfaceElevated)

                        HStack {
                            Text("PTT Shortcut")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textSecondary)

                            Spacer()

                            HotkeyRecorderButton(
                                hotkey: $settings.pttHotkey,
                                isRecording: $isRecordingPTTHotkey,
                                showReset: false
                            )
                        }

                        if isRecordingPTTHotkey {
                            Text("Press any key combination with ⌘, ⌥, ⌃, or ⇧")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor.opacity(0.8))
                        }
                    }
                }
                .onChange(of: settings.pttEnabled) { _, _ in
                    // Notify to re-register hotkeys
                    NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                }
            }

            // Queue Paste shortcut
            SettingsCard(title: "QUEUE PASTE") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paste from Queue")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Show picker to paste queued transcriptions")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Text("⌥⌘V")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }

                    Text("Recordings made while Talkie Live is the active app are queued instead of auto-pasted. Use this shortcut to select and paste from your queue.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Restore defaults (only show if shortcuts have been modified)
            if hasModifiedShortcuts {
                HStack {
                    Spacer()

                    Button(action: {
                        settings.hotkey = .default
                        settings.pttHotkey = .defaultPTT
                        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                            Text("Restore Default Shortcuts")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(isRestoreHovered ? .white : TalkieTheme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isRestoreHovered ? TalkieTheme.surfaceElevated : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .onHover { isRestoreHovered = $0 }

                    Spacer()
                }
                .padding(.top, Spacing.sm)
            }
        }
    }
}

// MARK: - Sounds Settings Section

struct SoundsSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @State private var selectedEvent: SoundEvent = .start

    enum SoundEvent: String, CaseIterable {
        case start = "Start"
        case finish = "Finish"
        case paste = "Paste"

        var icon: String {
            switch self {
            case .start: return "mic.fill"
            case .finish: return "checkmark.circle.fill"
            case .paste: return "doc.on.clipboard.fill"
            }
        }

        var description: String {
            switch self {
            case .start: return "When recording begins"
            case .finish: return "When recording ends"
            case .paste: return "When text is pasted"
            }
        }
    }

    private func binding(for event: SoundEvent) -> Binding<TalkieSound> {
        switch event {
        case .start: return $settings.startSound
        case .finish: return $settings.finishSound
        case .paste: return $settings.pastedSound
        }
    }

    @State private var isPlayingSequence = false

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "speaker.wave.2",
                title: "SOUNDS",
                subtitle: "Configure audio feedback for different events."
            )
        } content: {
            // Event selector - horizontal row with play all
            SettingsCard(title: "EVENT") {
                VStack(spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(SoundEvent.allCases, id: \.rawValue) { event in
                            SoundEventCard(
                                event: event,
                                sound: binding(for: event).wrappedValue,
                                isSelected: selectedEvent == event
                            ) {
                                selectedEvent = event
                            }
                        }
                    }

                    // Play sequence button
                    Button(action: playSequence) {
                        HStack(spacing: 6) {
                            Image(systemName: isPlayingSequence ? "stop.fill" : "play.fill")
                                .font(.system(size: 10))
                            Text(isPlayingSequence ? "Playing..." : "Play Sequence")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(isPlayingSequence ? .orange : .accentColor)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(isPlayingSequence ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPlayingSequence)
                }
            }

            // Sound picker for selected event
            SettingsCard(title: "SOUND FOR \(selectedEvent.rawValue.uppercased())") {
                SoundGrid(selection: binding(for: selectedEvent))
            }
        }
    }

    private func playSequence() {
        isPlayingSequence = true
        let sounds = [settings.startSound, settings.finishSound, settings.pastedSound]
        var delay: Double = 0

        for sound in sounds {
            if sound != .none {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    SoundManager.shared.preview(sound)
                }
                delay += 0.6
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) {
            isPlayingSequence = false
        }
    }
}

// MARK: - Sound Event Card

struct SoundEventCard: View {
    let event: SoundsSettingsSection.SoundEvent
    let sound: TalkieSound
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                // Icon
                Image(systemName: event.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : TalkieTheme.textSecondary)
                    .frame(height: 24)

                // Event name
                Text(event.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)

                // Current sound
                Text(sound.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : TalkieTheme.surfaceElevated))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Sound Grid

struct SoundGrid: View {
    @Binding var selection: TalkieSound

    private let columns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: Spacing.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.sm) {
            ForEach(TalkieSound.allCases, id: \.self) { sound in
                SoundChip(
                    sound: sound,
                    isSelected: selection == sound
                ) {
                    selection = sound
                }
            }
        }
    }
}

// MARK: - Sound Chip

struct SoundChip: View {
    let sound: TalkieSound
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPlaying = false

    var body: some View {
        Button(action: {
            action()
            if sound != .none {
                isPlaying = true
                SoundManager.shared.preview(sound)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isPlaying = false
                }
            }
        }) {
            HStack(spacing: 4) {
                // Checkmark for selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.accentColor)
                } else if sound == .none {
                    Image(systemName: "speaker.slash")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textMuted)
                } else {
                    Image(systemName: isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textSecondary)
                        .symbolEffect(.variableColor.iterative, isActive: isPlaying)
                }

                Text(sound.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .accentColor : TalkieTheme.textSecondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isSelected ? Color.accentColor.opacity(0.25) : (isHovered ? TalkieTheme.hover : TalkieTheme.surfaceElevated))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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

            // Context Settings - which app to show in history
            SettingsCard(title: "APP CONTEXT") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Which app to show in history")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .textCase(.uppercase)

                    ForEach(PrimaryContextSource.allCases, id: \.rawValue) { source in
                        PrimaryContextRow(
                            source: source,
                            isSelected: settings.primaryContextSource == source
                        ) {
                            settings.primaryContextSource = source
                        }
                    }
                }
            }

            SettingsCard(title: "CONTEXT CAPTURE") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Toggle(isOn: $settings.contextCaptureSessionAllowed) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Capture context this session")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Front app, window titles, and (optionally) focused text. Resets when you quit Talkie Live.")
                                .font(.system(size: 9))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }
                    }
                    .toggleStyle(.switch)

                    Text("Detail level")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .textCase(.uppercase)

                    ForEach(ContextCaptureDetail.allCases, id: \.rawValue) { detail in
                        ContextCaptureDetailRow(
                            detail: detail,
                            isSelected: settings.contextCaptureDetail == detail
                        ) {
                            settings.contextCaptureDetail = detail
                        }
                    }
                }
            }
        }
    }
}

struct PrimaryContextRow: View {
    let source: PrimaryContextSource
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(source.description)
                    .font(.system(size: 9))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

struct ContextCaptureDetailRow: View {
    let detail: ContextCaptureDetail
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(detail.description)
                    .font(.system(size: 9))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
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
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(mode.description)
                    .font(.system(size: 9))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
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
                subtitle: "Configure the recording indicator and floating pill."
            )
        } content: {
            // SECTION 1: Recording Indicator
            OverlaySectionHeader(
                icon: "sparkles",
                title: "RECORDING INDICATOR",
                description: "Visual feedback shown while recording audio"
            )

            // Indicator Style
            SettingsCard(title: "INDICATOR STYLE") {
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

            // Indicator Position
            SettingsCard(title: "INDICATOR POSITION") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(IndicatorPosition.allCases, id: \.rawValue) { position in
                        IndicatorPositionRow(
                            position: position,
                            isSelected: settings.overlayPosition == position
                        ) {
                            settings.overlayPosition = position
                        }
                    }
                }
            }

            // SECTION 2: Floating Pill
            OverlaySectionHeader(
                icon: "capsule.fill",
                title: "FLOATING PILL",
                description: "Persistent widget for quick access and status"
            )
            .padding(.top, Spacing.lg)

            // Pill Position
            SettingsCard(title: "PILL POSITION") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(PillPosition.allCases, id: \.rawValue) { position in
                        PillPositionRow(
                            position: position,
                            isSelected: settings.pillPosition == position
                        ) {
                            settings.pillPosition = position
                        }
                    }
                }
            }

            // Pill Options
            SettingsCard(title: "PILL OPTIONS") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Show on all screens toggle
                    SettingsToggleRow(
                        icon: "display.2",
                        title: "Show on all screens",
                        description: "Display pill on every connected monitor",
                        isOn: $settings.pillShowOnAllScreens
                    )

                    Rectangle()
                        .fill(Design.divider)
                        .frame(height: 0.5)

                    // Expand during recording toggle
                    SettingsToggleRow(
                        icon: "timer",
                        title: "Expand during recording",
                        description: "Show timer and controls while recording",
                        isOn: $settings.pillExpandsDuringRecording
                    )
                }
            }
        }
    }
}

// MARK: - Overlay Section Header

struct OverlaySectionHeader: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(SemanticColor.info)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.xs)
    }
}

// MARK: - Indicator Position Row

struct IndicatorPositionRow: View {
    let position: IndicatorPosition
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(position.description)
                    .font(.system(size: 9))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Pill Position Row

struct PillPositionRow: View {
    let position: PillPosition
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(position.description)
                    .font(.system(size: 9))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isOn ? SemanticColor.info : TalkieTheme.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(description)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
        }
        .padding(.vertical, Spacing.xs)
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
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(model.description)
                    .font(.system(size: 9))
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Audio Settings Section

struct AudioSettingsSection: View {
    @ObservedObject private var audioDevices = AudioDeviceManager.shared

    private var selectedDeviceName: String {
        if let device = audioDevices.inputDevices.first(where: { $0.id == audioDevices.selectedDeviceID }) {
            return device.name
        } else if let defaultDevice = audioDevices.inputDevices.first(where: { $0.isDefault }) {
            return defaultDevice.name
        }
        return "System Default"
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "mic",
                title: "AUDIO",
                subtitle: "Microphone selection and audio troubleshooting."
            )
        } content: {
            // Microphone Selection
            SettingsCard(title: "MICROPHONE") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Input Device")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Select which microphone to use for recording")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Menu {
                            ForEach(audioDevices.inputDevices) { device in
                                Button(action: {
                                    audioDevices.selectDevice(device.id)
                                }) {
                                    HStack {
                                        Text(device.name)
                                        if device.isDefault {
                                            Text("(System Default)")
                                                .foregroundColor(.secondary)
                                        }
                                        if device.id == audioDevices.selectedDeviceID {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedDeviceName)
                                    .font(.system(size: 11))
                                    .foregroundColor(TalkieTheme.textPrimary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(TalkieTheme.textTertiary)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(TalkieTheme.surfaceElevated)
                            .cornerRadius(CornerRadius.xs)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }

            // Troubleshooting
            SettingsCard(title: "TROUBLESHOOTING") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Audio Diagnostics")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Check input levels, permissions, and fix common issues")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Button(action: {
                            AudioTroubleshooterController.shared.show()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 11))
                                Text("Run Diagnostics")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(TalkieTheme.textPrimary)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(TalkieTheme.surfaceElevated)
                            .cornerRadius(CornerRadius.xs)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Transcription Settings Section

struct EngineSettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @ObservedObject private var engineClient = EngineClient.shared
    @ObservedObject private var audioDevices = AudioDeviceManager.shared
    @StateObject private var whisperService = WhisperService.shared
    @State private var downloadingModelId: String?
    @State private var downloadTask: Task<Void, Never>?

    /// Group available models by family
    private var modelsByFamily: [String: [ModelInfo]] {
        Dictionary(grouping: engineClient.availableModels) { $0.family }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "waveform",
                title: "TRANSCRIPTION",
                subtitle: "Speech recognition models and settings."
            )
        } content: {
            // Service Status - simplified, user-friendly
            SettingsCard(title: "STATUS") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(engineStatusColor)
                                    .frame(width: 8, height: 8)
                                Text(engineClient.isConnected ? "Ready" : "Connecting...")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(TalkieTheme.textPrimary)
                            }

                            if engineClient.isConnected, let status = engineClient.status {
                                Text("\(status.totalTranscriptions) transcriptions processed")
                                    .font(.system(size: 10))
                                    .foregroundColor(TalkieTheme.textTertiary)
                            } else if let error = engineClient.lastError {
                                Text(error)
                                    .font(.system(size: 10))
                                    .foregroundColor(SemanticColor.error.opacity(0.8))
                            } else {
                                Text("Starting transcription service...")
                                    .font(.system(size: 10))
                                    .foregroundColor(TalkieTheme.textTertiary)
                            }
                        }

                        Spacer()

                        if !engineClient.isConnected {
                            Button(action: {
                                engineClient.reconnect()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10))
                                    Text("Retry")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(CornerRadius.xs)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Speech Recognition Models - Dynamic from Engine
            ForEach(ModelFamily.allCases, id: \.rawValue) { family in
                if let models = modelsByFamily[family.rawValue], !models.isEmpty {
                    SettingsCard(title: "\(family.displayName.uppercased()) MODELS") {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(models) { model in
                                ModelManagementRow(
                                    model: model,
                                    isSelected: settings.selectedModelId == model.id,
                                    isDownloading: downloadingModelId == model.id,
                                    downloadProgress: engineClient.downloadProgress?.modelId == model.id
                                        ? Float(engineClient.downloadProgress?.progress ?? 0)
                                        : 0,
                                    onSelect: { settings.selectedModelId = model.id },
                                    onDownload: { downloadModel(model.id) },
                                    onDelete: { deleteModel(model.id) }
                                )

                                if model.id != models.last?.id {
                                    Divider()
                                        .background(TalkieTheme.hover)
                                }
                            }
                        }
                    }
                }
            }

            // Show message if no models available yet
            if engineClient.availableModels.isEmpty {
                SettingsCard(title: "MODELS") {
                    VStack(spacing: Spacing.sm) {
                        if engineClient.connectionState == .connected {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading available models...")
                                .font(.system(size: 11))
                                .foregroundColor(TalkieTheme.textTertiary)
                        } else {
                            Text("Connect to engine to see available models")
                                .font(.system(size: 11))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                }
            }

            // Info
            SettingsCard(title: "ABOUT ENGINE") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("TalkieEngine runs as a separate process to keep ML models warm in memory across app restarts. It supports multiple speech recognition models including Whisper and Parakeet, all running locally via Apple's Neural Engine.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Technical details
                    if let status = engineClient.status {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Divider()
                                .padding(.vertical, Spacing.xs)

                            // Process info
                            HStack(spacing: Spacing.xs) {
                                Text("Process ID:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(TalkieTheme.textSecondary)
                                Text("\(status.pid)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(TalkieTheme.textPrimary)
                            }

                            // XPC service name
                            if let mode = engineClient.connectedMode {
                                HStack(spacing: Spacing.xs) {
                                    Text("XPC Service:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(TalkieTheme.textSecondary)
                                    Text(mode.rawValue)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(TalkieTheme.textPrimary)
                                }
                            }

                            // Connection state
                            HStack(spacing: Spacing.xs) {
                                Text("Connection:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(TalkieTheme.textSecondary)
                                Text(engineClient.connectionState.rawValue)
                                    .font(.system(size: 9))
                                    .foregroundColor(engineStatusColor)
                            }

                            // Uptime
                            HStack(spacing: Spacing.xs) {
                                Text("Uptime:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(TalkieTheme.textSecondary)
                                Text(formatUptime(status.uptime))
                                    .font(.system(size: 9))
                                    .foregroundColor(TalkieTheme.textPrimary)
                            }

                            // Transcriptions processed
                            HStack(spacing: Spacing.xs) {
                                Text("Transcriptions:")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(TalkieTheme.textSecondary)
                                Text("\(status.totalTranscriptions)")
                                    .font(.system(size: 9))
                                    .foregroundColor(TalkieTheme.textPrimary)
                            }

                            // Memory usage
                            if let memoryMB = status.memoryUsageMB {
                                HStack(spacing: Spacing.xs) {
                                    Text("Memory:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(TalkieTheme.textSecondary)
                                    Text("\(memoryMB) MB")
                                        .font(.system(size: 9))
                                        .foregroundColor(TalkieTheme.textPrimary)
                                }
                            }

                            // Build type
                            if let isDebug = status.isDebugBuild {
                                HStack(spacing: Spacing.xs) {
                                    Text("Build:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(TalkieTheme.textSecondary)
                                    Text(isDebug ? "Debug" : "Release")
                                        .font(.system(size: 9))
                                        .foregroundColor(TalkieTheme.textPrimary)
                                }
                            }

                            // Loaded model
                            if let modelId = status.loadedModelId {
                                HStack(spacing: Spacing.xs) {
                                    Text("Loaded Model:")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(TalkieTheme.textSecondary)
                                    Text(modelId)
                                        .font(.system(size: 9))
                                        .foregroundColor(TalkieTheme.textPrimary)
                                }
                            }
                        }
                        .padding(.top, Spacing.xs)
                    }

                    HStack(spacing: Spacing.md) {
                        ModelInfoBadge(icon: "lock.shield", label: "Private")
                        ModelInfoBadge(icon: "bolt", label: "On-device")
                        ModelInfoBadge(icon: "memorychip", label: "Persistent")
                    }
                    .padding(.top, Spacing.xs)
                }
            }
        }
        .onAppear {
            Task {
                // Ensure connection first, then refresh
                let connected = await engineClient.ensureConnected()
                if connected {
                    engineClient.refreshStatus()
                    await engineClient.refreshAvailableModels()
                }
            }
        }
    }

    private var engineStatusColor: Color {
        switch engineClient.connectionState {
        case .connected: return SemanticColor.success
        case .connectedWrongBuild: return SemanticColor.warning
        case .connecting: return SemanticColor.warning
        case .disconnected: return .gray
        case .error: return SemanticColor.error
        }
    }

    private var selectedDeviceName: String {
        let selectedID = audioDevices.selectedDeviceID
        if let device = audioDevices.inputDevices.first(where: { $0.id == selectedID }) {
            return device.name
        }
        // Fallback to default device name
        if let defaultDevice = audioDevices.inputDevices.first(where: { $0.isDefault }) {
            return "\(defaultDevice.name) (Default)"
        }
        return "System Default"
    }

    private func formatUptime(_ date: Date?) -> String {
        guard let date = date else { return "--" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        return "\(hours)h \(minutes % 60)m"
    }

    private func formatUptime(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        let days = hours / 24
        return "\(days)d \(hours % 24)h"
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "1h+ ago"
    }

    private func downloadModel(_ modelId: String) {
        // Check if already downloaded
        if let model = engineClient.availableModels.first(where: { $0.id == modelId }),
           model.isDownloaded {
            return
        }

        downloadingModelId = modelId
        downloadTask = Task {
            do {
                try await engineClient.downloadModel(modelId)
                await MainActor.run {
                    downloadingModelId = nil
                    downloadTask = nil
                }
            } catch {
                await MainActor.run {
                    downloadingModelId = nil
                    downloadTask = nil
                }
            }
        }
    }

    private func deleteModel(_ modelId: String) {
        // TODO: Implement delete via engine XPC
        // For now, this is a no-op as deletion isn't implemented in the engine
    }
}

// MARK: - Engine Stat Badge

struct EngineStatBadge: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(.accentColor.opacity(0.8))

            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(TalkieTheme.textMuted)

                Text(value)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(TalkieTheme.textPrimary)
            }
        }
    }
}

/// Generic model management row that works with ModelInfo from the engine
struct ModelManagementRow: View {
    let model: ModelInfo
    let isSelected: Bool
    let isDownloading: Bool
    let downloadProgress: Float
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Selection indicator
            Button(action: onSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : TalkieTheme.textMuted)
            }
            .buttonStyle(.plain)
            .disabled(!model.isDownloaded)

            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(model.isDownloaded ? .white : TalkieTheme.textTertiary)

                    if model.isLoaded {
                        Text("LOADED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(SemanticColor.success)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(SemanticColor.success.opacity(0.2))
                            .cornerRadius(3)
                    }

                    Text(model.sizeDescription)
                        .font(.system(size: 8))
                        .foregroundColor(TalkieTheme.textMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(TalkieTheme.hover)
                        .cornerRadius(3)
                }

                Text(model.description)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textMuted)
            }

            Spacer()

            // Action buttons
            if isDownloading {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
                .frame(width: 60)
            } else if model.isDownloaded {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(isHovered ? SemanticColor.error : TalkieTheme.textMuted)
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0.5)
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                        Text("Download")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
        .background(isHovered ? TalkieTheme.divider : Color.clear)
        .onHover { isHovered = $0 }
    }
}

/// Legacy alias for backwards compatibility
typealias WhisperModelManagementRow = ModelManagementRow

struct ModelInfoBadge: View {
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(label)
                .font(.system(size: 9))
        }
        .foregroundColor(TalkieTheme.textTertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(TalkieTheme.hover)
        .cornerRadius(4)
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
                            color: SemanticColor.warning
                        )

                        StorageStatBox(
                            icon: "sum",
                            value: storageStats.totalStorageFormatted,
                            label: "Total",
                            color: SemanticColor.success
                        )
                    }

                    Divider()
                        .background(TalkieTheme.surfaceElevated)

                    // Secondary stats
                    HStack(spacing: Spacing.lg) {
                        // Time range
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TIME RANGE")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(TalkieTheme.textMuted)

                            if let oldest = storageStats.oldestDate, let newest = storageStats.newestDate {
                                Text("\(formatDate(oldest)) → \(formatDate(newest))")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(TalkieTheme.textSecondary)
                            } else {
                                Text("No data")
                                    .font(.system(size: 10))
                                    .foregroundColor(TalkieTheme.textMuted)
                            }
                        }

                        Spacer()

                        // Total words
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TOTAL WORDS")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(TalkieTheme.textMuted)

                            Text(formatNumber(storageStats.totalWords))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(TalkieTheme.textSecondary)
                        }

                        // Total duration
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("TOTAL DURATION")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(TalkieTheme.textMuted)

                            Text(formatDuration(storageStats.totalDurationSeconds))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(TalkieTheme.textSecondary)
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
                            .foregroundColor(TalkieTheme.textTertiary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("Last updated: \(formatTime(storageStats.lastUpdated))")
                            .font(.system(size: 9))
                            .foregroundColor(TalkieTheme.textMuted)
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
                                    .foregroundColor(TalkieTheme.textSecondary)
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
                        Text("Keep dictations for:")
                            .font(.system(size: 11))
                            .foregroundColor(TalkieTheme.textPrimary)

                        Spacer()

                        Picker("", selection: $settings.dictationTTLHours) {
                            ForEach(ttlOptions, id: \.self) { hours in
                                Text(formatTTL(hours)).tag(hours)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }

                    Text("Older dictations will be automatically deleted.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            // Storage Location & Actions
            SettingsCard(title: "DATA MANAGEMENT") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    // Location row
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)

                        Text("~/Library/Application Support/TalkieLive")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(TalkieTheme.textTertiary)
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
                        .background(TalkieTheme.surfaceElevated)

                    // Action buttons
                    HStack(spacing: Spacing.sm) {
                        StorageActionButton(
                            icon: "trash",
                            label: "Prune Old",
                            color: SemanticColor.warning
                        ) {
                            LiveDatabase.prune(olderThanHours: settings.dictationTTLHours)
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
                            color: SemanticColor.error
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
                LiveDatabase.deleteAll()
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
        let utterances = LiveDatabase.all()
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
        let utterances = LiveDatabase.all()
        var stats = StorageStats()

        stats.totalUtterances = utterances.count
        stats.totalWords = utterances.compactMap { $0.wordCount }.reduce(0, +)
        stats.totalDurationSeconds = utterances.compactMap { $0.durationSeconds }.reduce(0, +)
        stats.audioStorageBytes = await AudioStorage.totalStorageBytesAsync()

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
                .foregroundColor(TalkieTheme.textPrimary)

            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(TalkieTheme.textTertiary)
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
            .foregroundColor(isHovered ? color : TalkieTheme.textTertiary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isHovered ? color.opacity(0.15) : TalkieTheme.hover)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - About Settings Section

struct AboutSettingsSection: View {
    @ObservedObject private var engineClient = EngineClient.shared

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var appPath: String {
        Bundle.main.bundlePath
    }

    private var isProductionRelease: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    private var isInstalledLocation: Bool {
        appPath.hasPrefix("/Applications")
    }

    private var buildTypeLabel: String {
        if isProductionRelease && isInstalledLocation {
            return "Production"
        } else if isProductionRelease {
            return "Release"
        } else {
            return "Debug"
        }
    }

    private var buildTypeColor: Color {
        if isProductionRelease && isInstalledLocation {
            return SemanticColor.success
        } else {
            return SemanticColor.warning
        }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "info.circle",
                title: "ABOUT",
                subtitle: "Version information and system diagnostics."
            )
        } content: {
            // App Info (consolidated)
            SettingsCard(title: "APPLICATION") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    AboutInfoRow(label: "Talkie Live", value: "v\(appVersion) (\(buildNumber))")
                    AboutInfoRow(label: "Process ID", value: String(ProcessInfo.processInfo.processIdentifier), isMonospaced: true)
                    AboutInfoRow(label: "Bundle ID", value: bundleID, isMonospaced: true)
                    AboutInfoRow(label: "Build", value: buildTypeLabel, valueColor: buildTypeColor)

                    Divider()
                        .background(TalkieTheme.border.opacity(0.5))

                    AboutInfoRow(label: "Path", value: appPath, isMonospaced: true, canCopy: true)
                    AboutInfoRow(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                }
            }

            // Engine Status
            SettingsCard(title: "TALKIE ENGINE") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("Status")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(TalkieTheme.textTertiary)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(engineClient.isConnected ? SemanticColor.success : SemanticColor.error)
                                .frame(width: 8, height: 8)
                            Text(engineClient.isConnected ? "Connected" : "Not Running")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(engineClient.isConnected ? SemanticColor.success : SemanticColor.error)
                        }
                    }

                    if engineClient.isConnected, let status = engineClient.status {
                        AboutInfoRow(label: "Engine PID", value: String(status.pid), isMonospaced: true)
                        AboutInfoRow(label: "Bundle", value: status.bundleId, isMonospaced: true)
                    }
                }
            }

            // Support
            SettingsCard(title: "SUPPORT") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        Text("If you need help or want to report an issue, please include the information above.")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }

                    Button(action: copyDiagnostics) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 10))
                            Text("Copy Diagnostics")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(CornerRadius.xs)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func copyDiagnostics() {
        var diagnostics = """
        Talkie Live Diagnostics
        =======================
        Version: \(appVersion) (\(buildNumber))
        PID: \(ProcessInfo.processInfo.processIdentifier)
        Bundle ID: \(bundleID)
        Build: \(buildTypeLabel)
        Path: \(appPath)
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)

        TalkieEngine:
        """

        if engineClient.isConnected, let status = engineClient.status {
            diagnostics += """

            Status: Connected
            Engine PID: \(status.pid)
            Engine Bundle: \(status.bundleId)
            """
        } else {
            diagnostics += "\nStatus: Not Connected"
            if let error = engineClient.lastError {
                diagnostics += "\nLast Error: \(error)"
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
    }
}

struct AboutInfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .white
    var isMonospaced: Bool = false
    var canCopy: Bool = false

    @State private var showCopied = false

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(TalkieTheme.textTertiary)
            Spacer()
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 11, weight: .medium, design: isMonospaced ? .monospaced : .default))
                    .foregroundColor(valueColor.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if canCopy {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            showCopied = false
                        }
                    }) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(showCopied ? SemanticColor.success : TalkieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Quick Settings View (Focused: Capture + Output + Permissions)

enum QuickSettingsTab: String, CaseIterable {
    case audio
    case feedback
    case output
    case permissions
    case connections

    var title: String {
        switch self {
        case .audio: return "Audio"
        case .feedback: return "Feedback"
        case .output: return "Output"
        case .permissions: return "Permissions"
        case .connections: return "Connections"
        }
    }

    var icon: String {
        switch self {
        case .audio: return "mic.fill"
        case .feedback: return "rectangle.inset.topright.filled"
        case .output: return "arrow.right.doc.on.clipboard"
        case .permissions: return "lock.shield.fill"
        case .connections: return "network"
        }
    }
}

struct QuickSettingsView: View {
    @State private var selectedTab: QuickSettingsTab = .audio
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(QuickSettingsTab.allCases, id: \.self) { tab in
                    QuickSettingsTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        showWarning: tab == .permissions && !permissionManager.allRequiredGranted
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)

            Rectangle()
                .fill(TalkieTheme.divider)
                .frame(height: 0.5)
                .padding(.top, Spacing.sm)

            // Content
            ScrollView {
                switch selectedTab {
                case .audio:
                    AudioSettingsSection()
                case .feedback:
                    OverlaySettingsSection()
                case .output:
                    OutputSettingsSection()
                case .permissions:
                    PermissionsSettingsSection()
                case .connections:
                    ConnectionsSettingsSection()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TalkieTheme.background)
    }
}

struct QuickSettingsTabButton: View {
    let tab: QuickSettingsTab
    let isSelected: Bool
    var showWarning: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12))

                Text(tab.title)
                    .font(.system(size: 12, weight: .medium))

                if showWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(isSelected ? .white : TalkieTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isSelected ? TalkieTheme.accent : (isHovered ? TalkieTheme.surfaceElevated : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Connections Settings Section

struct ConnectionsSettingsSection: View {
    @State private var engineStatus: EngineConnectionStatus = .unknown
    @State private var talkieConnected = false
    @State private var isRefreshing = false

    private let myPID = ProcessInfo.processInfo.processIdentifier

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: "network")
                        .font(.system(size: 20))
                        .foregroundColor(TalkieTheme.accent)

                    Text("CONNECTIONS")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(TalkieTheme.textPrimary)

                    Spacer()

                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 0.5) : .default, value: isRefreshing)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(TalkieTheme.textSecondary)
                }

                Text("XPC service connections to Talkie ecosystem")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            // This Process
            ConnectionCard(
                title: "TalkieLive",
                subtitle: "This process",
                icon: "app.fill",
                status: .connected,
                pid: myPID,
                serviceName: nil
            )

            // TalkieEngine Connection
            ConnectionCard(
                title: "TalkieEngine",
                subtitle: "Transcription service",
                icon: "waveform",
                status: engineStatus,
                pid: engineStatus.pid,
                serviceName: TalkieEnvironment.current.engineXPCService
            )

            // Talkie Connection (observers)
            ConnectionCard(
                title: "Talkie",
                subtitle: "Main app (observing us)",
                icon: "app.badge.checkmark",
                status: talkieConnected ? .connected : .disconnected,
                pid: nil,
                serviceName: TalkieEnvironment.current.liveXPCService
            )

            // Environment Info
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("ENVIRONMENT")
                    .font(.techLabelSmall)
                    .tracking(Tracking.wide)
                    .foregroundColor(TalkieTheme.textTertiary)

                HStack {
                    Text("Mode:")
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textSecondary)
                    Text(TalkieEnvironment.current.rawValue.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(TalkieTheme.accent)

                    Spacer()

                    if let bundleID = Bundle.main.bundleIdentifier {
                        Text(bundleID)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .textSelection(.enabled)
                    }
                }
                .padding(Spacing.sm)
                .background(TalkieTheme.surfaceElevated)
                .cornerRadius(CornerRadius.sm)
            }
        }
        .padding(Spacing.lg)
        .onAppear { refresh() }
    }

    private func refresh() {
        isRefreshing = true

        // Check Engine connection
        Task {
            let client = EngineClient.shared
            let connected = await client.ensureConnected()

            await MainActor.run {
                if connected {
                    // Try to get PID from engine status
                    engineStatus = .connected
                } else {
                    engineStatus = .disconnected
                }

                // Check if Talkie is observing us
                talkieConnected = TalkieLiveXPCService.shared.isTalkieConnected

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isRefreshing = false
                }
            }
        }
    }
}

enum EngineConnectionStatus {
    case unknown
    case connected
    case disconnected

    var pid: Int32? { nil }  // TODO: Get from engine status
}

struct ConnectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let status: EngineConnectionStatus
    var pid: Int32?
    var serviceName: String?

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .disconnected: return .red
        case .unknown: return .orange
        }
    }

    private var statusText: String {
        switch status {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .unknown: return "Unknown"
        }
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(statusColor)
            }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(TalkieTheme.textSecondary)

                if let serviceName = serviceName {
                    Text(serviceName)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            Spacer()

            // Status + PID
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(statusColor)
                }

                if let pid = pid {
                    Text("PID \(pid)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }
        }
        .padding(Spacing.md)
        .background(TalkieTheme.surface)
        .cornerRadius(CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .strokeBorder(statusColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .frame(width: 650, height: 500)
        .preferredColorScheme(.dark)
}

#Preview("Quick Settings") {
    QuickSettingsView()
        .frame(width: 550, height: 500)
        .preferredColorScheme(.dark)
}

#Preview("Connections") {
    ConnectionsSettingsSection()
        .frame(width: 500, height: 500)
        .background(TalkieTheme.background)
        .preferredColorScheme(.dark)
}
