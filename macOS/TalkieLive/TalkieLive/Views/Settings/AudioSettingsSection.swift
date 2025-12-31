//
//  AudioSettingsSection.swift
//  TalkieLive
//
//  Audio settings: microphone selection and troubleshooting
//

import SwiftUI
import TalkieKit

// MARK: - Audio Settings Section

struct AudioSettingsSection: View {
    @ObservedObject private var audioDevices = AudioDeviceManager.shared

    private var selectedDeviceName: String {
        if let device = audioDevices.inputDevices.first(where: { $0.id == audioDevices.selectedDeviceID }) {
            return device.name
        } else if let defaultDevice = audioDevices.inputDevices.first(where: { $0.isDefault }) {
            return defaultDevice.name
        }
        return "System Default"
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "mic",
                title: "AUDIO",
                subtitle: "Microphone selection and audio troubleshooting."
            )
        } content: {
            // Microphone Selection
            SettingsCard(title: "MICROPHONE") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Input Device")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Select which microphone to use for recording")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Menu {
                            ForEach(audioDevices.inputDevices) { device in
                                Button(action: {
                                    audioDevices.selectDevice(device.id)
                                }) {
                                    HStack {
                                        Text(device.name)
                                        if device.isDefault {
                                            Text("(System Default)")
                                                .foregroundColor(.secondary)
                                        }
                                        if device.id == audioDevices.selectedDeviceID {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(selectedDeviceName)
                                    .font(.system(size: 11))
                                    .foregroundColor(TalkieTheme.textPrimary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(TalkieTheme.textTertiary)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(TalkieTheme.surfaceElevated)
                            .cornerRadius(CornerRadius.xs)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }

            // Troubleshooting
            SettingsCard(title: "TROUBLESHOOTING") {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Audio Diagnostics")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(TalkieTheme.textPrimary)
                            Text("Check input levels, permissions, and fix common issues")
                                .font(.system(size: 10))
                                .foregroundColor(TalkieTheme.textTertiary)
                        }

                        Spacer()

                        Button(action: {
                            AudioTroubleshooterController.shared.show()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 11))
                                Text("Run Diagnostics")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                                        .fill(Color.accentColor.opacity(0.1))
                                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                                }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
