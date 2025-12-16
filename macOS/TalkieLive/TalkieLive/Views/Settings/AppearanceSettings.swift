//
//  AppearanceSettings.swift
//  TalkieLive
//
//  Appearance settings with theme preview and customization
//

import SwiftUI

// MARK: - Appearance Settings Content (Talkie macOS style)

struct AppearanceSettingsContent: View {
    @ObservedObject var settings: LiveSettings

    // Tactical dark colors
    private let bgColor = Color(red: 0.06, green: 0.06, blue: 0.08)
    private let surfaceColor = Color(red: 0.1, green: 0.1, blue: 0.12)
    private let borderColor = Color(red: 0.15, green: 0.15, blue: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Quick Themes
            quickThemesSection

            // Appearance Mode
            appearanceModeSection

            // Accent Color
            accentColorSection

            // Font Size
            fontSizeSection
        }
    }

    // MARK: - Quick Themes

    private var quickThemesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("QUICK THEMES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            // Live preview
            themePreviewPanel

            // Theme buttons
            HStack(spacing: 6) {
                ForEach(VisualTheme.allCases, id: \.rawValue) { theme in
                    themeButton(theme)
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private var themePreviewPanel: some View {
        HStack(spacing: 0) {
            // Mini sidebar
            VStack(alignment: .leading, spacing: 2) {
                Text("LIVE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(TalkieTheme.textPrimary)
                    .padding(.bottom, 4)

                ForEach(["History", "Console", "Settings"], id: \.self) { item in
                    HStack(spacing: 4) {
                        Image(systemName: item == "History" ? "clock" : (item == "Console" ? "terminal" : "gearshape"))
                            .font(.system(size: 8))
                            .foregroundColor(item == "History" ? settings.accentColor.color : TalkieTheme.textMuted)
                        Text(item)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(item == "History" ? TalkieTheme.textPrimary : TalkieTheme.textTertiary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item == "History" ? settings.accentColor.color.opacity(0.2) : Color.clear)
                    .cornerRadius(3)
                }
            }
            .padding(8)
            .frame(width: 90)
            .background(bgColor)

            Rectangle()
                .fill(borderColor)
                .frame(width: 0.5)

            // Content area
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("TIMESTAMP")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(TalkieTheme.textMuted)
                        .frame(width: 60, alignment: .leading)
                    Text("TEXT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(TalkieTheme.textMuted)
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(TalkieTheme.divider)

                // Sample rows
                ForEach(0..<3, id: \.self) { i in
                    HStack {
                        Text(["12:34", "12:31", "12:28"][i])
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(TalkieTheme.textMuted)
                            .frame(width: 60, alignment: .leading)
                        Text(["Quick memo...", "Meeting notes...", "Recording..."][i])
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(TalkieTheme.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(i == 0 ? settings.accentColor.color.opacity(0.15) : Color.clear)
                }
            }
            .background(bgColor)
        }
        .frame(height: 80)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    private func themeButton(_ theme: VisualTheme) -> some View {
        let isActive = settings.visualTheme == theme

        return Button(action: { settings.applyVisualTheme(theme) }) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.previewColors.bg)
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(theme.previewColors.accent, lineWidth: 1)
                    )
                Text(theme.displayName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isActive ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isActive ? settings.accentColor.color.opacity(0.15) : TalkieTheme.divider)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isActive ? settings.accentColor.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Appearance Mode

    private var appearanceModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APPEARANCE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                    appearanceModeButton(mode)
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private func appearanceModeButton(_ mode: AppearanceMode) -> some View {
        let isSelected = settings.appearanceMode == mode

        return Button(action: { settings.appearanceMode = mode }) {
            VStack(spacing: 6) {
                Image(systemName: mode.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? settings.accentColor.color : .secondary)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? settings.accentColor.color.opacity(0.15) : TalkieTheme.divider)
                    .cornerRadius(8)

                Text(mode.displayName)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Accent Color

    private var accentColorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACCENT COLOR")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6)], spacing: 6) {
                ForEach(AccentColorOption.allCases, id: \.rawValue) { color in
                    accentColorButton(color)
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private func accentColorButton(_ colorOption: AccentColorOption) -> some View {
        let isSelected = settings.accentColor == colorOption

        return Button(action: { settings.accentColor = colorOption }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(colorOption.color)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(TalkieTheme.border, lineWidth: 1)
                    )

                Text(colorOption.displayName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? colorOption.color.opacity(0.15) : TalkieTheme.divider)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? colorOption.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Font Size

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FONT SIZE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(FontSize.allCases, id: \.rawValue) { size in
                    fontSizeButton(size)
                }
            }
        }
        .padding(12)
        .background(surfaceColor)
        .cornerRadius(8)
    }

    private func fontSizeButton(_ size: FontSize) -> some View {
        let isSelected = settings.fontSize == size

        return Button(action: { settings.fontSize = size }) {
            VStack(spacing: 4) {
                Text("Aa")
                    .font(size.bodyFont)  // Use actual scaled font for accurate preview
                    .foregroundColor(isSelected ? settings.accentColor.color : .secondary)

                Text(size.displayName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? settings.accentColor.color.opacity(0.15) : TalkieTheme.divider)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? settings.accentColor.color : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
