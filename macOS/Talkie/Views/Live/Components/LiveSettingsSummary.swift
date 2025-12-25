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
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: HUD + Pill
            HStack(spacing: 0) {
                // HUD info
                HStack(spacing: 4) {
                    Text("HUD:")
                        .foregroundColor(TalkieTheme.textTertiary)
                    Text(liveSettings.overlayStyle.showsTopOverlay ? liveSettings.overlayStyle.displayName : "Off")
                        .foregroundColor(TalkieTheme.textSecondary)
                    if liveSettings.overlayStyle.showsTopOverlay {
                        Text("·")
                            .foregroundColor(TalkieTheme.textMuted)
                        Text(liveSettings.overlayPosition.displayName)
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                }

                Spacer()

                // Pill info
                HStack(spacing: 4) {
                    Text("Pill:")
                        .foregroundColor(TalkieTheme.textTertiary)
                    Text(liveSettings.pillPosition.displayName)
                        .foregroundColor(TalkieTheme.textSecondary)
                    if liveSettings.pillExpandsDuringRecording {
                        Text("·")
                            .foregroundColor(TalkieTheme.textMuted)
                        Text("Expands")
                            .foregroundColor(TalkieTheme.textTertiary)
                    }
                }
            }

            // Line 2: Sounds
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
}

// MARK: - Preview

#Preview("LiveSettingsSummary") {
    LiveSettingsSummary()
        .environment(LiveSettings.shared)
        .padding(20)
        .background(TalkieTheme.divider)
}
