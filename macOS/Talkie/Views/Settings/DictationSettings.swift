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
            VStack(alignment: .leading, spacing: 28) {
                // MARK: Shortcuts
                VStack(alignment: .leading, spacing: 16) {
                    Text("SHORTCUTS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    // Toggle Hotkey
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Toggle Recording")
                            .font(.bodyMedium)
                            .foregroundColor(.primary)

                        Text("Press once to start recording, press again to stop.")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))

                        HotkeyRecorderButton(
                            hotkey: $live.hotkey,
                            isRecording: $isRecordingToggle
                        )
                    }

                    // Push-to-Talk Hotkey
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Push-to-Talk")
                            .font(.bodyMedium)
                            .foregroundColor(.primary)

                        Text("Hold down to record, release to stop.")
                            .font(SettingsManager.shared.fontXS)
                            .foregroundColor(.secondary.opacity(0.8))

                        StyledToggle(
                            label: "Enable Push-to-Talk",
                            isOn: $live.pttEnabled,
                            help: "Activate push-to-talk recording mode"
                        )

                        HotkeyRecorderButton(
                            hotkey: $live.pttHotkey,
                            isRecording: $isRecordingPTT
                        )
                        .opacity(live.pttEnabled ? 1.0 : 0.5)
                        .allowsHitTesting(live.pttEnabled)
                    }
                }

                Divider()

                // MARK: Audio Input
                VStack(alignment: .leading, spacing: 12) {
                    Text("AUDIO INPUT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Select which microphone to use for recording.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    AudioDeviceSelector()
                }

                Divider()

                // MARK: Visual Feedback (HUD/Overlay)
                VStack(alignment: .leading, spacing: 12) {
                    Text("VISUAL FEEDBACK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

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

                Divider()

                // MARK: Audio Feedback (Sounds)
                VStack(alignment: .leading, spacing: 12) {
                    Text("AUDIO FEEDBACK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Sound effects for recording events.")
                        .font(SettingsManager.shared.fontXS)
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
            }
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
            VStack(alignment: .leading, spacing: 24) {
                // MARK: Paste Action
                VStack(alignment: .leading, spacing: 12) {
                    Text("PASTE ACTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Where transcribed text is sent after recording completes.")
                        .font(SettingsManager.shared.fontXS)
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

                Divider()

                // MARK: Behavior
                VStack(alignment: .leading, spacing: 12) {
                    Text("BEHAVIOR")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    StyledToggle(
                        label: "Return to origin app after pasting",
                        isOn: $live.returnToOriginAfterPaste,
                        help: "Switch back to the app you were using when recording started"
                    )
                }

                Divider()

                // MARK: Context Preference
                VStack(alignment: .leading, spacing: 12) {
                    Text("CONTEXT PREFERENCE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Which app context should be considered primary for recordings.")
                        .font(SettingsManager.shared.fontXS)
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
            }
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
