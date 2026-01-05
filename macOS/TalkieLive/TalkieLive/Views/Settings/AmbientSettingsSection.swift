//
//  AmbientSettingsSection.swift
//  TalkieLive
//
//  Settings UI for ambient mode configuration.
//

import SwiftUI
import TalkieKit

struct AmbientSettingsSection: View {
    @ObservedObject private var settings = AmbientSettings.shared
    @ObservedObject private var controller = AmbientController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 20))
                        .foregroundColor(TalkieTheme.accent)

                    Text("AMBIENT MODE")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(TalkieTheme.textPrimary)

                    Spacer()

                    // Status badge
                    statusBadge
                }

                Text("Always-on listening with wake word activation")
                    .font(.system(size: 12))
                    .foregroundColor(TalkieTheme.textSecondary)
            }

            // Main toggle
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Ambient Mode")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TalkieTheme.textPrimary)
                        Text("Listen continuously for voice commands")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.isEnabled)
                        .toggleStyle(.switch)
                        .tint(.accentColor)
                        .labelsHidden()
                        .scaleEffect(0.8)
                }
            }

            // Phrases configuration
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("PHRASES")
                        .font(.techLabelSmall)
                        .tracking(Tracking.normal)
                        .foregroundColor(TalkieTheme.textMuted)

                    // Wake phrase
                    phraseRow(
                        label: "Wake phrase",
                        placeholder: "hey talkie",
                        value: $settings.wakePhrase,
                        description: "Say this to start a command"
                    )

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // End phrase
                    phraseRow(
                        label: "End phrase",
                        placeholder: "that's it",
                        value: $settings.endPhrase,
                        description: "Say this to complete a command"
                    )

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Cancel phrase
                    phraseRow(
                        label: "Cancel phrase",
                        placeholder: "never mind",
                        value: $settings.cancelPhrase,
                        description: "Say this to abort a command"
                    )
                }
            }

            // Audio feedback
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Chimes")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TalkieTheme.textPrimary)
                        Text("Play sounds on activation and completion")
                            .font(.system(size: 10))
                            .foregroundColor(TalkieTheme.textTertiary)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.enableChimes)
                        .toggleStyle(.switch)
                        .tint(.accentColor)
                        .labelsHidden()
                        .scaleEffect(0.8)
                }
            }

            // Buffer duration
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("Buffer Duration")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(TalkieTheme.textPrimary)

                        Spacer()

                        Text(formatDuration(settings.bufferDuration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(TalkieTheme.accent)
                    }

                    Text("How much audio history to keep in memory")
                        .font(.system(size: 10))
                        .foregroundColor(TalkieTheme.textTertiary)

                    Slider(
                        value: $settings.bufferDuration,
                        in: 60...600,
                        step: 60
                    )
                    .tint(.accentColor)
                }
            }

            // Reset button
            HStack {
                Spacer()

                Button(action: {
                    settings.resetToDefaults()
                }) {
                    Text("Reset to Defaults")
                        .font(.system(size: 11))
                        .foregroundColor(TalkieTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.lg)
    }

    // MARK: - Components

    @ViewBuilder
    private var statusBadge: some View {
        let (color, text) = statusInfo

        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color.opacity(0.2))
            )
    }

    private var statusInfo: (Color, String) {
        switch controller.state {
        case .disabled:
            return (.gray, "OFF")
        case .listening:
            return (.green, "LISTENING")
        case .command:
            return (.orange, "COMMAND")
        case .processing:
            return (.blue, "PROCESSING")
        case .cancelled:
            return (.gray, "CANCELLED")
        }
    }

    @ViewBuilder
    private func phraseRow(
        label: String,
        placeholder: String,
        value: Binding<String>,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TalkieTheme.textSecondary)

                Spacer()

                TextField(placeholder, text: value)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(TalkieTheme.textPrimary)
                    .frame(width: 150)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                    )
            }

            Text(description)
                .font(.system(size: 9))
                .foregroundColor(TalkieTheme.textTertiary)
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        if minutes == 1 {
            return "1 minute"
        }
        return "\(minutes) minutes"
    }
}

// MARK: - Preview

#Preview {
    AmbientSettingsSection()
        .frame(width: 450, height: 600)
        .background(TalkieTheme.background)
        .preferredColorScheme(.dark)
}
