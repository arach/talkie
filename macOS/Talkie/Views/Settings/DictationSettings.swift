//
//  DictationSettings.swift
//  Talkie
//
//  Dictation settings - Capture and Output configuration
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "DictationSettings")

// MARK: - Dictation Capture Settings

/// Capture settings: Shortcuts, Audio Input, and Feedback (HUD, sounds)
struct DictationCaptureSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings
    @State private var isRecordingToggle = false
    @State private var isRecordingPTT = false
    @State private var selectedSoundEvent: SoundEvent = .start

    var body: some View {
        @Bindable var live = liveSettings

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "mic.fill",
                title: "CAPTURE",
                subtitle: "Configure how dictation is triggered, captured, and what feedback you receive."
            )
        } content: {
            // MARK: - Shortcuts Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)

                    Text("SHORTCUTS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                VStack(spacing: 12) {
                    // Toggle Hotkey
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Toggle Recording")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(.primary)

                        Text("Press once to start recording, press again to stop.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))

                        HotkeyRecorderButton(
                            hotkey: $live.hotkey,
                            isRecording: $isRecordingToggle
                        )
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)

                    // Push-to-Talk Hotkey
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("Push-to-Talk")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(.primary)

                            Spacer()

                            Toggle("", isOn: $live.pttEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        Text("Hold down to record, release to stop.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))

                        if live.pttEnabled {
                            HotkeyRecorderButton(
                                hotkey: $live.pttHotkey,
                                isRecording: $isRecordingPTT
                            )
                        }
                    }
                    .padding(12)
                    .background(Theme.current.surface1)
                    .cornerRadius(8)
                }
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Audio Input Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("AUDIO INPUT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: "mic.fill")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.blue)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Select which microphone to use for recording.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    AudioDeviceSelector()
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Visual Feedback Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("VISUAL FEEDBACK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                VStack(spacing: 8) {
                    StyledToggle(
                        label: "Show HUD overlay",
                        isOn: Binding(
                            get: { live.overlayStyle.showsTopOverlay },
                            set: { show in
                                if show {
                                    live.overlayStyle = .particles
                                } else {
                                    live.overlayStyle = .pillOnly
                                }
                            }
                        ),
                        help: "Animated feedback at top of screen during recording"
                    )

                    StyledToggle(
                        label: "Expand pill during recording",
                        isOn: $live.pillExpandsDuringRecording,
                        help: "Show timer and audio level in the floating pill"
                    )

                    StyledToggle(
                        label: "Show ON AIR indicator",
                        isOn: $live.showOnAir,
                        help: "Display neon ON AIR sign during recording"
                    )
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Audio Feedback Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green)
                        .frame(width: 3, height: 14)

                    Text("AUDIO FEEDBACK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(selectedSoundEvent.rawValue.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Sound effects for recording events.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    HStack(spacing: 12) {
                        ForEach(SoundEvent.allCases, id: \.rawValue) { event in
                            SoundEventCard(
                                event: event,
                                sound: {
                                    switch event {
                                    case .start: return live.startSound
                                    case .finish: return live.finishSound
                                    case .paste: return live.pastedSound
                                    }
                                }(),
                                isSelected: selectedSoundEvent == event
                            ) {
                                selectedSoundEvent = event
                            }
                        }
                    }

                    SoundGrid(selection: {
                        switch selectedSoundEvent {
                        case .start: return $live.startSound
                        case .finish: return $live.finishSound
                        case .paste: return $live.pastedSound
                        }
                    }())
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)
        }
        .onAppear {
            logger.debug("DictationCaptureSettingsView appeared")
        }
    }
}

// MARK: - Dictation Output Settings

/// Output settings: Paste Action and modifiers
struct DictationOutputSettingsView: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings

    var body: some View {
        @Bindable var live = liveSettings

        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.right.doc.on.clipboard",
                title: "OUTPUT",
                subtitle: "Configure where transcribed text is delivered."
            )
        } content: {
            // MARK: - Paste Action Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("PASTE ACTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(live.routingMode.displayName.uppercased())
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.blue.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Where transcribed text is sent after recording completes.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    RadioButtonRow(
                        title: RoutingMode.paste.displayName,
                        description: RoutingMode.paste.description,
                        value: RoutingMode.paste,
                        selectedValue: live.routingMode
                    ) {
                        live.routingMode = .paste
                    }

                    RadioButtonRow(
                        title: RoutingMode.clipboardOnly.displayName,
                        description: RoutingMode.clipboardOnly.description,
                        value: RoutingMode.clipboardOnly,
                        selectedValue: live.routingMode
                    ) {
                        live.routingMode = .clipboardOnly
                    }
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Behavior Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)

                    Text("BEHAVIOR")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                StyledToggle(
                    label: "Return to origin app after pasting",
                    isOn: $live.returnToOriginAfterPaste,
                    help: "Switch back to the app you were using when recording started"
                )
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)

            // MARK: - Context Preference Section
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("CONTEXT PREFERENCE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Which app context should be considered primary for recordings.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    RadioButtonRow(
                        title: PrimaryContextSource.startApp.displayName,
                        description: PrimaryContextSource.startApp.description,
                        value: .startApp,
                        selectedValue: live.primaryContextSource
                    ) {
                        live.primaryContextSource = .startApp
                    }

                    RadioButtonRow(
                        title: PrimaryContextSource.endApp.displayName,
                        description: PrimaryContextSource.endApp.description,
                        value: .endApp,
                        selectedValue: live.primaryContextSource
                    ) {
                        live.primaryContextSource = .endApp
                    }
                }
                .padding(12)
                .background(Theme.current.surface1)
                .cornerRadius(8)
            }
            .padding(16)
            .background(Theme.current.surface2)
            .cornerRadius(8)
        }
        .onAppear {
            logger.debug("DictationOutputSettingsView appeared")
        }
    }
}

// MARK: - Previews

#Preview("Capture") {
    DictationCaptureSettingsView()
        .frame(width: 600, height: 800)
}

#Preview("Output") {
    DictationOutputSettingsView()
        .frame(width: 600, height: 500)
}
