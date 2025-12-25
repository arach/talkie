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
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("QUICK THEMES")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Apply a curated theme preset with one click.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                    // Preview Label
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "eye")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                        Text("PREVIEW")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                    }
                    .padding(.top, Spacing.xs)

                    // Live preview (top) - sidebar + table - WIDER for better proportions
                    HStack(spacing: 0) {
                        // Mini sidebar
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("TALKIE")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(Theme.current.foreground)
                                .padding(.bottom, Spacing.xs)

                            ForEach(["All Memos", "Recent", "Processed"], id: \.self) { item in
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: item == "All Memos" ? "square.stack" : (item == "Recent" ? "clock" : "checkmark.circle"))
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(item == "All Memos" ? .accentColor : Theme.current.foregroundMuted)
                                    Text(item)
                                        .font(Theme.current.fontSM)
                                        .foregroundColor(item == "All Memos" ? Theme.current.foreground : Theme.current.foregroundSecondary)
                                    Spacer()
                                    if item == "All Memos" {
                                        Text("103")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundMuted)
                                    }
                                }
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.xxs)
                                .background(item == "All Memos" ? Color.accentColor.opacity(Opacity.medium) : Color.clear)
                                .cornerRadius(CornerRadius.xs)
                            }
                        }
                        .padding(Spacing.sm)
                        .frame(width: 155)
                        .background(Theme.current.backgroundSecondary)

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
                                    .frame(width: 100, alignment: .leading)
                                Text("TITLE")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("DUR")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                    .frame(width: 45, alignment: .trailing)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(Theme.current.backgroundSecondary)

                            // Sample rows
                            ForEach(0..<5) { i in
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Theme.current.divider.opacity(Opacity.strong))
                                        .frame(height: 0.5)
                                    HStack(spacing: 0) {
                                        Text(["Nov 30, 11:22", "Nov 29, 15:42", "Nov 29, 12:51", "Nov 28, 21:49", "Nov 28, 19:33"][i])
                                            .font(Theme.current.fontSM)
                                            .foregroundColor(Theme.current.foregroundMuted)
                                            .frame(width: 100, alignment: .leading)
                                        Text(["Recording 2025-11-30", "Quick memo 11/29", "Recording 11/29", "Quick memo 11/28", "Meeting notes"][i])
                                            .font(Theme.current.fontSM)
                                            .foregroundColor(Theme.current.foreground)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(["0:09", "0:34", "0:08", "0:31", "1:04"][i])
                                            .font(Theme.current.fontSM)
                                            .foregroundColor(Theme.current.foregroundMuted)
                                            .frame(width: 45, alignment: .trailing)
                                    }
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xxs)
                                    .background(i == 0 ? Color.accentColor.opacity(Opacity.medium) : Color.clear)
                                }
                            }
                        }
                        .background(Theme.current.backgroundSecondary)
                    }
                    .cornerRadius(Spacing.xs)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.xs)
                            .stroke(Theme.current.divider, lineWidth: 0.5)
                    )

                    // Section divider - tighter spacing
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: Spacing.sm)
                        Rectangle()
                            .fill(Theme.current.divider.opacity(Opacity.half))
                            .frame(height: 1)
                        Spacer()
                            .frame(height: Spacing.xs)
                    }

                    // Themes & Accent - on one line, Mode separate below
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            // Themes
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "paintpalette")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                    Text("THEMES")
                                        .font(Theme.current.fontXSBold)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }

                                HStack(spacing: Spacing.xs) {
                                    ForEach(ThemePreset.allCases, id: \.rawValue) { preset in
                                        Button(action: { settingsManager.applyTheme(preset) }) {
                                            VStack(spacing: Spacing.xs) {
                                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                    .fill(preset.previewColors.bg)
                                                    .frame(width: 32, height: 24)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                            .stroke(preset.previewColors.accent, lineWidth: 1.5)
                                                    )
                                                Text(preset.displayName)
                                                    .font(.system(size: 8, weight: .medium))
                                                    .foregroundColor(isThemeActive(preset) ? Theme.current.foreground : Theme.current.foregroundSecondary)
                                            }
                                            .padding(.horizontal, Spacing.xs)
                                            .padding(.vertical, Spacing.xs)
                                            .background(isThemeActive(preset) ? Color.accentColor.opacity(Opacity.medium) : Color.clear)
                                            .cornerRadius(CornerRadius.xs)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                    .stroke(isThemeActive(preset) ? Color.accentColor : Color.clear, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(Spacing.sm)
                            .background(Theme.current.surface1)
                            .cornerRadius(CornerRadius.sm)

                            // Accent
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "paintbrush.pointed")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                    Text("ACCENT")
                                        .font(Theme.current.fontXSBold)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }

                                HStack(spacing: Spacing.xs) {
                                    ForEach(AccentColorOption.allCases, id: \.rawValue) { colorOption in
                                        accentColorCircle(colorOption)
                                    }
                                }
                            }
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.current.surface1)
                            .cornerRadius(CornerRadius.sm)
                        }

                        // Mode - compact horizontal row
                        HStack(spacing: Spacing.sm) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "moon.stars")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                                Text("MODE")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }

                            HStack(spacing: Spacing.xs) {
                                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                                    Button(action: { settingsManager.appearanceMode = mode }) {
                                        Image(systemName: mode.icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(settingsManager.appearanceMode == mode ? .accentColor : Theme.current.foregroundSecondary)
                                            .frame(width: 28, height: 28)
                                            .background(settingsManager.appearanceMode == mode ? Color.accentColor.opacity(Opacity.medium) : Theme.current.backgroundTertiary)
                                            .cornerRadius(CornerRadius.xs)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                    .stroke(settingsManager.appearanceMode == mode ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(mode.displayName)
                                }
                            }

                            Spacer()
                        }
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)
                    }
                }
                .padding(Spacing.lg)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)

                // MARK: - Typography
                GeometryReader { geometry in
                    let useColumns = geometry.size.width > 800

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("TYPOGRAPHY")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        if useColumns {
                            // 2-column layout for larger screens
                            HStack(alignment: .top, spacing: Spacing.md) {
                                // UI Chrome: Font + Size together
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    HStack(spacing: Spacing.xs) {
                                        Image(systemName: "macwindow")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary)
                                        Text("INTERFACE")
                                            .font(Theme.current.fontXSBold)
                                            .textCase(SettingsManager.shared.uiTextCase)
                                            .foregroundColor(Theme.current.foregroundSecondary)
                                    }

                                    HStack(spacing: Spacing.sm) {
                                        // UI Font
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            Text("Font")
                                                .font(Theme.current.fontXS)
                                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                            HStack(spacing: Spacing.xs) {
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
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            Text("Size")
                                                .font(Theme.current.fontXS)
                                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                            HStack(spacing: Spacing.xs) {
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
                                        HStack(spacing: Spacing.xs) {
                                            Text("ALL CAPS")
                                                .font(Theme.current.fontXS)
                                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                            Text("labels & headers")
                                                .font(Theme.current.fontXS)
                                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
                                        }
                                    }
                                    .toggleStyle(.switch)
                                    .tint(settingsManager.resolvedAccentColor)
                                    .controlSize(.mini)
                                }
                                .padding(Spacing.sm)
                                .frame(maxWidth: .infinity)
                                .background(Theme.current.surface1)
                                .cornerRadius(Spacing.xs)

                                // Content: Font + Size together
                                VStack(alignment: .leading, spacing: Spacing.sm) {
                                    HStack(spacing: Spacing.xs) {
                                        Image(systemName: "doc.text")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary)
                                        Text("TEXT CONTENT")
                                            .font(Theme.current.fontXSBold)
                                            .textCase(SettingsManager.shared.uiTextCase)
                                            .foregroundColor(Theme.current.foregroundSecondary)
                                    }

                                    HStack(spacing: Spacing.sm) {
                                        // Content Font
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            Text("Font")
                                                .font(Theme.current.fontXS)
                                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                            HStack(spacing: Spacing.xs) {
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
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            Text("Size")
                                                .font(Theme.current.fontXS)
                                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                            HStack(spacing: Spacing.xs) {
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
                                .padding(Spacing.sm)
                                .frame(maxWidth: .infinity)
                                .background(Theme.current.surface1)
                                .cornerRadius(Spacing.xs)
                            }
                        } else {
                            // Single column layout for smaller screens
                            // UI Chrome: Font + Size together
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "macwindow")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                    Text("INTERFACE")
                                        .font(Theme.current.fontXSBold)
                                        .textCase(SettingsManager.shared.uiTextCase)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }

                                HStack(spacing: Spacing.sm) {
                                    // UI Font
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text("Font")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                        HStack(spacing: Spacing.xs) {
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
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text("Size")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                        HStack(spacing: Spacing.xs) {
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
                                    HStack(spacing: Spacing.xs) {
                                        Text("ALL CAPS")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                        Text("labels & headers")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
                                    }
                                }
                                .toggleStyle(.switch)
                                .tint(settingsManager.resolvedAccentColor)
                                .controlSize(.mini)
                            }
                            .padding(Spacing.sm)
                            .background(Theme.current.surface1)
                            .cornerRadius(Spacing.xs)

                            // Content: Font + Size together
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "doc.text")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                    Text("TEXT CONTENT")
                                        .font(Theme.current.fontXSBold)
                                        .textCase(SettingsManager.shared.uiTextCase)
                                        .foregroundColor(Theme.current.foregroundSecondary)
                                }

                                HStack(spacing: Spacing.sm) {
                                    // Content Font
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text("Font")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                        HStack(spacing: Spacing.xs) {
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
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text("Size")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                        HStack(spacing: Spacing.xs) {
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
                            .padding(Spacing.sm)
                            .background(Theme.current.surface1)
                            .cornerRadius(Spacing.xs)
                        }

                        // Preview (always full width)
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Preview")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                // UI Font Preview
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text("UI Chrome")
                                        .font(Theme.current.fontXSBold)
                                        .textCase(SettingsManager.shared.uiTextCase)
                                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                    Text(settingsManager.uiAllCaps ? "MEMOS · ACTIONS · 12:34 PM" : "Memos · Actions · 12:34 PM")
                                        .font(settingsManager.themedFont(baseSize: 12))
                                        .foregroundColor(Theme.current.foreground)
                                }

                                Divider()

                                // Content Font Preview
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text("Content")
                                        .font(Theme.current.fontXSBold)
                                        .textCase(SettingsManager.shared.uiTextCase)
                                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                    Text("The quick brown fox jumps over the lazy dog. This is how your transcripts and notes will appear.")
                                        .font(settingsManager.contentFont(baseSize: 13))
                                        .foregroundColor(Theme.current.foreground)
                                }
                            }
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(settingsManager.surfaceInput)
                            .cornerRadius(Spacing.xs)
                            .overlay(
                                RoundedRectangle(cornerRadius: Spacing.xs)
                                    .stroke(Theme.current.foreground.opacity(Opacity.light), lineWidth: 1)
                            )
                        }
                    }
                    .padding(Spacing.lg)
                    .background(Theme.current.surface2)
                    .cornerRadius(CornerRadius.sm)
                }
                .frame(minHeight: 420)

                // Note about accent color
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(Theme.current.fontXS)
                        .foregroundColor(settingsManager.resolvedAccentColor)
                    Text("Accent color applies to Talkie only. System accent color is set in System Settings.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
                .padding(Spacing.sm)
                .background(settingsManager.resolvedAccentColor.opacity(Opacity.light))
                .cornerRadius(Spacing.xs)
        }
    }

    private func accentColorCircle(_ colorOption: AccentColorOption) -> some View {
        Button(action: { settingsManager.accentColor = colorOption }) {
            Circle()
                .fill(colorOption.color ?? .accentColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(settingsManager.accentColor == colorOption ? Color.white : Color.clear, lineWidth: 2)
                )
                .overlay(
                    Circle()
                        .stroke(Theme.current.divider, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(colorOption.displayName)
    }
}

// MARK: - Appearance Mode Button
struct AppearanceModeButton: View {
    let mode: AppearanceMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: mode.icon)
                    .font(Theme.current.fontHeadline)
                    .foregroundColor(isSelected ? .accentColor : Theme.current.foregroundSecondary)
                    .frame(width: 48, height: 48)
                    .background(isSelected ? Color.accentColor.opacity(Opacity.medium) : Theme.current.surface1)
                    .cornerRadius(Spacing.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.sm)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )

                Text(mode.displayName)
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
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
            HStack(spacing: Spacing.xs) {
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
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Color.accentColor.opacity(Opacity.light) : Theme.current.surface1)
            .cornerRadius(Spacing.xs)
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.xs)
                    .stroke(isSelected ? Color.accentColor.opacity(Opacity.half) : Theme.current.foreground.opacity(Opacity.light), lineWidth: 1)
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
            VStack(spacing: Spacing.xs) {
                Image(systemName: style.icon)
                    .font(Theme.current.fontSM)
                    .foregroundColor(isSelected ? .accentColor : Theme.current.foregroundSecondary)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? Color.accentColor.opacity(Opacity.medium) : Theme.current.surface1)
                    .cornerRadius(Spacing.xs)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.xs)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )

                Text(style.displayName)
                    .font(Theme.current.fontXS)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
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
            VStack(spacing: Spacing.xs) {
                Image(systemName: size.icon)
                    .font(Theme.current.fontSM)
                    .foregroundColor(isSelected ? .accentColor : Theme.current.foregroundSecondary)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? Color.accentColor.opacity(Opacity.medium) : Theme.current.surface1)
                    .cornerRadius(Spacing.xs)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.xs)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )

                Text(size.displayName)
                    .font(Theme.current.fontXS)
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 50)
    }
}

// MARK: - Theme Preset Card
struct ThemePresetCard: View {
    let preset: ThemePreset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Preview bar
                HStack(spacing: 0) {
                    preset.previewColors.bg
                        .frame(height: 32)
                        .overlay(
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: preset.icon)
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(preset.previewColors.accent)
                                Text("Aa")
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(preset.previewColors.fg)

                                Spacer()

                                if isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(Theme.current.fontSM)
                                        .foregroundColor(preset.previewColors.accent)
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            , alignment: .leading
                        )
                }
                .cornerRadius(Spacing.xs)

                // Name and description
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(preset.displayName)
                            .font(Theme.current.fontSMBold)
                            .foregroundColor(Theme.current.foreground)

                        if isActive {
                            Text("ACTIVE")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(Theme.current.foreground)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 1)
                                .background(Color.accentColor)
                                .cornerRadius(3)
                        }
                    }

                    Text(preset.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(Spacing.sm)
            .background(isActive ? Color.accentColor.opacity(Opacity.light) : Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(isActive ? Color.accentColor : Theme.current.foreground.opacity(Opacity.light), lineWidth: isActive ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

