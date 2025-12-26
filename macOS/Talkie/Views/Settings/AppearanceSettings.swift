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
    @State private var selectedTypographyContext: TypographyContext = .interface

    enum TypographyContext: String, CaseIterable {
        case interface = "Interface"
        case content = "Content"
    }

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
            VStack(alignment: .leading, spacing: Spacing.md) {
                // MARK: - Appearance Mode
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("APPEARANCE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(spacing: Spacing.xs) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                            Button(action: { settingsManager.appearanceMode = mode }) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 13))
                                        .foregroundColor(settingsManager.appearanceMode == mode ? .accentColor : Theme.current.foregroundSecondary)
                                    Text(mode.displayName)
                                        .font(Theme.current.fontSM)
                                        .foregroundColor(settingsManager.appearanceMode == mode ? .accentColor : Theme.current.foregroundSecondary)
                                }
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(settingsManager.appearanceMode == mode ? Color.accentColor.opacity(Opacity.medium) : Theme.current.backgroundTertiary)
                                .cornerRadius(CornerRadius.xs)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                                        .stroke(settingsManager.appearanceMode == mode ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Spacing.lg)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)

                // MARK: - Preview
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("PREVIEW")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    // Live preview - sidebar + table
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
                }
                .padding(Spacing.lg)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)

                // MARK: - Themes & Accent
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("THEMES & ACCENT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(alignment: .top, spacing: Spacing.md) {
                        // Themes
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Themes")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            HStack(alignment: .top, spacing: Spacing.xs) {
                                ForEach(ThemePreset.allCases, id: \.rawValue) { preset in
                                    Button(action: { settingsManager.applyTheme(preset) }) {
                                        VStack(spacing: Spacing.xs) {
                                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                .fill(preset.previewColors.bg)
                                                .frame(width: 44, height: 36)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                        .stroke(preset.previewColors.accent, lineWidth: 2)
                                                )
                                            Text(preset.displayName)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(isThemeActive(preset) ? Theme.current.foreground : Theme.current.foregroundSecondary)
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .frame(width: 60)
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

                        // Accent Colors - fixed width, top aligned
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Accent Color")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            HStack(alignment: .top, spacing: Spacing.xs) {
                                ForEach(AccentColorOption.allCases, id: \.rawValue) { colorOption in
                                    Button(action: { settingsManager.accentColor = colorOption }) {
                                        VStack(spacing: Spacing.xs) {
                                            Circle()
                                                .fill(colorOption.color ?? .accentColor)
                                                .frame(width: 36, height: 36)
                                                .overlay(
                                                    Circle()
                                                        .stroke(settingsManager.accentColor == colorOption ? Color.white : Color.clear, lineWidth: 2)
                                                )
                                                .overlay(
                                                    Circle()
                                                        .stroke(Theme.current.divider, lineWidth: 0.5)
                                                )
                                            Text(colorOption.displayName)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(settingsManager.accentColor == colorOption ? Theme.current.foreground : Theme.current.foregroundSecondary)
                                                .fixedSize(horizontal: true, vertical: false)
                                        }
                                        .frame(width: 64)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, Spacing.xs)
                                        .background(settingsManager.accentColor == colorOption ? Color.accentColor.opacity(Opacity.medium) : Color.clear)
                                        .cornerRadius(CornerRadius.xs)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                .stroke(settingsManager.accentColor == colorOption ? Color.accentColor : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Spacing.lg)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)

                // MARK: - Typography
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("TYPOGRAPHY")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    // Context Selector (Interface vs Content)
                    HStack(spacing: Spacing.xs) {
                        ForEach(TypographyContext.allCases, id: \.self) { context in
                            Button(action: { selectedTypographyContext = context }) {
                                Text(context.rawValue)
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(selectedTypographyContext == context ? .accentColor : Theme.current.foregroundSecondary)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
                                    .background(selectedTypographyContext == context ? Color.accentColor.opacity(Opacity.medium) : Theme.current.backgroundTertiary)
                                    .cornerRadius(CornerRadius.xs)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                                            .stroke(selectedTypographyContext == context ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Font & Size Pickers
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        // Font Style
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Font")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            HStack(spacing: Spacing.xs) {
                                ForEach(FontStyleOption.allCases, id: \.rawValue) { style in
                                    Button(action: {
                                        if selectedTypographyContext == .interface {
                                            settingsManager.uiFontStyle = style
                                        } else {
                                            settingsManager.contentFontStyle = style
                                        }
                                    }) {
                                        HStack(spacing: Spacing.xs) {
                                            Image(systemName: style.icon)
                                                .font(.system(size: 13))
                                            Text(style.displayName)
                                                .font(Theme.current.fontSM)
                                        }
                                        .foregroundColor(
                                            (selectedTypographyContext == .interface ? settingsManager.uiFontStyle : settingsManager.contentFontStyle) == style
                                            ? .accentColor : Theme.current.foregroundSecondary
                                        )
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, Spacing.xs)
                                        .background(
                                            (selectedTypographyContext == .interface ? settingsManager.uiFontStyle : settingsManager.contentFontStyle) == style
                                            ? Color.accentColor.opacity(Opacity.medium) : Theme.current.backgroundTertiary
                                        )
                                        .cornerRadius(CornerRadius.xs)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                .stroke(
                                                    (selectedTypographyContext == .interface ? settingsManager.uiFontStyle : settingsManager.contentFontStyle) == style
                                                    ? Color.accentColor : Color.clear,
                                                    lineWidth: 1.5
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Font Size
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Size")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            HStack(spacing: Spacing.xs) {
                                ForEach(FontSizeOption.allCases, id: \.rawValue) { size in
                                    Button(action: {
                                        if selectedTypographyContext == .interface {
                                            settingsManager.uiFontSize = size
                                        } else {
                                            settingsManager.contentFontSize = size
                                        }
                                    }) {
                                        Text(size.displayName)
                                            .font(Theme.current.fontSM)
                                            .foregroundColor(
                                                (selectedTypographyContext == .interface ? settingsManager.uiFontSize : settingsManager.contentFontSize) == size
                                                ? .accentColor : Theme.current.foregroundSecondary
                                            )
                                            .frame(width: 44, height: 32)
                                            .background(
                                                (selectedTypographyContext == .interface ? settingsManager.uiFontSize : settingsManager.contentFontSize) == size
                                                ? Color.accentColor.opacity(Opacity.medium) : Theme.current.backgroundTertiary
                                            )
                                            .cornerRadius(CornerRadius.xs)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                                    .stroke(
                                                        (selectedTypographyContext == .interface ? settingsManager.uiFontSize : settingsManager.contentFontSize) == size
                                                        ? Color.accentColor : Color.clear,
                                                        lineWidth: 1.5
                                                    )
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // All Caps (only for Interface)
                        if selectedTypographyContext == .interface {
                            Toggle(isOn: $settings.uiAllCaps) {
                                Text("All caps labels & headers")
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foregroundSecondary)
                            }
                            .toggleStyle(.switch)
                            .tint(settingsManager.resolvedAccentColor)
                            .controlSize(.small)
                        }

                        // Preview
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Preview")
                                .font(Theme.current.fontSM)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            if selectedTypographyContext == .interface {
                                Text(settingsManager.uiAllCaps ? "MEMOS · ACTIONS · 12:34 PM" : "Memos · Actions · 12:34 PM")
                                    .font(settingsManager.themedFont(baseSize: 12))
                                    .foregroundColor(Theme.current.foreground)
                                    .padding(Spacing.sm)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(settingsManager.surfaceInput)
                                    .cornerRadius(CornerRadius.xs)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                                            .stroke(Theme.current.foreground.opacity(Opacity.light), lineWidth: 1)
                                    )
                            } else {
                                Text("The quick brown fox jumps over the lazy dog. This is how your transcripts and notes will appear.")
                                    .font(settingsManager.contentFont(baseSize: 13))
                                    .foregroundColor(Theme.current.foreground)
                                    .padding(Spacing.sm)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(settingsManager.surfaceInput)
                                    .cornerRadius(CornerRadius.xs)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                                            .stroke(Theme.current.foreground.opacity(Opacity.light), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)

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
    }
}
