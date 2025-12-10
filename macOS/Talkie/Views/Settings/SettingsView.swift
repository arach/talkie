//
//  SettingsView.swift
//  Talkie macOS
//
//  Settings and workflow management UI (inspired by EchoFlow)
//

import SwiftUI
import CloudKit

enum SettingsSection: String, Hashable {
    case appearance
    case quickActions
    case autoRun
    case apiKeys
    case allowedCommands
    case outputSettings
    case localFiles
    case debugInfo
}

struct SettingsView: View {
    @ObservedObject var settingsManager = SettingsManager.shared
    @State private var apiKeyInput: String = ""
    @State private var showingSaveConfirmation = false
    @State private var selectedSection: SettingsSection = .apiKeys  // Default to API Keys

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

                        // WORKFLOWS
                        SettingsSidebarSection(title: "WORKFLOWS", isActive: selectedSection == .quickActions || selectedSection == .autoRun) {
                            SettingsSidebarItem(
                                icon: "bolt",
                                title: "QUICK ACTIONS",
                                isSelected: selectedSection == .quickActions
                            ) {
                                selectedSection = .quickActions
                            }
                            SettingsSidebarItem(
                                icon: "play.circle",
                                title: "AUTO-RUN",
                                isSelected: selectedSection == .autoRun
                            ) {
                                selectedSection = .autoRun
                            }
                        }

                        // API & PROVIDERS
                        SettingsSidebarSection(title: "API & PROVIDERS", isActive: selectedSection == .apiKeys) {
                            SettingsSidebarItem(
                                icon: "key",
                                title: "API KEYS",
                                isSelected: selectedSection == .apiKeys
                            ) {
                                selectedSection = .apiKeys
                            }
                        }

                        // SHELL & OUTPUT
                        SettingsSidebarSection(title: "SHELL & OUTPUT", isActive: selectedSection == .allowedCommands || selectedSection == .outputSettings) {
                            SettingsSidebarItem(
                                icon: "terminal",
                                title: "ALLOWED COMMANDS",
                                isSelected: selectedSection == .allowedCommands
                            ) {
                                selectedSection = .allowedCommands
                            }
                            SettingsSidebarItem(
                                icon: "arrow.right.doc.on.clipboard",
                                title: "OUTPUT & ALIASES",
                                isSelected: selectedSection == .outputSettings
                            ) {
                                selectedSection = .outputSettings
                            }
                        }

                        // DATA & FILES
                        SettingsSidebarSection(title: "DATA & FILES", isActive: selectedSection == .localFiles) {
                            SettingsSidebarItem(
                                icon: "folder",
                                title: "LOCAL FILES",
                                isSelected: selectedSection == .localFiles
                            ) {
                                selectedSection = .localFiles
                            }
                        }

                        // DEBUG
                        SettingsSidebarSection(title: "DEBUG", isActive: selectedSection == .debugInfo) {
                            SettingsSidebarItem(
                                icon: "ladybug",
                                title: "DEBUG INFO",
                                isSelected: selectedSection == .debugInfo
                            ) {
                                selectedSection = .debugInfo
                            }
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
                Group {
                    switch selectedSection {
                    case .appearance:
                        AppearanceSettingsView()
                    case .quickActions:
                        QuickActionsSettingsView()
                    case .autoRun:
                        AutoRunSettingsView()
                    case .apiKeys:
                        APISettingsView(settingsManager: settingsManager)
                    case .allowedCommands:
                        AllowedCommandsView()
                    case .outputSettings:
                        OutputSettingsView()
                    case .localFiles:
                        LocalFilesSettingsView()
                    case .debugInfo:
                        DebugInfoView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(contentBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

