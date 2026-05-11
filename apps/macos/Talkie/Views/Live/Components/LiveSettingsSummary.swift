//
//  LiveSettingsSummary.swift
//  Talkie
//
//  Compact read-only summary of current Live settings
//  Updates in real-time as settings change
//

import SwiftUI
import TalkieKit

struct LiveSettingsSummary: View {
    @Environment(AgentSettings.self) private var liveSettings: AgentSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("Top Bar:")
                        .foregroundColor(TalkieTheme.textTertiary)
                    Text(liveSettings.overlayStyle.showsTopOverlay ? "On" : "Off")
                        .foregroundColor(TalkieTheme.textSecondary)
                    if liveSettings.overlayStyle.showsTopOverlay {
                        Text("·")
                            .foregroundColor(TalkieTheme.textMuted)
                        Text(liveSettings.overlayPosition.displayName)
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Recording Pill:")
                        .foregroundColor(TalkieTheme.textTertiary)
                    Text(liveSettings.pillEnabled ? "On" : "Off")
                        .foregroundColor(TalkieTheme.textSecondary)
                    if liveSettings.pillEnabled {
                        Text("·")
                            .foregroundColor(TalkieTheme.textMuted)
                        Text(normalizedPillLabel)
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                }
            }

            HStack(spacing: 4) {
                Text("Sounds:")
                    .foregroundColor(TalkieTheme.textTertiary)
                Text(liveSettings.startSound.displayName)
                    .foregroundColor(TalkieTheme.textSecondary)
                Text("→")
                    .foregroundColor(TalkieTheme.textMuted)
                Text(liveSettings.finishSound.displayName)
                    .foregroundColor(TalkieTheme.textSecondary)
                Text("→")
                    .foregroundColor(TalkieTheme.textMuted)
                Text(liveSettings.pastedSound.displayName)
                    .foregroundColor(TalkieTheme.textSecondary)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(TalkieTheme.surface.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .stroke(TalkieTheme.border.opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    private var normalizedPillLabel: String {
        liveSettings.pillPosition == .topCenter ? PillPosition.bottomCenter.displayName : liveSettings.pillPosition.displayName
    }
}

// MARK: - Preview

#Preview("LiveSettingsSummary") {
    LiveSettingsSummary()
        .environment(AgentSettings.shared)
        .padding(20)
        .background(TalkieTheme.divider)
}
