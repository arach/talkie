//
//  SettingsColumns.swift
//  Talkie macOS
//
//  Split Settings into sidebar and content columns for 3-column NavigationSplitView
//

import SwiftUI
import TalkieKit

// MARK: - Settings Section Enum

enum SettingsSection: String, Hashable {
    // GENERAL (first things users see)
    case account             // User account & authentication
    case mode                // Product mode: visibility + information density
    case appearance
    case camera              // Camera bubble & clip capture settings
    case notch               // Legacy alias -> surface
    case surface             // Surface system — overlay, tray, shelf, shortcuts
    case home                // Legacy alias → appearance
    case extensions          // JavaScript extensions (Apps)

    // DICTATION (primary workflow)
    case voiceIO             // UX: Capture + Output
    case shortcutKeyboard    // Mac-authored companion shortcut board

    // SELECTION (reader — highlight text → process → TTS)
    case selection           // Quick Selection settings

    // AI (how it's processed)
    case aiProviders         // API Keys & Providers
    case models              // Consolidated: STT + TTS + LLM

    // DATA (where it lives)
    case storage             // Consolidated: Database + Files + Inventory
    case sync                // iOS + iCloud

    // CONTEXT (app profiles + processing + dictionary + actions)
    case context             // Unified context settings
    case dictionary          // Legacy → context
    case rules               // Legacy → context
    case actions             // Legacy → context
    case contextRules        // Legacy → context

    // AUTOMATION (event-triggered workflows)
    case automations

    // SYSTEM (meta/admin - technical settings)
    case helpers             // Background services + Server + Performance
    case featureFlags        // Runtime rollout state
    case about               // App info, version, permissions
    case feedback            // User feedback submission
    case devControl          // Dev control panel (DEBUG only)

    // Legacy - redirect to consolidated views
    case quickOpen           // → context
    case permissions         // → about
    case debug               // → about
    case performance         // → helpers
    case server              // → helpers

    // Legacy - kept for URL compatibility, redirect to consolidated views
    case dictationCapture    // → voiceIO
    case dictationOutput     // → voiceIO
    case transcriptionModels // → models
    case ttsVoices           // → models
    case llmModels           // → models
    case database            // → storage
    case files               // → storage
    case iOS                 // → sync
    case quickActions        // → context
    case connections         // → debug
    case debugInfo           // → debug
    case onboarding          // → debug
    case apps                // → extensions
    case audio               // For TalkieAgent HistoryView compatibility
    case engine              // For TalkieAgent HistoryView compatibility

    /// Convert URL path segment to section (e.g., "permissions" → .permissions)
    static func from(path: String) -> SettingsSection? {
        switch path {
        // DICTATION
        case "voice-io", "voiceio": return .voiceIO
        case "dictation-capture", "capture": return .voiceIO
        case "dictation-output", "output": return .voiceIO
        case "shortcut-keyboard", "shortcut-board", "companion-shortcuts", "shortcut-mode": return .shortcutKeyboard

        // SELECTION
        case "selection", "reader", "quick-selection": return .selection

        // CONTEXT
        case "context": return .context
        case "dictionary", "vocabulary": return .context
        case "rules", "transforms", "symbolic-mapping": return .context
        case "actions", "quick-actions", "context-actions", "quick-open": return .context
        case "context-rules": return .context

        // AI
        case "transcription", "transcription-models": return .models
        case "ai-providers", "providers", "api": return .aiProviders
        case "models": return .models
        case "tts", "tts-voices", "voices": return .models
        case "llm", "llm-models": return .models

        // DATA
        case "storage": return .storage
        case "database", "db": return .storage
        case "files": return .storage
        case "sync": return .sync
        case "ios", "iphone", "icloud": return .sync

        // AUTOMATION
        case "automations", "auto-run", "autorun": return .automations
        case "extensions", "apps": return .extensions

        // SYSTEM
        case "account": return .account
        case "mode", "settings-mode", "visibility": return .mode
        case "appearance": return .appearance
        case "home", "dashboard", "widgets": return .home
        case "feedback": return .feedback
        case "helpers", "server", "performance", "trace", "profiling": return .helpers
        case "feature-flags", "flags", "rollout": return .featureFlags
        case "about", "permissions", "debug", "debug-info", "version": return .about
        case "connections": return .about
        case "onboarding", "progress": return .about
        case "dev", "dev-control": return .devControl
        case "camera", "video", "bubble": return .camera
        case "surface", "overlay": return .surface
        case "notch", "dynamic-island", "overlay-notch": return .surface

        default: return nil
        }
    }

    /// URL path segment for this section
    var pathSegment: String {
        switch self {
        // Primary sections
        case .account: return "account"
        case .mode: return "mode"
        case .voiceIO: return "voice-io"
        case .shortcutKeyboard: return "shortcut-keyboard"
        case .selection: return "selection"
        case .context: return "context"
        case .dictionary: return "context"
        case .rules: return "context"
        case .actions: return "context"
        case .contextRules: return "context"
        case .aiProviders: return "ai-providers"
        case .models: return "models"
        case .storage: return "storage"
        case .sync: return "sync"
        case .automations: return "automations"
        case .extensions: return "extensions"
        case .appearance: return "appearance"
        case .camera: return "camera"
        case .surface: return "surface"
        case .notch: return "surface"
        case .home: return "appearance"
        case .feedback: return "feedback"
        case .helpers: return "helpers"
        case .featureFlags: return "feature-flags"
        case .about: return "about"
        case .devControl: return "dev-control"
        // Legacy redirects
        case .quickOpen: return "context"
        case .permissions: return "about"
        case .debug: return "about"
        case .performance: return "helpers"
        case .server: return "helpers"

        // Legacy redirects
        case .dictationCapture: return "voice-io"
        case .dictationOutput: return "voice-io"
        case .transcriptionModels: return "models"
        case .ttsVoices: return "models"
        case .llmModels: return "models"
        case .database: return "storage"
        case .files: return "storage"
        case .iOS: return "sync"
        case .quickActions: return "context"
        case .connections: return "debug"
        case .debugInfo: return "debug"
        case .onboarding: return "debug"
        case .apps: return "extensions"
        case .audio: return "audio"
        case .engine: return "engine"
        }
    }

    /// Canonical section used for UI routing/visibility.
    var canonicalSection: SettingsSection {
        switch self {
        case .quickOpen, .quickActions, .actions:
            return .context
        case .dictionary, .rules, .contextRules:
            return .context
        case .home:
            return .appearance
        case .permissions, .debug, .debugInfo, .connections, .onboarding:
            return .about
        case .performance, .server:
            return .helpers
        case .dictationCapture, .dictationOutput:
            return .voiceIO
        case .transcriptionModels, .ttsVoices, .llmModels:
            return .models
        case .database, .files:
            return .storage
        case .iOS:
            return .sync
        case .apps:
            return .extensions
        case .notch:
            return .surface
        default:
            return self
        }
    }

    /// Target audience detail level required to show this section in Settings.
    var targetAudienceDetails: SettingsAudience {
        switch canonicalSection {
        case .extensions, .devControl, .audio, .engine:
            return .pro
        default:
            return .simple
        }
    }

    func isVisible(for audience: SettingsAudience) -> Bool {
        audience.canAccess(targetAudienceDetails)
    }
}

// MARK: - Sidebar Helper Components

struct SettingsSidebarSection<Content: View>: View {
    let title: String
    var isActive: Bool = false
    var iconsOnly: Bool = false
    @ViewBuilder let content: Content

    private var isScope: Bool { SettingsManager.shared.isScopeTheme }

    var body: some View {
        VStack(alignment: iconsOnly ? .center : .leading, spacing: isScope ? 4 : 2) {
            if !iconsOnly {
                if isScope {
                    HStack(spacing: 6) {
                        PhosphorDot(
                            color: isActive ? ScopeAmber.solid : ScopeAmber.solid.opacity(0.55),
                            size: 4
                        )
                        Text(title.uppercased())
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.wide)
                            .foregroundStyle(isActive ? ScopeAmber.solid : ScopeInk.subtle)
                            .phosphorGlow(
                                color: ScopeAmber.solid,
                                radius: 3,
                                opacity: isActive ? 0.32 : 0.12
                            )
                    }
                    .padding(.leading, 6)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    Text(title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isActive ? Theme.current.foregroundSecondary : Theme.current.foregroundSecondary.opacity(0.6))
                        .padding(.leading, 6)
                        .padding(.bottom, 2)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }

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
    var iconsOnly: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var rowFrame: CGRect = .zero

    // Accent color matching native sidebar navigation
    private var accentColor: Color {
        SettingsManager.shared.accentColor.color ?? Color.accentColor
    }

    private var isScope: Bool { SettingsManager.shared.isScopeTheme }

    // Scope-mode foreground colors
    private var scopeIconColor: Color {
        isSelected ? ScopeInk.primary : ScopeInk.faint
    }
    private var scopeTextColor: Color {
        isSelected ? ScopeInk.primary : ScopeInk.dim
    }

    var body: some View {
        HStack(spacing: 0) {
            if !iconsOnly {
                if isScope {
                    // Amber inset stripe (left edge) — armed channel
                    Rectangle()
                        .fill(isSelected ? ScopeAmber.solid : Color.clear)
                        .frame(width: 2)
                        .padding(.vertical, 1)
                        .animation(.easeOut(duration: 0.15), value: isSelected)
                } else {
                    // Left accent bar (expanded mode)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isSelected ? accentColor : Color.clear)
                        .frame(width: 3)
                        .padding(.vertical, 2)
                        .animation(.easeOut(duration: 0.15), value: isSelected)
                }
            }

            HStack(spacing: iconsOnly ? 0 : 8) {
                Image(systemName: icon)
                    .font(.system(size: iconsOnly ? 10 : 11))
                    .foregroundColor(isScope ? scopeIconColor : (isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary))
                    .frame(width: iconsOnly ? 18 : 20, height: iconsOnly ? 18 : nil, alignment: .center)

                if !iconsOnly {
                    if isScope {
                        Text(title.uppercased())
                            .font(ScopeType.channel)
                            .tracking(ScopeType.Tracking.normal)
                            .foregroundStyle(scopeTextColor)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        Text(title.uppercased())
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary.opacity(0.85))
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    Spacer(minLength: 0)

                    if isScope && isSelected {
                        // Phosphor dot pin — armed/active indicator
                        PhosphorDot(color: ScopeAmber.solid, size: 4)
                            .padding(.trailing, 2)
                    }
                }
            }
            .padding(.leading, iconsOnly ? 0 : 4)
            .padding(.trailing, iconsOnly ? 0 : 8)
        }
        .padding(.vertical, iconsOnly ? 4 : 5)
        .frame(maxWidth: .infinity, alignment: iconsOnly ? .center : .leading)
        .background(
            Group {
                if isScope {
                    Rectangle()
                        .fill(
                            isSelected
                                ? ScopeAmber.tintSubtle
                                : (isHovered ? ScopeCanvas.canvasOverlay : Color.clear)
                        )
                } else {
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .fill(isSelected ? Theme.current.backgroundTertiary : (isHovered ? Theme.current.backgroundTertiary.opacity(0.5) : Color.clear))
                }
            }
        )
        .overlay(
            Group {
                if isScope {
                    // Scope: hairline only on hover; selection is carried by the inset stripe + tint
                    Rectangle()
                        .strokeBorder(
                            ScopeEdge.faint.opacity(isHovered && !isSelected ? 1.0 : 0),
                            lineWidth: 0.5
                        )
                } else {
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(
                            isSelected ? accentColor.opacity(0.24) : Theme.current.divider.opacity(isHovered ? 0.45 : 0),
                            lineWidth: 1
                        )
                }
            }
        )
        // Bottom accent bar (compact mode only)
        .overlay(alignment: .bottom) {
            if iconsOnly {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isSelected ? (isScope ? ScopeAmber.solid : accentColor) : Color.clear)
                    .frame(width: 16, height: 2)
                    .padding(.bottom, 1)
                    .animation(.easeOut(duration: 0.15), value: isSelected)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { rowFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, newFrame in
                        rowFrame = newFrame
                    }
            }
        }
        .onContinuousHover { phase in
            guard iconsOnly else { return }
            let tooltip = SidebarTooltipState.shared
            switch phase {
            case .active:
                let anchor = CGPoint(x: rowFrame.maxX, y: rowFrame.midY)
                if tooltip.label == title {
                    tooltip.updateAnchor(anchor)
                } else {
                    tooltip.show(label: title, anchor: anchor)
                }
            case .ended:
                tooltip.dismiss(matching: title)
            }
        }
    }
}

// MARK: - Settings Sidebar Column (for middle column in 3-column mode)

struct SettingsSidebarColumn: View {
    @Binding var selectedSection: SettingsSection
    @Environment(SettingsManager.self) private var settingsManager
    @State private var edgeHandleHovered = false

    /// Compact mode — driven directly by the persisted preference
    private var compact: Bool { settingsManager.settingsSidebarIconsOnly }

    private var settingsAudience: SettingsAudience {
        settingsManager.settingsAudience
    }

    private var activeSection: SettingsSection {
        selectedSection.canonicalSection
    }

    @ViewBuilder
    private func sidebarItem(_ section: SettingsSection, icon: String, title: String) -> some View {
        if section.isVisible(for: settingsAudience) {
            SettingsSidebarItem(
                icon: icon,
                title: title,
                isSelected: activeSection == section,
                iconsOnly: compact
            ) {
                selectedSection = section
            }
        }
    }

    private var accentColor: Color {
        SettingsManager.shared.accentColor.color ?? Color.accentColor
    }

    private var isScope: Bool { settingsManager.isScopeTheme }

    @ViewBuilder
    private var headerLabel: some View {
        if isScope {
            HStack(spacing: 0) {
                // Phosphor dot doubles as the "armed" mark for the sidebar
                PhosphorDot(color: ScopeAmber.solid, size: 5)
                    .frame(width: 24, alignment: .center)
                    .padding(.leading, 4)
                    .padding(.trailing, compact ? 0 : 6)

                if !compact {
                    Text("· SETTINGS")
                        .font(ScopeType.eyebrow)
                        .tracking(ScopeType.Tracking.wide)
                        .foregroundStyle(ScopeAmber.solid)
                        .phosphorGlow(radius: 3, opacity: 0.28)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    Spacer(minLength: 0)

                    Image(systemName: "sidebar.left")
                        .font(.system(size: 10))
                        .foregroundStyle(ScopeInk.faint)
                        .padding(.trailing, 4)
                        .transition(.opacity)
                }
            }
        } else {
            HStack(spacing: 0) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 24, alignment: .center)
                    .padding(.leading, 4)
                    .padding(.trailing, compact ? 0 : 6)

                if !compact {
                    Text("Settings")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)
                        .transition(.move(edge: .leading).combined(with: .opacity))

                    Spacer(minLength: 0)

                    Image(systemName: "sidebar.left")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(0.5))
                        .padding(.trailing, 4)
                        .transition(.opacity)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Settings Header — click to toggle compact/expanded
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    settingsManager.settingsSidebarIconsOnly.toggle()
                }
            } label: {
                headerLabel
                    .frame(height: SettingsHeaderLayout.primaryLineHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, SettingsHeaderLayout.topPadding)
                    .padding(.bottom, SettingsHeaderLayout.bottomPadding)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(compact ? "Expand settings menu" : "Collapse settings menu")

            // Menu Sections (secondary content starts here)
            // Order: GENERAL → DICTATION → AI → DATA → WORKFLOWS → SYSTEM
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: compact ? Spacing.xs : Spacing.lg) {
                    // Top spacing before first section (breathing room from header)
                    Spacer().frame(height: Spacing.xs)

                    // General items (no section header — self-explanatory)
                    VStack(spacing: 2) {
                        sidebarItem(.about, icon: "info.circle", title: "About")
                        sidebarItem(.account, icon: "person.circle", title: "Account")
                        sidebarItem(.mode, icon: "slider.horizontal.3", title: "Mode")
                        sidebarItem(.appearance, icon: "paintbrush", title: "Appearance")
                        sidebarItem(.surface, icon: "rectangle.topthird.inset.filled", title: "Notch")
                    }

                    // INPUT (capture, voice & selection)
                    SettingsSidebarSection(title: "INPUT", isActive: activeSection == .camera || activeSection == .voiceIO || activeSection == .shortcutKeyboard || activeSection == .selection, iconsOnly: compact) {
                        sidebarItem(.camera, icon: "camera.viewfinder", title: "Capture")
                        sidebarItem(.voiceIO, icon: "mic.and.signal.meter", title: "Dictation")
                        sidebarItem(.shortcutKeyboard, icon: "square.grid.2x2", title: "Command Deck")
                        sidebarItem(.selection, icon: "text.cursor", title: "Selection")
                    }

                    // PROCESSING (context, AI, data)
                    // Automations moved out of Settings — they're per-workflow
                    // triggers and live on the Workflows surface.
                    SettingsSidebarSection(title: "PROCESSING", isActive: activeSection == .context || activeSection == .aiProviders || activeSection == .models || activeSection == .storage || activeSection == .sync, iconsOnly: compact) {
                        sidebarItem(.context, icon: "square.stack.3d.forward.dottedline", title: "Context")
                        sidebarItem(.aiProviders, icon: "key", title: "Providers")
                        sidebarItem(.models, icon: "cpu", title: "Models")
                        sidebarItem(.storage, icon: "internaldrive", title: "Storage")
                        sidebarItem(.sync, icon: "iphone.gen3.radiowaves.left.and.right", title: "Devices")
                    }

                    // SYSTEM (meta/admin - technical settings).
                    // Apps is now a tab inside Helpers; no standalone entry.
                    SettingsSidebarSection(title: "SYSTEM", isActive: activeSection == .helpers || activeSection == .featureFlags || activeSection == .feedback || activeSection == .devControl, iconsOnly: compact) {
                        sidebarItem(.helpers, icon: "app.connected.to.app.below.fill", title: "Helpers")
                        sidebarItem(.featureFlags, icon: "flag.fill", title: "Feature Flags")
                        sidebarItem(.feedback, icon: "bubble.left.and.text.bubble.right", title: "Feedback")
                        #if DEBUG
                        sidebarItem(.devControl, icon: "hammer.fill", title: "Dev Control")
                        #endif
                    }
                }
                .padding(.horizontal, compact ? Spacing.xs : Spacing.sm)
                .padding(.bottom, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isScope ? ScopeCanvas.canvasAlt : Theme.current.background)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(isScope ? ScopeEdge.faint : Theme.current.border.opacity(0.7))
                .frame(width: isScope ? 1 : 0.5)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isScope ? ScopeEdge.subtle : Theme.current.border.opacity(0.45))
                .frame(width: 0.5)
        }
        .overlay(alignment: .trailing) {
            // Edge handle — subtle pill on the right edge to toggle collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    settingsManager.settingsSidebarIconsOnly.toggle()
                }
            } label: {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        isScope
                            ? ScopeInk.faint.opacity(edgeHandleHovered ? 0.45 : 0.15)
                            : Theme.current.foreground.opacity(edgeHandleHovered ? 0.2 : 0.06)
                    )
                    .frame(width: 4, height: 28)
                    .contentShape(Rectangle().inset(by: -6))
            }
            .buttonStyle(.plain)
            .help(compact ? "Expand settings menu" : "Collapse settings menu")
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    edgeHandleHovered = hovering
                }
            }
            .offset(x: 2)
        }
        .animation(.easeInOut(duration: 0.2), value: compact)
    }
}

// MARK: - Settings Content Column (for detail column in 3-column mode)

struct SettingsContentColumn: View {
    @Binding var selectedSection: SettingsSection
    @Environment(SettingsManager.self) private var settingsManager
    @State private var dismissedDirectLinkNotices: Set<SettingsSection> = []

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.current.background)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Theme.current.border.opacity(0.18))
                    .frame(width: 1)
            }
    }

    private var section: SettingsSection {
        selectedSection.canonicalSection
    }

    private var sectionName: String {
        section.pathSegment.replacing("-", with: " ").uppercased()
    }

    private var shouldShowDirectLinkNotice: Bool {
        !section.isVisible(for: settingsManager.settingsAudience)
            && !dismissedDirectLinkNotices.contains(section)
    }

    @ViewBuilder
    private var contentView: some View {
        switch section {
        // GENERAL
        case .camera:
            sectionWithAudienceNotice { CameraSettingsView() }
        case .surface, .notch:
            sectionWithAudienceNotice { SurfaceSettingsView() }

        // DICTATION
        case .voiceIO:
            sectionWithAudienceNotice { VoiceIOSettingsView() }
        case .shortcutKeyboard:
            sectionWithAudienceNotice { CompanionShortcutKeyboardSettingsView() }

        // SELECTION
        case .selection:
            sectionWithAudienceNotice { SelectionSettingsView() }

        // CONTEXT
        case .context:
            sectionWithAudienceNotice { ContextSettingsView() }

        // AI
        case .aiProviders:
            sectionWithAudienceNotice { APISettingsView() }
        case .models:
            sectionWithAudienceNotice { ModelsSettingsView() }

        // DATA
        case .storage:
            sectionWithAudienceNotice { StorageSettingsView() }
        case .sync:
            sectionWithAudienceNotice { iOSSettingsView() }

        // AUTOMATION
        case .automations:
            sectionWithAudienceNotice { AutomationsSettingsView() }
        case .extensions:
            sectionWithAudienceNotice { AppsSettingsView() }

        // SYSTEM
        case .account:
            sectionWithAudienceNotice { AccountSettingsView() }
        case .mode:
            sectionWithAudienceNotice { ModeSettingsView() }
        case .appearance:
            sectionWithAudienceNotice { AppearanceSettingsView() }
        case .feedback:
            sectionWithAudienceNotice { FeedbackSettingsView() }
        case .helpers:
            sectionWithAudienceNotice { HelperAppsSettingsView() }
        case .featureFlags:
            sectionWithAudienceNotice { FeatureFlagsSettingsView() }
        case .about:
            sectionWithAudienceNotice { AboutSettingsView() }
        case .devControl:
            #if DEBUG
            sectionWithAudienceNotice { DevControlPanelView() }
            #else
            Text("Dev Control is only available in DEBUG builds")
            #endif

        // Legacy/compatibility
        case .audio:
            sectionWithAudienceNotice { Text("Audio settings placeholder") }
        case .engine:
            sectionWithAudienceNotice { Text("Engine settings placeholder") }

        // Legacy aliases never reached after canonical mapping
        case .home, .quickOpen, .permissions, .debug, .performance, .server,
                .dictationCapture, .dictationOutput, .transcriptionModels,
                .ttsVoices, .llmModels, .database, .files, .iOS,
                .quickActions, .connections, .debugInfo, .onboarding, .apps,
                .dictionary, .rules, .actions, .contextRules:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sectionWithAudienceNotice<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if section.isVisible(for: settingsManager.settingsAudience) {
            content()
        } else {
            content()
                .overlay(alignment: .topTrailing) {
                    if shouldShowDirectLinkNotice {
                        SettingsAudienceDirectLinkNoticeView(
                            sectionName: sectionName,
                            requiredAudience: section.targetAudienceDetails,
                            onDismiss: {
                                dismissedDirectLinkNotices.insert(section)
                            }
                        ) {
                            selectedSection = .mode
                        }
                        .padding(.top, Spacing.sm)
                        .padding(.trailing, Spacing.md)
                        .frame(maxWidth: 520)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(2)
                    }
                }
        }
    }
}

private struct SettingsAudienceDirectLinkNoticeView: View {
    let sectionName: String
    let requiredAudience: SettingsAudience
    let onDismiss: () -> Void
    let onOpenMode: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "info.circle")
                .font(Theme.current.fontSM)
                .foregroundColor(Theme.current.foregroundSecondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Direct link opened \(sectionName)")
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(Theme.current.foreground)

                Text("This section is usually shown in \(requiredAudience.displayName) Mode. To find it again from the Settings menu, open Mode and switch it there. You can still use direct links any time.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: Spacing.sm)

            Button("Open Mode") {
                onOpenMode()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.current.foregroundSecondary)
            .padding(.top, 2)
        }
        .padding(Spacing.sm)
        .background(Theme.current.backgroundTertiary.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.divider, lineWidth: 1)
        )
        .cornerRadius(CornerRadius.sm)
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}
