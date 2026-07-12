//
//  AudioSettingsSection.swift
//  TalkieAgent
//
//  Audio settings: microphone selection and troubleshooting
//

import SwiftUI
import TalkieKit

// MARK: - Audio Settings Section

struct AudioSettingsSection: View {
    @ObservedObject private var audioDevices = AudioDeviceManager.shared
    @ObservedObject private var settings = LiveSettings.shared

    private var selectedDeviceName: String {
        let mode = settings.selectedMicrophoneMode
        if mode == .systemDefault {
            return "System Default"
        }
        if let device = audioDevices.inputDevices.first(where: { $0.id == audioDevices.selectedDeviceID }) {
            return device.name
        }
        // Fixed device not available - show saved name with warning indicator
        if let savedName = settings.selectedMicrophoneName {
            return "\(savedName) (unavailable)"
        }
        return "System Default"
    }

    private var isSystemDefaultMode: Bool {
        settings.selectedMicrophoneMode == .systemDefault
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
                                .foregroundColor(AgentTheme.textPrimary)
                            Text("Select which microphone to use for recording")
                                .font(.system(size: 10))
                                .foregroundColor(AgentTheme.textTertiary)
                        }

                        Spacer()

                        Menu {
                            // System Default option
                            Button(action: {
                                audioDevices.selectSystemDefault()
                            }) {
                                HStack {
                                    Text("System Default")
                                    if isSystemDefaultMode {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            Divider()

                            // Specific devices
                            ForEach(audioDevices.inputDevices) { device in
                                Button(action: {
                                    audioDevices.selectDevice(device)
                                }) {
                                    HStack {
                                        Text(device.name)
                                        if device.isDefault {
                                            Text("(default)")
                                                .foregroundColor(.secondary)
                                        }
                                        if !isSystemDefaultMode && device.id == audioDevices.selectedDeviceID {
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
                                    .foregroundColor(AgentTheme.textPrimary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(AgentTheme.textTertiary)
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 6)
                            .background(AgentTheme.surfaceElevated)
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
                                .foregroundColor(AgentTheme.textPrimary)
                            Text("Check input levels, permissions, and fix common issues")
                                .font(.system(size: 10))
                                .foregroundColor(AgentTheme.textTertiary)
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
