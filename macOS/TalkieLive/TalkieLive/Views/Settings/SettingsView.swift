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
            // MARK: - Settings Sections Navigation (glass sidebar)
            GlassSidebar {
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
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)

                // Sections List
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.xs) {
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

            // Glass edge separator
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

            // MARK: - Settings Content (right column with glass background)
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
            .background(.ultraThinMaterial)
        }
        .glassPanel()
        .ignoresSafeArea(.all, edges: .all)
        .id("embedded-settings-\(settings.glassMode)")  // Force full view rebuild on glass mode change
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? TalkieTheme.accent : TalkieTheme.textSecondary)
                    .frame(width: 16)

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? TalkieTheme.textPrimary : TalkieTheme.textSecondary)

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    // Base fill
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(
                            isSelected
                                ? TalkieTheme.accent.opacity(0.18)
                                : (isHovered ? Color.white.opacity(0.08) : Color.clear)
                        )

                    // Top highlight on selection/hover
                    if isSelected || isHovered {
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isSelected ? 0.2 : 0.1),
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
            .shadow(color: isSelected ? TalkieTheme.accent.opacity(0.2) : Color.clear, radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .animation(TalkieAnimation.fast, value: isSelected)
        .animation(TalkieAnimation.fast, value: isHovered)
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
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Spacing.md) {
                // Icon in a subtle glass container
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(Color.accentColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .frame(width: 36, height: 36)

                // Title and subtitle stacked
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Spacing.sm) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(Tracking.normal)
                            .foregroundColor(TalkieTheme.textPrimary)

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.15))
                                )
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textTertiary)
                }

                Spacer()
            }

            // Subtle separator line
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.top, Spacing.md)
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
            .background(
                ZStack {
                    // Consistent glass-like card background
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(Color.white.opacity(0.04))
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
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
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                }
            )
        }
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
// MARK: - Quick Settings View (Focused: Capture + Output + Permissions)

enum QuickSettingsTab: String, CaseIterable {
    case shortcuts
    case sounds
    case audio
    case feedback
    case output
    case permissions
    case connections

    var title: String {
        switch self {
        case .shortcuts: return "Shortcuts"
        case .sounds: return "Sounds"
        case .audio: return "Audio"
        case .feedback: return "Feedback"
        case .output: return "Output"
        case .permissions: return "Permissions"
        case .connections: return "Connections"
        }
    }

    var icon: String {
        switch self {
        case .shortcuts: return "command"
        case .sounds: return "speaker.wave.2"
        case .audio: return "mic.fill"
        case .feedback: return "rectangle.inset.topright.filled"
        case .output: return "arrow.right.doc.on.clipboard"
        case .permissions: return "lock.shield.fill"
        case .connections: return "network"
        }
    }
}

struct QuickSettingsView: View {
    var initialTab: QuickSettingsTab = .shortcuts
    @State private var selectedTab: QuickSettingsTab = .shortcuts
    @StateObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var settings = LiveSettings.shared

    init(initialTab: QuickSettingsTab = .shortcuts) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Glass tab bar - full width with evenly distributed tabs
            HStack(spacing: 0) {
                ForEach(QuickSettingsTab.allCases, id: \.self) { tab in
                    QuickSettingsTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        showWarning: tab == .permissions && !permissionManager.allRequiredGranted
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                    .frame(maxWidth: .infinity)  // Each tab takes equal width
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)
            .background(
                ZStack {
                    if settings.glassMode {
                        // Glass mode: Frosted glass base
                        Rectangle()
                            .fill(.thinMaterial)

                        // Top highlight
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.08),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    } else {
                        // Legacy mode: Solid dark background
                        Rectangle()
                            .fill(Color(white: 0.10))
                    }

                    // Bottom edge (subtle separator)
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.white.opacity(settings.glassMode ? 0.06 : 0.12))
                            .frame(height: 1)
                    }
                }
            )

            // Content with glass background
            ScrollView {
                switch selectedTab {
                case .shortcuts:
                    ShortcutsQuickSection()
                case .sounds:
                    SoundsSettingsSection()
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
        .glassPanel()
        .id("quick-settings-\(settings.glassMode)")  // Force full view rebuild on glass mode change
    }
}

struct QuickSettingsTabButton: View {
    let tab: QuickSettingsTab
    let isSelected: Bool
    var showWarning: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .medium))

                if showWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                }
            }
            .foregroundColor(isSelected ? .white : TalkieTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    if isSelected {
                        // Selected: accent color
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(TalkieTheme.accent)

                        if settings.glassMode {
                            // Glass highlight on top
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.3),
                                            Color.white.opacity(0.1),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    } else if isHovered {
                        if settings.glassMode {
                            // Glass mode: subtle glass hover
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(Color.white.opacity(0.1))

                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.15),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    ),
                                    lineWidth: 0.5
                                )
                        } else {
                            // Legacy mode: solid hover
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(Color(white: 0.2))

                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        }
                    }
                }
            )
            .shadow(color: isSelected ? TalkieTheme.accent.opacity(settings.glassMode ? 0.4 : 0.2) : Color.clear, radius: settings.glassMode ? 6 : 3, y: 2)
        }
        .buttonStyle(.plain)
        .animation(TalkieAnimation.fast, value: isSelected)
        .animation(TalkieAnimation.fast, value: isHovered)
        .onHover { isHovered = $0 }
        .help(tab.title)
    }
}

// MARK: - Shortcuts Quick Section

struct ShortcutsQuickSection: View {
    @ObservedObject private var settings = LiveSettings.shared
    @State private var isRecordingToggle = false
    @State private var isRecordingPTT = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: "command")
                        .font(.system(size: 20))
                        .foregroundColor(TalkieTheme.accent)

                    Text("SHORTCUTS")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(TalkieTheme.textPrimary)
                }

                Text("Global keyboard shortcuts")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            // Toggle Recording
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toggle Recording")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TalkieTheme.textPrimary)
                        Text("Press to start/stop")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }

                    Spacer()

                    HotkeyRecorderButton(
                        hotkey: $settings.hotkey,
                        isRecording: $isRecordingToggle,
                        showReset: false
                    )
                }

                if isRecordingToggle {
                    Text("Press any key with ⌘, ⌥, ⌃, or ⇧")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor.opacity(0.8))
                        .padding(.top, Spacing.xs)
                }
            }

            // Push-to-Talk
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Push-to-Talk")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Hold to record")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Toggle("", isOn: $settings.pttEnabled)
                            .toggleStyle(.switch)
                            .tint(.accentColor)
                            .labelsHidden()
                            .scaleEffect(0.8)
                    }

                    if settings.pttEnabled {
                        Divider()
                            .background(Color.white.opacity(0.1))

                        HStack {
                            Text("PTT Shortcut")
                                .font(.system(size: 11))
                                .foregroundColor(TalkieTheme.textSecondary)

                            Spacer()

                            HotkeyRecorderButton(
                                hotkey: $settings.pttHotkey,
                                isRecording: $isRecordingPTT,
                                showReset: false
                            )
                        }

                        if isRecordingPTT {
                            Text("Press any key with ⌘, ⌥, ⌃, or ⇧")
                                .font(.system(size: 10))
                                .foregroundColor(.accentColor.opacity(0.8))
                        }
                    }
                }
                .onChange(of: settings.pttEnabled) { _, _ in
                    NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
                }
            }

            // Queue Paste (read-only display)
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Paste from Queue")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TalkieTheme.textPrimary)
                        Text("Select queued transcription")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }

                    Spacer()

                    Text("⌥⌘V")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                .fill(Color.accentColor.opacity(0.15))
                        )
                }
            }
        }
        .padding(Spacing.lg)
    }
}

// MARK: - Glass Card Component

struct GlassCard<Content: View>: View {
    var intensity: GlassIntensity = .subtle
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Spacing.md)
        .glassBackground(intensity: intensity, cornerRadius: CornerRadius.md)
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
