//
//  OverlaySettingsSection.swift
//  TalkieAgent
//
//  Overlay settings: top bar, recording pill, and notch takeover
//

import SwiftUI
import TalkieKit

struct OverlaySettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "rectangle.inset.topright.filled",
                title: "VISUAL FEEDBACK",
                subtitle: "TalkieAgent feedback only. Talkie’s larger surface is configured separately."
            )
        } content: {
            SettingsCard(title: "CONTEXT") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("This page controls the small TalkieAgent top bar and recording pill.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textSecondary)

                    Text("Talkie’s larger surface is separate. When Talkie connects, that surface can take over the top edge.")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textTertiary)
                }
            }

            SettingsCard(title: "PREVIEW") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Fixed positions only. Top row = top bar. Bottom row = recording pill.")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)

                    LivePreviewScreen(
                        overlayStyle: $settings.overlayStyle,
                        hudPlacement: $settings.overlayPlacement,
                        pillEnabled: $settings.pillEnabled,
                        pillPlacement: $settings.pillPlacement
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            SettingsCard(title: "TOP BAR") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SettingsToggleRow(
                        icon: "sparkles",
                        title: "Show top bar",
                        description: "Particle feedback at the top edge",
                        isOn: Binding(
                            get: { settings.overlayStyle.showsTopOverlay },
                            set: { show in
                                settings.overlayStyle = show ? .particles : .pillOnly
                            }
                        )
                    )

                    Rectangle()
                        .fill(Design.divider)
                        .frame(height: 0.5)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Position")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textSecondary)

                        AgentOverlayPositionRow(placement: $settings.overlayPlacement)
                    }
                    .padding(.leading, 28)
                    .opacity(settings.overlayStyle.showsTopOverlay ? 1.0 : 0.45)

                    Text("Particles are the only top-bar style here. If Talkie’s larger surface is active, it replaces this top bar.")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textTertiary)
                        .padding(.leading, 28)
                }
            }

            SettingsCard(title: "RECORDING PILL") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SettingsToggleRow(
                        icon: "capsule",
                        title: "Show recording pill",
                        description: "Persistent recording indicator",
                        isOn: $settings.pillEnabled
                    )

                    Rectangle()
                        .fill(Design.divider)
                        .frame(height: 0.5)

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Position")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textSecondary)

                        AgentPillPositionRow(placement: $settings.pillPlacement)
                    }
                    .padding(.leading, 28)
                    .opacity(settings.pillEnabled ? 1.0 : 0.45)
                    .disabled(!settings.pillEnabled)
                }
            }

            if NotchInfo.detect().hasNotch {
                SettingsCard(title: "NOTCH") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SettingsToggleRow(
                            icon: "macbook",
                            title: "Notch overlay",
                            description: "Show recording animation around the notch",
                            isOn: $settings.notchOverlayEnabled
                        )

                        Text("This is optional. Turn it off if you only want the top bar and recording pill.")
                            .font(.system(size: 9))
                            .foregroundColor(TalkieTheme.textTertiary)
                            .padding(.leading, 28)
                    }
                }
            }
        }
        .onAppear {
            normalizeSettings()
        }
    }

    private func normalizeSettings() {
        if settings.overlayStyle.showsTopOverlay, settings.overlayStyle != .particles {
            settings.overlayStyle = .particles
        }

        if settings.pillPosition == .topCenter {
            settings.pillPosition = .bottomCenter
        }
    }
}

private struct AgentOverlayPositionRow: View {
    @Binding var placement: NormalizedPlacement

    var body: some View {
        HStack(spacing: 6) {
            AgentPositionButton(
                title: "Left",
                isSelected: placement.nearestIndicatorPosition == .topLeft
            ) {
                placement = .init(indicatorPosition: .topLeft)
            }

            AgentPositionButton(
                title: "Center",
                isSelected: placement.nearestIndicatorPosition == .topCenter
            ) {
                placement = .init(indicatorPosition: .topCenter)
            }

            AgentPositionButton(
                title: "Right",
                isSelected: placement.nearestIndicatorPosition == .topRight
            ) {
                placement = .init(indicatorPosition: .topRight)
            }
        }
    }
}

private struct AgentPillPositionRow: View {
    @Binding var placement: NormalizedPlacement

    private var selectedPosition: PillPosition {
        let nearest = placement.nearestPillPosition
        return nearest == .topCenter ? .bottomCenter : nearest
    }

    var body: some View {
        HStack(spacing: 6) {
            AgentPositionButton(
                title: "Left",
                isSelected: selectedPosition == .bottomLeft
            ) {
                placement = .init(pillPosition: .bottomLeft)
            }

            AgentPositionButton(
                title: "Center",
                isSelected: selectedPosition == .bottomCenter
            ) {
                placement = .init(pillPosition: .bottomCenter)
            }

            AgentPositionButton(
                title: "Right",
                isSelected: selectedPosition == .bottomRight
            ) {
                placement = .init(pillPosition: .bottomRight)
            }
        }
    }
}

private struct AgentPositionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isSelected ? .white : TalkieTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.cyan.opacity(0.82) : (isHovered ? TalkieTheme.hover : TalkieTheme.surface))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.cyan : TalkieTheme.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
