//
//  OverlaySettingsSection.swift
//  TalkieLive
//
//  Overlay settings: HUD overlay, floating pill, visual feedback
//

import SwiftUI
import TalkieKit

// MARK: - Overlay Settings Section

struct OverlaySettingsSection: View {
    @ObservedObject private var settings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "rectangle.inset.topright.filled",
                title: "VISUAL FEEDBACK",
                subtitle: "Configure HUD overlay and floating pill positions."
            )
        } content: {
            // Interactive Preview (from TalkieKit)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("PREVIEW")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1)
                        .foregroundColor(TalkieTheme.textSecondary)

                    Spacer()

                    Text("Hover to simulate recording")
                        .font(.system(size: 9))
                        .foregroundColor(TalkieTheme.textTertiary)
                }

                LivePreviewScreen(
                    overlayStyle: $settings.overlayStyle,
                    hudPosition: $settings.overlayPosition,
                    pillPosition: $settings.pillPosition,
                    showOnAir: $settings.showOnAir
                )
                .frame(maxWidth: .infinity)
                .scaleEffect(0.85)
                .frame(height: 230)
            }
            .padding(.bottom, Spacing.md)

            // HUD Settings
            SettingsCard(title: "HUD OVERLAY") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    // Toggle HUD
                    SettingsToggleRow(
                        icon: "sparkles",
                        title: "Show HUD overlay",
                        description: "Animated feedback at top of screen",
                        isOn: Binding(
                            get: { settings.overlayStyle.showsTopOverlay },
                            set: { show in
                                settings.overlayStyle = show ? .particles : .pillOnly
                            }
                        )
                    )

                    if settings.overlayStyle.showsTopOverlay {
                        Rectangle()
                            .fill(Design.divider)
                            .frame(height: 0.5)

                        // Style selector
                        HStack(spacing: Spacing.sm) {
                            Text("Style")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textSecondary)

                            LiveStyleSelector(selection: $settings.overlayStyle)
                        }
                        .padding(.leading, 28)
                    }

                    Rectangle()
                        .fill(Design.divider)
                        .frame(height: 0.5)

                    // ON AIR toggle
                    SettingsToggleRow(
                        icon: "record.circle",
                        title: "Show ON AIR indicator",
                        description: "Neon sign in corner during recording",
                        isOn: $settings.showOnAir
                    )
                }
            }

            // Pill Settings
            SettingsCard(title: "FLOATING PILL") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SettingsToggleRow(
                        icon: "timer",
                        title: "Expand during recording",
                        description: "Show timer and audio level",
                        isOn: $settings.pillExpandsDuringRecording
                    )

                    Rectangle()
                        .fill(Design.divider)
                        .frame(height: 0.5)

                    SettingsToggleRow(
                        icon: "display.2",
                        title: "Show on all screens",
                        description: "Display on every connected monitor",
                        isOn: $settings.pillShowOnAllScreens
                    )
                }
            }
        }
    }
}

// MARK: - Overlay Section Header

struct OverlaySectionHeader: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(SemanticColor.info)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.xs)
    }
}

// MARK: - Indicator Position Row

struct IndicatorPositionRow: View {
    let position: IndicatorPosition
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(position.description)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// MARK: - Pill Position Row

struct PillPositionRow: View {
    let position: PillPosition
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(position.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textPrimary)

                Text(position.description)
                    .font(.system(size: 9))
                    .foregroundColor(TalkieTheme.textTertiary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? TalkieTheme.hover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .onHover { isHovered = $0 }
    }
}

// Note: SettingsToggleRow and WhisperModelRow are defined in SettingsView.swift
