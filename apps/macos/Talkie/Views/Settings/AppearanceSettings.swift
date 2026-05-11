//
//  AppearanceSettings.swift
//  Talkie macOS
//
//  Appearance customization: themes, colors, and typography.
//

import SwiftUI

// MARK: - Appearance Settings View
struct AppearanceSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager
    @State private var selectedTypographyContext: TypographyContext = .interface
    @State private var selectedSection: AppearanceSection = .general

    enum TypographyContext: String, CaseIterable {
        case interface = "UI Chrome"
        case content = "Reading"

        var icon: String {
            switch self {
            case .interface: return "sidebar.squares.left"
            case .content: return "text.alignleft"
            }
        }

        var scopeDescription: String {
            switch self {
            case .interface:
                return "Affects navigation, headers, labels, and controls."
            case .content:
                return "Affects transcript, notes, and long-form reading text."
            }
        }
    }

    enum AppearanceSection: String, CaseIterable {
        case general = "GENERAL APPEARANCE"
        case layout = "HOME LAYOUT"

        var icon: String {
            switch self {
            case .general: return "paintbrush"
            case .layout: return "rectangle.grid.2x2"
            }
        }
    }

    /// Check if this theme is the current active theme
    private func isThemeActive(_ preset: ThemePreset) -> Bool {
        return settingsManager.currentTheme == preset
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "paintbrush",
                title: "APPEARANCE",
                subtitle: "Customize visuals, typography, and layout."
            )
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                sectionTabs
                    .padding(.horizontal, Spacing.sm)

                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(height: 1)

                Group {
                    switch selectedSection {
                    case .general:
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            appearanceSection
                            accentColorNote
                        }
                        .padding(.top, Spacing.md)

                    case .layout:
                        HomeLayoutSettingsSection(
                            sectionTitle: "HOME LAYOUT",
                            sectionSubtitle: "Choose the rows and cards visible on your home screen."
                        )
                        .padding(.top, Spacing.md)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sectionTabs: some View {
        HStack(spacing: 0) {
            ForEach(AppearanceSection.allCases, id: \.rawValue) { section in
                let isSelected = selectedSection == section
                Button(action: { selectedSection = section }) {
                    VStack(spacing: Spacing.xxs) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: section.icon)
                                .font(.system(size: 11))
                            Text(section.rawValue)
                                .font(Theme.current.fontXSBold)
                        }
                        .foregroundColor(isSelected ? settingsManager.resolvedAccentColor : Theme.current.foregroundSecondary)
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.xs)

                        Rectangle()
                            .fill(isSelected ? settingsManager.resolvedAccentColor : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Combined Appearance Section

    /// Unified appearance section: Theme + Typography controls card, Preview card (responsive)
    private var appearanceSection: some View {
        @Bindable var settings = settingsManager

        // Use ViewThatFits to switch between horizontal and vertical layouts
        return ViewThatFits(in: .horizontal) {
            // Wide layout: side by side
            HStack(alignment: .top, spacing: Spacing.md) {
                controlsCard
                    .frame(maxWidth: 580)
                previewCard
                    .frame(minWidth: 220, maxWidth: .infinity)
            }

            // Narrow layout: stacked
            VStack(alignment: .leading, spacing: Spacing.md) {
                controlsCard
                previewCard
            }
        }
    }

    /// Controls card containing Theme + Typography settings
    private var controlsCard: some View {
        @Bindable var settings = settingsManager

        return VStack(alignment: .leading, spacing: Spacing.md) {
            // THEME subsection
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("THEME")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                // Mode row
                HStack(spacing: Spacing.sm) {
                    Text("Mode")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 50, alignment: .leading)

                    HStack(spacing: 2) {
                        ForEach(AppearanceMode.allCases, id: \.rawValue) { mode in
                            Button(action: { settingsManager.appearanceMode = mode }) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 12))
                                    Text(mode.displayName)
                                        .font(Theme.current.fontSM)
                                }
                                .foregroundColor(settingsManager.appearanceMode == mode ? .white : Theme.current.foregroundSecondary)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.sm)
                                .background(settingsManager.appearanceMode == mode ? settingsManager.resolvedAccentColor : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.current.backgroundTertiary)
                    .cornerRadius(CornerRadius.sm)

                    Spacer()
                }

                // Style row (wrapping)
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text("Style")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 50, alignment: .leading)
                        .padding(.top, Spacing.xs)

                    WrappingHStack(spacing: Spacing.xs) {
                        ForEach(ThemePreset.allCases, id: \.rawValue) { preset in
                            ThemeTile(
                                preset: preset,
                                isSelected: isThemeActive(preset),
                                action: { settingsManager.applyTheme(preset) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Accent row (wrapping)
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text("Accent")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 50, alignment: .leading)
                        .padding(.top, Spacing.xs)

                    WrappingHStack(spacing: Spacing.xs) {
                        ForEach(AccentColorOption.allCases, id: \.rawValue) { colorOption in
                            AccentColorTile(
                                colorOption: colorOption,
                                isSelected: settingsManager.accentColor == colorOption,
                                action: { settingsManager.accentColor = colorOption }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // TYPOGRAPHY subsection
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("TYPOGRAPHY")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                // Scope row (UI chrome vs content text) - aligned with other rows
                HStack(spacing: Spacing.sm) {
                    Text("Scope")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 50, alignment: .leading)

                    HStack(spacing: 2) {
                        ForEach(TypographyContext.allCases, id: \.self) { context in
                            Button(action: { selectedTypographyContext = context }) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: context.icon)
                                        .font(.system(size: 10))
                                    Text(context.rawValue)
                                        .font(Theme.current.fontXS)
                                }
                                .foregroundColor(selectedTypographyContext == context ? .white : Theme.current.foregroundSecondary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(selectedTypographyContext == context ? settingsManager.resolvedAccentColor : Color.clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.current.backgroundTertiary)
                    .cornerRadius(CornerRadius.xs)

                    Spacer()
                }

                HStack(spacing: Spacing.sm) {
                    Color.clear
                        .frame(width: 50)

                    Text(selectedTypographyContext.scopeDescription)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    Spacer()
                }

                // Font row
                HStack(spacing: Spacing.sm) {
                    Text("Font")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 50, alignment: .leading)

                    let currentFont = selectedTypographyContext == .interface ? settingsManager.uiFontStyle : settingsManager.contentFontStyle
                    Menu {
                        ForEach(FontStyleOption.allCases, id: \.rawValue) { style in
                            Button(action: {
                                if selectedTypographyContext == .interface {
                                    settingsManager.uiFontStyle = style
                                } else {
                                    settingsManager.contentFontStyle = style
                                }
                            }) {
                                HStack {
                                    Image(systemName: style.icon)
                                    Text(style.displayName)
                                    if currentFont == style {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: currentFont.icon)
                                .font(.system(size: 11))
                            Text(currentFont.displayName)
                                .font(Theme.current.fontSM)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                        .foregroundColor(Theme.current.foreground)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Theme.current.backgroundTertiary)
                        .cornerRadius(CornerRadius.xs)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Spacer()
                }

                // Size row
                HStack(spacing: Spacing.sm) {
                    Text("Size")
                        .font(Theme.current.fontSM)
                        .foregroundColor(Theme.current.foregroundSecondary)
                        .frame(width: 50, alignment: .leading)

                    HStack(spacing: 2) {
                        ForEach(FontSizeOption.allCases, id: \.rawValue) { size in
                            let isActive = (selectedTypographyContext == .interface ? settingsManager.uiFontSize : settingsManager.contentFontSize) == size
                            Button(action: {
                                if selectedTypographyContext == .interface {
                                    settingsManager.uiFontSize = size
                                } else {
                                    settingsManager.contentFontSize = size
                                }
                            }) {
                                Text(size.displayName)
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(isActive ? .white : Theme.current.foregroundSecondary)
                                    .padding(.horizontal, Spacing.sm)
                                    .padding(.vertical, Spacing.xs)
                                    .background(isActive ? settingsManager.resolvedAccentColor : Color.clear)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.current.backgroundTertiary)
                    .cornerRadius(CornerRadius.xs)

                    Spacer()
                }

                // All Caps toggle (only for Interface)
                if selectedTypographyContext == .interface {
                    HStack(spacing: Spacing.sm) {
                        Text("Style")
                            .font(Theme.current.fontSM)
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .frame(width: 50, alignment: .leading)

                        Toggle(isOn: $settings.uiAllCaps) {
                            Text("ALL CAPS")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }
                        .toggleStyle(.switch)
                        .tint(settingsManager.resolvedAccentColor)
                        .controlSize(.small)

                        Spacer()
                    }
                }
            }

            Rectangle()
                .fill(Theme.current.divider.opacity(0.7))
                .frame(height: 1)

            ConsoleTerminalAppearanceControls(
                title: "TERMINAL",
                subtitle: "Controls the embedded Ghostty surfaces used in Talkie's console."
            )
        }
        .settingsSectionCard()
    }

    /// Preview card showing theme and typography samples
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("PREVIEW")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            // Component showcase
            themePreviewContent
        }
        .settingsSectionCard()
    }

    /// Theme preview content - showcases actual Talkie UI components
    private var themePreviewContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Row 1: Buttons
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("Buttons")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 50, alignment: .leading)

                HStack(spacing: Spacing.xs) {
                    TalkieButton("Primary", variant: .primary, size: .small) { }
                    TalkieButton("Secondary", variant: .secondary, size: .small) { }
                    TalkieButton("Ghost", variant: .ghost, size: .small) { }
                }
            }

            // Row 2: Status badges
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("Status")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 50, alignment: .leading)
                    .padding(.top, 2)

                HStack(spacing: Spacing.xs) {
                    StatusBadge(.success, "Success", size: .compact)
                    StatusBadge(.warning, "Warning", size: .compact)
                    StatusBadge(.error, "Error", size: .compact)
                    StatusBadge(.pending, "Pending", size: .compact)
                }
            }

            // Row 3: Controls
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("Controls")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 50, alignment: .leading)

                HStack(spacing: Spacing.sm) {
                    Toggle("", isOn: .constant(true))
                        .toggleStyle(.switch)
                        .tint(settingsManager.resolvedAccentColor)
                        .controlSize(.mini)
                        .labelsHidden()

                    Toggle("", isOn: .constant(false))
                        .toggleStyle(.switch)
                        .tint(settingsManager.resolvedAccentColor)
                        .controlSize(.mini)
                        .labelsHidden()

                    // Chip-style selection
                    HStack(spacing: 2) {
                        Text("All")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                            .background(settingsManager.resolvedAccentColor)
                            .cornerRadius(CornerRadius.xs)
                        Text("Memos")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.current.foregroundSecondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 2)
                    }
                    .background(Theme.current.backgroundTertiary)
                    .cornerRadius(CornerRadius.xs)
                }
            }

            // Row 4: Table
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("Table")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 50, alignment: .leading)
                    .padding(.top, 3)

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("TITLE")
                        Spacer()
                        Text("STATUS")
                            .frame(width: 50, alignment: .trailing)
                    }
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 3)

                    Rectangle().fill(Theme.current.divider).frame(height: 0.5)

                    // Rows
                    ForEach(0..<4) { i in
                        HStack {
                            Text(["Meeting notes", "Quick idea", "Project update", "Call summary"][i])
                                .font(.system(size: 9))
                                .foregroundColor(Theme.current.foreground)
                                .lineLimit(1)
                            Spacer()
                            Circle()
                                .fill([Color.green, settingsManager.resolvedAccentColor, Color.orange, Theme.current.foregroundMuted][i])
                                .frame(width: 6, height: 6)
                        }
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 3)
                        .background(i == 0 ? settingsManager.resolvedAccentColor.opacity(Opacity.medium) : Color.clear)

                        if i < 3 {
                            Rectangle().fill(Theme.current.divider.opacity(Opacity.medium)).frame(height: 0.5)
                        }
                    }
                }
                .background(Theme.current.backgroundTertiary)
                .cornerRadius(CornerRadius.xs)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .stroke(Theme.current.divider, lineWidth: 0.5)
                )
            }

            // Row 5: Text/Typography samples
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text("Text")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 50, alignment: .leading)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Heading")
                        .font(settingsManager.themedFont(baseSize: 14))
                        .foregroundColor(Theme.current.foreground)
                    Text("Body text with secondary styling")
                        .font(settingsManager.themedFont(baseSize: 11))
                        .foregroundColor(Theme.current.foregroundSecondary)
                    Text("MUTED · CAPTION · 12:34 PM")
                        .font(settingsManager.themedFont(baseSize: 10))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }
        }
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

// MARK: - Theme Tile

/// Simple theme preview tile
private struct ThemeTile: View {
    let preset: ThemePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                // Theme preview - simple colored square with accent border
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(preset.previewColors.bg)
                    .frame(width: 56, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .stroke(preset.previewColors.accent, lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay(
                        // Small accent indicator
                        RoundedRectangle(cornerRadius: 1)
                            .fill(preset.previewColors.accent)
                            .frame(width: 20, height: 3)
                            .padding(.top, 6),
                        alignment: .top
                    )

                // Label
                Text(preset.displayName)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)
                    .lineLimit(1)
            }
            .padding(Spacing.xs)
            .background(isSelected ? Color.accentColor.opacity(Opacity.medium) : Color.clear)
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Accent Color Tile

/// Simple accent color selector
private struct AccentColorTile: View {
    let colorOption: AccentColorOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Color swatch
                Circle()
                    .fill(colorOption.color ?? .accentColor)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Color.white : Color.clear, lineWidth: 2)
                    )
                    .overlay(
                        Circle()
                            .stroke(Theme.current.divider.opacity(0.3), lineWidth: 0.5)
                    )

                // Label
                Text(colorOption.displayName)
                    .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundMuted)
                    .lineLimit(1)
            }
            .frame(minWidth: 44)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? (colorOption.color ?? .accentColor).opacity(Opacity.medium) : Color.clear)
            .cornerRadius(CornerRadius.xs)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Wrapping HStack

/// A horizontal stack that wraps items to new lines when needed
private struct WrappingHStack<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat = 8, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        _WrappingHStackLayout(spacing: spacing) {
            content()
        }
    }
}

private struct _WrappingHStackLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)

        for (index, subview) in subviews.enumerated() {
            let position = result.positions[index]
            subview.place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: ProposedViewSize(subview.sizeThatFits(.unspecified))
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap to next line
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return (
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}
