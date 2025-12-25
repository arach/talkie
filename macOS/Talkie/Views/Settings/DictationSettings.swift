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
            // MARK: - Shortcuts & Audio Input (Two-Column Layout)
            HStack(alignment: .top, spacing: Spacing.md) {
                // Left Column: Shortcuts
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.orange)
                            .frame(width: 3, height: 14)

                        Text("SHORTCUTS")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()
                    }

                    VStack(spacing: Spacing.xs) {
                        // Toggle Recording - Compact inline layout
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Toggle Recording")
                                        .font(Theme.current.fontSMMedium)
                                        .foregroundColor(Theme.current.foreground)

                                    Text("Press once to start, press again to stop")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                }

                                Spacer()

                                HotkeyRecorderButton(
                                    hotkey: $live.hotkey,
                                    isRecording: $isRecordingToggle
                                )
                            }
                        }
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)

                        // Push-to-Talk - Right-aligned toggle and shortcut
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Push-to-Talk")
                                        .font(Theme.current.fontSMMedium)
                                        .foregroundColor(Theme.current.foreground)

                                    Text("Hold down to record, release to stop")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))
                                }

                                Spacer()

                                Toggle("", isOn: $live.pttEnabled)
                                    .toggleStyle(.switch)
                                    .labelsHidden()
                            }

                            if live.pttEnabled {
                                HStack {
                                    Spacer()
                                    HotkeyRecorderButton(
                                        hotkey: $live.pttHotkey,
                                        isRecording: $isRecordingPTT
                                    )
                                }
                            }
                        }
                        .padding(Spacing.sm)
                        .background(Theme.current.surface1)
                        .cornerRadius(CornerRadius.sm)
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)
                .frame(maxWidth: .infinity)

                // Right Column: Audio Input
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.blue)
                            .frame(width: 3, height: 14)

                        Text("AUDIO INPUT")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Spacer()

                        Image(systemName: "mic.fill")
                            .font(Theme.current.fontXS)
                            .foregroundColor(.accentColor)
                    }

                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Microphone to use for recording")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                        AudioDeviceSelector()

                        // Mic Test
                        MicTestView()
                            .padding(.top, 4)
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface2)
                .cornerRadius(CornerRadius.sm)
                .frame(maxWidth: .infinity)
            }

            // MARK: - Visual Feedback Section (Prominent, Beautiful)
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("VISUAL FEEDBACK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                // Main layout: Screen LEFT, Settings RIGHT (from Live settings)
                HStack(alignment: .top, spacing: Spacing.xl) {
                    // LEFT: Mock screen preview
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("PREVIEW")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)

                        Text("Hover to simulate recording")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

                        LivePreviewScreen(
                            overlayStyle: $live.overlayStyle,
                            hudPosition: $live.overlayPosition,
                            pillPosition: $live.pillPosition,
                            showOnAir: $live.showOnAir
                        )
                    }

                    // RIGHT: Settings (HUD top, ON AIR middle, Pill bottom)
                    VStack(alignment: .leading, spacing: 0) {
                        // HUD Section (top-aligned)
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

                                    // Speed toggle (applies to both particles and waveform)
                                    HStack(spacing: Spacing.sm) {
                                        Text("Speed")
                                            .font(Theme.current.fontXS)
                                            .foregroundColor(Theme.current.foregroundSecondary)

                                        Picker("", selection: Binding(
                                            get: {
                                                // particlesCalm = slow, particles = fast
                                                // waveform = slow, waveformSensitive = fast
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

                        Spacer().frame(height: Spacing.md)

                        // ON AIR (small middle section)
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

                        // Pill Section (bottom-aligned)
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
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

            // MARK: - Audio Feedback Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green)
                        .frame(width: 3, height: 14)

                    Text("AUDIO FEEDBACK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text(selectedSoundEvent.rawValue.uppercased())
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Sound effects for recording events.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.prominent))

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
                    }

                    SoundGrid(selection: {
                        switch selectedSoundEvent {
                        case .start: return $live.startSound
                        case .finish: return $live.finishSound
                        case .paste: return $live.pastedSound
                        }
                    }())
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)
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
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

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
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)

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
            .padding(Spacing.md)
            .background(Theme.current.surface2)
            .cornerRadius(CornerRadius.sm)
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
