//
//  SettingsView.swift
//  Talkie macOS
//
//  Settings and workflow management UI (inspired by EchoFlow)
//

import SwiftUI
import CloudKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var settingsManager = SettingsManager.shared
    @State private var apiKeyInput: String = ""
    @State private var showingSaveConfirmation = false

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List {
                Section("APPEARANCE") {
                    NavigationLink(destination: AppearanceSettingsView()) {
                        Label {
                            Text("Theme & Colors")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        } icon: {
                            Image(systemName: "paintbrush")
                                .font(.system(size: 11))
                                .frame(width: 16)
                        }
                    }
                }

                Section("WORKFLOWS") {
                    NavigationLink(destination: QuickActionsSettingsView()) {
                        Label {
                            Text("Quick Actions")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        } icon: {
                            Image(systemName: "bolt.circle")
                                .font(.system(size: 11))
                                .frame(width: 16)
                        }
                    }
                }

                Section("API & PROVIDERS") {
                    NavigationLink(destination: APISettingsView(settingsManager: settingsManager)) {
                        Label {
                            Text("API Keys")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        } icon: {
                            Image(systemName: "key")
                                .font(.system(size: 11))
                                .frame(width: 16)
                        }
                    }
                }

                Section("SHELL & OUTPUT") {
                    NavigationLink(destination: AllowedCommandsView()) {
                        Label {
                            Text("Allowed Commands")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        } icon: {
                            Image(systemName: "terminal")
                                .font(.system(size: 11))
                                .frame(width: 16)
                        }
                    }

                    NavigationLink(destination: OutputSettingsView()) {
                        Label {
                            Text("Output & Aliases")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        } icon: {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .frame(width: 16)
                        }
                    }
                }

                Section("DATA & FILES") {
                    NavigationLink(destination: LocalFilesSettingsView()) {
                        Label {
                            Text("Local Files")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        } icon: {
                            Image(systemName: "folder.badge.person.crop")
                                .font(.system(size: 11))
                                .frame(width: 16)
                        }
                    }
                }

                Section("DEBUG") {
                    NavigationLink(destination: DebugInfoView()) {
                        Label {
                            Text("Debug Info")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        } icon: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .frame(width: 16)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            // Default detail view
            VStack(spacing: 20) {
                Image(systemName: "gear")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("SELECT A SETTING")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }
}

// MARK: - Appearance Settings View
struct AppearanceSettingsView: View {
    @ObservedObject private var settingsManager = SettingsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "paintbrush")
                            .font(.system(size: 16))
                        Text("APPEARANCE")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Customize how Talkie looks on your Mac.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                // MARK: - Theme Presets
                VStack(alignment: .leading, spacing: 12) {
                    Text("QUICK THEMES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    Text("Apply a curated theme preset with one click.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(ThemePreset.allCases, id: \.rawValue) { preset in
                            ThemePresetCard(
                                preset: preset,
                                action: { settingsManager.applyTheme(preset) }
                            )
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                // MARK: - Theme Mode
                VStack(alignment: .leading, spacing: 12) {
                    Text("APPEARANCE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                // MARK: - Accent Color
                VStack(alignment: .leading, spacing: 12) {
                    Text("ACCENT COLOR")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    Text("Used for buttons, selections, and highlights.")
                        .font(.system(size: 10, design: .monospaced))
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
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                // MARK: - Typography
                VStack(alignment: .leading, spacing: 12) {
                    Text("TYPOGRAPHY")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    // Font Style
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Font Style")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))

                        HStack(spacing: 8) {
                            ForEach(FontStyleOption.allCases, id: \.rawValue) { style in
                                FontStyleButton(
                                    style: style,
                                    isSelected: settingsManager.fontStyle == style,
                                    action: { settingsManager.fontStyle = style }
                                )
                            }
                        }
                    }

                    Divider()

                    // Font Size
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Font Size")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))

                        HStack(spacing: 8) {
                            ForEach(FontSizeOption.allCases, id: \.rawValue) { size in
                                FontSizeButton(
                                    size: size,
                                    isSelected: settingsManager.fontSize == size,
                                    action: { settingsManager.fontSize = size }
                                )
                            }
                        }
                    }

                    // Preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text("The quick brown fox jumps over the lazy dog.")
                                .font(settingsManager.themedFont(baseSize: 13))
                            Text("0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ")
                                .font(settingsManager.themedFont(baseSize: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                // Note about accent color
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text("Accent color applies to Talkie only. System accent color is set in System Settings.")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(6)

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
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
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 48, height: 48)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
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
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
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
            VStack(spacing: 6) {
                Image(systemName: style.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(style.displayName)
                    .font(.system(size: 9, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 70)
    }
}

// MARK: - Font Size Button
struct FontSizeButton: View {
    let size: FontSizeOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: size.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(size.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Preset Card
struct ThemePresetCard: View {
    let preset: ThemePreset
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
                                    .font(.system(size: 10))
                                    .foregroundColor(preset.previewColors.accent)
                                Text("Aa")
                                    .font(.system(size: 11, weight: .medium, design: preset.fontStyle == .monospace ? .monospaced : (preset.fontStyle == .rounded ? .rounded : .default)))
                                    .foregroundColor(preset.previewColors.fg)
                            }
                            .padding(.horizontal, 10)
                            , alignment: .leading
                        )
                }
                .cornerRadius(6)

                // Name and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.displayName)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)

                    Text(preset.description)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "key")
                            .font(.system(size: 16))
                        Text("API KEYS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Manage API keys for cloud AI providers. Keys are stored securely in the macOS Keychain.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

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

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
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
                    .font(.system(size: 14))
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
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue.opacity(0.5), lineWidth: 1)
                        )

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .buttonStyle(.bordered)

                    Button(action: onSave) {
                        Text("Save")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if isConfigured {
                // Display mode with key
                HStack(spacing: 8) {
                    // Key display
                    HStack(spacing: 8) {
                        Text(isRevealed ? (currentKey ?? "") : maskedKey)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        // Reveal button
                        Button(action: onReveal) {
                            Image(systemName: isRevealed ? "eye.slash" : "eye")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isRevealed ? "Hide API key" : "Reveal API key")
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)

                    Button(action: onEdit) {
                        Text("Edit")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .buttonStyle(.bordered)

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
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
                                .font(.system(size: 10))
                            Text("Add API Key")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Link(destination: URL(string: helpURL)!) {
                        HStack(spacing: 4) {
                            Text("Get key")
                                .font(.system(size: 9, design: .monospaced))
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 8))
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
                            .font(.system(size: 16))
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
        .background(Color(NSColor.textBackgroundColor))
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
                .font(.system(size: 20))
                .foregroundColor(installed ? .blue : .secondary)
                .frame(width: 32, height: 32)
                .background(Color(NSColor.controlBackgroundColor))
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
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            // Status/Action
            if installed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("INSTALLED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.green)
                }
            } else {
                Button(action: {}) {
                    Text("DOWNLOAD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
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
        .background(Color(NSColor.controlBackgroundColor))
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
                            .font(.system(size: 16))
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
        .background(Color(NSColor.textBackgroundColor))
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
                            .font(.system(size: 16))
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
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Allowed Commands View
struct AllowedCommandsView: View {
    @State private var newCommandPath: String = ""
    @State private var customCommands: [String] = []
    @State private var showingWhichResult: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 16))
                        Text("ALLOWED COMMANDS")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Manage which CLI tools can be executed by workflow shell steps.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                // Add new command
                VStack(alignment: .leading, spacing: 12) {
                    Text("ADD COMMAND")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TextField("/path/to/executable", text: $newCommandPath)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)

                        Button(action: findCommand) {
                            Text("WHICH")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                            Text(result)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                    }

                    Text("Enter the full path to the executable (e.g., /Users/you/.bun/bin/claude)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider()

                // Custom commands
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR CUSTOM COMMANDS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)

                                Text(path)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)

                                Spacer()

                                Button(action: { removeCommand(path) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red.opacity(0.7))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }

                Divider()

                // Default commands (collapsed)
                VStack(alignment: .leading, spacing: 12) {
                    Text("BUILT-IN COMMANDS (\(ShellStepConfig.defaultAllowedExecutables.count))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    DisclosureGroup {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                            ForEach(ShellStepConfig.defaultAllowedExecutables.sorted(), id: \.self) { path in
                                Text(path)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } label: {
                        Text("Show built-in allowed commands")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("OUTPUT SETTINGS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    Text("Configure default output location and path aliases for workflows.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

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
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .help("Browse for folder")

                        Button(action: saveDirectory) {
                            Text("Save")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    // Current value display
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                        Text(SaveFileStepConfig.defaultOutputDirectory)
                            .font(.system(size: 9, design: .monospaced))
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
                            .font(.system(size: 10, design: .monospaced))
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
                            .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)

                        Button(action: createDirectory) {
                            HStack(spacing: 4) {
                                Image(systemName: "folder.badge.plus")
                                Text("Create Folder")
                            }
                            .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)

                        Button(action: resetToDefault) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Default")
                            }
                            .font(.system(size: 10))
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
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.secondary)

                        Text("Define shortcuts like @Obsidian, @Notes to use in file paths")
                            .font(.system(size: 10))
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
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)

                                    // Path
                                    Text(path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Spacer()

                                    // Delete button
                                    Button(action: { removeAlias(alias) }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary.opacity(0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.controlBackgroundColor))
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
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)

                            Button(action: addAlias) {
                                Text("Add")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newAliasName.isEmpty || newAliasPath.isEmpty)
                        }
                    }

                    // Usage hint
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text("Use in Save File step directory: @Obsidian/Voice Notes")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(6)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.textBackgroundColor))
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
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
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
    @State private var pinnedWorkflowIDs: Set<UUID> = QuickActionsConfig.pinnedWorkflowIDs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("QUICK ACTIONS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.secondary)

                    Text("Pin workflows to show them as quick actions when viewing a memo.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Pinned workflows
                VStack(alignment: .leading, spacing: 12) {
                    Text("PINNED WORKFLOWS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    if pinnedWorkflows.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "pin.slash")
                                .foregroundColor(.secondary)
                            Text("No workflows pinned")
                                .foregroundColor(.secondary)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(pinnedWorkflows) { workflow in
                                workflowRow(workflow, isPinned: true)
                            }
                        }
                    }
                }

                Divider()

                // Available workflows
                VStack(alignment: .leading, spacing: 12) {
                    Text("AVAILABLE WORKFLOWS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary)

                    if unpinnedWorkflows.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                            Text("All workflows are pinned")
                                .foregroundColor(.secondary)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(unpinnedWorkflows) { workflow in
                                workflowRow(workflow, isPinned: false)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.textBackgroundColor))
    }

    private var pinnedWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { pinnedWorkflowIDs.contains($0.id) }
    }

    private var unpinnedWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { !pinnedWorkflowIDs.contains($0.id) }
    }

    @ViewBuilder
    private func workflowRow(_ workflow: WorkflowDefinition, isPinned: Bool) -> some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: workflow.icon)
                .font(.system(size: 14))
                .foregroundColor(workflow.color.color)
                .frame(width: 24, height: 24)
                .background(workflow.color.color.opacity(0.15))
                .cornerRadius(6)

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                Text(workflow.description)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Pin/unpin button
            Button(action: { togglePin(workflow) }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12))
                    .foregroundColor(isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "Unpin from quick actions" : "Pin to quick actions")
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func togglePin(_ workflow: WorkflowDefinition) {
        if pinnedWorkflowIDs.contains(workflow.id) {
            pinnedWorkflowIDs.remove(workflow.id)
        } else {
            pinnedWorkflowIDs.insert(workflow.id)
        }
        QuickActionsConfig.pinnedWorkflowIDs = pinnedWorkflowIDs
    }
}

// MARK: - Quick Actions Configuration

enum QuickActionsConfig {
    private static let pinnedKey = "TalkiePinnedWorkflowIDs"

    static var pinnedWorkflowIDs: Set<UUID> {
        get {
            guard let data = UserDefaults.standard.data(forKey: pinnedKey),
                  let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) else {
                return []
            }
            return ids
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: pinnedKey)
            }
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 16))
                        Text("DEBUG INFO")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Diagnostic information about the app environment.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

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
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
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
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.person.crop")
                            .font(.system(size: 16))
                        Text("LOCAL FILES")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.primary)

                    Text("Store your transcripts and audio files locally on your Mac.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Value proposition - always visible
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                        Text("YOUR DATA, YOUR FILES")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.green)
                    }

                    Text("Local files are stored as plain text (Markdown) and standard audio formats. You can open, edit, backup, or move them freely. No lock-in, full portability.")
                        .font(.system(size: 10, design: .monospaced))
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
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                Text("Save Transcripts Locally")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            HStack(spacing: 4) {
                                Text("Save as Markdown with YAML frontmatter.")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Link("File format", destination: URL(string: "https://talkie.jdi.do/docs/file-format")!)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }
                    }
                    .toggleStyle(.switch)
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
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                                .help("Browse for folder")

                                Button(action: { TranscriptFileManager.shared.openTranscriptsFolderInFinder() }) {
                                    Image(systemName: "arrow.up.forward.square")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                                .help("Open in Finder")
                            }
                        }
                        .padding(.leading, 24)
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                // MARK: - Audio Section
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settingsManager.saveAudioLocally) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 12))
                                    .foregroundColor(.purple)
                                Text("Save Audio Files Locally")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                            }
                            Text("Copy M4A audio recordings to your local folder.")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
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
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                                .help("Browse for folder")

                                Button(action: { TranscriptFileManager.shared.openAudioFolderInFinder() }) {
                                    Image(systemName: "arrow.up.forward.square")
                                        .font(.system(size: 12))
                                }
                                .buttonStyle(.bordered)
                                .help("Open in Finder")
                            }

                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                                Text("Audio files can take significant disk space")
                                    .font(.system(size: 9, design: .monospaced))
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
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                // Stats and actions (only show if any local files enabled)
                if settingsManager.localFilesEnabled {
                    Divider()

                    // Stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FILE STATISTICS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.secondary)

                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(stats.transcripts)")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.blue)
                                Text("Transcripts")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(stats.audioFiles)")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.purple)
                                Text("Audio Files")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                                Text("Total Size")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }

                    // Quick actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("QUICK ACTIONS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button(action: syncNow) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Sync Now")
                                }
                                .font(.system(size: 10))
                            }
                            .buttonStyle(.bordered)

                            Button(action: refreshStats) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Refresh Stats")
                                }
                                .font(.system(size: 10))
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
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(6)
                    }
                }

                Spacer()
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
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
