//
//  SettingsView.swift
//  Talkie macOS
//
//  Settings and workflow management UI (inspired by EchoFlow)
//

import SwiftUI
import CloudKit

enum SettingsSection: String, Hashable {
    // APPEARANCE
    case appearance

    // MEMOS (Quick Actions, Quick Open, Automations)
    case quickActions
    case quickOpen
    case automations

    // DICTATION
    case dictationCapture
    case dictationOutput

    // AI MODELS
    case aiProviders         // API Keys & Providers
    case transcriptionModels // Transcription (STT) model selection
    case llmModels           // AI/LLM model selection

    // STORAGE
    case database            // Retention, cleanup
    case files               // Local paths, exports
    case cloud               // Sync (future)

    // SYSTEM
    case helpers             // Background services (TalkieLive, TalkieEngine)
    case permissions
    case debugInfo
    case devControl          // Dev control panel (DEBUG only)

    // Legacy/compatibility
    case audio               // For TalkieLive HistoryView compatibility
    case engine              // For TalkieLive HistoryView compatibility

    /// Convert URL path segment to section (e.g., "permissions" → .permissions)
    static func from(path: String) -> SettingsSection? {
        switch path {
        case "appearance": return .appearance
        case "dictation-capture", "capture": return .dictationCapture
        case "dictation-output", "output": return .dictationOutput
        case "quick-actions", "actions": return .quickActions
        case "quick-open": return .quickOpen
        case "automations", "auto-run", "autorun": return .automations
        case "ai-providers", "providers", "api": return .aiProviders
        case "transcription", "transcription-models": return .transcriptionModels
        case "llm", "llm-models": return .llmModels
        case "database", "db": return .database
        case "files": return .files
        case "cloud", "sync": return .cloud
        case "helpers": return .helpers
        case "permissions": return .permissions
        case "debug", "debug-info": return .debugInfo
        case "dev", "dev-control": return .devControl
        default: return nil
        }
    }

    /// URL path segment for this section
    var pathSegment: String {
        switch self {
        case .appearance: return "appearance"
        case .dictationCapture: return "dictation-capture"
        case .dictationOutput: return "dictation-output"
        case .quickActions: return "quick-actions"
        case .quickOpen: return "quick-open"
        case .automations: return "automations"
        case .aiProviders: return "ai-providers"
        case .transcriptionModels: return "transcription"
        case .llmModels: return "llm"
        case .database: return "database"
        case .files: return "files"
        case .cloud: return "cloud"
        case .helpers: return "helpers"
        case .permissions: return "permissions"
        case .debugInfo: return "debug"
        case .devControl: return "dev"
        case .audio: return "audio"
        case .engine: return "engine"
        }
    }
}

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State private var apiKeyInput: String = ""
    @State private var showingSaveConfirmation = false
    @State private var selectedSection: SettingsSection

    // Settings sidebar width - user-adjustable with smart defaults
    @AppStorage("settings.sidebarWidth") private var sidebarWidth: Double = 220
    private let sidebarMinWidth: Double = 180
    private let sidebarMaxWidth: Double = 320

    /// Initialize with optional starting section (defaults to .appearance)
    init(initialSection: SettingsSection = .appearance) {
        _selectedSection = State(initialValue: initialSection)
    }

    // Theme-aware colors for light/dark mode
    private var sidebarBackground: Color { Theme.current.backgroundSecondary }
    private var contentBackground: Color { Theme.current.background }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                // Settings Header - with breathing room at top
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundColor(Theme.current.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.sm)

                // Menu Sections
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.md) {
                        // APPEARANCE
                        SettingsSidebarSection(title: "APPEARANCE", isActive: selectedSection == .appearance) {
                            SettingsSidebarItem(
                                icon: "moon.stars",
                                title: "THEME & COLORS",
                                isSelected: selectedSection == .appearance
                            ) {
                                selectedSection = .appearance
                            }
                        }

                        // MEMOS
                        SettingsSidebarSection(title: "MEMOS", isActive: selectedSection == .quickActions || selectedSection == .quickOpen || selectedSection == .automations) {
                            SettingsSidebarItem(
                                icon: "bolt",
                                title: "QUICK ACTIONS",
                                isSelected: selectedSection == .quickActions
                            ) {
                                selectedSection = .quickActions
                            }
                            SettingsSidebarItem(
                                icon: "arrow.up.forward.app",
                                title: "QUICK OPEN",
                                isSelected: selectedSection == .quickOpen
                            ) {
                                selectedSection = .quickOpen
                            }
                            SettingsSidebarItem(
                                icon: "play.circle",
                                title: "AUTOMATIONS",
                                isSelected: selectedSection == .automations
                            ) {
                                selectedSection = .automations
                            }
                        }

                        // DICTATION
                        SettingsSidebarSection(title: "DICTATION", isActive: selectedSection == .dictationCapture || selectedSection == .dictationOutput) {
                            SettingsSidebarItem(
                                icon: "mic.fill",
                                title: "CAPTURE",
                                isSelected: selectedSection == .dictationCapture
                            ) {
                                selectedSection = .dictationCapture
                            }
                            SettingsSidebarItem(
                                icon: "arrow.right.doc.on.clipboard",
                                title: "OUTPUT",
                                isSelected: selectedSection == .dictationOutput
                            ) {
                                selectedSection = .dictationOutput
                            }
                        }

                        // AI MODELS
                        SettingsSidebarSection(title: "AI MODELS", isActive: selectedSection == .aiProviders || selectedSection == .transcriptionModels || selectedSection == .llmModels) {
                            SettingsSidebarItem(
                                icon: "key",
                                title: "PROVIDERS & KEYS",
                                isSelected: selectedSection == .aiProviders
                            ) {
                                selectedSection = .aiProviders
                            }
                            SettingsSidebarItem(
                                icon: "waveform",
                                title: "TRANSCRIPTION",
                                isSelected: selectedSection == .transcriptionModels
                            ) {
                                selectedSection = .transcriptionModels
                            }
                            SettingsSidebarItem(
                                icon: "brain",
                                title: "LLM",
                                isSelected: selectedSection == .llmModels
                            ) {
                                selectedSection = .llmModels
                            }
                        }

                        // STORAGE
                        SettingsSidebarSection(title: "STORAGE", isActive: selectedSection == .database || selectedSection == .files || selectedSection == .cloud) {
                            SettingsSidebarItem(
                                icon: "cylinder",
                                title: "DATABASE",
                                isSelected: selectedSection == .database
                            ) {
                                selectedSection = .database
                            }
                            SettingsSidebarItem(
                                icon: "folder",
                                title: "FILES",
                                isSelected: selectedSection == .files
                            ) {
                                selectedSection = .files
                            }
                            SettingsSidebarItem(
                                icon: "cloud",
                                title: "CLOUD",
                                isSelected: selectedSection == .cloud
                            ) {
                                selectedSection = .cloud
                            }
                        }

                        // SYSTEM
                        SettingsSidebarSection(title: "SYSTEM", isActive: selectedSection == .helpers || selectedSection == .permissions || selectedSection == .debugInfo || selectedSection == .devControl) {
                            SettingsSidebarItem(
                                icon: "app.connected.to.app.below.fill",
                                title: "HELPERS",
                                isSelected: selectedSection == .helpers
                            ) {
                                selectedSection = .helpers
                            }
                            SettingsSidebarItem(
                                icon: "lock.shield",
                                title: "PERMISSIONS",
                                isSelected: selectedSection == .permissions
                            ) {
                                selectedSection = .permissions
                            }
                            SettingsSidebarItem(
                                icon: "ladybug",
                                title: "DEBUG INFO",
                                isSelected: selectedSection == .debugInfo
                            ) {
                                selectedSection = .debugInfo
                            }

                            #if DEBUG
                            SettingsSidebarItem(
                                icon: "hammer.fill",
                                title: "DEV CONTROL",
                                isSelected: selectedSection == .devControl
                            ) {
                                selectedSection = .devControl
                            }
                            #endif
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
                }
            }
            .frame(width: sidebarWidth)
            .background(sidebarBackground)

            // Resizable divider
            SettingsSidebarResizer(
                width: $sidebarWidth,
                minWidth: sidebarMinWidth,
                maxWidth: sidebarMaxWidth
            )

            // MARK: - Content Area
            VStack(spacing: 0) {
                // Content based on selection
                contentView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugNavigate)) { notification in
            // Handle talkie://d/settings/{section} navigation
            guard let path = notification.userInfo?["path"] as? String else { return }
            let components = path.split(separator: "/")

            // Check if this is a settings path: settings/permissions, settings/appearance, etc.
            guard components.first == "settings", components.count >= 2 else { return }

            let sectionName = String(components[1])
            if let section = SettingsSection.from(path: sectionName) {
                selectedSection = section
                NSLog("[SettingsView] Debug navigated to: \(section)")
            }
        }
        #endif
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedSection {
        // APPEARANCE
        case .appearance:
            AppearanceSettingsView()

        // DICTATION
        case .dictationCapture:
            DictationCaptureSettingsView()
        case .dictationOutput:
            DictationOutputSettingsView()

        // ACTIONS
        case .quickActions:
            QuickActionsSettingsView()
        case .quickOpen:
            QuickOpenSettingsView()
        case .automations:
            AutomationsSettingsView()

        // AI MODELS
        case .aiProviders:
            APISettingsView()
        case .transcriptionModels:
            TranscriptionModelsSettingsView()
        case .llmModels:
            ModelLibraryView()

        // STORAGE
        case .database:
            DatabaseSettingsView()
        case .files:
            LocalFilesSettingsView()
        case .cloud:
            CloudSettingsView()

        // SYSTEM
        case .helpers:
            HelperAppsSettingsView()
        case .permissions:
            PermissionsSettingsView()
        case .debugInfo:
            DebugInfoView()
        case .devControl:
            #if DEBUG
            DevControlPanelView()
            #else
            Text("Dev Control Panel is only available in DEBUG builds")
            #endif

        // Legacy/compatibility
        case .audio:
            Text("Audio settings placeholder")
        case .engine:
            Text("Engine settings placeholder")
        }
    }
}

// MARK: - Settings Sidebar Components

struct SettingsSidebarSection<Content: View>: View {
    let title: String
    var isActive: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isActive ? Theme.current.foregroundSecondary : Theme.current.foregroundMuted)
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
                .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundMuted)
                .frame(width: 14)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Theme.current.backgroundTertiary : (isHovered ? Theme.current.backgroundTertiary.opacity(0.5) : Color.clear))
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

// MARK: - Settings Sidebar Resizer Component

/// Native-style resizer divider (mimics NSSplitView behavior)
private struct SettingsSidebarResizer: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        // Native macOS split view style: 1px divider with expanded hit area
        ZStack {
            // Background to prevent window color bleeding through
            Rectangle()
                .fill(Theme.current.background)
                .frame(width: 8)

            // Visible 1px divider line - use theme color for consistency
            Rectangle()
                .fill(TalkieTheme.divider)
                .frame(width: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else if !isDragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    let newWidth = width + value.translation.width
                    width = min(maxWidth, max(minWidth, newWidth))
                }
                .onEnded { _ in
                    isDragging = false
                    if !isHovering {
                        NSCursor.pop()
                    }
                }
        )
    }
}
