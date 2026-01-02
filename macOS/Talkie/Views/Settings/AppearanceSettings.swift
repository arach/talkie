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
            // MARK: - Appearance Mode
            appearanceModeSection

            // MARK: - Preview
            previewSection

            // MARK: - Themes & Accent
            themesAndAccentSection

            // MARK: - Typography
            typographySection

            // Note about accent color
            accentColorNote
        }
    }

    // MARK: - Sections

    private var appearanceModeSection: some View {
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
                            Text(mode.displayName)
                                .font(Theme.current.fontSM)
                        }
                        .foregroundColor(settingsManager.appearanceMode == mode ? .accentColor : Theme.current.foregroundSecondary)
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
        .settingsSectionCard()
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PREVIEW")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            // Live preview - simplified adaptive layout
            HStack(spacing: 0) {
                // Mini sidebar - proportional width
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
                                .lineLimit(1)
                            Spacer(minLength: 0)
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
                .frame(minWidth: 100, maxWidth: 160)
                .background(Theme.current.backgroundSecondary)

                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(width: 0.5)

                // Table - flexible width
                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: Spacing.sm) {
                        Text("TIMESTAMP")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Spacer()
                        Text("TITLE")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)
                        Spacer()
                        Text("DUR")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Theme.current.backgroundSecondary)

                    // Sample rows
                    ForEach(0..<3) { i in
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Theme.current.divider.opacity(Opacity.strong))
                                .frame(height: 0.5)
                            HStack(spacing: Spacing.sm) {
                                Text(["Nov 30", "Nov 29", "Nov 28"][i])
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foregroundMuted)
                                    .lineLimit(1)
                                Text(["Recording", "Quick memo", "Notes"][i])
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foreground)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(["0:09", "0:34", "1:04"][i])
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xxs)
                            .background(i == 0 ? Color.accentColor.opacity(Opacity.medium) : Color.clear)
                        }
                    }
                }
                .background(Theme.current.backgroundSecondary)
            }
            .cornerRadius(CornerRadius.xs)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .stroke(Theme.current.divider, lineWidth: 0.5)
            )
        }
        .settingsSectionCard()
    }

    private var themesAndAccentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("THEMES & ACCENT")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            // Themes
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Themes")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                // Wrap themes in a flexible flow
                HStack(spacing: Spacing.xs) {
                    ForEach(ThemePreset.allCases, id: \.rawValue) { preset in
                        Button(action: { settingsManager.applyTheme(preset) }) {
                            VStack(spacing: Spacing.xs) {
                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                    .fill(preset.previewColors.bg)
                                    .aspectRatio(1.2, contentMode: .fit)
                                    .frame(minWidth: 36, maxWidth: 48)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                                            .stroke(preset.previewColors.accent, lineWidth: 2)
                                    )
                                Text(preset.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(isThemeActive(preset) ? Theme.current.foreground : Theme.current.foregroundSecondary)
                                    .lineLimit(1)
                            }
                            .padding(Spacing.xs)
                            .background(isThemeActive(preset) ? Color.accentColor.opacity(Opacity.medium) : Color.clear)
                            .cornerRadius(CornerRadius.xs)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.xs)
                                    .stroke(isThemeActive(preset) ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Accent Colors
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Accent Color")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)

                HStack(spacing: Spacing.xs) {
                    ForEach(AccentColorOption.allCases, id: \.rawValue) { colorOption in
                        Button(action: { settingsManager.accentColor = colorOption }) {
                            VStack(spacing: Spacing.xs) {
                                Circle()
                                    .fill(colorOption.color ?? .accentColor)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(settingsManager.accentColor == colorOption ? Color.white : Color.clear, lineWidth: 2)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(Theme.current.divider, lineWidth: 0.5)
                                    )
                                Text(colorOption.displayName)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(settingsManager.accentColor == colorOption ? Theme.current.foreground : Theme.current.foregroundSecondary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, Spacing.xs)
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
                    Spacer(minLength: 0)
                }
            }
        }
        .settingsSectionCard()
    }

    private var typographySection: some View {
        @Bindable var settings = settingsManager

        return VStack(alignment: .leading, spacing: Spacing.sm) {
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
                Spacer(minLength: 0)
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
                        Spacer(minLength: 0)
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
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
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
                        Spacer(minLength: 0)
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

                    Group {
                        if selectedTypographyContext == .interface {
                            Text(settingsManager.uiAllCaps ? "MEMOS · ACTIONS · 12:34 PM" : "Memos · Actions · 12:34 PM")
                                .font(settingsManager.themedFont(baseSize: 12))
                        } else {
                            Text("The quick brown fox jumps over the lazy dog.")
                                .font(settingsManager.contentFont(baseSize: 13))
                        }
                    }
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
        .settingsSectionCard()
    }

    private var accentColorNote: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "info.circle")
                .font(Theme.current.fontXS)
                .foregroundColor(settingsManager.resolvedAccentColor)
            Text("Accent color applies to Talkie only. System accent color is set in System Settings.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(Spacing.sm)
        .liquidGlassCard(cornerRadius: CornerRadius.xs, tint: settingsManager.resolvedAccentColor.opacity(Opacity.light))
    }
}
