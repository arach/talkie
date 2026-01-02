//
//  SettingsColumns.swift
//  Talkie macOS
//
//  Split Settings into sidebar and content columns for 3-column NavigationSplitView
//

import SwiftUI

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
