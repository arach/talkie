//
//  AppearancePickerNext.swift
//  Talkie iOS
//
//  INTENTIONAL REDESIGN — not a port. The legacy SettingsView's
//  appearance section is a radio-button list inside the larger
//  settings tree. This surface deliberately redesigns it as a
//  standalone theme browser with preview cards that render each
//  theme's actual chrome tokens — selection becomes a visual
//  comparison, not a label list.
//
//  Caveats:
//  - The rest of the legacy Settings tree (Bridge, Keyboard, AI
//    providers, etc.) is not surfaced here. Routed-from-Home gear
//    intentionally lands on appearance only for now.
//  - The chrome miniatures are a design vocabulary, not a port.
//
//  Five themes (Scope · Midnight · Tactical · Ghost · Lift). Tap
//  swaps ThemeManager.shared.currentTheme.
//

import SwiftUI

struct AppearancePickerNext: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 14) {
                    AppearanceModeRow()
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

                    HStack(spacing: 6) {
                        Text("· THEME")
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.colors.textTertiary)
                        Spacer()
                        Text(theme.currentTheme.displayName.uppercased())
                            .talkieType(.channelLabelTiny)
                            .foregroundStyle(theme.currentTheme.chrome.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    VStack(spacing: 10) {
                        ForEach(AppTheme.allCases) { themeOption in
                            ThemePreviewCard(themeOption: themeOption,
                                             isActive: themeOption == theme.currentTheme,
                                             onSelect: {
                                                 withAnimation(.easeOut(duration: 0.2)) {
                                                     theme.currentTheme = themeOption
                                                 }
                                             })
                        }
                    }
                    .padding(.horizontal, 12)

                    Spacer(minLength: 80)
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack {
            Button(action: { AppShellRouter.shared.openHome() }) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14))
                    Text("Done")
                        .talkieType(.preview)
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Appearance")
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)

            Spacer()

            Color.clear.frame(width: 44, height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(theme.currentTheme.chrome.edgeFaint)
                .frame(height: theme.currentTheme.chrome.hairlineWidth),
            alignment: .bottom
        )
    }
}

// MARK: - Appearance mode (system / light / dark) — segmented

private struct AppearanceModeRow: View {
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("· APPEARANCE MODE")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, 4)

            HStack(spacing: 0) {
                ForEach(AppearanceMode.allCases) { mode in
                    let isActive = (theme.appearanceMode == mode)
                    Button(action: { theme.appearanceMode = mode }) {
                        HStack(spacing: 5) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 11, weight: .medium))
                            Text(mode.displayName)
                                .talkieType(.fieldLabel)
                        }
                        .foregroundStyle(isActive
                            ? theme.colors.cardBackground
                            : theme.colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isActive ? theme.currentTheme.chrome.accent : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                Capsule()
                    .fill(theme.colors.cardBackground)
                    .overlay(Capsule().strokeBorder(
                        theme.currentTheme.chrome.edgeFaint,
                        lineWidth: theme.currentTheme.chrome.hairlineWidth
                    ))
            )
        }
    }
}

// MARK: - Theme preview card

private struct ThemePreviewCard: View {
    let themeOption: AppTheme
    let isActive: Bool
    let onSelect: () -> Void

    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        Button(action: onSelect) {
            cardContent
        }
        .buttonStyle(CardPressStyle())
    }

    private var cardContent: some View {
        HStack(spacing: 12) {
                // Mini chrome render with the option's tokens
                ThemeMiniature(themeOption: themeOption)
                    .frame(width: 80, height: 100)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(themeOption.displayName)
                            .talkieType(.listTitle)
                            .foregroundStyle(theme.colors.textPrimary)
                        if isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.currentTheme.chrome.accent)
                        }
                    }

                    Text(themeOption.description)
                        .talkieType(.fieldLabel)
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        ThemeTokenChip(label: cornerLabel, value: themeOption)
                        ThemeTokenChip(label: edgeLabel, value: themeOption)
                    }
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                isActive
                                    ? theme.currentTheme.chrome.accentStrong
                                    : theme.currentTheme.chrome.edgeFaint,
                                lineWidth: isActive ? 1.5 : theme.currentTheme.chrome.hairlineWidth
                            )
                    )
            )
    }

    private var cornerLabel: String {
        let c = themeOption.chrome.chromeCorner
        if c == 0 { return "SQUARE" }
        if c <= 4 { return "TIGHT" }
        return "ROUND"
    }

    private var edgeLabel: String {
        let g = themeOption.chrome.glowRadius
        if g <= 1.5 { return "MATTE" }
        if g <= 4 { return "SOFT" }
        return "DIFFUSE"
    }
}

private struct ThemeTokenChip: View {
    let label: String
    let value: AppTheme

    var body: some View {
        Text(label)
            .talkieType(.channelLabelTiny)
            .foregroundStyle(value.chrome.accent.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(value.chrome.accentTint)
            )
    }
}

// MARK: - Miniature theme render

private struct ThemeMiniature: View {
    let themeOption: AppTheme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(themeOption.colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(themeOption.chrome.edgeFaint, lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Faux card with hairline
                RoundedRectangle(cornerRadius: themeOption.chrome.chromeCorner + 4)
                    .fill(themeOption.colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: themeOption.chrome.chromeCorner + 4)
                            .strokeBorder(themeOption.chrome.edgeFaint, lineWidth: themeOption.chrome.hairlineWidth)
                    )
                    .frame(height: 28)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)

                // Faux text lines
                VStack(alignment: .leading, spacing: 3) {
                    line(width: 60)
                    line(width: 44)
                }
                .padding(.horizontal, 10)

                Spacer()

                // Faux voice button
                Circle()
                    .fill(themeOption.colors.cardBackground)
                    .overlay(Circle().strokeBorder(themeOption.chrome.accentStrong, lineWidth: 1))
                    .frame(width: 16, height: 16)
                    .shadow(color: themeOption.chrome.accentGlow,
                            radius: themeOption.chrome.glowRadius,
                            y: 1)
                    .padding(8)
            }
        }
    }

    private func line(width: CGFloat) -> some View {
        Capsule()
            .fill(themeOption.colors.textSecondary.opacity(0.45))
            .frame(width: width, height: 2.5)
    }
}
