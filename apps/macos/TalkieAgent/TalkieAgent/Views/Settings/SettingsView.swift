//
//  SettingsView.swift
//  TalkieAgent
//
//  Settings UI with sidebar navigation
//

import SwiftUI
import AppKit
import Carbon.HIToolbox
import TalkieKit

private let settingsCanvasBackground = opsAdaptive(
    light: Color(red: 242.0 / 255.0, green: 243.0 / 255.0, blue: 245.0 / 255.0),
    dark: OpsInk.bg
)

private let settingsCardBackground = opsAdaptive(
    light: Color.white,
    dark: OpsInk.surface
)

private let settingsCardBorder = opsAdaptive(
    light: Color(red: 211.0 / 255.0, green: 213.0 / 255.0, blue: 218.0 / 255.0),
    dark: OpsHairline.standard
)

private let settingsCardShadow = opsAdaptive(
    light: Color.black.opacity(0.035),
    dark: Color.clear
)

private let settingsHeaderDivider = opsAdaptive(
    light: Color(red: 222.0 / 255.0, green: 224.0 / 255.0, blue: 228.0 / 255.0),
    dark: OpsHairline.subtle
)

// MARK: - Settings Section Enum

enum SettingsSection: String, Hashable, CaseIterable {
    // Appearance
    case appearance
    // Behavior
    case shortcuts
    case capture
    case sounds
    case output
    case overlay
    case audio  // Microphone & audio troubleshooting
    // System
    case engine  // Now "Transcription" - AI models
    case storage
    case permissions  // Permission Center
    case featureFlags
    case about
    #if DEBUG
    case debug  // Debug settings dump
    #endif

    var title: String {
        switch self {
        case .appearance: return "APPEARANCE"
        case .shortcuts: return "SHORTCUTS"
        case .capture: return "CAPTURE"
        case .sounds: return "SOUNDS"
        case .output: return "OUTPUT"
        case .overlay: return "OVERLAY"
        case .audio: return "AUDIO"
        case .engine: return "TRANSCRIPTION"
        case .storage: return "STORAGE"
        case .permissions: return "PERMISSIONS"
        case .featureFlags: return "FEATURE FLAGS"
        case .about: return "ABOUT"
        #if DEBUG
        case .debug: return "DEBUG"
        #endif
        }
    }

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .shortcuts: return "command"
        case .capture: return "viewfinder"
        case .sounds: return "speaker.wave.2"
        case .output: return "arrow.right.doc.on.clipboard"
        case .overlay: return "rectangle.inset.topright.filled"
        case .audio: return "mic"
        case .engine: return "waveform"
        case .storage: return "folder"
        case .permissions: return "lock.shield"
        case .featureFlags: return "flag.fill"
        case .about: return "info.circle"
        #if DEBUG
        case .debug: return "ladybug"
        #endif
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = LiveSettings.shared
    @ObservedObject private var troubleshooterController = AudioTroubleshooterController.shared
    @State private var selectedSection: SettingsSection = .appearance

    /// Persisted width of the secondary (settings) navigation rail, so it
    /// matches the resize behavior of the primary Agent Home rail beside it.
    @AppStorage("talkie.agentSettings.sidebar.width") private var sidebarWidth: Double = 180

    /// When set, Settings is presented in-shell (Agent Home) and this returns home.
    /// When nil, it's a standalone window and falls back to the environment dismiss.
    var onClose: (() -> Void)? = nil

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    private var sidebarBackground: Color { OpsInk.chrome }
    private var contentBackground: Color { settingsCanvasBackground }
    private var bottomBarBackground: Color { OpsInk.chrome }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                // Settings header — "Titled": back chip + display title + rule.
                // (Replaces the old tiny "‹ SETTINGS" eyebrow.)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        if onClose != nil {
                            Button(action: close) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(OpsInk.muted)
                                    .frame(width: 22, height: 22)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(OpsInk.bg)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(OpsHairline.subtle, lineWidth: 0.5)
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Back to Agent Home")
                        }

                        Text("Settings")
                            .font(OpsType.ui(OpsSize.xl, weight: .semibold))
                            .foregroundStyle(OpsInk.ink)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, 12)

                    OpsDivider(color: OpsHairline.subtle)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

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
                            isActive: selectedSection == .shortcuts || selectedSection == .capture || selectedSection == .sounds || selectedSection == .output || selectedSection == .overlay || selectedSection == .audio
                        ) {
                            SettingsSidebarItem(
                                icon: "command",
                                title: "SHORTCUTS",
                                isSelected: selectedSection == .shortcuts
                            ) {
                                selectedSection = .shortcuts
                            }
                            SettingsSidebarItem(
                                icon: "viewfinder",
                                title: "CAPTURE",
                                isSelected: selectedSection == .capture
                            ) {
                                selectedSection = .capture
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
                            isActive: selectedSection == .engine || selectedSection == .storage || selectedSection == .permissions || selectedSection == .featureFlags || selectedSection == .about
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
                                icon: "flag.fill",
                                title: "FEATURE FLAGS",
                                isSelected: selectedSection == .featureFlags
                            ) {
                                selectedSection = .featureFlags
                            }
                            SettingsSidebarItem(
                                icon: "info.circle",
                                title: "ABOUT",
                                isSelected: selectedSection == .about
                            ) {
                                selectedSection = .about
                            }
                        }

                        #if DEBUG
                        SettingsSidebarSection(
                            title: "DEVELOPER",
                            isActive: selectedSection == .debug
                        ) {
                            SettingsSidebarItem(
                                icon: "ladybug",
                                title: "DEBUG",
                                isSelected: selectedSection == .debug
                            ) {
                                selectedSection = .debug
                            }
                        }
                        #endif
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: CGFloat(sidebarWidth))
            .background(sidebarBackground)

            // Resizable divider — drag to size the settings rail (persisted).
            SettingsSidebarResizeHandle(width: $sidebarWidth)

            // MARK: - Content Area
            VStack(spacing: 0) {
                // Content based on selection
                Group {
                    switch selectedSection {
                    case .appearance:
                        AppearanceSettingsSection()
                    case .shortcuts:
                        ShortcutsSettingsSection()
                    case .capture:
                        CaptureSettingsSection()
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
                    case .featureFlags:
                        FeatureFlagsSettingsSection()
                    case .about:
                        AboutSettingsSection()
                    #if DEBUG
                    case .debug:
                        DebugSettingsSection()
                    #endif
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom bar with Done button (standalone window only)
                if onClose == nil {
                    HStack {
                        Spacer()
                        Button("DONE") {
                            close()
                        }
                        .buttonStyle(SettingsDoneButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(bottomBarBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(contentBackground)
        }
        .frame(minWidth: onClose == nil ? 600 : nil, maxWidth: .infinity, minHeight: onClose == nil ? 450 : nil, maxHeight: .infinity)
        .sheet(isPresented: $troubleshooterController.isShowing) {
            AudioTroubleshooterView()
        }
    }
}

// MARK: - Sidebar Components

struct SettingsSidebarSection<Content: View>: View {
    let title: String
    var isActive: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(OpsType.mono(OpsSize.xxs, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(isActive ? OpsTint.amber.color : OpsInk.muted)
            }
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
        HStack(spacing: 0) {
            // Armed channel: amber inset stripe on selection
            Rectangle()
                .fill(isSelected ? OpsTint.amber.color : Color.clear)
                .frame(width: 2)
                .padding(.vertical, 1)
                .animation(.easeOut(duration: 0.15), value: isSelected)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? OpsInk.ink : OpsInk.muted)
                    .frame(width: 20)

                Text(title.uppercased())
                    .font(OpsType.mono(OpsSize.xs, weight: isSelected ? .semibold : .medium))
                    .tracking(0.5)
                    .foregroundStyle(isSelected ? OpsInk.ink : OpsInk.ink.opacity(0.9))

                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Rectangle()
                .fill(
                    isSelected
                        ? OpsSurface.selected(OpsTint.amber.color)
                        : (isHovered ? OpsSurface.hover : Color.clear)
                )
        )
        .overlay(
            Rectangle()
                .strokeBorder(OpsHairline.subtle.opacity(isHovered && !isSelected ? 1.0 : 0), lineWidth: 0.5)
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

// MARK: - Resizable Sidebar Divider

/// The hairline between the settings rail and content, widened into a
/// drag-to-resize handle with a resize cursor — mirroring the primary Agent
/// Home rail's resize affordance that sits just to the left.
struct SettingsSidebarResizeHandle: View {
    @Binding var width: Double
    var minWidth: Double = 168
    var maxWidth: Double = 320

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragStartWidth: Double?
    @State private var cursorPushed = false

    var body: some View {
        Rectangle()
            .fill(isHovered || isDragging ? OpsTint.amber.color.opacity(0.55) : OpsHairline.standard)
            .frame(width: 1)
            .overlay {
                // Invisible, wider hit target centered on the hairline.
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 11)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHovered = hovering
                        if hovering { pushCursor() } else { popCursorIfIdle() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStartWidth == nil {
                                    dragStartWidth = width
                                    isDragging = true
                                    pushCursor()
                                }
                                let proposed = (dragStartWidth ?? width) + Double(value.translation.width)
                                width = min(maxWidth, max(minWidth, proposed))
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                                isDragging = false
                                popCursorIfIdle()
                            }
                    )
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isDragging)
    }

    private func pushCursor() {
        guard !cursorPushed else { return }
        NSCursor.resizeLeftRight.push()
        cursorPushed = true
    }

    private func popCursorIfIdle() {
        guard cursorPushed, !isHovered, !isDragging else { return }
        NSCursor.pop()
        cursorPushed = false
    }
}

struct SettingsDoneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OpsType.ui(OpsSize.xs, weight: .semibold))
            .foregroundStyle(OpsInk.bg)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(OpsTint.amber.color)
            .clipShape(.rect(cornerRadius: OpsRadius.standard))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Settings Page Container

struct SettingsPageContainer<Header: View, Content: View>: View {
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sticky header on the canvas, content scrolls beneath (matches Talkie settings).
            header
                .padding(.horizontal, 28)
                .padding(.top, 22)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(settingsCanvasBackground)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OpsSpacing.xxxl) {
                    content
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(settingsCanvasBackground)
    }
}

struct SettingsPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Eyebrow: uppercase tracked label, reserving dots for actionable state.
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(OpsType.mono(OpsSize.xxs, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(OpsTint.amber.color)

                if let badge {
                    Text(badge)
                        .font(OpsType.mono(OpsSize.micro, weight: .bold))
                        .foregroundStyle(OpsTint.amber.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(OpsSurface.tintFill(OpsTint.amber.color)))
                }
            }

            // Prominent page title mirrors the Agent Home scaffold.
            Text(title.capitalized)
                .font(OpsType.ui(OpsSize.xxl, weight: .semibold))
                .foregroundStyle(OpsInk.ink)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(OpsType.ui(OpsSize.sm))
                    .foregroundStyle(OpsInk.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 640, alignment: .leading)
            }

            OpsDivider(color: settingsHeaderDivider).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String?
    var depth: GlassDepth = .subtle
    @ViewBuilder let content: Content

    init(title: String? = nil, depth: GlassDepth = .subtle, @ViewBuilder content: () -> Content) {
        self.title = title
        self.depth = depth
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OpsSpacing.md) {
            if let title = title {
                OpsSectionLabel(title)
            }

            OpsCard(
                padding: OpsSpacing.xl,
                fill: settingsCardBackground,
                stroke: settingsCardBorder
            ) {
                VStack(alignment: .leading, spacing: OpsSpacing.md) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .shadow(color: settingsCardShadow, radius: 10, x: 0, y: 3)
        }
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let description: String?
    @Binding var isOn: Bool

    init(icon: String, title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.icon = icon
        self.title = title
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: OpsSpacing.md) {
            Image(systemName: icon)
                .font(OpsType.ui(OpsSize.sm))
                .foregroundStyle(isOn ? OpsTint.amber.color : OpsInk.dim)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OpsType.ui(OpsSize.xs, weight: .medium))
                    .foregroundStyle(OpsInk.ink)

                if let description, !description.isEmpty {
                    Text(description)
                        .font(OpsType.ui(OpsSize.micro))
                        .foregroundStyle(OpsInk.dim)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(OpsTint.amber.color)
                .labelsHidden()
                .scaleEffect(0.75)
        }
        .padding(.vertical, OpsSpacing.xs)
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
                    .font(OpsType.ui(OpsSize.xs, weight: .medium))
                    .foregroundStyle(OpsInk.ink)

                Text(model.description)
                    .font(OpsType.ui(OpsSize.micro))
                    .foregroundStyle(OpsInk.dim)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(OpsTint.amber.color)
            }
        }
        .padding(OpsSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: OpsRadius.standard)
                .fill(isSelected ? OpsSurface.selected(OpsTint.amber.color) : (isHovered ? OpsSurface.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}
// MARK: - Quick Settings View (Focused: Capture + Output + Permissions)

enum QuickSettingsTab: String, CaseIterable {
    case history
    case shortcuts
    case sounds
    case audio
    case feedback
    case output
    case permissions
    case connections
    case performance
    case featureFlags
    case about
    #if DEBUG
    case accessibility  // Developer-only: AX element scanner
    case debug
    #endif

    var title: String {
        switch self {
        case .history: return "History"
        case .shortcuts: return "Shortcuts"
        case .sounds: return "Sounds"
        case .audio: return "Audio"
        case .feedback: return "Feedback"
        case .output: return "Output"
        case .permissions: return "Permissions"
        case .connections: return "Connections"
        case .performance: return "Performance"
        case .featureFlags: return "Feature Flags"
        case .about: return "About"
        #if DEBUG
        case .accessibility: return "AX Scan"
        case .debug: return "Debug"
        #endif
        }
    }

    var icon: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .shortcuts: return "command"
        case .sounds: return "speaker.wave.2"
        case .audio: return "mic.fill"
        case .feedback: return "rectangle.inset.topright.filled"
        case .output: return "arrow.right.doc.on.clipboard"
        case .permissions: return "lock.shield.fill"
        case .connections: return "network"
        case .performance: return "gauge.with.needle"
        case .featureFlags: return "flag.fill"
        case .about: return "info.circle"
        #if DEBUG
        case .accessibility: return "accessibility"
        case .debug: return "ladybug"
        #endif
        }
    }
}

struct QuickSettingsView: View {
    var initialTab: QuickSettingsTab = .shortcuts
    @State private var selectedTab: QuickSettingsTab = .shortcuts
    @StateObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var settings = LiveSettings.shared
    @ObservedObject private var troubleshooterController = AudioTroubleshooterController.shared

    init(initialTab: QuickSettingsTab = .shortcuts) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                // History at the top - primary action
                Label(QuickSettingsTab.history.title, systemImage: QuickSettingsTab.history.icon)
                    .tag(QuickSettingsTab.history)

                Section("Input") {
                    ForEach([QuickSettingsTab.shortcuts, .audio], id: \.self) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .tag(tab)
                    }
                }

                Section("Output") {
                    ForEach([QuickSettingsTab.sounds, .feedback, .output], id: \.self) { tab in
                        Label(tab.title, systemImage: tab.icon)
                            .tag(tab)
                    }
                }

                Section("System") {
                    ForEach([QuickSettingsTab.permissions, .connections, .performance, .featureFlags, .about], id: \.self) { tab in
                        HStack {
                            Label(tab.title, systemImage: tab.icon)
                            if tab == .permissions && !permissionManager.allRequiredGranted {
                                Spacer()
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 10))
                            }
                        }
                        .tag(tab)
                    }
                }

                #if DEBUG
                Section("Developer") {
                    Label("AX Scan", systemImage: "accessibility")
                        .tag(QuickSettingsTab.accessibility)
                    Label("Debug", systemImage: "ladybug")
                        .tag(QuickSettingsTab.debug)
                }
                #endif
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            // History doesn't use ScrollView - it has its own
            if selectedTab == .history {
                HistorySection()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        switch selectedTab {
                        case .history:
                            EmptyView() // Handled above
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
                        case .performance:
                            PerformanceSettingsSection()
                        case .featureFlags:
                            FeatureFlagsSettingsSection()
                        case .about:
                            AboutSettingsSection()
                        #if DEBUG
                        case .accessibility:
                            AccessibilityInventorySection()
                        case .debug:
                            DebugSettingsSection()
                        #endif
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $troubleshooterController.isShowing) {
            AudioTroubleshooterView()
        }
    }
}

// MARK: - Sidebar Section Header

struct QuickSettingsSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: OpsSpacing.xs) {
            OpsSectionLabel(title)
                .padding(.leading, OpsSpacing.md)
                .padding(.bottom, 2)

            content
        }
    }
}

// MARK: - Sidebar Navigation Item

struct QuickSettingsSidebarItem: View {
    let tab: QuickSettingsTab
    let isSelected: Bool
    var showWarning: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)

                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))

                Spacer()

                if showWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
            }
            .foregroundStyle(isSelected ? OpsInk.ink : OpsInk.muted)
            .padding(.horizontal, OpsSpacing.md)
            .padding(.vertical, OpsSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: OpsRadius.standard)
                    .fill(isSelected ? OpsSurface.selected(OpsTint.amber.color) : OpsSurface.hover)
            )
            .opacity(isSelected || isHovered ? 1.0 : 0.0)
            .contentShape(RoundedRectangle(cornerRadius: OpsRadius.standard))
        }
        .buttonStyle(.plain)
        .animation(TalkieAnimation.fast, value: isSelected)
        .animation(TalkieAnimation.fast, value: isHovered)
        .onHover { isHovered = $0 }
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
            // Fixed geometry - icon with optional warning badge
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .medium))

                if showWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
            .foregroundStyle(isSelected ? OpsInk.ink : OpsInk.muted)
            .frame(height: 36)
            .padding(.horizontal, 14)
            .background(
                // Inner selection indicator
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: OpsRadius.standard)
                            .fill(OpsSurface.selected(OpsTint.amber.color))
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: OpsRadius.standard)
                            .fill(OpsSurface.hover)
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: OpsRadius.standard))
            // Label floats below - subtle, smaller treatment
            .overlay(alignment: .bottom) {
                Text(tab.title.uppercased())
                    .font(OpsType.mono(7, weight: .semibold))
                    .tracking(0.3)
                    .foregroundStyle(OpsInk.dim)
                    .opacity(isSelected || isHovered ? 1.0 : 0.0)
                    .offset(y: 16)
            }
        }
        .buttonStyle(.plain)
        .animation(TalkieAnimation.fast, value: isSelected)
        .animation(TalkieAnimation.fast, value: isHovered)
        .onHover { isHovered = $0 }
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
                        .foregroundColor(AgentTheme.accent)

                    Text("SHORTCUTS")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(AgentTheme.textPrimary)
                }

                Text("Global keyboard shortcuts")
                    .font(.system(size: 12))
                    .foregroundColor(AgentTheme.textSecondary)
            }

            // Toggle Recording
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Toggle Recording")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AgentTheme.textPrimary)
                        Text("Press to start/stop")
                            .font(.system(size: 10))
                            .foregroundColor(AgentTheme.textTertiary)
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
                                .foregroundColor(AgentTheme.textPrimary)
                            Text("Hold to record")
                                .font(.system(size: 10))
                                .foregroundColor(AgentTheme.textTertiary)
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
                                .foregroundColor(AgentTheme.textSecondary)

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
                            .foregroundColor(AgentTheme.textPrimary)
                        Text("Select queued transcription")
                            .font(.system(size: 10))
                            .foregroundColor(AgentTheme.textTertiary)
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

// MARK: - Glass Card Component (Liquid Glass)

struct GlassCard<Content: View>: View {
    var depth: GlassDepth = .subtle
    var isInteractive: Bool = false
    @ViewBuilder let content: () -> Content

    // Legacy initializer for compatibility
    init(intensity: GlassIntensity = .subtle, @ViewBuilder content: @escaping () -> Content) {
        // Map old intensity to new depth
        switch intensity {
        case .subtle: self.depth = .subtle
        case .medium: self.depth = .standard
        case .strong: self.depth = .prominent
        }
        self.isInteractive = false
        self.content = content
    }

    // New Liquid Glass initializer
    init(depth: GlassDepth = .subtle, isInteractive: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.depth = depth
        self.isInteractive = isInteractive
        self.content = content
    }

    var body: some View {
        OpsCard(padding: OpsSpacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
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
        .background(AgentTheme.background)
        .preferredColorScheme(.dark)
}
