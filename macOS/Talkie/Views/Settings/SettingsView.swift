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
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settingsManager = SettingsManager.shared
    @State private var apiKeyInput: String = ""
    @State private var showingSaveConfirmation = false
    @State private var selectedSection: SettingsSection = .apiKeys  // Default to API Keys

    // Use DesignSystem colors for Midnight theme consistency
    // Sidebar is slightly elevated, content is true black, cards pop out slightly
    private let sidebarBackground = MidnightSurface.elevated
    private let contentBackground = MidnightSurface.content
    private let bottomBarBackground = MidnightSurface.sidebar

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                // Settings Header - with breathing room at top
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
                .fill(MidnightSurface.divider)
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

