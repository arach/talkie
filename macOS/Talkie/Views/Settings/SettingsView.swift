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

    // MEMOS (Quick Actions, Quick Open, Auto-Run)
    case quickActions
    case quickOpen
    case autoRun

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
    case permissions
    case debugInfo
    case devControl          // Dev control panel (DEBUG only)

    // Legacy/compatibility
    case audio               // For TalkieLive HistoryView compatibility
    case engine              // For TalkieLive HistoryView compatibility
}

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State private var apiKeyInput: String = ""
    @State private var showingSaveConfirmation = false
    @State private var selectedSection: SettingsSection = .appearance  // Default to Appearance (less aggressive)

    // Theme-aware colors for light/dark mode
    private var sidebarBackground: Color { Theme.current.backgroundSecondary }
    private var contentBackground: Color { Theme.current.background }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                // Settings Header - with breathing room at top
                Text("SETTINGS")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundColor(Theme.current.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // Menu Sections
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
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
                        SettingsSidebarSection(title: "MEMOS", isActive: selectedSection == .quickActions || selectedSection == .quickOpen || selectedSection == .autoRun) {
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
                                title: "AUTO-RUN",
                                isSelected: selectedSection == .autoRun
                            ) {
                                selectedSection = .autoRun
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
                        SettingsSidebarSection(title: "SYSTEM", isActive: selectedSection == .permissions || selectedSection == .debugInfo || selectedSection == .devControl) {
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
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: 220)
            .background(sidebarBackground)

            // Divider
            Rectangle()
                .fill(Theme.current.divider)
                .frame(width: 1)

            // MARK: - Content Area
            VStack(spacing: 0) {
                // Content based on selection
                contentView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
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
        case .autoRun:
            AutoRunSettingsView()

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
                .foregroundColor(isSelected ? (SettingsManager.shared.appearanceMode == .dark ? .white : .white) : Theme.current.foregroundMuted)
                .frame(width: 14)

            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isSelected ? (SettingsManager.shared.appearanceMode == .dark ? .white : .white) : Theme.current.foregroundSecondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor : (isHovered ? Theme.current.backgroundTertiary : Color.clear))
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
