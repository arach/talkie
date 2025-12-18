//
//  LiveSettingsView.swift
//  Talkie
//
//  Live settings view using Talkie's design system
//  With instrumented components from TalkieLive
//

import SwiftUI
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LiveSettings")

enum LiveSettingsSection: String, Hashable {
    case general
    case shortcuts
    case sounds
    case audio
    case transcription
    case autoPaste
    case storage
    case permissions
}

struct LiveSettingsView: View {
    @ObservedObject private var liveSettings = LiveSettings.shared
    @State private var selectedSection: LiveSettingsSection = .general

    // Theme-aware colors for light/dark mode
    private var sidebarBackground: Color { Theme.current.backgroundSecondary }
    private var contentBackground: Color { Theme.current.background }

    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Sidebar
            VStack(spacing: 0) {
                // Settings Header
                Text("LIVE SETTINGS")
                    .font(.system(size: 10, weight: .bold, design: .default))
                    .foregroundColor(Theme.current.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 20)
                    .padding(.bottom, 12)

                // Menu Sections
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // GENERAL
                        SettingsSidebarSection(title: "GENERAL", isActive: selectedSection == .general) {
                            SettingsSidebarItem(
                                icon: "waveform",
                                title: "OVERVIEW",
                                isSelected: selectedSection == .general
                            ) {
                                selectedSection = .general
                            }
                        }

                        // RECORDING
                        SettingsSidebarSection(title: "RECORDING", isActive: selectedSection == .shortcuts || selectedSection == .sounds || selectedSection == .audio) {
                            SettingsSidebarItem(
                                icon: "command",
                                title: "SHORTCUTS",
                                isSelected: selectedSection == .shortcuts
                            ) {
                                selectedSection = .shortcuts
                            }
                            SettingsSidebarItem(
                                icon: "speaker.wave.2",
                                title: "SOUNDS",
                                isSelected: selectedSection == .sounds
                            ) {
                                selectedSection = .sounds
                            }
                            SettingsSidebarItem(
                                icon: "mic",
                                title: "AUDIO",
                                isSelected: selectedSection == .audio
                            ) {
                                selectedSection = .audio
                            }
                        }

                        // PROCESSING
                        SettingsSidebarSection(title: "PROCESSING", isActive: selectedSection == .transcription || selectedSection == .autoPaste) {
                            SettingsSidebarItem(
                                icon: "text.bubble",
                                title: "TRANSCRIPTION",
                                isSelected: selectedSection == .transcription
                            ) {
                                selectedSection = .transcription
                            }
                            SettingsSidebarItem(
                                icon: "arrow.right.doc.on.clipboard",
                                title: "AUTO-PASTE",
                                isSelected: selectedSection == .autoPaste
                            ) {
                                selectedSection = .autoPaste
                            }
                        }

                        // SYSTEM
                        SettingsSidebarSection(title: "SYSTEM", isActive: selectedSection == .storage || selectedSection == .permissions) {
                            SettingsSidebarItem(
                                icon: "clock",
                                title: "STORAGE",
                                isSelected: selectedSection == .storage
                            ) {
                                selectedSection = .storage
                            }
                            SettingsSidebarItem(
                                icon: "lock.shield",
                                title: "PERMISSIONS",
                                isSelected: selectedSection == .permissions
                            ) {
                                selectedSection = .permissions
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
            .frame(width: 220)
            .background(sidebarBackground)

            // Divider
            Rectangle()
                .fill(Theme.current.divider)
                .frame(width: 1)

            // MARK: - Content Area
            VStack(spacing: 0) {
                Group {
                    switch selectedSection {
                    case .general:
                        GeneralLiveSettingsView()
                    case .shortcuts:
                        ShortcutsLiveSettingsView()
                    case .sounds:
                        SoundsLiveSettingsView()
                    case .audio:
                        AudioLiveSettingsView()
                    case .transcription:
                        TranscriptionLiveSettingsView()
                    case .autoPaste:
                        AutoPasteLiveSettingsView()
                    case .storage:
                        StorageLiveSettingsView()
                    case .permissions:
                        PermissionsLiveSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(contentBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Radio Button Row Component

struct RadioButtonRow<T: Equatable>: View {
    let title: String
    let description: String
    let value: T
    let selectedValue: T
    let onSelect: () -> Void
    var preview: AnyView? = nil

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selectedValue == value ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(selectedValue == value ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let preview = preview {
                    preview
                        .frame(width: 80, height: 40)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }
}

// MARK: - General Settings

struct GeneralLiveSettingsView: View {
    @ObservedObject private var liveSettings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "waveform",
                title: "GENERAL",
                subtitle: "Configure Live recording behavior and visual feedback."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                // Overlay Style
                VStack(alignment: .leading, spacing: 12) {
                    Text("OVERLAY STYLE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Visual indicator shown while recording.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    RadioButtonRow(
                        title: OverlayStyle.particles.displayName,
                        description: OverlayStyle.particles.description,
                        value: OverlayStyle.particles,
                        selectedValue: liveSettings.overlayStyle,
                        preview: AnyView(WavyParticlesPreview(calm: false))
                    ) {
                        liveSettings.overlayStyle = .particles
                        logger.info("Overlay style changed to: particles")
                    }

                    RadioButtonRow(
                        title: OverlayStyle.particlesCalm.displayName,
                        description: OverlayStyle.particlesCalm.description,
                        value: OverlayStyle.particlesCalm,
                        selectedValue: liveSettings.overlayStyle,
                        preview: AnyView(WavyParticlesPreview(calm: true))
                    ) {
                        liveSettings.overlayStyle = .particlesCalm
                        logger.info("Overlay style changed to: particlesCalm")
                    }

                    RadioButtonRow(
                        title: OverlayStyle.waveform.displayName,
                        description: OverlayStyle.waveform.description,
                        value: OverlayStyle.waveform,
                        selectedValue: liveSettings.overlayStyle,
                        preview: AnyView(WaveformBarsPreview(sensitive: false))
                    ) {
                        liveSettings.overlayStyle = .waveform
                        logger.info("Overlay style changed to: waveform")
                    }

                    RadioButtonRow(
                        title: OverlayStyle.waveformSensitive.displayName,
                        description: OverlayStyle.waveformSensitive.description,
                        value: OverlayStyle.waveformSensitive,
                        selectedValue: liveSettings.overlayStyle,
                        preview: AnyView(WaveformBarsPreview(sensitive: true))
                    ) {
                        liveSettings.overlayStyle = .waveformSensitive
                        logger.info("Overlay style changed to: waveformSensitive")
                    }

                    RadioButtonRow(
                        title: OverlayStyle.pillOnly.displayName,
                        description: OverlayStyle.pillOnly.description,
                        value: OverlayStyle.pillOnly,
                        selectedValue: liveSettings.overlayStyle,
                        preview: AnyView(PillOnlyPreview())
                    ) {
                        liveSettings.overlayStyle = .pillOnly
                        logger.info("Overlay style changed to: pillOnly")
                    }
                }

                // Overlay Position (if overlay is shown)
                if liveSettings.overlayStyle.showsTopOverlay {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OVERLAY POSITION")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(.secondary)

                        Picker("Overlay Position", selection: $liveSettings.overlayPosition) {
                            ForEach(OverlayPosition.allCases, id: \.self) { position in
                                Text(position.displayName).tag(position)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // Pill Position
                VStack(alignment: .leading, spacing: 12) {
                    Text("PILL POSITION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Floating widget that shows recording status.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    Picker("Pill Position", selection: $liveSettings.pillPosition) {
                        ForEach(PillPosition.allCases, id: \.self) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Show pill on all screens", isOn: $liveSettings.pillShowOnAllScreens)
                        .font(SettingsManager.shared.fontSM)

                    Toggle("Expand pill during recording", isOn: $liveSettings.pillExpandsDuringRecording)
                        .font(SettingsManager.shared.fontSM)
                }

                // Sound Feedback
                VStack(alignment: .leading, spacing: 12) {
                    Text("SOUND FEEDBACK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Recording Start")
                            .font(SettingsManager.shared.fontSM)
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $liveSettings.startSound) {
                            ForEach(TalkieSound.allCases, id: \.self) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }

                    HStack {
                        Text("Recording End")
                            .font(SettingsManager.shared.fontSM)
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $liveSettings.finishSound) {
                            ForEach(TalkieSound.allCases, id: \.self) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }

                    HStack {
                        Text("Text Pasted")
                            .font(SettingsManager.shared.fontSM)
                            .frame(width: 120, alignment: .leading)
                        Picker("", selection: $liveSettings.pastedSound) {
                            ForEach(TalkieSound.allCases, id: \.self) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                }
            }
        }
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsLiveSettingsView: View {
    @ObservedObject private var liveSettings = LiveSettings.shared
    @State private var isRecordingToggle = false
    @State private var isRecordingPTT = false

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "command",
                title: "SHORTCUTS",
                subtitle: "Configure keyboard shortcuts for Live recording."
            )
        } content: {
            VStack(alignment: .leading, spacing: 24) {
                // Toggle Hotkey
                VStack(alignment: .leading, spacing: 12) {
                    Text("TOGGLE RECORDING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Press once to start recording, press again to stop.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    HotkeyRecorderButton(
                        hotkey: $liveSettings.hotkey,
                        isRecording: $isRecordingToggle
                    )
                }

                // Push-to-Talk Hotkey
                VStack(alignment: .leading, spacing: 12) {
                    Text("PUSH-TO-TALK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Hold down to record, release to stop.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    Toggle("Enable Push-to-Talk", isOn: $liveSettings.pttEnabled)
                        .font(SettingsManager.shared.fontSM)
                        .onChange(of: liveSettings.pttEnabled) { _, enabled in
                            logger.info("Push-to-Talk \(enabled ? "enabled" : "disabled")")
                        }

                    if liveSettings.pttEnabled {
                        HotkeyRecorderButton(
                            hotkey: $liveSettings.pttHotkey,
                            isRecording: $isRecordingPTT
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: liveSettings.pttEnabled)
        .onAppear {
            logger.debug("ShortcutsLiveSettingsView appeared")
        }
    }
}

// MARK: - Audio Settings

struct AudioLiveSettingsView: View {
    @ObservedObject private var liveSettings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "mic",
                title: "AUDIO",
                subtitle: "Configure microphone input for Live recording."
            )
        } content: {
            VStack(alignment: .leading, spacing: 24) {
                // Microphone Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("INPUT DEVICE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Select which microphone to use for recording. The level meter shows real-time input volume.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    AudioDeviceSelector()
                }
            }
        }
        .onAppear {
            logger.debug("AudioLiveSettingsView appeared")
        }
    }
}

// MARK: - Sounds Settings

struct SoundsLiveSettingsView: View {
    @ObservedObject private var liveSettings = LiveSettings.shared
    @State private var selectedEvent: SoundEvent = .start

    private func binding(for event: SoundEvent) -> Binding<TalkieSound> {
        switch event {
        case .start: return $liveSettings.startSound
        case .finish: return $liveSettings.finishSound
        case .paste: return $liveSettings.pastedSound
        }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "speaker.wave.2",
                title: "SOUNDS",
                subtitle: "Configure audio feedback for recording events."
            )
        } content: {
            VStack(alignment: .leading, spacing: 24) {
                // Event Selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("SELECT EVENT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        ForEach(SoundEvent.allCases, id: \.rawValue) { event in
                            SoundEventCard(
                                event: event,
                                sound: binding(for: event).wrappedValue,
                                isSelected: selectedEvent == event
                            ) {
                                selectedEvent = event
                                logger.debug("Selected sound event: \(event.rawValue)")
                            }
                        }
                    }

                    // Play sequence button
                    HStack {
                        Spacer()
                        PlaySequenceButton(sounds: [
                            liveSettings.startSound,
                            liveSettings.finishSound,
                            liveSettings.pastedSound
                        ])
                    }
                }

                // Sound Grid for selected event
                VStack(alignment: .leading, spacing: 12) {
                    Text("SOUND FOR \(selectedEvent.rawValue.uppercased())")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text(selectedEvent.description)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    SoundGrid(selection: binding(for: selectedEvent))
                }
            }
        }
        .onAppear {
            logger.debug("SoundsLiveSettingsView appeared")
        }
        .onChange(of: liveSettings.startSound) { _, newValue in
            logger.info("Start sound changed to: \(newValue.displayName)")
        }
        .onChange(of: liveSettings.finishSound) { _, newValue in
            logger.info("Finish sound changed to: \(newValue.displayName)")
        }
        .onChange(of: liveSettings.pastedSound) { _, newValue in
            logger.info("Pasted sound changed to: \(newValue.displayName)")
        }
    }
}

// MARK: - Transcription Settings

struct TranscriptionLiveSettingsView: View {
    @ObservedObject private var liveSettings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "text.bubble",
                title: "TRANSCRIPTION",
                subtitle: "Configure the speech-to-text engine."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                Text("TRANSCRIPTION ENGINE")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(.secondary)

                Text("Selected model: \(liveSettings.selectedModelId)")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary)

                Text("⚠️ Model selection UI coming soon")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.orange)
            }
        }
    }
}

// MARK: - Auto-Paste Settings

struct AutoPasteLiveSettingsView: View {
    @ObservedObject private var liveSettings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "arrow.right.doc.on.clipboard",
                title: "AUTO-PASTE",
                subtitle: "Control how transcribed text is delivered."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("ROUTING MODE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    RadioButtonRow(
                        title: RoutingMode.paste.displayName,
                        description: RoutingMode.paste.description,
                        value: RoutingMode.paste,
                        selectedValue: liveSettings.routingMode
                    ) {
                        liveSettings.routingMode = .paste
                    }

                    RadioButtonRow(
                        title: RoutingMode.clipboardOnly.displayName,
                        description: RoutingMode.clipboardOnly.description,
                        value: RoutingMode.clipboardOnly,
                        selectedValue: liveSettings.routingMode
                    ) {
                        liveSettings.routingMode = .clipboardOnly
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("BEHAVIOR")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Toggle("Return to origin app after pasting", isOn: $liveSettings.returnToOriginAfterPaste)
                        .font(SettingsManager.shared.fontSM)
                }
            }
        }
    }
}

// MARK: - Storage Settings

struct StorageLiveSettingsView: View {
    @ObservedObject private var liveSettings = LiveSettings.shared

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "clock",
                title: "STORAGE",
                subtitle: "Configure how long Live recordings are kept."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("RETENTION PERIOD")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(.secondary)

                    Text("Recordings older than this will be automatically deleted.")
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.8))

                    HStack {
                        Stepper(
                            value: $liveSettings.utteranceTTLHours,
                            in: 1...720,
                            step: 24
                        ) {
                            Text("\(liveSettings.utteranceTTLHours) hours (\(liveSettings.utteranceTTLHours / 24) days)")
                                .font(SettingsManager.shared.fontSM)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Permissions Settings

struct PermissionsLiveSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "lock.shield",
                title: "PERMISSIONS",
                subtitle: "Manage system permissions for Live recording."
            )
        } content: {
            VStack(alignment: .leading, spacing: 20) {
                Text("⚠️ Permissions UI coming soon")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.orange)

                Text("Required permissions:")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(.secondary)

                Text("• Microphone access (for recording)")
                    .font(SettingsManager.shared.fontSM)
                Text("• Accessibility access (for auto-paste)")
                    .font(SettingsManager.shared.fontSM)
            }
        }
    }
}

#Preview {
    LiveSettingsView()
        .frame(width: 800, height: 600)
}
