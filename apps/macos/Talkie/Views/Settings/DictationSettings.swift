//
//  DictationSettings.swift
//  Talkie
//
//  Dictation settings - Recording and Delivery configuration
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Recording Settings Content

/// Recording tab: Shortcuts, Microphone, Sounds, and Display (HUD/Pill)
/// Everything about "what happens while I'm talking"
struct DictationRecordingSettingsContent: View {
    @Environment(AgentSettings.self) private var liveSettings: AgentSettings
    @State private var isRecordingToggle = false
    @State private var isRecordingPTT = false
    @State private var selectedSoundEvent: SoundEvent = .start

    var body: some View {
        @Bindable var live = liveSettings

        VStack(alignment: .leading, spacing: Spacing.lg) {
            // MARK: - Input Section (Shortcuts + Microphone)
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("INPUT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                // Shortcuts row
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("SHORTCUTS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundMuted)

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
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)

                // Microphone row (compact)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "mic")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundMuted)

                        Text("MICROPHONE")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    AudioDeviceSelector()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Sounds Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("SOUNDS")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Text(selectedSoundEvent.rawValue.uppercased())
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
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
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Display Section (Agent Feedback)
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("DISPLAY")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.current.foregroundMuted)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("This section controls the small recording feedback from TalkieAgent.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Text("Use Surface Settings for Talkie’s larger surface. That surface supports notch Macs and external displays, can be turned off, and takes over the top-edge particles when active.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }

                        Spacer()

                        Button("Open Surface Settings") {
                            NavigationState.shared.navigateToSettings(.surface)
                        }
                        .buttonStyle(.plain)
                        .font(Theme.current.fontXS)
                        .foregroundColor(.cyan)
                    }
                    .padding(.bottom, Spacing.xs)

                    HStack(alignment: .top, spacing: Spacing.xl) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("PREVIEW")
                                .font(Theme.current.fontXSBold)
                                .foregroundColor(Theme.current.foregroundSecondary)

                            Text("Fixed positions only. Top bar uses the top row, recording pill uses the bottom row.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)

                            TalkieKit.LivePreviewScreen(
                                overlayStyle: $live.overlayStyle,
                                hudPlacement: $live.overlayPlacement,
                                pillEnabled: $live.pillEnabled,
                                pillPlacement: $live.pillPlacement
                            )
                        }

                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("TOP BAR")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                StyledToggle(
                                    label: "Show top bar",
                                    isOn: Binding(
                                        get: { live.overlayStyle.showsTopOverlay },
                                        set: { show in
                                            live.overlayStyle = show ? .particles : .pillOnly
                                        }
                                    ),
                                    help: "Particles at the top edge when the Talkie surface is not active"
                                )

                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text("Position")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)

                                    OverlayQuickPositionRow(placement: $live.overlayPlacement)
                                }
                                .opacity(live.overlayStyle.showsTopOverlay ? 1.0 : 0.45)

                                Text("Particles are the only top-bar style here. If Talkie’s larger surface is active, it replaces this top bar.")
                                    .font(Theme.current.fontXS)
                                    .foregroundColor(Theme.current.foregroundMuted)
                            }
                            .padding(Spacing.sm)
                            .background(Theme.current.surface2)
                            .cornerRadius(CornerRadius.sm)

                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("RECORDING PILL")
                                    .font(Theme.current.fontXSBold)
                                    .foregroundColor(Theme.current.foregroundSecondary)

                                StyledToggle(
                                    label: "Show recording pill",
                                    isOn: $live.pillEnabled,
                                    help: "Small indicator that stays visible while recording"
                                )

                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text("Position")
                                        .font(Theme.current.fontXS)
                                        .foregroundColor(Theme.current.foregroundSecondary)

                                    PillQuickPositionRow(placement: $live.pillPlacement)
                                }
                                .opacity(live.pillEnabled ? 1.0 : 0.45)
                                .disabled(!live.pillEnabled)
                            }
                            .padding(Spacing.sm)
                            .background(Theme.current.surface2)
                            .cornerRadius(CornerRadius.sm)
                        }
                        .frame(width: 280)
                    }

                    LiveSettingsSummary()
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
                .onAppear {
                    normalizeDisplaySettings(liveSettings)
                }
            }
            .settingsSectionCard(padding: Spacing.md)
        }
    }

    private func normalizeDisplaySettings(_ settings: AgentSettings) {
        if settings.overlayStyle.showsTopOverlay, settings.overlayStyle != .particles {
            settings.overlayStyle = .particles
        }

        if settings.pillPosition == .topCenter {
            settings.pillPosition = .bottomCenter
        }
    }
}

struct CompanionShortcutKeyboardSettingsView: View {
    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "square.grid.2x2",
                title: "PAIRED SHORTCUT KEYBOARD",
                subtitle: "Define the keyboard surface that paired iPhone and iPad devices can render when they follow this Mac."
            )
        } content: {
            ScrollView {
                CompanionShortcutKeyboardSettingsCard()
                    .padding(.top, Spacing.md)
            }
        }
    }
}

private struct CompanionShortcutKeyboardSettingsCard: View {
    @Environment(SettingsManager.self) private var settingsManager: SettingsManager

    var body: some View {
        @Bindable var settings = settingsManager

        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.orange)
                    .frame(width: 3, height: 14)

                Text("SHORTCUT KEYBOARD")
                    .font(Theme.current.fontXSBold)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                Text("\(activeShortcutCount(for: settings.defaultDeviceShortcutBoardSlots))/16")
                    .font(.techLabelSmall)
                    .foregroundColor(.orange.opacity(Opacity.prominent))
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: settings.companionShortcutModeEnabled ? "square.grid.2x2.fill" : "square.grid.2x2")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(settings.companionShortcutModeEnabled ? .orange : Theme.current.foregroundSecondary)
                        .frame(width: 32, height: 32)
                        .background((settings.companionShortcutModeEnabled ? Color.orange : Theme.current.foregroundSecondary).opacity(0.12))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Author the keyboard your iPhone and iPad can render when they follow this Mac.")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Text("This is a Mac-defined input surface, so it lives here with the rest of dictation input. Pairing and terminal setup stay in Devices.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Toggle("", isOn: $settings.companionShortcutModeEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                HStack(spacing: Spacing.sm) {
                    Text(settings.companionShortcutModeEnabled ? "Publishing to paired devices that opt in." : "Board is authored here, but not currently being published.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Button("Open Devices") {
                        NavigationState.shared.navigateToSettings(.sync)
                    }
                    .buttonStyle(.plain)
                    .font(Theme.current.fontXS)
                    .foregroundColor(.cyan)
                }
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    Text("BOARD")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Button(action: {
                        settings.resetDefaultDeviceShortcutBoardToStarterKit()
                    }) {
                        Text("STARTER KIT")
                            .font(Theme.current.fontXSMedium)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Text("Each tile is one key in the Talkie space of the shortcut board. Start with the starter kit, then swap individual keys as we learn what should be fast-access.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(0..<normalizedSlots(for: settings.defaultDeviceShortcutBoardSlots).count, id: \.self) { index in
                        shortcutSlotCard(
                            index: index,
                            slotID: normalizedSlots(for: settings.defaultDeviceShortcutBoardSlots)[index]
                        ) { updatedSlot in
                            var updated = normalizedSlots(for: settings.defaultDeviceShortcutBoardSlots)
                            guard updated.indices.contains(index) else { return }
                            updated[index] = updatedSlot
                            settings.setDefaultDeviceShortcutBoardSlots(updated)
                        }
                    }
                }
            }
            .padding(Spacing.sm)
            .background(Theme.current.surface1)
            .cornerRadius(CornerRadius.sm)
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private func normalizedSlots(for slots: [String]) -> [String] {
        let trimmed = Array(slots.prefix(16))
        if trimmed.count == 16 {
            return trimmed
        }
        return trimmed + Array(repeating: "", count: 16 - trimmed.count)
    }

    private func activeShortcutCount(for slots: [String]) -> Int {
        normalizedSlots(for: slots).filter { !$0.isEmpty }.count
    }

    @ViewBuilder
    private func shortcutSlotCard(index: Int, slotID: String, onChange: @escaping (String) -> Void) -> some View {
        let preset = CompanionShortcutBoardPreset(rawValue: slotID)

        Menu {
            Button("Empty") {
                onChange("")
            }

            Divider()

            ForEach(CompanionShortcutBoardPreset.allCases) { option in
                Button {
                    onChange(option.rawValue)
                } label: {
                    Label(option.title, systemImage: option.icon)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text("Key \(index + 1)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()

                    Image(systemName: preset?.icon ?? "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(preset?.color ?? Theme.current.foregroundSecondary)
                        .frame(width: 24, height: 24)
                        .background((preset?.color ?? Theme.current.foregroundSecondary).opacity(0.12))
                        .cornerRadius(7)
                }

                Text(preset?.title ?? "Empty")
                    .font(Theme.current.fontXSMedium)
                    .foregroundColor(Theme.current.foreground)
                    .lineLimit(1)

                Text(preset?.subtitle ?? "Leave this key open for now.")
                    .font(Theme.current.fontXS)
                    .foregroundColor(Theme.current.foregroundSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .padding(10)
            .background(Theme.current.background.opacity(0.35))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

enum CompanionShortcutBoardPreset: String, CaseIterable, Identifiable {
    case talkieRecord = "talkie-record"
    case talkieDictate = "talkie-dictate"
    case talkieSearch = "talkie-search"
    case macSessions = "mac-sessions"
    case macWindows = "mac-windows"
    case macClaude = "mac-claude"
    case talkieSSH = "talkie-ssh"
    case talkieSettings = "talkie-settings"
    case talkieMemos = "talkie-memos"
    case talkieKeyboard = "talkie-keyboard"
    case talkieHome = "talkie-home"
    case talkieAgent = "talkie-agent"
    case talkiePending = "talkie-pending"
    case talkieCommand = "talkie-command"
    case talkieRecent = "talkie-recent"
    case talkieDevices = "talkie-devices"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .talkieRecord: return "Record Memo"
        case .talkieDictate: return "Dictate"
        case .talkieSearch: return "Search"
        case .macSessions: return "Workflow Picker"
        case .macWindows: return "Screenshot"
        case .macClaude: return "Claude"
        case .talkieSSH: return "Shell"
        case .talkieSettings: return "Voice Command"
        case .talkieMemos: return "Memos"
        case .talkieKeyboard: return "Screen Recording"
        case .talkieHome: return "Home"
        case .talkieAgent: return "Pi"
        case .talkiePending: return "Pending"
        case .talkieCommand: return "Command"
        case .talkieRecent: return "Recent"
        case .talkieDevices: return "Devices"
        }
    }

    var subtitle: String {
        switch self {
        case .talkieRecord: return "Start or stop a memo recording on your Mac."
        case .talkieDictate: return "Start or stop dictation on the paired Mac."
        case .talkieSearch: return "Open Mac search inside Talkie."
        case .macSessions: return "Jump into workflows on your Mac."
        case .macWindows: return "Begin the screenshot flow on your Mac."
        case .macClaude: return "Open the Claude console tab on your Mac."
        case .talkieSSH: return "Open the Talkie Shell tab on your Mac."
        case .talkieSettings: return "Start voice command capture on the Mac."
        case .talkieMemos: return "Jump to your memo library on the Mac."
        case .talkieKeyboard: return "Begin the screen recording flow on your Mac."
        case .talkieHome: return "Bring Talkie home to the front."
        case .talkieAgent: return "Open the Pi console tab on your Mac."
        case .talkiePending: return "Open pending actions."
        case .talkieCommand: return "Open the command palette."
        case .talkieRecent: return "Open recent agent activity."
        case .talkieDevices: return "Open device settings."
        }
    }

    var icon: String {
        switch self {
        case .talkieRecord: return "square.and.pencil"
        case .talkieDictate: return "mic.fill"
        case .talkieSearch: return "magnifyingglass"
        case .macSessions: return "wand.and.stars"
        case .macWindows: return "camera.viewfinder"
        case .macClaude: return "sparkles"
        case .talkieSSH: return "terminal"
        case .talkieSettings: return "waveform.badge.mic"
        case .talkieMemos: return "waveform"
        case .talkieKeyboard: return "record.circle"
        case .talkieHome: return "house"
        case .talkieAgent: return "circle.grid.cross"
        case .talkiePending: return "hourglass"
        case .talkieCommand: return "command"
        case .talkieRecent: return "clock.arrow.circlepath"
        case .talkieDevices: return "ipad.and.iphone"
        }
    }

    var color: Color {
        switch self {
        case .talkieRecord: return .indigo
        case .talkieDictate: return .orange
        case .talkieSearch: return .blue
        case .macSessions: return .teal
        case .macWindows: return .green
        case .macClaude: return .purple
        case .talkieSSH: return .mint
        case .talkieSettings: return .pink
        case .talkieMemos: return .pink
        case .talkieKeyboard: return .red
        case .talkieHome: return .indigo
        case .talkieAgent: return .blue
        case .talkiePending: return .yellow
        case .talkieCommand: return .indigo
        case .talkieRecent: return .gray
        case .talkieDevices: return .cyan
        }
    }

    static let defaultSlots = TalkieSettingsConfiguration.defaultLegacyShortcutSlots
}

// MARK: - Delivery Settings Content

/// Delivery tab: Paste action, behavior, drafts, context
/// Everything about "what happens to the text after recording"
struct DictationDeliverySettingsContent: View {
    @Environment(AgentSettings.self) private var liveSettings: AgentSettings

    var body: some View {
        @Bindable var live = liveSettings

        VStack(alignment: .leading, spacing: Spacing.lg) {
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

            // MARK: - Selection Section
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cyan)
                        .frame(width: 3, height: 14)

                    Text("SELECTION")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)

                    Spacer()
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Selected text is replaced in place")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Text("Highlight text, start dictation, and Talkie will overwrite the current selection when it pastes.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "square.and.pencil")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                        Text("Hold Shift while recording if you want to route the result to Drafts instead.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
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
    }
}

private struct OverlayQuickPositionRow: View {
    @Binding var placement: NormalizedPlacement

    var body: some View {
        HStack(spacing: 6) {
            quickButton("Left", anchor: .init(indicatorPosition: .topLeft))
            quickButton("Center", anchor: .init(indicatorPosition: .topCenter))
            quickButton("Right", anchor: .init(indicatorPosition: .topRight))
        }
    }

    private func quickButton(_ title: String, anchor: NormalizedPlacement) -> some View {
        let isSelected = placement.nearestIndicatorPosition == anchor.nearestIndicatorPosition

        return Button(title) {
            placement = anchor
        }
        .buttonStyle(.plain)
        .font(Theme.current.fontXS)
        .foregroundColor(isSelected ? .white : Theme.current.foregroundSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isSelected ? Color.cyan.opacity(0.82) : Theme.current.surface1)
        )
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.cyan : Theme.current.divider.opacity(0.65), lineWidth: 0.5)
        )
    }
}

private struct PillQuickPositionRow: View {
    @Binding var placement: NormalizedPlacement

    var body: some View {
        HStack(spacing: 6) {
            quickButton("Left", anchor: .init(pillPosition: .bottomLeft))
            quickButton("Center", anchor: .init(pillPosition: .bottomCenter))
            quickButton("Right", anchor: .init(pillPosition: .bottomRight))
        }
    }

    private func quickButton(_ title: String, anchor: NormalizedPlacement) -> some View {
        let currentSelection = placement.nearestPillPosition == .topCenter ? PillPosition.bottomCenter : placement.nearestPillPosition
        let isSelected = currentSelection == anchor.nearestPillPosition

        return Button(title) {
            placement = anchor
        }
        .buttonStyle(.plain)
        .font(Theme.current.fontXS)
        .foregroundColor(isSelected ? .white : Theme.current.foregroundSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isSelected ? Color.cyan.opacity(0.82) : Theme.current.surface1)
        )
        .overlay(
            Capsule()
                .stroke(isSelected ? Color.cyan : Theme.current.divider.opacity(0.65), lineWidth: 0.5)
        )
    }
}

// MARK: - Capture Settings Recap (JSON)

/// Compact JSON representation of capture settings
struct CaptureSettingsRecap: View {
    @Environment(AgentSettings.self) private var liveSettings: AgentSettings

    private var jsonString: String {
        let settings: [String: Any] = [
            "hotkey": liveSettings.hotkey.displayString,
            "ptt": [
                "enabled": liveSettings.pttEnabled,
                "hotkey": liveSettings.pttHotkey.displayString
            ],
            "overlay": [
                "style": liveSettings.overlayStyle.rawValue,
                "position": liveSettings.overlayPosition.rawValue
            ],
            "floatingPill": [
                "position": liveSettings.pillPosition.rawValue,
                "expands": liveSettings.pillExpandsDuringRecording,
                "allScreens": liveSettings.pillShowOnAllScreens
            ],
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

#Preview("Recording") {
    DictationRecordingSettingsContent()
        .environment(AgentSettings.shared)
        .frame(width: 600, height: 800)
}

#Preview("Delivery") {
    DictationDeliverySettingsContent()
        .environment(AgentSettings.shared)
        .frame(width: 600, height: 500)
}
