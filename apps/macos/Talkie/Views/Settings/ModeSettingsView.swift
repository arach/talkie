//
//  ModeSettingsView.swift
//  Talkie macOS
//
//  Controls settings visibility and information density.
//

import SwiftUI

struct ModeSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "slider.horizontal.3",
                title: "MODE",
                subtitle: "Choose which settings Talkie exposes and how much detail it shows across the UI."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                settingsAudienceSection
                detailLevelSection
            }
        }
    }

    private var settingsAudienceSection: some View {
        @Bindable var settings = settingsManager

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                sectionAccent(color: .teal)

                Text("SETTINGS VISIBILITY")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()
            }

            Text("Controls which sections appear in Settings navigation.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(spacing: Spacing.sm) {
                ForEach(SettingsAudience.allCases, id: \.self) { audience in
                    ModeAudienceCard(
                        audience: audience,
                        isSelected: settings.settingsAudience == audience,
                        isProToolsActive: audience == .pro && settings.isProToolsActive,
                        onSelect: {
                            if audience == .pro {
                                if settings.isProToolsActive {
                                    settings.settingsAudience = audience
                                } else {
                                    ProOnboardingManager.shared.shouldShowProOnboarding = true
                                }
                            } else {
                                settings.settingsAudience = audience
                            }
                        }
                    )
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var detailLevelSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                sectionAccent(color: .orange)

                Text("DETAIL LEVEL")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()
            }

            Text("Controls how much context, diagnostics, and technical information appears inside views.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            HStack(alignment: .center, spacing: Spacing.sm) {
                Text("Level")
                    .font(Theme.current.fontSM)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .frame(width: 56, alignment: .leading)

                HStack(spacing: 2) {
                    ForEach(DetailLevel.allCases, id: \.rawValue) { level in
                        Button(action: { settingsManager.detailLevel = level }) {
                            Text(level.displayName)
                                .font(Theme.current.fontXS)
                                .foregroundColor(settingsManager.detailLevel == level ? .white : Theme.current.foregroundSecondary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xs)
                                .background(settingsManager.detailLevel == level ? settingsManager.resolvedAccentColor : Color.clear)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Theme.current.backgroundTertiary)
                .cornerRadius(CornerRadius.xs)

                Spacer()
            }

            HStack(alignment: .top, spacing: Spacing.sm) {
                Color.clear
                    .frame(width: 56)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(settingsManager.detailLevel.description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    if settingsManager.detailLevel == .max {
                        Text("Technical shows the most context, diagnostics, and implementation detail.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func sectionAccent(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 3, height: 16)
    }
}

private struct ModeAudienceCard: View {
    let audience: SettingsAudience
    let isSelected: Bool
    var isProToolsActive: Bool = false
    let onSelect: () -> Void

    @State private var isHovered = false

    private var icon: String {
        switch audience {
        case .simple: return "gearshape"
        case .advanced: return "slider.horizontal.3"
        case .pro: return isProToolsActive ? "checkmark.seal.fill" : "wrench.and.screwdriver"
        }
    }

    private var accentColor: Color {
        if audience == .pro && !isProToolsActive {
            return .orange
        }
        return .teal
    }

    private var description: String {
        switch audience {
        case .simple: return "Core controls only."
        case .advanced: return "More configuration and diagnostics."
        case .pro:
            return isProToolsActive ? "Pro Tools active." : "Set up Pro Tools."
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Rectangle()
                    .fill(accentColor.opacity(isSelected ? 1.0 : 0.2))
                    .frame(height: 3)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? accentColor : Theme.current.foregroundMuted)

                    Text(audience.displayName)
                        .font(Theme.current.fontSMBold)
                        .foregroundColor(isSelected ? Theme.current.foreground : Theme.current.foregroundSecondary)

                    Text(description)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, Spacing.sm)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? Theme.current.surface2 : Theme.current.surface1)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(isSelected ? accentColor.opacity(0.6) : Theme.current.divider, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ModeSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 640, height: 480)
}
