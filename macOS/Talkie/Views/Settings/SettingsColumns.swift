//
//  SettingsColumns.swift
//  Talkie macOS
//
//  Split Settings into sidebar and content columns for 3-column NavigationSplitView
//

import SwiftUI

// MARK: - Settings Section Enum

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
    case dictionary

    // AI MODELS
    case aiProviders         // API Keys & Providers
    case transcriptionModels // Transcription (STT) model selection
    case ttsVoices           // Text-to-Speech voice selection
    case llmModels           // AI/LLM model selection

    // STORAGE
    case database            // Retention, cleanup
    case files               // Local paths, exports

    // iOS (user-facing connectivity)
    case iOS                 // Unified iOS settings (iCloud + Bridge + devices)

    // SYSTEM
    case connections         // Connection Center (unified view)
    case helpers             // Background services (TalkieLive, TalkieEngine)
    case server              // TalkieServer (power user / debugging)
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
        case "dictionary": return .dictionary
        case "quick-actions", "actions": return .quickActions
        case "quick-open": return .quickOpen
        case "automations", "auto-run", "autorun": return .automations
        case "ai-providers", "providers", "api": return .aiProviders
        case "transcription", "transcription-models": return .transcriptionModels
        case "tts", "tts-voices", "voices": return .ttsVoices
        case "llm", "llm-models": return .llmModels
        case "database", "db": return .database
        case "files": return .files
        case "ios", "iphone", "icloud": return .iOS
        case "connections": return .connections
        case "server": return .server
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
        case .dictionary: return "dictionary"
        case .quickActions: return "quick-actions"
        case .quickOpen: return "quick-open"
        case .automations: return "automations"
        case .aiProviders: return "ai-providers"
        case .transcriptionModels: return "transcription"
        case .ttsVoices: return "tts"
        case .llmModels: return "llm"
        case .database: return "database"
        case .files: return "files"
        case .iOS: return "ios"
        case .connections: return "connections"
        case .server: return "server"
        case .helpers: return "helpers"
        case .permissions: return "permissions"
        case .debugInfo: return "debug"
        case .devControl: return "dev"
        case .audio: return "audio"
        case .engine: return "engine"
        }
    }
}

// MARK: - Sidebar Helper Components

struct SettingsSidebarSection<Content: View>: View {
    let title: String
    var isActive: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isActive ? Theme.current.foregroundSecondary : Theme.current.foregroundSecondary.opacity(0.6))
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

    // Accent color matching native sidebar navigation
    private var accentColor: Color {
        SettingsManager.shared.accentColor.color ?? Color.accentColor
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar (matches native SidebarRow)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? accentColor : Color.clear)
                .frame(width: 3)
                .padding(.vertical, 2)
                .animation(.easeOut(duration: 0.15), value: isSelected)

            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary.opacity(0.85))

                Spacer(minLength: 0)
            }
            .padding(.leading, 5)
            .padding(.trailing, 8)
        }
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

// MARK: - Settings Sidebar Column (for middle column in 3-column mode)

struct SettingsSidebarColumn: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(spacing: 0) {
            // Settings Header
            Text("SETTINGS")
                .font(.system(size: 10, weight: .bold, design: .default))
                .foregroundColor(Theme.current.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.md)
                .padding(.top, 8)  // Match main navigation TALKIE header
                .padding(.bottom, Spacing.sm)

            // Menu Sections
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: Spacing.md) {
                    // APPEARANCE
                    SettingsSidebarSection(title: "APPEARANCE", isActive: selectedSection == .appearance) {
                        SettingsSidebarItem(
                            icon: "paintbrush",
                            title: "APPEARANCE",
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
                    SettingsSidebarSection(title: "DICTATION", isActive: selectedSection == .dictationCapture || selectedSection == .dictationOutput || selectedSection == .dictionary) {
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
                        SettingsSidebarItem(
                            icon: "text.book.closed",
                            title: "DICTIONARY",
                            isSelected: selectedSection == .dictionary
                        ) {
                            selectedSection = .dictionary
                        }
                    }

                    // AI MODELS
                    SettingsSidebarSection(title: "AI MODELS", isActive: selectedSection == .aiProviders || selectedSection == .transcriptionModels || selectedSection == .ttsVoices || selectedSection == .llmModels) {
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
                            icon: "speaker.wave.2",
                            title: "VOICES",
                            isSelected: selectedSection == .ttsVoices
                        ) {
                            selectedSection = .ttsVoices
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
                    SettingsSidebarSection(title: "STORAGE", isActive: selectedSection == .database || selectedSection == .files) {
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
                    }

                    // iOS (user-facing connectivity)
                    SettingsSidebarSection(title: "iOS", isActive: selectedSection == .iOS) {
                        SettingsSidebarItem(
                            icon: "iphone",
                            title: "CONNECTION",
                            isSelected: selectedSection == .iOS
                        ) {
                            selectedSection = .iOS
                        }
                    }

                    // SYSTEM
                    SettingsSidebarSection(title: "SYSTEM", isActive: selectedSection == .connections || selectedSection == .helpers || selectedSection == .server || selectedSection == .permissions || selectedSection == .debugInfo || selectedSection == .devControl) {
                        SettingsSidebarItem(
                            icon: "point.3.connected.trianglepath.dotted",
                            title: "CONNECTIONS",
                            isSelected: selectedSection == .connections
                        ) {
                            selectedSection = .connections
                        }
                        SettingsSidebarItem(
                            icon: "app.connected.to.app.below.fill",
                            title: "HELPERS",
                            isSelected: selectedSection == .helpers
                        ) {
                            selectedSection = .helpers
                        }
                        SettingsSidebarItem(
                            icon: "server.rack",
                            title: "SERVER",
                            isSelected: selectedSection == .server
                        ) {
                            selectedSection = .server
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.backgroundSecondary)
    }
}

// MARK: - Settings Content Column (for detail column in 3-column mode)

struct SettingsContentColumn: View {
    @Binding var selectedSection: SettingsSection

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        case .dictionary:
            DictionarySettingsView()

        // ACTIONS
        case .quickActions:
            QuickActionsSettingsView()
        case .quickOpen:
            QuickOpenSettingsView()
        case .automations:
            Text("Automations settings coming soon")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.current.surface1)

        // AI MODELS
        case .aiProviders:
            APISettingsView()
        case .transcriptionModels:
            TranscriptionModelsSettingsView()
        case .ttsVoices:
            TTSVoicesSettingsView()
        case .llmModels:
            ModelLibraryView()

        // STORAGE
        case .database:
            DatabaseSettingsView()
        case .files:
            LocalFilesSettingsView()

        // iOS
        case .iOS:
            iOSSettingsView()

        // SYSTEM
        case .connections:
            ConnectionCenterView(selectedSection: $selectedSection)
        case .helpers:
            HelperAppsSettingsView()
        case .server:
            ServerSettingsView()
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
