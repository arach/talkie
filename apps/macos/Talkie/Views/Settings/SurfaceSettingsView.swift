//
//  SurfaceSettingsView.swift
//  Talkie
//
//  Compatibility destination for links to the retired Talkie-owned surface.
//  Live overlay presentation is owned by TalkieAgent.
//

import SwiftUI

struct SurfaceSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "rectangle.topthird.inset.filled",
                title: "LIVE OVERLAY",
                subtitle: "The recording and capture surface is now managed by Talkie Agent."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ownershipCard
                behaviorCard
            }
        }
    }

    private var ownershipCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("ONE LIVE SURFACE", systemImage: "sparkles.rectangle.stack")
                .font(Theme.current.fontSM.weight(.semibold))
                .foregroundStyle(Theme.current.foreground)

            Text("Talkie Agent owns the menu-bar overlay, recording feedback, and capture status. Talkie no longer runs a second notch renderer behind it.")
                .font(Theme.current.fontSM)
                .foregroundStyle(Theme.current.foregroundSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open Talkie Agent Settings", systemImage: "arrow.up.right") {
                ServiceManager.shared.live.showSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsSectionCard(padding: Spacing.lg)
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("WHAT MOVED", systemImage: "arrow.triangle.branch")
                .font(Theme.current.fontSM.weight(.semibold))
                .foregroundStyle(Theme.current.foreground)

            settingRow(
                icon: "waveform",
                title: "Recording feedback",
                detail: "Shape, placement, and reactivity live with the Agent overlay."
            )
            settingRow(
                icon: "camera.viewfinder",
                title: "Capture feedback",
                detail: "Screenshot and screen-recording state use the same surface owner."
            )
            settingRow(
                icon: "rectangle.on.rectangle",
                title: "Camera bubble",
                detail: "Size, shape, and screen placement remain in Capture settings."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsSectionCard(padding: Spacing.lg)
    }

    private func settingRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(Theme.current.accent)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(Theme.current.fontSM.weight(.medium))
                    .foregroundStyle(Theme.current.foreground)
                Text(detail)
                    .font(Theme.current.fontXS)
                    .foregroundStyle(Theme.current.foregroundSecondary)
            }
        }
    }
}
