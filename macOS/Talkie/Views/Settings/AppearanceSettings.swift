//
//  AppearanceSettings.swift
//  Talkie macOS
//
//  Extracted from SettingsView.swift
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

// MARK: - Appearance Settings View
struct AppearanceSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager

    /// Check if this theme is the current active theme
    private func isThemeActive(_ preset: ThemePreset) -> Bool {
        return settingsManager.currentTheme == preset
    }

    var body: some View {
        @Bindable var settings = settingsManager

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
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Apply a curated theme preset with one click.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    // Preview Label
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.7))
                        Text("PREVIEW")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .padding(.top, 4)

                    // Live preview (top) - sidebar + table
                    HStack(spacing: 0) {
                        // Mini sidebar
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TALKIE")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(SettingsManager.shared.tacticalForeground)
                                .padding(.bottom, 4)

                            ForEach(["All Memos", "Recent", "Processed"], id: \.self) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: item == "All Memos" ? "square.stack" : (item == "Recent" ? "clock" : "checkmark.circle"))
                                        .font(SettingsManager.shared.fontXS)
                                        .foregroundColor(item == "All Memos" ? .accentColor : Theme.current.foregroundMuted)
                                    Text(item)
                                        .font(SettingsManager.shared.fontSM)
                                        .foregroundColor(item == "All Memos" ? SettingsManager.shared.tacticalForeground : Theme.current.foregroundSecondary)
                                    Spacer()
                                    if item == "All Memos" {
                                        Text("103")
                                            .font(SettingsManager.shared.fontXS)
                                            .foregroundColor(Theme.current.foregroundMuted)
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
                            .fill(Theme.current.divider)
                            .frame(width: 0.5)

                        // Table
                        VStack(spacing: 0) {
                            // Header row
                            HStack(spacing: 0) {
                                Text("TIMESTAMP")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .frame(width: 90, alignment: .leading)
                                Text("TITLE")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("DUR")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.current.backgroundSecondary)

                            // Sample rows
                            ForEach(0..<5) { i in
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Theme.current.divider.opacity(0.3))
                                        .frame(height: 0.5)
                                    HStack(spacing: 0) {
                                        Text(["Nov 30, 11:22", "Nov 29, 15:42", "Nov 29, 12:51", "Nov 28, 21:49", "Nov 28, 19:33"][i])
                                            .font(SettingsManager.shared.fontSM)
                                            .foregroundColor(Theme.current.foregroundMuted)
                                            .frame(width: 90, alignment: .leading)
                                        Text(["Recording 2025-11-30", "Quick memo 11/29", "Recording 11/29", "Quick memo 11/28", "Meeting notes"][i])
                                            .font(SettingsManager.shared.fontSM)
                                            .foregroundColor(SettingsManager.shared.tacticalForeground)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(["0:09", "0:34", "0:08", "0:31", "1:04"][i])
                                            .font(SettingsManager.shared.fontSM)
                                            .foregroundColor(Theme.current.foregroundMuted)
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
                            .stroke(Theme.current.divider, lineWidth: 0.5)
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
                                .background(isThemeActive(preset) ? Color.accentColor.opacity(0.15) : Theme.current.backgroundTertiary)
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
                .background(Theme.current.surface2)
                .cornerRadius(8)

                // MARK: - Theme Mode + Accent Color (side-by-side on larger screens)
                GeometryReader { geometry in
                    let useColumns = geometry.size.width > 700

                    if useColumns {
                        HStack(alignment: .top, spacing: 12) {
                            // Appearance Mode
                            VStack(alignment: .leading, spacing: 12) {
                                Text("APPEARANCE")
                                    .font(Theme.current.fontXSBold)
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
                            .frame(maxWidth: .infinity)
                            .background(Theme.current.surface2)
                            .cornerRadius(8)

                            // Accent Color
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ACCENT COLOR")
                                    .font(Theme.current.fontXSBold)
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
                            .frame(maxWidth: .infinity)
                            .background(Theme.current.surface2)
                            .cornerRadius(8)
                        }
                    } else {
                        VStack(spacing: 12) {
                            // Appearance Mode
                            VStack(alignment: .leading, spacing: 12) {
                                Text("APPEARANCE")
                                    .font(Theme.current.fontXSBold)
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
                            .background(Theme.current.surface2)
                            .cornerRadius(8)

                            // Accent Color
                            VStack(alignment: .leading, spacing: 12) {
                                Text("ACCENT COLOR")
                                    .font(Theme.current.fontXSBold)
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
                            .background(Theme.current.surface2)
                            .cornerRadius(8)
                        }
                    }
                }
                .frame(height: 200)

                // MARK: - Typography
                GeometryReader { geometry in
                    let useColumns = geometry.size.width > 800

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TYPOGRAPHY")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary)

                        if useColumns {
                            // 2-column layout for larger screens
                            HStack(alignment: .top, spacing: 10) {
                                // UI Chrome: Font + Size together
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("UI Chrome")
                                        .font(Theme.current.fontXSBold)
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
                                    Toggle(isOn: $settings.uiAllCaps) {
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
                                .frame(maxWidth: .infinity)
                                .background(Theme.current.surface1)
                                .cornerRadius(6)

                                // Content: Font + Size together
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Content")
                                        .font(Theme.current.fontXSBold)
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
                                .frame(maxWidth: .infinity)
                                .background(Theme.current.surface1)
                                .cornerRadius(6)
                            }
                        } else {
                            // Single column layout for smaller screens
                            // UI Chrome: Font + Size together
                            VStack(alignment: .leading, spacing: 8) {
                                Text("UI Chrome")
                                    .font(Theme.current.fontXSBold)
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
                                Toggle(isOn: $settings.uiAllCaps) {
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
                            .background(Theme.current.surface1)
                            .cornerRadius(6)

                            // Content: Font + Size together
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Content")
                                    .font(Theme.current.fontXSBold)
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
                            .background(Theme.current.surface1)
                            .cornerRadius(6)
                        }

                        // Preview (always full width)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Preview")
                                .font(SettingsManager.shared.fontXS)
                                .foregroundColor(.secondary.opacity(0.8))

                            VStack(alignment: .leading, spacing: 12) {
                                // UI Font Preview
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("UI Chrome")
                                        .font(Theme.current.fontXSBold)
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
                                        .font(Theme.current.fontXSBold)
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
                    .background(Theme.current.surface2)
                    .cornerRadius(8)
                }
                .frame(minHeight: 420)

                // Note about accent color
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(settingsManager.resolvedAccentColor)
                    Text("Accent color applies to Talkie only. System accent color is set in System Settings.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(settingsManager.resolvedAccentColor.opacity(0.1))
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
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Theme.current.surface1)
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
private struct AccentColorButton: View {
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
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Theme.current.surface1)
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
                    .background(isSelected ? Color.accentColor.opacity(0.15) : Theme.current.surface1)
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
            .background(isSelected ? Color.accentColor.opacity(0.15) : Theme.current.surface1)
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
            .background(isActive ? Color.accentColor.opacity(0.1) : Theme.current.surface1)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

