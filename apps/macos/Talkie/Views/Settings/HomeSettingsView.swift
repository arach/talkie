//
//  HomeSettingsView.swift
//  Talkie macOS
//
//  Home screen widget and layout customization
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

struct HomeSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "house",
                title: "HOME",
                subtitle: "Customize your home screen layout and widgets."
            )
        } content: {
            HomeLayoutSettingsSection(
                sectionTitle: "HOME LAYOUT",
                sectionSubtitle: "Customize your home screen layout and widgets."
            )
        }
        .onAppear {
            log.debug("HomeSettingsView appeared")
        }
    }
}

struct HomeLayoutSettingsSection: View {
    @Environment(SettingsManager.self) private var settingsManager

    let sectionTitle: String
    let sectionSubtitle: String

    init(
        sectionTitle: String = "HOME LAYOUT",
        sectionSubtitle: String = "Customize your home screen rows and cards."
    ) {
        self.sectionTitle = sectionTitle
        self.sectionSubtitle = sectionSubtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            sectionHeader(title: sectionTitle, subtitle: sectionSubtitle, color: .blue)

            rowVisibilitySection

            ForEach(settingsManager.homeLayoutConfig.visibleRows) { rowType in
                cardVisibilitySection(for: rowType)
            }
        }
    }

    private var rowVisibilitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(title: "ROWS", subtitle: "Choose which sections appear on home", color: .blue)

            VStack(spacing: Spacing.xs) {
                ForEach(HomeRowType.allCases.filter { $0 != .brand && $0 != .setup }) { rowType in
                    HomeLayoutRowToggle(
                        rowType: rowType,
                        isEnabled: settingsManager.homeLayoutConfig.isRowVisible(rowType),
                        onToggle: {
                            var config = settingsManager.homeLayoutConfig
                            config.toggleRow(rowType)
                            settingsManager.homeLayoutConfig = config
                        }
                    )
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func cardVisibilitySection(for rowType: HomeRowType) -> some View {
        let visibleCards = settingsManager.homeLayoutConfig.visibleCardsForRow(rowType)
        let allCards = rowType.availableCards

        return VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(
                title: rowType.displayName.uppercased(),
                subtitle: "\(visibleCards.count)/\(allCards.count) visible",
                color: colorForRowType(rowType)
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.sm),
                    GridItem(.flexible(), spacing: Spacing.sm)
                ],
                spacing: Spacing.sm
            ) {
                ForEach(allCards, id: \.rawValue) { cardType in
                    HomeLayoutCardToggle(
                        cardType: cardType,
                        isEnabled: settingsManager.homeLayoutConfig.isCardVisible(cardType),
                        onToggle: {
                            var config = settingsManager.homeLayoutConfig
                            config.toggleCard(cardType)
                            settingsManager.homeLayoutConfig = config
                        }
                    )
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func sectionHeader(title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3, height: 14)

            Text(title)
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)

            Spacer()

            Text(subtitle.uppercased())
                .font(.techLabelSmall)
                .foregroundColor(Theme.current.foregroundMuted)
        }
    }

    private func colorForRowType(_ rowType: HomeRowType) -> Color {
        switch rowType {
        case .brand: return .purple
        case .stats: return .cyan
        case .actions: return .orange
        case .devices: return .indigo
        case .widgets: return .green
        case .features: return .teal
        case .recent: return .blue
        case .setup: return .gray
        }
    }
}

private struct HomeLayoutRowToggle: View {
    let rowType: HomeRowType
    let isEnabled: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.md) {
                Image(systemName: rowType.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isEnabled ? .accentColor : Theme.current.foregroundMuted)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rowType.displayName)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(isEnabled ? Theme.current.foreground : Theme.current.foregroundSecondary)

                    Text(rowType.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isEnabled ? .accentColor : Theme.current.foregroundMuted)
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(isHovered ? Theme.current.surfaceHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct HomeLayoutCardToggle: View {
    let cardType: HomeCardType
    let isEnabled: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: cardType.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isEnabled ? .accentColor : Theme.current.foregroundMuted)
                    .frame(width: 20)

                Text(cardType.displayName)
                    .font(Theme.current.fontSM)
                    .foregroundColor(isEnabled ? Theme.current.foreground : Theme.current.foregroundSecondary)

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(isEnabled ? .accentColor : Theme.current.foregroundMuted)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .fill(isEnabled ? Color.accentColor.opacity(0.1) : (isHovered ? Theme.current.surfaceHover : Theme.current.surface1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.xs)
                    .stroke(isEnabled ? Color.accentColor.opacity(0.3) : Theme.current.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    HomeSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 600, height: 700)
}
