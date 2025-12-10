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

// MARK: - Appearance Settings View
struct AppearanceSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared

    /// Check if this theme is the current active theme
    private func isThemeActive(_ preset: ThemePreset) -> Bool {
        return settingsManager.currentTheme == preset
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "paintbrush",
                title: "APPEARANCE",
                subtitle: "Customize how Talkie looks on your Mac."
            )
        } content: {
            // MARK: - Theme Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("QUICK THEMES")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    Text("Apply a curated theme preset with one click.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    // Live preview (top) - sidebar + table
                    HStack(spacing: 0) {
                        // Mini sidebar
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TALKIE")
                                .font(SettingsManager.shared.fontXSBold)
                                .tracking(1)
                                .foregroundColor(SettingsManager.shared.tacticalForeground)
                                .padding(.bottom, 4)

                            ForEach(["All Memos", "Recent", "Processed"], id: \.self) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: item == "All Memos" ? "square.stack" : (item == "Recent" ? "clock" : "checkmark.circle"))
                                        .font(SettingsManager.shared.fontXS)
                                        .foregroundColor(item == "All Memos" ? .accentColor : SettingsManager.shared.tacticalForegroundMuted)
                                    Text(item)
                                        .font(SettingsManager.shared.fontSM)
                                        .foregroundColor(item == "All Memos" ? SettingsManager.shared.tacticalForeground : SettingsManager.shared.tacticalForegroundSecondary)
                                    Spacer()
                                    if item == "All Memos" {
                                        Text("103")
                                            .font(SettingsManager.shared.fontXS)
                                            .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(item == "All Memos" ? Color.accentColor.opacity(0.15) : Color.clear)
                                .cornerRadius(4)
                            }
                        }
                        .padding(8)
                        .frame(width: 130)
                        .background(SettingsManager.shared.tacticalBackground)

                        Rectangle()
                            .fill(SettingsManager.shared.tacticalDivider)
                            .frame(width: 0.5)

                        // Table
                        VStack(spacing: 0) {
                            // Header row
                            HStack(spacing: 0) {
                                Text("TIMESTAMP")
                                    .font(SettingsManager.shared.fontXSBold)
                                    .foregroundColor(SettingsManager.shared.tacticalForegroundSecondary)
                                    .frame(width: 90, alignment: .leading)
                                Text("TITLE")
                                    .font(SettingsManager.shared.fontXSBold)
                                    .foregroundColor(SettingsManager.shared.tacticalForegroundSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("DUR")
                                    .font(SettingsManager.shared.fontXSBold)
                                    .foregroundColor(SettingsManager.shared.tacticalForegroundSecondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SettingsManager.shared.tacticalBackgroundSecondary)

                            // Sample rows
                            ForEach(0..<5) { i in
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(SettingsManager.shared.tacticalDivider.opacity(0.3))
                                        .frame(height: 0.5)
                                    HStack(spacing: 0) {
                                        Text(["Nov 30, 11:22", "Nov 29, 15:42", "Nov 29, 12:51", "Nov 28, 21:49", "Nov 28, 19:33"][i])
                                            .font(SettingsManager.shared.fontSM)
                                            .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)
                                            .frame(width: 90, alignment: .leading)
                                        Text(["Recording 2025-11-30", "Quick memo 11/29", "Recording 11/29", "Quick memo 11/28", "Meeting notes"][i])
                                            .font(SettingsManager.shared.fontSM)
                                            .foregroundColor(SettingsManager.shared.tacticalForeground)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(["0:09", "0:34", "0:08", "0:31", "1:04"][i])
                                            .font(SettingsManager.shared.fontSM)
                                            .foregroundColor(SettingsManager.shared.tacticalForegroundMuted)
                                            .frame(width: 40, alignment: .trailing)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(i == 0 ? Color.accentColor.opacity(0.15) : Color.clear)
                                }
                            }
                        }
                        .background(SettingsManager.shared.tacticalBackground)
                    }
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(SettingsManager.shared.tacticalDivider, lineWidth: 0.5)
                    )

                    // Theme selection (bottom)
                    HStack(spacing: 6) {
                        ForEach(ThemePreset.allCases, id: \.rawValue) { preset in
                            Button(action: { settingsManager.applyTheme(preset) }) {
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(preset.previewColors.bg)
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(preset.previewColors.accent, lineWidth: 1)
                                        )
                                    Text(preset.displayName)
                                        .font(SettingsManager.shared.fontXS)
                                        .foregroundColor(isThemeActive(preset) ? .primary : .secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(isThemeActive(preset) ? Color.accentColor.opacity(0.15) : SettingsManager.shared.tacticalBackgroundTertiary)
                                .cornerRadius(4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isThemeActive(preset) ? Color.accentColor : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .background(SettingsManager.shared.surface2)
                .cornerRadius(8)

                // MARK: - Theme Mode
                VStack(alignment: .leading, spacing: 12) {
                    Text("APPEARANCE")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                            AppearanceModeButton(
                                mode: mode,
                                isSelected: settingsManager.appearanceMode == mode,
                                action: { settingsManager.appearanceMode = mode }
                            )
                        }
                    }
                }
                .padding(16)
                .background(SettingsManager.shared.surface2)
                .cornerRadius(8)

                // MARK: - Accent Color
                VStack(alignment: .leading, spacing: 12) {
                    Text("ACCENT COLOR")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    Text("Used for buttons, selections, and highlights.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(AccentColorOption.allCases, id: \.rawValue) { colorOption in
                            AccentColorButton(
                                colorOption: colorOption,
                                isSelected: settingsManager.accentColor == colorOption,
                                action: { settingsManager.accentColor = colorOption }
                            )
                        }
                    }
                }
                .padding(16)
                .background(SettingsManager.shared.surface2)
                .cornerRadius(8)

                // MARK: - Typography
                VStack(alignment: .leading, spacing: 10) {
                    Text("TYPOGRAPHY")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    // UI Chrome: Font + Size together
                    VStack(alignment: .leading, spacing: 8) {
                        Text("UI Chrome")
                            .font(SettingsManager.shared.fontXSBold)
                            .textCase(SettingsManager.shared.uiTextCase)
                            .foregroundColor(.secondary.opacity(0.6))

                        HStack(spacing: 12) {
                            // UI Font
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Font")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary.opacity(0.8))
                                HStack(spacing: 4) {
                                    ForEach(FontStyleOption.allCases, id: \.rawValue) { style in
                                        FontStyleButton(
                                            style: style,
                                            isSelected: settingsManager.uiFontStyle == style,
                                            action: { settingsManager.uiFontStyle = style }
                                        )
                                    }
                                }
                            }

                            Divider().frame(height: 36)

                            // UI Size
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Size")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary.opacity(0.8))
                                HStack(spacing: 4) {
                                    ForEach(FontSizeOption.allCases, id: \.rawValue) { size in
                                        FontSizeButton(
                                            size: size,
                                            isSelected: settingsManager.uiFontSize == size,
                                            action: { settingsManager.uiFontSize = size }
                                        )
                                    }
                                }
                            }
                        }

                        // ALL CAPS toggle
                        Toggle(isOn: $settingsManager.uiAllCaps) {
                            HStack(spacing: 4) {
                                Text("ALL CAPS")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary.opacity(0.8))
                                Text("labels & headers")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(settingsManager.resolvedAccentColor)
                        .controlSize(.mini)
                    }
                    .padding(10)
                    .background(SettingsManager.shared.surface1)
                    .cornerRadius(6)

                    // Content: Font + Size together
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Content")
                            .font(SettingsManager.shared.fontXSBold)
                            .textCase(SettingsManager.shared.uiTextCase)
                            .foregroundColor(.secondary.opacity(0.6))

                        HStack(spacing: 12) {
                            // Content Font
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Font")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary.opacity(0.8))
                                HStack(spacing: 4) {
                                    ForEach(FontStyleOption.allCases, id: \.rawValue) { style in
                                        FontStyleButton(
                                            style: style,
                                            isSelected: settingsManager.contentFontStyle == style,
                                            action: { settingsManager.contentFontStyle = style }
                                        )
                                    }
                                }
                            }

                            Divider().frame(height: 36)

                            // Content Size
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Size")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary.opacity(0.8))
                                HStack(spacing: 4) {
                                    ForEach(FontSizeOption.allCases, id: \.rawValue) { size in
                                        FontSizeButton(
                                            size: size,
                                            isSelected: settingsManager.contentFontSize == size,
                                            action: { settingsManager.contentFontSize = size }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(SettingsManager.shared.surface1)
                    .cornerRadius(6)

                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))

                        VStack(alignment: .leading, spacing: 12) {
                            // UI Font Preview
                            VStack(alignment: .leading, spacing: 2) {
                                Text("UI Chrome")
                                    .font(SettingsManager.shared.fontXSBold)
                                    .textCase(SettingsManager.shared.uiTextCase)
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text(settingsManager.uiAllCaps ? "MEMOS · ACTIONS · 12:34 PM" : "Memos · Actions · 12:34 PM")
                                    .font(settingsManager.themedFont(baseSize: 12))
                                    .foregroundColor(.primary)
                            }

                            Divider()

                            // Content Font Preview
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Content")
                                    .font(SettingsManager.shared.fontXSBold)
                                    .textCase(SettingsManager.shared.uiTextCase)
                                    .foregroundColor(.secondary.opacity(0.6))
                                Text("The quick brown fox jumps over the lazy dog. This is how your transcripts and notes will appear.")
                                    .font(settingsManager.contentFont(baseSize: 13))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(settingsManager.surfaceInput)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
                .padding(16)
                .background(SettingsManager.shared.surface2)
                .cornerRadius(8)

                // Note about accent color
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.blue)
                    Text("Accent color applies to Talkie only. System accent color is set in System Settings.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)
        }
    }
}

// MARK: - Appearance Mode Button
struct AppearanceModeButton: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: mode.icon)
                    .font(SettingsManager.shared.fontHeadline)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 48, height: 48)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : SettingsManager.shared.surface1)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(mode.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 80)
    }
}

// MARK: - Accent Color Button
struct AccentColorButton: View {
    let colorOption: AccentColorOption
    let isSelected: Bool
    let action: () -> Void

    private var displayColor: Color {
        colorOption.color ?? .accentColor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Color swatch
                if colorOption == .system {
                    // Gradient for system
                    LinearGradient(
                        colors: [.blue, .purple, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 14, height: 14)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(displayColor)
                        .frame(width: 14, height: 14)
                }

                Text(colorOption.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(SettingsManager.shared.fontXSBold)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : SettingsManager.shared.surface1)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Font Style Button
struct FontStyleButton: View {
    let style: FontStyleOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: style.icon)
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : SettingsManager.shared.surface1)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )

                Text(style.displayName)
                    .font(.system(size: 8, weight: isSelected ? .medium : .regular, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 50)
    }
}

// MARK: - Font Size Button
struct FontSizeButton: View {
    let size: FontSizeOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: size.icon)
                    .font(.system(size: size.previewFontSize - 2))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(size.displayName)
                    .font(.system(size: size.previewFontSize, weight: isSelected ? .medium : .regular, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.15) : SettingsManager.shared.surface1)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Preset Card
struct ThemePresetCard: View {
    let preset: ThemePreset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Preview bar
                HStack(spacing: 0) {
                    preset.previewColors.bg
                        .frame(height: 32)
                        .overlay(
                            HStack(spacing: 6) {
                                Image(systemName: preset.icon)
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(preset.previewColors.accent)
                                Text("Aa")
                                    .font(.system(size: 11, weight: .medium, design: preset.uiFontStyle == .monospace ? .monospaced : (preset.uiFontStyle == .rounded ? .rounded : .default)))
                                    .foregroundColor(preset.previewColors.fg)

                                Spacer()

                                if isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(SettingsManager.shared.fontSM)
                                        .foregroundColor(preset.previewColors.accent)
                                }
                            }
                            .padding(.horizontal, 10)
                            , alignment: .leading
                        )
                }
                .cornerRadius(6)

                // Name and description
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(preset.displayName)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)

                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor)
                                .cornerRadius(3)
                        }
                    }

                    Text(preset.description)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .background(isActive ? Color.accentColor.opacity(0.1) : SettingsManager.shared.surface1)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - API Settings View
struct APISettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @State private var editingProvider: String?
    @State private var editingKeyInput: String = ""
    @State private var revealedKeys: Set<String> = []

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "key",
                title: "API KEYS",
                subtitle: "Manage API keys for cloud AI providers. Keys are stored securely in the macOS Keychain."
            )
        } content: {
            // Provider API Keys
            VStack(spacing: 16) {
                    APIKeyRow(
                        provider: "OpenAI",
                        icon: "brain.head.profile",
                        placeholder: "sk-...",
                        helpURL: "https://platform.openai.com/api-keys",
                        isConfigured: settingsManager.openaiApiKey != nil,
                        currentKey: settingsManager.openaiApiKey,
                        isEditing: editingProvider == "openai",
                        isRevealed: revealedKeys.contains("openai"),
                        editingKey: $editingKeyInput,
                        onEdit: {
                            editingProvider = "openai"
                            editingKeyInput = settingsManager.openaiApiKey ?? ""
                        },
                        onSave: {
                            settingsManager.openaiApiKey = editingKeyInput.isEmpty ? nil : editingKeyInput
                            settingsManager.saveSettings()
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onCancel: {
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onReveal: {
                            if revealedKeys.contains("openai") {
                                revealedKeys.remove("openai")
                            } else {
                                revealedKeys.insert("openai")
                            }
                        },
                        onDelete: {
                            settingsManager.openaiApiKey = nil
                            settingsManager.saveSettings()
                        }
                    )

                    APIKeyRow(
                        provider: "Anthropic",
                        icon: "sparkles",
                        placeholder: "sk-ant-...",
                        helpURL: "https://console.anthropic.com/settings/keys",
                        isConfigured: settingsManager.anthropicApiKey != nil,
                        currentKey: settingsManager.anthropicApiKey,
                        isEditing: editingProvider == "anthropic",
                        isRevealed: revealedKeys.contains("anthropic"),
                        editingKey: $editingKeyInput,
                        onEdit: {
                            editingProvider = "anthropic"
                            editingKeyInput = settingsManager.anthropicApiKey ?? ""
                        },
                        onSave: {
                            settingsManager.anthropicApiKey = editingKeyInput.isEmpty ? nil : editingKeyInput
                            settingsManager.saveSettings()
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onCancel: {
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onReveal: {
                            if revealedKeys.contains("anthropic") {
                                revealedKeys.remove("anthropic")
                            } else {
                                revealedKeys.insert("anthropic")
                            }
                        },
                        onDelete: {
                            settingsManager.anthropicApiKey = nil
                            settingsManager.saveSettings()
                        }
                    )

                    APIKeyRow(
                        provider: "Gemini",
                        icon: "cloud.fill",
                        placeholder: "AIzaSy...",
                        helpURL: "https://makersuite.google.com/app/apikey",
                        isConfigured: settingsManager.hasValidApiKey,
                        currentKey: settingsManager.geminiApiKey.isEmpty ? nil : settingsManager.geminiApiKey,
                        isEditing: editingProvider == "gemini",
                        isRevealed: revealedKeys.contains("gemini"),
                        editingKey: $editingKeyInput,
                        onEdit: {
                            editingProvider = "gemini"
                            editingKeyInput = settingsManager.geminiApiKey
                        },
                        onSave: {
                            settingsManager.geminiApiKey = editingKeyInput
                            settingsManager.saveSettings()
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onCancel: {
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onReveal: {
                            if revealedKeys.contains("gemini") {
                                revealedKeys.remove("gemini")
                            } else {
                                revealedKeys.insert("gemini")
                            }
                        },
                        onDelete: {
                            settingsManager.geminiApiKey = ""
                            settingsManager.saveSettings()
                        }
                    )

                    APIKeyRow(
                        provider: "Groq",
                        icon: "bolt.fill",
                        placeholder: "gsk_...",
                        helpURL: "https://console.groq.com/keys",
                        isConfigured: settingsManager.groqApiKey != nil,
                        currentKey: settingsManager.groqApiKey,
                        isEditing: editingProvider == "groq",
                        isRevealed: revealedKeys.contains("groq"),
                        editingKey: $editingKeyInput,
                        onEdit: {
                            editingProvider = "groq"
                            editingKeyInput = settingsManager.groqApiKey ?? ""
                        },
                        onSave: {
                            settingsManager.groqApiKey = editingKeyInput.isEmpty ? nil : editingKeyInput
                            settingsManager.saveSettings()
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onCancel: {
                            editingProvider = nil
                            editingKeyInput = ""
                        },
                        onReveal: {
                            if revealedKeys.contains("groq") {
                                revealedKeys.remove("groq")
                            } else {
                                revealedKeys.insert("groq")
                            }
                        },
                        onDelete: {
                            settingsManager.groqApiKey = nil
                            settingsManager.saveSettings()
                        }
                    )
                }

            Divider()
                .background(MidnightSurface.divider)
                .padding(.vertical, 8)

            // LLM Cost Tier Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("LLM COST TIER")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Text("Controls the default model quality for workflow LLM steps. Budget uses cheaper/faster models, Capable uses more powerful models.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)

                Picker("Cost Tier", selection: $settingsManager.llmCostTier) {
                    ForEach(LLMCostTier.allCases, id: \.self) { tier in
                        Text(tier.displayName).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Tier description
                HStack(spacing: 6) {
                    Circle()
                        .fill(tierColor(settingsManager.llmCostTier))
                        .frame(width: 6, height: 6)
                    Text(tierDescription(settingsManager.llmCostTier))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)

            Spacer()
        }
    }

    private func tierColor(_ tier: LLMCostTier) -> Color {
        switch tier {
        case .budget: return .green
        case .balanced: return .orange
        case .capable: return .purple
        }
    }

    private func tierDescription(_ tier: LLMCostTier) -> String {
        switch tier {
        case .budget:
            return "Uses Groq (free) or Gemini Flash. Fastest, lowest cost."
        case .balanced:
            return "Uses Gemini 2.0 Flash or GPT-4o-mini. Good balance of quality and cost."
        case .capable:
            return "Uses Claude Sonnet or GPT-4o. Best quality for complex reasoning."
        }
    }
}

// MARK: - API Key Row Component
struct APIKeyRow: View {
    let provider: String
    let icon: String
    let placeholder: String
    let helpURL: String
    let isConfigured: Bool
    let currentKey: String?
    let isEditing: Bool
    let isRevealed: Bool
    @Binding var editingKey: String
    let onEdit: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    private var maskedKey: String {
        guard let key = currentKey, !key.isEmpty else { return "Not configured" }
        if key.count <= 8 { return String(repeating: "•", count: key.count) }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(SettingsManager.shared.fontTitle)
                    .foregroundColor(isConfigured ? .blue : .secondary)
                    .frame(width: 20)

                Text(provider.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)

                Spacer()

                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(isConfigured ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(isConfigured ? "CONFIGURED" : "NOT SET")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(isConfigured ? .green : .orange)
                }
            }

            if isEditing {
                // Edit mode
                HStack(spacing: 8) {
                    SecureField(placeholder, text: $editingKey)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(SettingsManager.shared.surface1)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(SettingsManager.shared.fontXSMedium)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onSave) {
                        Text("Save")
                            .font(SettingsManager.shared.fontXSMedium)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if isConfigured {
                // Display mode with key - passive text field style
                HStack(spacing: 8) {
                    // Key display styled as disabled text field
                    HStack(spacing: 8) {
                        Text(isRevealed ? (currentKey ?? "") : maskedKey)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        // Reveal button
                        Button(action: onReveal) {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .help(isRevealed ? "Hide API key" : "Reveal API key")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(CornerRadius.xs)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )

                    Button(action: onEdit) {
                        Text("Edit")
                            .font(SettingsManager.shared.fontXSMedium)
                    }
                    .buttonStyle(.bordered)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(SettingsManager.shared.fontXS)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            } else {
                // Not configured - show add button
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(SettingsManager.shared.fontXS)
                            Text("Add API Key")
                                .font(SettingsManager.shared.fontXSMedium)
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Link(destination: URL(string: helpURL)!) {
                        HStack(spacing: 4) {
                            Text("Get key")
                                .font(SettingsManager.shared.fontXS)
                            Image(systemName: "arrow.up.right.square")
                                .font(SettingsManager.shared.fontXS)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(16)
        .background(SettingsManager.shared.surface2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Model Library View
struct ModelLibraryView: View {
    @ObservedObject var settingsManager = SettingsManager.shared

    let models: [(model: AIModel, installed: Bool)] = [
        (.geminiFlash, true),
        (.geminiPro, false)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "brain")
                            .font(SettingsManager.shared.fontTitle)
                        Text("MODEL LIBRARY")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Manage the AI models available for your workflows. Download models to enable them in the Workflow Builder.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                // Models
                VStack(spacing: 16) {
                    ForEach(models, id: \.model.rawValue) { item in
                        ModelCard(model: item.model, installed: item.installed)
                    }
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(settingsManager.surfaceInput)
    }
}

// MARK: - Model Card
struct ModelCard: View {
    let model: AIModel
    let installed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            Image(systemName: "sparkles")
                .font(SettingsManager.shared.fontHeadline)
                .foregroundColor(installed ? .blue : .secondary)
                .frame(width: 32, height: 32)
                .background(SettingsManager.shared.surface1)
                .cornerRadius(8)

            // Info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(model.badge)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(model == .geminiPro ? Color.purple : Color.blue)
                        .cornerRadius(4)
                }

                Text(model.description)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Text("ID: \(model.rawValue)")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            // Status/Action
            if installed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.green)
                    Text("INSTALLED")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.green)
                }
            } else {
                Button(action: {}) {
                    Text("DOWNLOAD")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(SettingsManager.shared.surface1)
        .cornerRadius(8)
    }
}

// MARK: - Workflows View
struct WorkflowsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(SettingsManager.shared.fontTitle)
                        Text("WORKFLOWS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Manage and customize your workflow actions.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Coming soon: Workflow builder and customization")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsManager.shared.surfaceInput)
    }
}

// MARK: - Activity Log View
struct ActivityLogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet.clipboard")
                            .font(SettingsManager.shared.fontTitle)
                        Text("ACTIVITY LOG")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("View workflow execution history.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                Text("Coming soon: Activity log and execution history")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsManager.shared.surfaceInput)
    }
}

// MARK: - Allowed Commands View
struct AllowedCommandsView: View {
    @State private var newCommandPath: String = ""
    @State private var customCommands: [String] = []
    @State private var showingWhichResult: String?

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "terminal",
                title: "ALLOWED COMMANDS",
                subtitle: "Manage which CLI tools can be executed by workflow shell steps."
            )
        } content: {
            // Add new command
                VStack(alignment: .leading, spacing: 12) {
                    Text("ADD COMMAND")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField("/path/to/executable", text: $newCommandPath)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(SettingsManager.shared.surface1)
                            .cornerRadius(6)

                        Button(action: findCommand) {
                            Text("WHICH")
                                .font(SettingsManager.shared.fontXSBold)
                                .tracking(1)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.secondary)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Find path for a command name")

                        Button(action: addCommand) {
                            Text("ADD")
                                .font(SettingsManager.shared.fontXSBold)
                                .tracking(1)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(newCommandPath.isEmpty ? Color.gray : Color.blue)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(newCommandPath.isEmpty)
                    }

                    if let result = showingWhichResult {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.blue)
                            Text(result)
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.blue)
                        }
                    }

                    Text("Enter the full path to the executable (e.g., /Users/you/.bun/bin/claude)")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Custom commands
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR CUSTOM COMMANDS")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    if customCommands.isEmpty {
                        Text("No custom commands added yet.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(customCommands, id: \.self) { path in
                            HStack {
                                Image(systemName: "terminal")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.green)

                                Text(path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)

                                Spacer()

                                Button(action: { removeCommand(path) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(SettingsManager.shared.fontSM)
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(SettingsManager.shared.surface1)
                            .cornerRadius(6)
                        }
                    }
                }

                Divider()

                // Default commands (collapsed)
                VStack(alignment: .leading, spacing: 12) {
                    Text("BUILT-IN COMMANDS (\(ShellStepConfig.defaultAllowedExecutables.count))")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(1)
                        .foregroundColor(.secondary)

                    DisclosureGroup {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(ShellStepConfig.defaultAllowedExecutables.sorted(), id: \.self) { path in
                                Text(path)
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } label: {
                        Text("Show built-in allowed commands")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.blue)
                    }
                }
        }
        .onAppear {
            loadCustomCommands()
        }
    }

    private func loadCustomCommands() {
        customCommands = ShellStepConfig.customAllowedExecutables
    }

    private func addCommand() {
        let path = newCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        ShellStepConfig.addAllowedExecutable(path)
        customCommands = ShellStepConfig.customAllowedExecutables
        newCommandPath = ""
        showingWhichResult = nil
    }

    private func removeCommand(_ path: String) {
        ShellStepConfig.removeAllowedExecutable(path)
        customCommands = ShellStepConfig.customAllowedExecutables
    }

    private func findCommand() {
        let name = newCommandPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        // Only search system paths that won't trigger permission dialogs
        // Avoid ~/Library and other protected user directories
        let systemPaths = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "/bin/\(name)",
        ]

        // Check system paths first (safe, no permission prompts)
        for path in systemPaths {
            if FileManager.default.fileExists(atPath: path) {
                newCommandPath = path
                showingWhichResult = "Found: \(path)"
                return
            }
        }

        // For user-specific paths, provide suggestions without checking
        // This avoids triggering macOS permission dialogs
        let suggestions = [
            "~/.bun/bin/\(name)",
            "~/.claude/local/\(name)",
            "~/.local/bin/\(name)",
            "~/.cargo/bin/\(name)",
        ]

        showingWhichResult = "Not found in system paths. Try one of:\n" + suggestions.joined(separator: "\n")
    }
}

// MARK: - Output Settings View

struct OutputSettingsView: View {
    @State private var outputDirectory: String = SaveFileStepConfig.defaultOutputDirectory
    @State private var showingFolderPicker = false
    @State private var statusMessage: String?

    // Path aliases
    @State private var pathAliases: [String: String] = SaveFileStepConfig.pathAliases
    @State private var newAliasName: String = ""
    @State private var newAliasPath: String = ""
    @State private var showingAliasFolderPicker = false

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.down.doc",
                title: "OUTPUT",
                subtitle: "Configure default output location and path aliases for workflows."
            )
        } content: {
            // Directory picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("DEFAULT OUTPUT FOLDER")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField("~/Documents/Talkie", text: $outputDirectory)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))

                        Button(action: { showingFolderPicker = true }) {
                            Image(systemName: "folder")
                                .font(SettingsManager.shared.fontSM)
                        }
                        .buttonStyle(.bordered)
                        .help("Browse for folder")

                        Button(action: saveDirectory) {
                            Text("Save")
                                .font(SettingsManager.shared.fontXSMedium)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    // Current value display
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.blue)
                        Text(SaveFileStepConfig.defaultOutputDirectory)
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }

                // Status message
                if let message = statusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: message.contains("✓") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundColor(message.contains("✓") ? .green : .orange)
                        Text(message)
                            .font(SettingsManager.shared.fontXS)
                    }
                }

                Divider()

                // Quick actions
                VStack(alignment: .leading, spacing: 12) {
                    Text("QUICK ACTIONS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Button(action: openInFinder) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.gearshape")
                                Text("Open in Finder")
                            }
                            .font(SettingsManager.shared.fontXS)
                        }
                        .buttonStyle(.bordered)

                        Button(action: createDirectory) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                Text("Create Folder")
                            }
                            .font(SettingsManager.shared.fontXS)
                        }
                        .buttonStyle(.bordered)

                        Button(action: resetToDefault) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Default")
                            }
                            .font(SettingsManager.shared.fontXS)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // MARK: - Path Aliases Section
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PATH ALIASES")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        Text("Define shortcuts like @Obsidian, @Notes to use in file paths")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))
                    }

                    // Existing aliases
                    if !pathAliases.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(pathAliases.sorted(by: { $0.key < $1.key }), id: \.key) { alias, path in
                                HStack(spacing: 12) {
                                    // Alias name
                                    HStack(spacing: 2) {
                                        Text("@")
                                            .foregroundColor(.blue)
                                        Text(alias)
                                            .fontWeight(.medium)
                                    }
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 100, alignment: .leading)

                                    // Arrow
                                    Image(systemName: "arrow.right")
                                        .font(SettingsManager.shared.fontXS)
                                        .foregroundColor(.secondary)

                                    // Path
                                    Text(path)
                                        .font(SettingsManager.shared.fontXS)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()

                                    // Delete button
                                    Button(action: { removeAlias(alias) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(SettingsManager.shared.fontSM)
                                            .foregroundColor(.secondary.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(SettingsManager.shared.surface1)
                                .cornerRadius(6)
                            }
                        }
                    }

                    // Add new alias
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ADD NEW ALIAS")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            HStack(spacing: 2) {
                                Text("@")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.blue)
                                TextField("Obsidian", text: $newAliasName)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 100)
                            }

                            TextField("/path/to/folder", text: $newAliasPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))

                            Button(action: { showingAliasFolderPicker = true }) {
                                Image(systemName: "folder")
                                    .font(SettingsManager.shared.fontSM)
                            }
                            .buttonStyle(.bordered)

                            Button(action: addAlias) {
                                Text("Add")
                                    .font(SettingsManager.shared.fontXSMedium)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newAliasName.isEmpty || newAliasPath.isEmpty)
                        }
                    }

                    // Usage hint
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.yellow)
                        Text("Use in Save File step directory: @Obsidian/Voice Notes")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(6)
                }

        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    outputDirectory = url.path
                    saveDirectory()
                }
            case .failure(let error):
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingAliasFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    newAliasPath = url.path
                }
            case .failure(let error):
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
        .onAppear {
            outputDirectory = SaveFileStepConfig.defaultOutputDirectory
            pathAliases = SaveFileStepConfig.pathAliases
        }
    }

    private func saveDirectory() {
        let path = outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            statusMessage = "Path cannot be empty"
            return
        }

        // Expand ~ to home directory
        let expandedPath: String
        if path.hasPrefix("~") {
            expandedPath = NSString(string: path).expandingTildeInPath
        } else {
            expandedPath = path
        }

        SaveFileStepConfig.defaultOutputDirectory = expandedPath
        outputDirectory = expandedPath
        statusMessage = "✓ Output directory saved"

        // Clear status after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if statusMessage == "✓ Output directory saved" {
                statusMessage = nil
            }
        }
    }

    private func openInFinder() {
        let path = SaveFileStepConfig.defaultOutputDirectory
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            statusMessage = "Folder doesn't exist yet. Create it first."
        }
    }

    private func createDirectory() {
        do {
            try SaveFileStepConfig.ensureDefaultDirectoryExists()
            statusMessage = "✓ Folder created"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if statusMessage == "✓ Folder created" {
                    statusMessage = nil
                }
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func resetToDefault() {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            statusMessage = "Error: Cannot access documents directory"
            return
        }
        let defaultPath = documents.appendingPathComponent("Talkie").path
        outputDirectory = defaultPath
        SaveFileStepConfig.defaultOutputDirectory = defaultPath
        statusMessage = "✓ Reset to ~/Documents/Talkie"
    }

    private func addAlias() {
        let name = newAliasName.trimmingCharacters(in: .whitespacesAndNewlines)
        var path = newAliasPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !path.isEmpty else { return }

        // Expand ~ to home directory
        if path.hasPrefix("~") {
            path = NSString(string: path).expandingTildeInPath
        }

        SaveFileStepConfig.setPathAlias(name, path: path)
        pathAliases = SaveFileStepConfig.pathAliases
        newAliasName = ""
        newAliasPath = ""
        statusMessage = "✓ Added @\(name)"

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if statusMessage == "✓ Added @\(name)" {
                statusMessage = nil
            }
        }
    }

    private func removeAlias(_ name: String) {
        SaveFileStepConfig.removePathAlias(name)
        pathAliases = SaveFileStepConfig.pathAliases
    }
}

// MARK: - Quick Actions Settings View

struct QuickActionsSettingsView: View {
    @ObservedObject private var workflowManager = WorkflowManager.shared
    @State private var selectedWorkflow: WorkflowDefinition?
    @State private var showingWorkflowEditor = false

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "bolt",
                title: "QUICK ACTIONS",
                subtitle: "Pin workflows to show them as quick actions when viewing a memo. Pinned workflows sync to iOS via iCloud."
            )
        } content: {
            // Pinned workflows
            VStack(alignment: .leading, spacing: 12) {
                Text("PINNED WORKFLOWS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(MidnightSurface.Text.secondary)

                if pinnedWorkflows.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.slash")
                            .foregroundColor(MidnightSurface.Text.secondary)
                        Text("No workflows pinned")
                            .foregroundColor(MidnightSurface.Text.secondary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MidnightSurface.card)
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(pinnedWorkflows) { workflow in
                            workflowRow(workflow)
                        }
                    }
                }
            }

            Divider()
                .background(MidnightSurface.divider)

            // Available workflows
            VStack(alignment: .leading, spacing: 12) {
                Text("AVAILABLE WORKFLOWS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(MidnightSurface.Text.secondary)

                if unpinnedWorkflows.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("All workflows are pinned")
                            .foregroundColor(MidnightSurface.Text.secondary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MidnightSurface.card)
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(unpinnedWorkflows) { workflow in
                            workflowRow(workflow)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingWorkflowEditor) {
            if let workflow = selectedWorkflow {
                WorkflowEditorSheet(
                    workflow: workflow,
                    isNew: false,
                    onSave: { updatedWorkflow in
                        workflowManager.updateWorkflow(updatedWorkflow)
                        showingWorkflowEditor = false
                    },
                    onCancel: {
                        showingWorkflowEditor = false
                    }
                )
                .frame(minWidth: 600, minHeight: 500)
            }
        }
    }

    private var pinnedWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { $0.isPinned }
    }

    private var unpinnedWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { !$0.isPinned }
    }

    @ViewBuilder
    private func workflowRow(_ workflow: WorkflowDefinition) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: workflow.icon)
                .font(SettingsManager.shared.fontTitle)
                .foregroundColor(workflow.color.color)
                .frame(width: 24, height: 24)
                .background(workflow.color.color.opacity(0.15))
                .cornerRadius(6)

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Text(workflow.description)
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Edit button
            Button(action: { editWorkflow(workflow) }) {
                Image(systemName: "pencil")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit workflow")

            // Pin/unpin button
            Button(action: { togglePin(workflow) }) {
                Image(systemName: workflow.isPinned ? "pin.fill" : "pin")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(workflow.isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(workflow.isPinned ? "Unpin from quick actions" : "Pin to quick actions")
        }
        .padding(10)
        .background(SettingsManager.shared.surface1)
        .cornerRadius(8)
    }

    private func editWorkflow(_ workflow: WorkflowDefinition) {
        selectedWorkflow = workflow
        showingWorkflowEditor = true
    }

    private func togglePin(_ workflow: WorkflowDefinition) {
        var updated = workflow
        updated.isPinned.toggle()
        updated.modifiedAt = Date()
        workflowManager.updateWorkflow(updated)
    }
}

// MARK: - Debug Info View

struct DebugInfoView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)],
        animation: .default
    )
    private var allVoiceMemos: FetchedResults<VoiceMemo>

    @State private var iCloudStatus: String = "Checking..."

    private var environment: String {
        #if DEBUG
        return "Development"
        #else
        return "Production"
        #endif
    }

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "Unknown"
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "info.circle",
                title: "DEBUG INFO",
                subtitle: "Diagnostic information about the app environment."
            )
        } content: {
            Divider()

            // Info rows
            VStack(spacing: 12) {
                debugRow(label: "Environment", value: environment, valueColor: environment == "Development" ? .orange : .green)
                debugRow(label: "iCloud Status", value: iCloudStatus)
                debugRow(label: "CloudKit Container", value: "iCloud.com.jdi.talkie")
                debugRow(label: "Bundle ID", value: bundleID)
                debugRow(label: "Version", value: "\(version) (\(build))")
                debugRow(label: "Voice Memos", value: "\(allVoiceMemos.count)")
                debugRow(label: "Last Sync", value: SyncStatusManager.shared.lastSyncAgo)
            }

            Divider()

            // Sync status section
            VStack(alignment: .leading, spacing: 12) {
                Text("SYNC STATUS")
                    .font(SettingsManager.shared.fontXSBold)
                    .tracking(1)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Circle()
                        .fill(syncStatusColor)
                        .frame(width: 8, height: 8)
                    Text(syncStatusText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsManager.shared.surface1)
                .cornerRadius(8)
            }
        }
        .onAppear {
            checkiCloudStatus()
        }
    }

    @ViewBuilder
    private func debugRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(valueColor)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SettingsManager.shared.surface2)
        .cornerRadius(6)
    }

    private var syncStatusColor: Color {
        switch SyncStatusManager.shared.state {
        case .idle: return .gray
        case .syncing: return .blue
        case .synced: return .green
        case .error: return .red
        }
    }

    private var syncStatusText: String {
        switch SyncStatusManager.shared.state {
        case .idle: return "Idle"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .error(let message): return "Error: \(message)"
        }
    }

    private func checkiCloudStatus() {
        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        container.accountStatus { status, error in
            DispatchQueue.main.async {
                if let error = error {
                    iCloudStatus = "Error: \(error.localizedDescription)"
                    return
                }

                switch status {
                case .available:
                    iCloudStatus = "Available"
                case .noAccount:
                    iCloudStatus = "No Account"
                case .restricted:
                    iCloudStatus = "Restricted"
                case .couldNotDetermine:
                    iCloudStatus = "Could Not Determine"
                case .temporarilyUnavailable:
                    iCloudStatus = "Temporarily Unavailable"
                @unknown default:
                    iCloudStatus = "Unknown"
                }
            }
        }
    }
}

// MARK: - Local Files Settings View

struct LocalFilesSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var showingTranscriptsFolderPicker = false
    @State private var showingAudioFolderPicker = false
    @State private var statusMessage: String?
    @State private var stats: (transcripts: Int, audioFiles: Int, totalSize: Int64) = (0, 0, 0)

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "folder.badge.person.crop",
                title: "LOCAL FILES",
                subtitle: "Store your transcripts and audio files locally on your Mac."
            )
        } content: {
            // Value proposition - always visible
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(.green)
                        Text("YOUR DATA, YOUR FILES")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.green)
                    }

                    Text("Local files are stored as plain text (Markdown) and standard audio formats. You can open, edit, backup, or move them freely. No lock-in, full portability.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color.green.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )

                Divider()

                // MARK: - Transcripts Section
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settingsManager.saveTranscriptsLocally) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text")
                                    .font(SettingsManager.shared.fontSM)
                                    .foregroundColor(.blue)
                                Text("Save Transcripts Locally")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            HStack(spacing: 4) {
                                Text("Save as Markdown with YAML frontmatter.")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                                Link("File format", destination: URL(string: "https://talkie.jdi.do/docs/file-format")!)
                                    .font(SettingsManager.shared.fontXS)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(settingsManager.resolvedAccentColor)
                    .onChange(of: settingsManager.saveTranscriptsLocally) { _, enabled in
                        if enabled {
                            TranscriptFileManager.shared.ensureFoldersExist()
                            syncNow()
                        }
                    }

                    if settingsManager.saveTranscriptsLocally {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TRANSCRIPTS FOLDER")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                TextField("~/Documents/Talkie/Transcripts", text: $settingsManager.transcriptsFolderPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))

                                Button(action: { showingTranscriptsFolderPicker = true }) {
                                    Image(systemName: "folder")
                                        .font(SettingsManager.shared.fontSM)
                                }
                                .buttonStyle(.bordered)
                                .help("Browse for folder")

                                Button(action: { TranscriptFileManager.shared.openTranscriptsFolderInFinder() }) {
                                    Image(systemName: "arrow.up.forward.square")
                                        .font(SettingsManager.shared.fontSM)
                                }
                                .buttonStyle(.bordered)
                                .help("Open in Finder")
                            }
                        }
                        .padding(.leading, 24)
                    }
                }
                .padding(16)
                .background(SettingsManager.shared.surface2)
                .cornerRadius(8)

                // MARK: - Audio Section
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settingsManager.saveAudioLocally) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(SettingsManager.shared.fontSM)
                                    .foregroundColor(.purple)
                                Text("Save Audio Files Locally")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            Text("Copy M4A audio recordings to your local folder.")
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .tint(settingsManager.resolvedAccentColor)
                    .onChange(of: settingsManager.saveAudioLocally) { _, enabled in
                        if enabled {
                            TranscriptFileManager.shared.ensureFoldersExist()
                            syncNow()
                        }
                    }

                    if settingsManager.saveAudioLocally {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AUDIO FOLDER")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(0.5)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                TextField("~/Documents/Talkie/Audio", text: $settingsManager.audioFolderPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))

                                Button(action: { showingAudioFolderPicker = true }) {
                                    Image(systemName: "folder")
                                        .font(SettingsManager.shared.fontSM)
                                }
                                .buttonStyle(.bordered)
                                .help("Browse for folder")

                                Button(action: { TranscriptFileManager.shared.openAudioFolderInFinder() }) {
                                    Image(systemName: "arrow.up.forward.square")
                                        .font(SettingsManager.shared.fontSM)
                                }
                                .buttonStyle(.bordered)
                                .help("Open in Finder")
                            }

                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.orange)
                                Text("Audio files can take significant disk space")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.orange)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .padding(.leading, 24)
                    }
                }
                .padding(16)
                .background(SettingsManager.shared.surface2)
                .cornerRadius(8)

                // Stats and actions (only show if any local files enabled)
                if settingsManager.localFilesEnabled {
                    Divider()

                    // Stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FILE STATISTICS")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(stats.transcripts)")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                                Text("Transcripts")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(stats.audioFiles)")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.purple)
                                Text("Audio Files")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                Text("Total Size")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SettingsManager.shared.surface2)
                        .cornerRadius(8)
                    }

                    // Quick actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("QUICK ACTIONS")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button(action: syncNow) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Sync Now")
                                }
                                .font(SettingsManager.shared.fontXS)
                            }
                            .buttonStyle(.bordered)

                            Button(action: refreshStats) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Refresh Stats")
                                }
                                .font(SettingsManager.shared.fontXS)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Status message
                    if let message = statusMessage {
                        HStack(spacing: 6) {
                            Image(systemName: message.contains("✓") ? "checkmark.circle.fill" : "info.circle.fill")
                                .foregroundColor(message.contains("✓") ? .green : .blue)
                            Text(message)
                                .font(SettingsManager.shared.fontXS)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

        }
        .fileImporter(
            isPresented: $showingTranscriptsFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    settingsManager.transcriptsFolderPath = url.path
                    TranscriptFileManager.shared.ensureFoldersExist()
                    refreshStats()
                }
            case .failure(let error):
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $showingAudioFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    settingsManager.audioFolderPath = url.path
                    TranscriptFileManager.shared.ensureFoldersExist()
                    refreshStats()
                }
            case .failure(let error):
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
        .onAppear {
            refreshStats()
        }
    }

    private func syncNow() {
        let context = PersistenceController.shared.container.viewContext
        TranscriptFileManager.shared.syncAllMemos(context: context)
        statusMessage = "✓ Synced local files"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            refreshStats()
            if statusMessage == "✓ Synced local files" {
                statusMessage = nil
            }
        }
    }

    private func refreshStats() {
        stats = TranscriptFileManager.shared.getStats()
    }
}

// MARK: - Auto-Run Settings View

struct AutoRunSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared
    @ObservedObject private var workflowManager = WorkflowManager.shared
    @State private var selectedWorkflowId: UUID?

    private var autoRunWorkflows: [WorkflowDefinition] {
        workflowManager.workflows
            .filter { $0.autoRun }
            .sorted { $0.autoRunOrder < $1.autoRunOrder }
    }

    private var availableWorkflows: [WorkflowDefinition] {
        workflowManager.workflows
            .filter { !$0.autoRun }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "bolt.circle",
                title: "AUTO-RUN",
                subtitle: "Configure workflows that run automatically when memos sync."
            )
        } content: {
            // Master toggle
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settingsManager.autoRunWorkflowsEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Auto-Run Workflows")
                                .font(SettingsManager.shared.fontSMBold)
                            Text("When enabled, workflows marked as auto-run will execute automatically when new memos sync from your iPhone.")
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(16)
                .background(SettingsManager.shared.surface1)
                .cornerRadius(8)

                if settingsManager.autoRunWorkflowsEnabled {
                    Divider()

                    // Auto-run workflows list
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("AUTO-RUN WORKFLOWS")
                                .font(SettingsManager.shared.fontXSBold)
                                .tracking(1)
                                .foregroundColor(.secondary)

                            Spacer()

                            if !availableWorkflows.isEmpty {
                                Menu {
                                    ForEach(availableWorkflows) { workflow in
                                        Button(action: { enableAutoRun(workflow) }) {
                                            Label(workflow.name, systemImage: workflow.icon)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                        Text("Add")
                                    }
                                    .font(SettingsManager.shared.fontXSMedium)
                                }
                            }
                        }

                        if autoRunWorkflows.isEmpty {
                            // Default Hey Talkie workflow info
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "waveform.badge.mic")
                                        .font(.system(size: 16))
                                        .foregroundColor(.purple)
                                        .frame(width: 32, height: 32)
                                        .background(Color.purple.opacity(0.15))
                                        .cornerRadius(6)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Hey Talkie (Default)")
                                            .font(SettingsManager.shared.fontSMBold)
                                        Text("Detects \"Hey Talkie\" voice commands and routes to workflows")
                                            .font(SettingsManager.shared.fontXS)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text("ACTIVE")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                }
                                .padding(12)
                                .background(SettingsManager.shared.surface1)
                                .cornerRadius(8)

                                Text("The default Hey Talkie workflow runs automatically. Add your own workflows to customize.")
                                    .font(SettingsManager.shared.fontXS)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            ForEach(autoRunWorkflows) { workflow in
                                AutoRunWorkflowRow(
                                    workflow: workflow,
                                    onDisable: { disableAutoRun(workflow) },
                                    onMoveUp: autoRunWorkflows.first?.id == workflow.id ? nil : { moveWorkflowUp(workflow) },
                                    onMoveDown: autoRunWorkflows.last?.id == workflow.id ? nil : { moveWorkflowDown(workflow) }
                                )
                            }
                        }
                    }

                    Divider()

                    // How it works
                    VStack(alignment: .leading, spacing: 12) {
                        Text("HOW IT WORKS")
                            .font(SettingsManager.shared.fontXSBold)
                            .tracking(1)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            howItWorksRow(number: "1", text: "Record a memo on iPhone")
                            howItWorksRow(number: "2", text: "Memo syncs to Mac via iCloud")
                            howItWorksRow(number: "3", text: "Auto-run workflows execute in order")
                            howItWorksRow(number: "4", text: "Workflows with trigger steps gate themselves (e.g., \"Hey Talkie\")")
                            howItWorksRow(number: "5", text: "Universal workflows (like indexers) run on all memos")
                        }
                        .padding(12)
                        .background(SettingsManager.shared.surface1)
                        .cornerRadius(8)
                    }
            }
        }
    }

    private func howItWorksRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 16, height: 16)
                .background(Color.accentColor.opacity(0.15))
                .cornerRadius(8)

            Text(text)
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary)
        }
    }

    private func enableAutoRun(_ workflow: WorkflowDefinition) {
        var updated = workflow
        updated.autoRun = true
        updated.autoRunOrder = (autoRunWorkflows.map { $0.autoRunOrder }.max() ?? -1) + 1
        workflowManager.updateWorkflow(updated)
    }

    private func disableAutoRun(_ workflow: WorkflowDefinition) {
        var updated = workflow
        updated.autoRun = false
        updated.autoRunOrder = 0
        workflowManager.updateWorkflow(updated)
    }

    private func moveWorkflowUp(_ workflow: WorkflowDefinition) {
        guard let index = autoRunWorkflows.firstIndex(where: { $0.id == workflow.id }), index > 0 else { return }
        let previous = autoRunWorkflows[index - 1]

        var updatedCurrent = workflow
        var updatedPrevious = previous
        let tempOrder = updatedCurrent.autoRunOrder
        updatedCurrent.autoRunOrder = updatedPrevious.autoRunOrder
        updatedPrevious.autoRunOrder = tempOrder

        workflowManager.updateWorkflow(updatedCurrent)
        workflowManager.updateWorkflow(updatedPrevious)
    }

    private func moveWorkflowDown(_ workflow: WorkflowDefinition) {
        guard let index = autoRunWorkflows.firstIndex(where: { $0.id == workflow.id }), index < autoRunWorkflows.count - 1 else { return }
        let next = autoRunWorkflows[index + 1]

        var updatedCurrent = workflow
        var updatedNext = next
        let tempOrder = updatedCurrent.autoRunOrder
        updatedCurrent.autoRunOrder = updatedNext.autoRunOrder
        updatedNext.autoRunOrder = tempOrder

        workflowManager.updateWorkflow(updatedCurrent)
        workflowManager.updateWorkflow(updatedNext)
    }
}

struct AutoRunWorkflowRow: View {
    let workflow: WorkflowDefinition
    let onDisable: () -> Void
    let onMoveUp: (() -> Void)?
    let onMoveDown: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Reorder buttons
            VStack(spacing: 4) {
                if let moveUp = onMoveUp {
                    Button(action: moveUp) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                if let moveDown = onMoveDown {
                    Button(action: moveDown) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .frame(width: 16)

            // Workflow icon
            Image(systemName: workflow.icon)
                .font(.system(size: 14))
                .foregroundColor(workflow.color.color)
                .frame(width: 28, height: 28)
                .background(workflow.color.color.opacity(0.15))
                .cornerRadius(6)

            // Workflow info
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(SettingsManager.shared.fontSMBold)
                Text(workflow.description.isEmpty ? "\(workflow.steps.count) step(s)" : workflow.description)
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            if workflow.isEnabled {
                Text("ACTIVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            } else {
                Text("DISABLED")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .foregroundColor(.secondary)
                    .cornerRadius(4)
            }

            // Remove button
            Button(action: onDisable) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from auto-run")
        }
        .padding(12)
        .background(SettingsManager.shared.surface1)
        .cornerRadius(8)
    }
}
