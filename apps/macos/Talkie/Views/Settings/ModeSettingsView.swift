//
//  ModeSettingsView.swift
//  Talkie macOS
//
//  Shows the launch detail defaults.
//

import SwiftUI

struct ModeSettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "gauge.with.dots.needle.bottom.100percent",
                title: "DETAIL",
                subtitle: "Talkie launches with the complete settings surface and technical detail enabled."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                launchDetailSection
            }
        }
    }

    private var launchDetailSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                sectionAccent(color: .teal)

                Text("LAUNCH DETAIL")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()
            }

            Text("Mode selection has been folded into the product default.")
                .font(Theme.current.fontXS)
                .foregroundColor(Theme.current.foregroundMuted)

            VStack(spacing: 1) {
                lockedModeRow(
                    icon: "wrench.and.screwdriver",
                    title: "Settings Surface",
                    value: settingsManager.settingsAudience.displayName,
                    detail: "All launch-ready controls are visible."
                )

                lockedModeRow(
                    icon: "cpu",
                    title: "Detail Level",
                    value: settingsManager.detailLevel.displayName,
                    detail: settingsManager.detailLevel.description
                )
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func lockedModeRow(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(settingsManager.resolvedAccentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Theme.current.fontSMBold)
                    .foregroundColor(Theme.current.foreground)

                Text(detail)
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            Text(value.uppercased())
                .font(Theme.current.fontXSBold)
                .foregroundColor(settingsManager.resolvedAccentColor)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(settingsManager.resolvedAccentColor.opacity(0.12))
                .clipShape(.rect(cornerRadius: CornerRadius.xs))
        }
        .padding(.vertical, Spacing.sm)
    }

    private func sectionAccent(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 3, height: 16)
    }
}

#Preview {
    ModeSettingsView()
        .environment(SettingsManager.shared)
        .frame(width: 640, height: 480)
}
