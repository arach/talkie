//
//  TTSVoicesSettingsView.swift
//  Talkie
//
//  Settings view for Text-to-Speech voice selection.
//  Highlights Apple, OpenAI, and ElevenLabs voices.
//

import AppKit
import SwiftUI
import TalkieKit

struct TTSVoicesSettingsView: View {
    @State private var settings = SettingsManager.shared
    @State private var appleVoices: [TTSVoiceMetadata] = []
    @State private var isLoadingAppleVoices = true
    @State private var showingAppleVoiceBrowser = false
    @State private var previewVoiceId: String?
    @State private var previewText = "Talkie can read selected text back to you with the voice you choose here."
    @State private var isPreviewing = false
    @State private var previewError: String?

    private var resolvedSelectedVoiceId: String {
        TTSVoiceCatalog.voice(byId: settings.selectedTTSVoiceId)?.id
            ?? TTSVoiceCatalog.recommendedSettingsVoiceId(hasOpenAIKey: settings.hasOpenAIKey())
    }

    private var voiceGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 188, maximum: 220), spacing: 10)]
    }

    var body: some View {
        SettingsPageContainer {
            SettingsPageHeader(
                icon: "speaker.wave.2",
                title: "TEXT-TO-SPEECH VOICES",
                subtitle: "Choose between Apple, OpenAI, and ElevenLabs voices."
            )
        } content: {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                previewSection
                openAISection
                elevenLabsSection
                appleSection
            }
        }
        .onAppear {
            migrateLegacyVoiceSelectionIfNeeded()
            loadAppleVoicesIfNeeded()
            syncSelectedAppleVoice()
        }
        .sheet(isPresented: $showingAppleVoiceBrowser) {
            AppleVoiceBrowserSheet(
                voices: appleVoices,
                selectedVoiceId: resolvedSelectedVoiceId,
                previewVoiceId: previewVoiceId,
                onSelect: { voice in
                    selectVoice(voice)
                },
                onPreview: { voice in
                    setPreviewVoice(voice)
                }
            )
        }
    }

    private var appleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(
                title: "APPLE",
                subtitle: "Curated English starters",
                color: TTSVoiceProvider.apple.color,
                repoURL: nil,
                demoURL: nil
            )

            Text("Start with a few strong English voices. Open the library for everything else already installed on this Mac.")
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)

            LazyVGrid(columns: voiceGridColumns, spacing: 12) {
                if isLoadingAppleVoices {
                    ForEach(0..<3, id: \.self) { _ in
                        AppleVoicePlaceholderCard()
                    }
                    AppleVoiceLibraryCard(
                        totalVoiceCount: nil,
                        extraVoiceCount: nil,
                        onBrowse: {},
                        onOpenSettings: {}
                    )
                    .redacted(reason: .placeholder)
                } else if curatedAppleVoices.isEmpty {
                    AppleVoiceEmptyCard(
                        onBrowse: showAppleVoiceBrowser,
                        onOpenSettings: openAppleVoiceSettings
                    )

                    AppleVoiceLibraryCard(
                        totalVoiceCount: appleVoices.count,
                        extraVoiceCount: nil,
                        onBrowse: showAppleVoiceBrowser,
                        onOpenSettings: openAppleVoiceSettings
                    )
                } else {
                    ForEach(curatedAppleVoices, id: \.id) { voice in
                        voiceCard(for: voice)
                    }

                    AppleVoiceLibraryCard(
                        totalVoiceCount: appleVoices.count,
                        extraVoiceCount: max(appleVoices.count - curatedAppleVoices.count, 0),
                        onBrowse: showAppleVoiceBrowser,
                        onOpenSettings: openAppleVoiceSettings
                    )
                }
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var openAISection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(
                title: "OPENAI",
                subtitle: "Fast cloud voices with a clean default lineup",
                color: TTSVoiceProvider.openAI.color,
                repoURL: nil,
                demoURL: nil,
                isLocal: false
            )

            if settings.hasOpenAIKey() {
                Text("Great cost-to-quality pick for readback. Includes the full OpenAI voice set for preview and selection.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)

                LazyVGrid(columns: voiceGridColumns, spacing: 10) {
                    ForEach(TTSVoiceCatalog.openAIVoices, id: \.id) { voice in
                        voiceCard(for: voice)
                    }
                }
            } else {
                OpenAISetupCard()
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREVIEW")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.current.foreground)

                    Text(previewSummaryText)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.current.foregroundMuted)
                }

                Spacer()

                if isPreviewing {
                    Button("Stop") {
                        stopPreview()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Play Preview") {
                        playPreview()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(previewTargetVoice == nil)
                }
            }

            TextEditor(text: $previewText)
                .font(.system(size: 12))
                .frame(minHeight: 72)
                .padding(8)
                .background(Theme.current.surface2)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Theme.current.divider, lineWidth: 1)
                )

            if let previewError, !previewError.isEmpty {
                Text(previewError)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    private var elevenLabsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(
                title: "ELEVENLABS",
                subtitle: "Cloud voices split by plan access",
                color: TTSVoiceProvider.elevenLabs.color,
                repoURL: nil,
                demoURL: nil,
                isLocal: false
            )

            if settings.hasElevenLabsKey() {
                Text("Premade voices work on free plans. Voice Library picks may require a paid ElevenLabs plan.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)

                voiceGroup(
                    title: "Included On Free Plans",
                    subtitle: "Premade ElevenLabs voices available by default.",
                    voices: TTSVoiceCatalog.elevenLabsFreeVoices,
                    accent: TTSVoiceProvider.elevenLabs.color
                )

                if !TTSVoiceCatalog.elevenLabsPremiumVoices.isEmpty {
                    voiceGroup(
                        title: "Premium Voices",
                        subtitle: "Voice Library picks that may need paid access.",
                        voices: TTSVoiceCatalog.elevenLabsPremiumVoices,
                        accent: Color.orange.opacity(0.85)
                    )
                }
            } else {
                ElevenLabsSetupCard()
            }
        }
        .settingsSectionCard(padding: Spacing.md)
    }

    // MARK: - Section Header

    private func sectionHeader(
        title: String,
        subtitle: String,
        color: Color,
        repoURL: URL?,
        demoURL: URL?,
        isLocal: Bool = true
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Rectangle()
                .fill(color)
                .frame(width: 3, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 1))

            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.current.foreground)

            Text("•")
                .foregroundColor(Theme.current.foregroundMuted)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)

            LocalCloudBadge(isLocal: isLocal)

            Spacer()

            // Links
            if let repoURL {
                Link(destination: repoURL) {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                        Text("Repo")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }

            if let demoURL {
                Link(destination: demoURL) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.circle")
                            .font(.system(size: 9))
                        Text("Demo")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(Theme.current.foregroundMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func voiceGroup(
        title: String,
        subtitle: String,
        voices: [TTSVoiceMetadata],
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            LazyVGrid(columns: voiceGridColumns, spacing: 10) {
                ForEach(voices, id: \.id) { voice in
                    voiceCard(for: voice)
                }
            }
        }
    }

    // MARK: - Voice Card

    private func voiceCard(for voice: TTSVoiceMetadata) -> some View {
        let isSelected = resolvedSelectedVoiceId == voice.id
        let isPreviewTarget = previewVoiceId == voice.id

        return TTSVoiceCard(
            voice: voice,
            isSelected: isSelected,
            isPreviewTarget: isPreviewTarget,
            onPreview: { setPreviewVoice(voice) },
            onSelect: { selectVoice(voice) }
        )
    }

    // MARK: - Actions

    private func selectVoice(_ voice: TTSVoiceMetadata) {
        settings.selectedTTSVoiceId = voice.id
        previewVoiceId = nil

        switch voice.provider {
        case .apple:
            SpeechSynthesisService.shared.selectedVoiceIdentifier = voice.voiceId
        case .elevenLabs, .openAI:
            break
        }
    }

    private func loadAppleVoicesIfNeeded(force: Bool = false) {
        if !force, !appleVoices.isEmpty { return }

        isLoadingAppleVoices = true
        Task.detached(priority: .userInitiated) {
            let voices = TTSVoiceCatalog.systemVoices()
            await MainActor.run {
                self.appleVoices = voices
                self.isLoadingAppleVoices = false
            }
        }
    }

    private func showAppleVoiceBrowser() {
        if appleVoices.isEmpty {
            loadAppleVoicesIfNeeded(force: true)
        }
        showingAppleVoiceBrowser = true
    }

    private func setPreviewVoice(_ voice: TTSVoiceMetadata) {
        previewVoiceId = voice.id
        previewError = nil
    }

    private func migrateLegacyVoiceSelectionIfNeeded() {
        guard settings.selectedTTSVoiceId.hasPrefix("kokoro:") else { return }
        settings.selectedTTSVoiceId = TTSVoiceCatalog.recommendedSettingsVoiceId(hasOpenAIKey: settings.hasOpenAIKey())
    }

    private func syncSelectedAppleVoice() {
        let selectedVoiceId = resolvedSelectedVoiceId
        guard selectedVoiceId.hasPrefix("com.apple.voice") else { return }
        SpeechSynthesisService.shared.selectedVoiceIdentifier = selectedVoiceId
    }

    private func openAppleVoiceSettings() {
        if let voiceSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Accessibility?SpokenContent") {
            NSWorkspace.shared.open(voiceSettingsURL)
            return
        }

        if let settingsURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: settingsURL, configuration: configuration)
        }
    }

    private var selectedVoice: TTSVoiceMetadata? {
        appleVoices.first { $0.id == resolvedSelectedVoiceId }
            ?? TTSVoiceCatalog.voice(byId: resolvedSelectedVoiceId)
    }

    private var previewTargetVoice: TTSVoiceMetadata? {
        if let previewVoiceId {
            return appleVoices.first { $0.id == previewVoiceId }
                ?? TTSVoiceCatalog.voice(byId: previewVoiceId)
        }

        return selectedVoice
    }

    private var curatedAppleVoices: [TTSVoiceMetadata] {
        var starters = TTSVoiceCatalog.englishStarterSystemVoices(limit: 3).filter { starter in
            appleVoices.contains(where: { $0.id == starter.id })
        }
        if let selectedVoice, selectedVoice.provider == .apple,
           !starters.contains(where: { $0.id == selectedVoice.id }) {
            starters = Array(([selectedVoice] + starters).prefix(3))
        }
        return starters
    }

    private var previewSummaryText: String {
        guard let previewTargetVoice else {
            if resolvedSelectedVoiceId.hasPrefix("com.apple.voice") {
                return "Current voice: Apple voice"
            }
            return "Select a voice to hear it."
        }

        if previewVoiceId != nil, previewTargetVoice.id != resolvedSelectedVoiceId {
            return "Previewing \(previewTargetVoice.displayName) • not selected"
        }

        return "Current voice: \(previewTargetVoice.displayName) • \(previewTargetVoice.provider.displayName)"
    }

    private func playPreview() {
        guard !previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let previewTargetVoice else { return }

        previewError = nil
        isPreviewing = true

        switch previewTargetVoice.provider {
        case .apple:
            let speechService = SpeechSynthesisService.shared
            speechService.selectedVoiceIdentifier = previewTargetVoice.voiceId
            speechService.speak(previewText) {
                Task { @MainActor in
                    isPreviewing = false
                }
            }
        case .elevenLabs:
            Task {
                do {
                    let apiKey = SettingsManager.shared.fetchElevenLabsKey()
                    let audioURL = try await TTSService.synthesizeElevenLabs(
                        text: previewText,
                        voiceId: previewTargetVoice.voiceId,
                        apiKey: apiKey
                    )
                    await MainActor.run {
                        if let sound = NSSound(contentsOf: audioURL, byReference: true) {
                            sound.play()
                        } else {
                            previewError = "Preview audio was generated but could not be played."
                        }
                        isPreviewing = false
                    }
                } catch {
                    await MainActor.run {
                        previewError = "Preview failed: \(error.localizedDescription)"
                        isPreviewing = false
                    }
                }
            }
        case .openAI:
            Task {
                do {
                    let apiKey = SettingsManager.shared.openaiApiKey
                    let audioURL = try await TTSService.synthesizeOpenAI(
                        text: previewText,
                        voice: previewTargetVoice.voiceId,
                        apiKey: apiKey
                    )
                    await MainActor.run {
                        if let sound = NSSound(contentsOf: audioURL, byReference: true) {
                            sound.play()
                        } else {
                            previewError = "Preview audio was generated but could not be played."
                        }
                        isPreviewing = false
                    }
                } catch {
                    await MainActor.run {
                        previewError = "Preview failed: \(error.localizedDescription)"
                        isPreviewing = false
                    }
                }
            }
        }
    }

    private func stopPreview() {
        SpeechSynthesisService.shared.stop()
        isPreviewing = false
    }
}

// MARK: - TTS Voice Card

struct TTSVoiceCard: View {
    let voice: TTSVoiceMetadata
    let isSelected: Bool
    let isPreviewTarget: Bool
    let onPreview: () -> Void
    let onSelect: () -> Void

    private let settings = SettingsManager.shared
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                HStack(spacing: 4) {
                    Text(voice.provider.badge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(voice.provider.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(voice.provider.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    if voice.provider == .elevenLabs {
                        Text(voice.accessTier.badgeText)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(voice.accessTier == .premium ? Color.orange : Color.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background((voice.accessTier == .premium ? Color.orange : Color.green).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    Text(voice.secondaryBadgeText ?? voice.gender.prefix(1).uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Theme.current.foregroundMuted.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                if isSelected {
                    statusPill("SELECTED", color: settings.midnightStatusReady)
                } else if isPreviewTarget {
                    statusPill("PREVIEW", color: voice.provider.color.opacity(0.9))
                }
            }

            Text(voice.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(settings.midnightTextPrimary)
                .lineLimit(1)

            Text(voice.description)
                .font(.system(size: 9))
                .foregroundColor(settings.midnightTextSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text(voice.style)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(settings.midnightTextSecondary)

                Text("•")
                    .foregroundColor(settings.midnightTextTertiary)

                Text(voice.language)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(settings.midnightTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            actionButton
        }
        .padding(10)
        .frame(height: 104, alignment: .top)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var cardBackground: Color {
        isHovered ? settings.midnightSurfaceHover : settings.midnightSurface
    }

    private var borderColor: Color {
        if isSelected {
            return voice.provider.color.opacity(0.6)
        }
        if isPreviewTarget {
            return voice.provider.color.opacity(0.35)
        }
        if isHovered {
            return settings.midnightBorderActive
        }
        return settings.midnightBorder
    }

    private func statusPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundColor(color)
    }

    @ViewBuilder
    private var actionButton: some View {
        HStack(spacing: 8) {
            Button(action: onPreview) {
                Text("Preview")
                    .font(.system(size: 9, weight: .medium))
                .foregroundColor(isPreviewTarget ? voice.provider.color : Theme.current.foregroundMuted)
            }
            .buttonStyle(.plain)

            Spacer()

            if !isSelected {
                Button(action: onSelect) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 9))
                        Text("Select")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            } else {
                Text("Selected")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(settings.midnightStatusReady)
            }
        }
    }
}

private struct AppleVoiceBrowserSheet: View {
    let voices: [TTSVoiceMetadata]
    let selectedVoiceId: String
    let previewVoiceId: String?
    let onSelect: (TTSVoiceMetadata) -> Void
    let onPreview: (TTSVoiceMetadata) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var languageFilter: AppleVoiceLanguageFilter = .english

    private var filteredVoices: [TTSVoiceMetadata] {
        voices.filter { voice in
            let matchesLanguage: Bool = {
                switch languageFilter {
                case .english:
                    return voice.localeIdentifier?.lowercased().hasPrefix("en") == true
                case .all:
                    return true
                }
            }()
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || voice.displayName.localizedStandardContains(query)
                || voice.language.localizedStandardContains(query)
                || voice.style.localizedStandardContains(query)
            return matchesLanguage && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.md) {
                    TextField("Search voices", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Picker("Filter", selection: $languageFilter) {
                        ForEach(AppleVoiceLanguageFilter.allCases, id: \.self) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }

                Text("\(filteredVoices.count) voices shown • premium and enhanced voices appear first")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.current.foregroundMuted)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredVoices, id: \.id) { voice in
                            AppleVoiceRow(
                                voice: voice,
                                isSelected: selectedVoiceId == voice.id,
                                isPreviewTarget: previewVoiceId == voice.id,
                                onPreview: {
                                    onPreview(voice)
                                },
                                onSelect: {
                                    onSelect(voice)
                                    dismiss()
                                }
                            )
                        }
                    }
                }
            }
            .padding(Spacing.lg)
            .navigationTitle("Apple Voices")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

private enum AppleVoiceLanguageFilter: CaseIterable {
    case english
    case all

    var label: String {
        switch self {
        case .english: return "English"
        case .all: return "All Languages"
        }
    }
}

private struct AppleVoicePlaceholderCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.current.surface2)
                .frame(width: 42, height: 16)

            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.current.surface2)
                .frame(width: 110, height: 14)

            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.current.surface2)
                .frame(height: 12)

            Spacer()

            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.current.surface2)
                .frame(width: 58, height: 12)
        }
        .padding(10)
        .frame(height: 104)
        .background(Theme.current.surface1)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.divider, lineWidth: 1)
        )
    }
}

private struct AppleVoiceLibraryCard: View {
    let totalVoiceCount: Int?
    let extraVoiceCount: Int?
    let onBrowse: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LIBRARY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(TTSVoiceProvider.apple.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(TTSVoiceProvider.apple.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Spacer()

                if let totalVoiceCount {
                    Text("\(totalVoiceCount)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.current.foregroundMuted)
                }
            }

            Text(libraryTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.current.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Text(librarySubtitle)
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            HStack {
                Button("Browse Library", action: onBrowse)
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.blue)

                Spacer()

                Button("Apple Settings", action: onOpenSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(10)
        .frame(height: 104)
        .background(Theme.current.surface1)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.divider, lineWidth: 1)
        )
    }

    private var libraryTitle: String {
        if let extraVoiceCount {
            return "\(extraVoiceCount)+ more voices"
        }
        if let totalVoiceCount {
            return "\(totalVoiceCount) installed voices"
        }
        return "More Apple voices"
    }

    private var librarySubtitle: String {
        if totalVoiceCount != nil {
            return "Browse the full installed library, with premium and enhanced voices listed first."
        }
        return "Browse the full library or open Apple settings to add more voices."
    }
}

private struct AppleVoiceEmptyCard: View {
    let onBrowse: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Apple voices loaded yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.current.foreground)

            Text("Open the library to retry the scan, or jump to Apple settings to manage voices.")
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button("Browse", action: onBrowse)
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.blue)

                Spacer()

                Button("Settings", action: onOpenSettings)
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.current.foregroundMuted)
            }
        }
        .padding(10)
        .frame(height: 104)
        .background(Theme.current.surface1)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.divider, lineWidth: 1)
        )
    }
}

private struct OpenAISetupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add an OpenAI API key")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.current.foreground)

            Text("Configure OpenAI in AI Providers to enable fast cloud readback and previews here.")
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text("Settings → AI Providers")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(TTSVoiceProvider.openAI.color)
        }
        .padding(10)
        .frame(height: 104)
        .background(Theme.current.surface1)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.divider, lineWidth: 1)
        )
    }
}

private struct ElevenLabsSetupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add an ElevenLabs API key")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.current.foreground)

            Text("Configure ElevenLabs in AI Providers to unlock both free-plan and premium voice previews here.")
                .font(.system(size: 10))
                .foregroundColor(Theme.current.foregroundMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text("Settings → AI Providers")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(TTSVoiceProvider.elevenLabs.color)
        }
        .padding(10)
        .frame(height: 104)
        .background(Theme.current.surface1)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(Theme.current.divider, lineWidth: 1)
        )
    }
}

private struct AppleVoiceRow: View {
    let voice: TTSVoiceMetadata
    let isSelected: Bool
    let isPreviewTarget: Bool
    let onPreview: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(voice.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.current.foreground)

                    if let badge = voice.secondaryBadgeText {
                        Text(badge)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(TTSVoiceProvider.apple.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(TTSVoiceProvider.apple.color.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if isPreviewTarget {
                        Text("PREVIEW")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(TTSVoiceProvider.apple.color.opacity(0.85))
                    }
                }

                Text("\(voice.language) • \(voice.description)")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.current.foregroundMuted)
            }

            Spacer()

            HStack(spacing: 12) {
                Button("Preview", action: onPreview)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isPreviewTarget ? TTSVoiceProvider.apple.color : Theme.current.foregroundMuted)

                Button(isSelected ? "Selected" : "Select", action: onSelect)
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .blue : Theme.current.foregroundMuted)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.current.surface2 : Theme.current.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .stroke(
                    isSelected ? TTSVoiceProvider.apple.color.opacity(0.5) :
                        (isPreviewTarget ? TTSVoiceProvider.apple.color.opacity(0.25) : Theme.current.divider),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
    }
}

// MARK: - Preview

#Preview("TTS Voices Settings") {
    TTSVoicesSettingsView()
        .frame(width: 600, height: 500)
}
