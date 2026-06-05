//
//  SelectionSettingsView.swift
//  Talkie macOS
//
//  Selection input settings: Trigger + Processing tabs
//  Configures the Quick Selection / Reader pipeline:
//  highlight text → hotkey → optional LLM processing → TTS readback
//

import SwiftUI
import TalkieKit

private let log = Log(.ui)

// MARK: - Selection Settings (Tabbed)

struct SelectionSettingsView: View {
    @Environment(AgentSettings.self) private var settings: AgentSettings
    @State private var selectedTab: SelectionTab = .trigger

    enum SelectionTab: String, CaseIterable {
        case trigger = "TRIGGER"
        case processing = "PROCESSING"

        var icon: String {
            switch self {
            case .trigger: return "keyboard"
            case .processing: return "wand.and.stars"
            }
        }

        var color: Color {
            switch self {
            case .trigger: return .green
            case .processing: return .orange
            }
        }
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "text.cursor",
                title: "SELECTION",
                subtitle: "Select text in any app, then speak or summarize it."
            )
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(SelectionTab.allCases, id: \.rawValue) { tab in
                        tabItem(tab)
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.sm)

                Rectangle()
                    .fill(Theme.current.divider)
                    .frame(height: 1)

                ScrollView {
                    switch selectedTab {
                    case .trigger:
                        SelectionTriggerContent()
                            .padding(.top, Spacing.md)
                    case .processing:
                        SelectionProcessingContent()
                            .padding(.top, Spacing.md)
                    }
                }
            }
        }
        .onAppear {
            log.debug("SelectionSettingsView appeared")
        }
    }

    @ViewBuilder
    private func tabItem(_ tab: SelectionTab) -> some View {
        let isSelected = selectedTab == tab

        Button(action: { selectedTab = tab }) {
            VStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11))

                    Text(tab.rawValue)
                        .font(Theme.current.fontXSBold)
                }
                .foregroundColor(isSelected ? tab.color : Theme.current.foregroundSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

                Rectangle()
                    .fill(isSelected ? tab.color : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trigger Tab

struct SelectionTriggerContent: View {
    @Environment(AgentSettings.self) private var settings: AgentSettings
    @State private var isRecordingHotkey = false

    var body: some View {
        @Bindable var s = settings

        VStack(alignment: .leading, spacing: Spacing.lg) {
            // MARK: - Shortcut Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.green)
                        .frame(width: 3, height: 14)

                    Text("SHORTCUT")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.sm) {
                        Text("Quick Selection")
                            .font(Theme.current.fontSMMedium)
                            .foregroundColor(Theme.current.foreground)

                        Toggle("", isOn: $s.selectionEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                    }

                    Text("Select text in any app, then press the shortcut to read or summarize it aloud.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)

                    HotkeyRecorderButton(
                        hotkey: $s.selectionQuickHotkey,
                        isRecording: $isRecordingHotkey
                    )
                    .opacity(s.selectionEnabled ? 1.0 : 0.5)
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Feedback Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple)
                        .frame(width: 3, height: 14)

                    Text("FEEDBACK")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show feedback overlay")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)

                            Text("Toast HUD showing mode and playback controls near the cursor.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }

                        Spacer()

                        Toggle("", isOn: $s.selectionShowFeedbackOverlay)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Capture Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.blue)
                        .frame(width: 3, height: 14)

                    Text("CAPTURE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Screenshot source window")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)

                            Text("Capture a screenshot of the app window when reading a selection.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }

                        Spacer()

                        Toggle("", isOn: $s.selectionCaptureScreenshot)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep history")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)

                            Text("Store readouts in the library. Turn off for ephemeral use.")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundMuted)
                        }

                        Spacer()

                        Toggle("", isOn: $s.selectionKeepHistory)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.mini)
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
    }
}

// MARK: - Processing Tab

struct SelectionProcessingContent: View {
    @Environment(AgentSettings.self) private var settings: AgentSettings

    var body: some View {
        @Bindable var s = settings

        VStack(alignment: .leading, spacing: Spacing.lg) {
            // MARK: - Mode Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3, height: 14)

                    Text("MODE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("How selected text is processed before speaking.")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.bottom, Spacing.xs)

                    ForEach(SelectionMode.allCases) { mode in
                        RadioButtonRow(
                            title: mode.displayName,
                            description: mode.description,
                            value: mode,
                            selectedValue: s.selectionDefaultMode,
                            onSelect: {
                                s.selectionDefaultMode = mode
                            }
                        )
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - App Overrides Section (only in Auto mode)
            if s.selectionDefaultMode == .auto {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(spacing: Spacing.sm) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.blue)
                            .frame(width: 3, height: 14)

                        Text("APP OVERRIDES")
                            .font(Theme.current.fontXSBold)
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }

                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("In Auto mode, these app categories use specific processing.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                            .padding(.bottom, Spacing.xs)

                        ForEach(Array(s.selectionAppOverrides.enumerated()), id: \.element.id) { index, override in
                            appOverrideRow(index: index, override: override)
                        }
                    }
                    .padding(Spacing.sm)
                    .background(Theme.current.surface1)
                    .cornerRadius(CornerRadius.sm)
                }
                .settingsSectionCard(padding: Spacing.md)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // MARK: - Voice Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.teal)
                        .frame(width: 3, height: 14)

                    Text("VOICE")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                SelectionVoicePickerCard(selectionTTSVoiceId: Binding(
                    get: { s.selectionTTSVoiceId },
                    set: { s.selectionTTSVoiceId = $0 }
                ))

                SelectionVoicePickerCard(
                    selectionTTSVoiceId: Binding(
                        get: { s.agentVoiceTTSVoiceId },
                        set: { s.agentVoiceTTSVoiceId = $0 }
                    ),
                    title: "Use dedicated Agent reply voice",
                    dedicatedDescription: "Agent replies use their own TTS voice.",
                    inheritedDescription: "Agent replies use selection/global TTS fallback.",
                    defaultVoiceId: {
                        TTSVoiceCatalog.recommendedSettingsVoiceId(
                            hasOpenAIKey: SettingsManager.shared.hasOpenAIKey()
                        )
                    }
                )
            }
            .settingsSectionCard(padding: Spacing.md)

            // MARK: - Timing Section
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.gray)
                        .frame(width: 3, height: 14)

                    Text("TIMING")
                        .font(Theme.current.fontXSBold)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    // LLM Timeout
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("LLM timeout")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)

                            Spacer()

                            Text("\(Int(s.selectionLLMTimeout))s")
                                .font(Theme.current.fontSM.monospacedDigit())
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Slider(value: $s.selectionLLMTimeout, in: 3...15, step: 1)
                            .controlSize(.small)

                        Text("Maximum time to wait for LLM processing before falling back to verbatim.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }

                    Divider()

                    // Short text threshold
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("Short text threshold")
                                .font(Theme.current.fontSMMedium)
                                .foregroundColor(Theme.current.foreground)

                            Spacer()

                            Text("\(s.selectionShortTextThreshold) words")
                                .font(Theme.current.fontSM.monospacedDigit())
                                .foregroundColor(Theme.current.foregroundSecondary)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(s.selectionShortTextThreshold) },
                                set: { s.selectionShortTextThreshold = Int($0) }
                            ),
                            in: 10...200,
                            step: 5
                        )
                        .controlSize(.small)

                        Text("In Auto mode, selections shorter than this are read verbatim.")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                }
                .padding(Spacing.sm)
                .background(Theme.current.surface1)
                .cornerRadius(CornerRadius.sm)
            }
            .settingsSectionCard(padding: Spacing.md)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
        .animation(.easeInOut(duration: 0.2), value: settings.selectionDefaultMode)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func appOverrideRow(index: Int, override: SelectionAppCategoryOverride) -> some View {
        @Bindable var s = settings

        HStack(spacing: Spacing.sm) {
            Image(systemName: iconForCategory(override.id))
                .font(.system(size: 11))
                .foregroundColor(Theme.current.foregroundSecondary)
                .frame(width: 20)

            Text(override.label)
                .font(Theme.current.fontSMMedium)
                .foregroundColor(Theme.current.foreground)

            Spacer()

            Picker("", selection: Binding(
                get: { override.mode },
                set: { newMode in
                    var updated = s.selectionAppOverrides
                    updated[index].mode = newMode
                    s.selectionAppOverrides = updated
                }
            )) {
                ForEach([SelectionMode.verbatim, .summary, .explanation], id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
        .padding(.vertical, 2)
    }

    private func iconForCategory(_ id: String) -> String {
        switch id {
        case "terminals": return "terminal"
        case "code": return "chevron.left.forwardslash.chevron.right"
        case "browsers": return "globe"
        case "documents": return "doc.text"
        default: return "app"
        }
    }

}

// MARK: - Voice Picker Card

private struct SelectionVoicePickerCard: View {
    @Binding var selectionTTSVoiceId: String?
    var title = "Use dedicated voice"
    var dedicatedDescription = "Selection uses its own TTS voice."
    var inheritedDescription = "Using global TTS voice from Models settings."
    var defaultVoiceId: () -> String = {
        TalkieSharedSettings.string(forKey: AgentSettingsKey.selectedTTSVoiceId)
            ?? TTSVoiceCatalog.recommendedSettingsVoiceId(hasOpenAIKey: SettingsManager.shared.hasOpenAIKey())
    }

    @State private var availableVoices: [VoiceOption] = []
    @State private var isLoading = true

    private var hasDedicatedVoice: Bool { selectionTTSVoiceId != nil }

    /// Effective voice ID — what's actually selected (or the global fallback label)
    private var effectiveVoiceId: String {
        selectionTTSVoiceId ?? "global"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.current.fontSMMedium)
                        .foregroundColor(Theme.current.foreground)

                    Text(hasDedicatedVoice
                         ? dedicatedDescription
                         : inheritedDescription)
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { hasDedicatedVoice },
                    set: { newValue in
                        if newValue {
                            selectionTTSVoiceId = defaultVoiceId()
                        } else {
                            selectionTTSVoiceId = nil
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
            }

            if hasDedicatedVoice {
                Divider()

                if isLoading {
                    HStack(spacing: Spacing.sm) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading voices...")
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundMuted)
                    }
                } else {
                    // Grouped voice picker
                    Picker("Voice", selection: Binding(
                        get: { selectionTTSVoiceId ?? "" },
                        set: { selectionTTSVoiceId = $0 }
                    )) {
                        let grouped = Dictionary(grouping: availableVoices, by: \.provider)
                        let providerOrder: [String] = ["OpenAI", "ElevenLabs Free", "ElevenLabs Premium", "Apple"]

                        ForEach(providerOrder, id: \.self) { provider in
                            if let voices = grouped[provider], !voices.isEmpty {
                                Section(provider) {
                                    ForEach(voices) { voice in
                                        Text(voice.label).tag(voice.id)
                                    }
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
        }
        .padding(Spacing.sm)
        .background(Theme.current.surface1)
        .cornerRadius(CornerRadius.sm)
        .onAppear {
            if selectionTTSVoiceId?.hasPrefix("kokoro:") == true {
                selectionTTSVoiceId = nil
            }
            loadVoices()
        }
    }

    private func loadVoices() {
        Task.detached(priority: .userInitiated) {
            var voices: [VoiceOption] = []

            // OpenAI voices
            for voice in TTSVoiceCatalog.openAIVoices {
                voices.append(VoiceOption(
                    id: voice.id,
                    label: "\(voice.displayName) — \(voice.style)",
                    provider: "OpenAI"
                ))
            }

            // ElevenLabs voices
            for voice in TTSVoiceCatalog.elevenLabsVoices {
                voices.append(VoiceOption(
                    id: voice.id,
                    label: "\(voice.displayName) — \(voice.style)",
                    provider: voice.accessTier == .included ? "ElevenLabs Free" : "ElevenLabs Premium"
                ))
            }

            // Apple system voices (English only, top quality first)
            let appleVoices = TTSVoiceCatalog.englishStarterSystemVoices(limit: 12)
            for voice in appleVoices {
                voices.append(VoiceOption(
                    id: voice.id,
                    label: "\(voice.displayName) — \(voice.style)",
                    provider: "Apple"
                ))
            }

            let loadedVoices = voices
            await MainActor.run {
                availableVoices = loadedVoices
                isLoading = false
            }
        }
    }
}

private struct VoiceOption: Identifiable {
    let id: String
    let label: String
    let provider: String
}

// OpenAITTSVoiceCatalog is defined in ModelsCatalog.swift

// MARK: - Previews

#Preview("Selection Settings") {
    SelectionSettingsView()
        .environment(AgentSettings.shared)
        .frame(width: 600, height: 800)
}
