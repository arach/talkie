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
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // MARK: - Shortcuts Section
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SHORTCUTS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    HStack(alignment: .top, spacing: Spacing.lg) {
                        // Toggle Hotkey
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Toggle Recording")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)

                            Text("Press once to start, press again to stop.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)

                            HotkeyRecorderButton(
                                hotkey: $live.hotkey,
                                isRecording: $isRecordingToggle
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Push-to-Talk Hotkey
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack(spacing: Spacing.sm) {
                                Text("Push-to-Talk")
                                    .font(Theme.current.fontSMMedium)
                                    .foregroundColor(Theme.current.foreground)

                                Toggle("", isOn: $live.pttEnabled)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                                    .controlSize(.mini)
                            }

                            Text("Hold down to record, release to stop.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)

                            HotkeyRecorderButton(
                                hotkey: $live.pttHotkey,
                                isRecording: $isRecordingPTT
                            )
                            .opacity(live.pttEnabled ? 1.0 : 0.5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider()
                    .opacity(Opacity.medium)

                // MARK: - Audio Input Section
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("AUDIO INPUT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Text("Select which microphone to use for recording.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    AudioDeviceSelector()
                }

                Divider()
                    .opacity(Opacity.medium)

                // MARK: - Audio Feedback Section
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("AUDIO FEEDBACK")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        Text(selectedSoundEvent.rawValue.uppercased())
                            .font(.techLabelSmall)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    Text("Sound effects for recording events.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    HStack(spacing: Spacing.sm) {
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

                        Spacer()

                        // Play sequence button
                        PlaySequenceButton(sounds: [
                            live.startSound,
                            live.finishSound,
                            live.pastedSound
                        ])
                    }

                    SoundGrid(selection: {
                        switch selectedSoundEvent {
                        case .start: return $live.startSound
                        case .finish: return $live.finishSound
                        case .paste: return $live.pastedSound
                        }
                    }())
                }

                Divider()
                    .opacity(Opacity.medium)

                // MARK: - Visual Feedback with Preview
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("VISUAL FEEDBACK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    // Main layout: Preview LEFT, Settings RIGHT
                    HStack(alignment: .top, spacing: Spacing.xl) {
                        // LEFT: Mock screen preview
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("PREVIEW")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Text("Hover to simulate recording")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)

                            LivePreviewScreen(
                                overlayStyle: $live.overlayStyle,
                                hudPosition: $live.overlayPosition,
                                pillPosition: $live.pillPosition,
                                showOnAir: $live.showOnAir
                            )
                        }

                        // RIGHT: Settings (HUD top, ON AIR lower, Pill bottom)
                        VStack(alignment: .leading, spacing: 0) {
                            // HUD Section
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("HUD")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)

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
                                    help: "Animated feedback at top of screen"
                                )

                                if live.overlayStyle.showsTopOverlay {
                                    VStack(alignment: .leading, spacing: Spacing.sm) {
                                        LiveStyleSelector(selection: $live.overlayStyle)

                                        // Speed toggle
                                        HStack(spacing: Spacing.sm) {
                                            Text("Speed")
                                                .font(Theme.current.fontXS)
                                                .foregroundColor(Theme.current.foregroundSecondary)

                                            Picker("", selection: Binding(
                                                get: {
                                                    if live.overlayStyle == .particlesCalm || live.overlayStyle == .waveform {
                                                        return "slow"
                                                    }
                                                    return "fast"
                                                },
                                                set: { speed in
                                                    if live.overlayStyle == .particles || live.overlayStyle == .particlesCalm {
                                                        live.overlayStyle = speed == "slow" ? .particlesCalm : .particles
                                                    } else if live.overlayStyle == .waveform || live.overlayStyle == .waveformSensitive {
                                                        live.overlayStyle = speed == "slow" ? .waveform : .waveformSensitive
                                                    }
                                                }
                                            )) {
                                                Text("Slow").tag("slow")
                                                Text("Fast").tag("fast")
                                            }
                                            .pickerStyle(.segmented)
                                            .frame(width: 100)
                                        }
                                    }
                                    .padding(.leading, Spacing.xxs)
                                }
                            }

                            Spacer().frame(height: Spacing.xl)

                            // ON AIR Section
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack(spacing: Spacing.xs) {
                                    Text("ON AIR")
                                        .font(.system(size: 8, weight: .black))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, Spacing.xxs)
                                        .background(
                                            RoundedRectangle(cornerRadius: Spacing.xxs)
                                                .fill(live.showOnAir ? Color.red : Color.gray.opacity(Opacity.half))
                                        )

                                    Toggle("", isOn: $live.showOnAir)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .controlSize(.mini)
                                }

                                Text("Neon sign in top-left during recording")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }

                            Spacer()

                            // Pill Section
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("PILL")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                StyledToggle(
                                    label: "Expand during recording",
                                    isOn: $live.pillExpandsDuringRecording,
                                    help: "Show timer and audio level"
                                )

                                StyledToggle(
                                    label: "Show on all screens",
                                    isOn: $live.pillShowOnAllScreens,
                                    help: "Display on every connected display"
                                )
                            }
                        }
                        .frame(width: 220)
                    }

                    // Settings summary
                    LiveSettingsSummary()
                }

                Divider()
                    .opacity(Opacity.medium)

                // MARK: - Settings Recap (JSON)
                CaptureSettingsRecap()
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
            // MARK: - Paste Action Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("PASTE ACTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text(live.routingMode.displayName.uppercased())
                        .font(.techLabelSmall)
                        .foregroundColor(.blue.opacity(Opacity.prominent))
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Where transcribed text is sent after recording completes.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

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
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Behavior Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)

                    Text("BEHAVIOR")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                StyledToggle(
                    label: "Return to origin app after pasting",
                    isOn: $live.returnToOriginAfterPaste,
                    help: "Switch back to the app you were using when recording started"
                )
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Scratchpad Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("SCRATCHPAD")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    if live.autoScratchpadOnSelection {
                        Text("AUTO")
                            .font(.techLabelSmall)
                            .foregroundColor(.cyan.opacity(Opacity.prominent))
                    }
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    StyledToggle(
                        label: "Auto-open with selection",
                        isOn: $live.autoScratchpadOnSelection,
                        help: "When text is selected, open in Scratchpad to edit or transform it"
                    )

                    if live.autoScratchpadOnSelection {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "info.circle")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                            Text("Select text → press hotkey → dictate your edit")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }
                        .padding(.leading, Spacing.sm)
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Context Preference Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("CONTEXT PREFERENCE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Which app context should be considered primary for recordings.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

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
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)
        }
        .onAppear {
            logger.debug("DictationOutputSettingsView appeared")
        }
    }
}

// MARK: - Capture Settings Recap (JSON)

/// Compact JSON representation of capture settings
struct CaptureSettingsRecap: View {
    @Environment(LiveSettings.self) private var liveSettings: LiveSettings

    private var jsonString: String {
        let settings: [String: Any] = [
            "hotkey": liveSettings.hotkey.displayString,
            "ptt": [
                "enabled": liveSettings.pttEnabled,
                "hotkey": liveSettings.pttHotkey.displayString
            ],
            "hud": [
                "style": liveSettings.overlayStyle.rawValue,
                "position": liveSettings.overlayPosition.rawValue
            ],
            "pill": [
                "position": liveSettings.pillPosition.rawValue,
                "expands": liveSettings.pillExpandsDuringRecording,
                "allScreens": liveSettings.pillShowOnAllScreens
            ],
            "onAir": liveSettings.showOnAir,
            "sounds": [
                "start": liveSettings.startSound.rawValue,
                "finish": liveSettings.finishSound.rawValue,
                "paste": liveSettings.pastedSound.rawValue
            ]
        ]

        // Format as compact JSON
        if let data = try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Image(systemName: "curlybraces")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundMuted)

                Text("SETTINGS")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundMuted)

                Spacer()

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(jsonString, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }

            Text(jsonString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .fill(Theme.current.surface1.opacity(Opacity.half))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .stroke(Theme.current.divider.opacity(Opacity.half), lineWidth: 0.5)
                )
        )
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
