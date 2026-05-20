//
//  ReadAloudNext.swift
//  Talkie iOS
//
//  Read Aloud — TTS playback surface for the Next shell.
//

import AVFoundation
import SwiftUI
import UIKit

struct ReadAloudNext: View {
    @EnvironmentObject private var chromeState: ShellChrome
    @ObservedObject private var theme = ThemeManager.shared
    @State private var player = ReadAloudPlayer()
    @State private var speechService = SpeechSynthesisService.shared

    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                hairline

                ScrollView {
                    VStack(spacing: 0) {
                        if player.variant == .idle {
                            IdleSourcePicker(player: player)
                        } else {
                            NowReadingPanel(player: player)
                            SourceViewer(player: player)
                        }

                        VoiceControls(player: player)

                        if player.variant == .queue {
                            QueueList(player: player)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 88)
                }
                .scrollIndicators(.hidden)
            }
        }
        .onAppear {
            player.bind(speechService: speechService)
        }
        .onDisappear {
            player.stop()
        }
        .onChange(of: player.rate) { _, newValue in
            speechService.setPlaybackRate(Float(newValue))
        }
        .onChange(of: player.pitch) { _, newValue in
            speechService.speechPitch = Float(newValue)
        }
        .onChange(of: player.selectedVoiceIdentifier) { _, newValue in
            speechService.selectedVoiceIdentifier = newValue
        }
    }

    private var header: some View {
        HStack {
            Text("TALKIE · READ ALOUD")
                .talkieType(.wordmark)
                .foregroundStyle(theme.colors.textSecondary)
            Spacer()
            Button {
                player.stop()
                chromeState.dismissChrome()
                AppShellRouter.shared.openHome()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(theme.currentTheme.chrome.edgeFaint.opacity(0.72)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var hairline: some View {
        Rectangle()
            .fill(theme.currentTheme.chrome.edgeFaint)
            .frame(height: theme.currentTheme.chrome.hairlineWidth)
    }
}

// MARK: - Player model

@MainActor
@Observable
final class ReadAloudPlayer {
    enum Variant: String, CaseIterable, Identifiable {
        case idle, playing, queue
        var id: String { rawValue }
    }

    enum SourceKind: String, CaseIterable, Identifiable {
        case text, image, url, pdf
        var id: String { rawValue }

        var label: String { rawValue.uppercased() }
        var icon: String {
            switch self {
            case .text: return "doc.text"
            case .image: return "photo"
            case .url: return "link"
            case .pdf: return "doc.richtext"
            }
        }
    }

    struct Item: Identifiable {
        let id = UUID()
        let kind: SourceKind
        let title: String
        let meta: String
        let sourcePath: String
        let text: String
        let sourceURL: URL?
        let referenceEyebrow: String?
        let duration: TimeInterval
    }

    struct QueueItem: Identifiable {
        let id = UUID()
        let title: String
        let meta: String
    }

    var variant: Variant = .playing
    var selectedKind: SourceKind = .text
    var sourceExpanded = true
    var selectedVoiceIdentifier: String?
    var rate = 1.0
    var pitch = 1.0
    var autoPause = true
    var activeChunkIndex = 1
    var progress = 0.44
    var voices: [AVSpeechSynthesisVoice] = []

    private weak var speechService: SpeechSynthesisService?
    private var progressTask: Task<Void, Never>?
    private var chunksCache: [String] = []

    let queue: [QueueItem] = [
        QueueItem(title: "Idea: offline-first sync architecture", meta: "1:42"),
        QueueItem(title: "Meeting notes — product roadmap", meta: "2:18"),
        QueueItem(title: "Keyboard configurator reference", meta: "0:54")
    ]

    private let items: [SourceKind: Item] = [
        .text: Item(
            kind: .text,
            title: "Conference Bio",
            meta: "COMPOSE · 31 WORDS · 0:24 / 1:08",
            sourcePath: "conference-bio.txt",
            text: "I'm a designer working at the intersection of voice interfaces and instrument-grade tooling. My background spans broadcast audio, editorial publishing, and software product design. I'm currently exploring how voice-first capture can fit into desk and pocket workflows without giving up the precision of a hardware console. Talk to me about voice UI, instrument vocabulary, channel-label semantics, or anything radio.",
            sourceURL: nil,
            referenceEyebrow: nil,
            duration: 68
        ),
        .image: Item(
            kind: .image,
            title: "Scope dashboard notes",
            meta: "SCAN · 142 CHARS · 0:11 / 0:38",
            sourcePath: "scope-dashboard.png",
            text: "the trace band should anchor to the bottom of the sheet so the chrome reads as one panel rather than two",
            sourceURL: nil,
            referenceEyebrow: "OCR EXCERPT · 142 CHARS",
            duration: 38
        ),
        .url: Item(
            kind: .url,
            title: "Apple's vision for the next OS",
            meta: "URL · DARINGFIREBALL.NET · 1:02 / 4:18",
            sourcePath: "daringfireball.net/2026/05/apple-vision",
            text: "Apple's next OS quietly trades chrome for content, but the new defaults expose more of the system's editorial voice than ever before",
            sourceURL: URL(string: "https://daringfireball.net/2026/05/apple-vision"),
            referenceEyebrow: "ARTICLE EXCERPT",
            duration: 258
        ),
        .pdf: Item(
            kind: .pdf,
            title: "On Bullshit · Frankfurt",
            meta: "PDF · 12 PAGES · 3:14 / 28:42",
            sourcePath: "on-bullshit-frankfurt.pdf",
            text: "It is impossible for someone to lie unless he thinks he knows the truth. Producing bullshit requires no such conviction",
            sourceURL: nil,
            referenceEyebrow: "PAGE 3 OF 12",
            duration: 1_722
        )
    ]

    var currentItem: Item {
        items[selectedKind] ?? fallbackItem
    }

    private var fallbackItem: Item {
        Item(
            kind: .text,
            title: "No readable source",
            meta: "TEXT · 0 WORDS · READY",
            sourcePath: "Empty source",
            text: "Choose a readable source to begin playback.",
            sourceURL: nil,
            referenceEyebrow: nil,
            duration: 1
        )
    }

    var chunks: [String] {
        chunks(for: currentItem.text)
    }

    var playedBarCount: Int {
        min(32, max(0, Int((progress * 32).rounded(.down))))
    }

    var selectedVoiceLabel: String {
        if let voice = voices.first(where: { $0.identifier == selectedVoiceIdentifier }) {
            return "\(voice.name) · \(voice.language)"
        }
        return "System · Auto"
    }

    func bind(speechService: SpeechSynthesisService) {
        self.speechService = speechService
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }
            .sorted { lhs, rhs in lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
        selectedVoiceIdentifier = speechService.selectedVoiceIdentifier ?? voices.first?.identifier
        rate = Double(speechService.playbackRate)
        pitch = Double(speechService.speechPitch)
        chunksCache = chunks(for: currentItem.text)
    }

    func selectSource(_ kind: SourceKind, variant nextVariant: Variant = .playing) {
        selectedKind = kind
        variant = nextVariant
        activeChunkIndex = kind == .text ? 1 : 0
        progress = kind == .text ? 0.44 : 0.28
        chunksCache = chunks(for: currentItem.text)
    }

    func togglePlayback() {
        guard let speechService else { return }
        if speechService.isSpeaking {
            stop()
            return
        }

        if variant == .idle {
            variant = .playing
        }

        chunksCache = chunks(for: currentItem.text)
        speechService.selectedVoiceIdentifier = selectedVoiceIdentifier
        speechService.speechPitch = Float(pitch)
        speechService.setPlaybackRate(Float(rate))
        speechService.speak(currentItem.text) { [weak self] in
            Task { @MainActor in
                self?.progressTask?.cancel()
                self?.progress = 1
                self?.activeChunkIndex = max(0, (self?.chunksCache.count ?? 1) - 1)
            }
        }
        startHighlightShim()
    }

    func stop() {
        speechService?.stop()
        progressTask?.cancel()
        progressTask = nil
    }

    func skipBackward() {
        progress = max(0, progress - 0.12)
        activeChunkIndex = max(0, activeChunkIndex - 1)
    }

    func skipForward() {
        progress = min(1, progress + 0.12)
        activeChunkIndex = min(max(0, chunks.count - 1), activeChunkIndex + 1)
    }

    func openOriginal() {
        guard let url = currentItem.sourceURL else { return }
        UIApplication.shared.open(url)
    }

    fileprivate func chunkState(for index: Int) -> ReadAloudChunkState {
        if index < activeChunkIndex { return .played }
        if index == activeChunkIndex { return .playing }
        return .upcoming
    }

    private func startHighlightShim() {
        progressTask?.cancel()
        let totalChunks = max(1, chunksCache.count)
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard let self else { return }
                self.progress = min(0.98, self.progress + 0.022)
                self.activeChunkIndex = min(totalChunks - 1, Int((self.progress * Double(totalChunks)).rounded(.down)))
            }
        }
    }

    private func chunks(for text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ".!?\n")
        let raw = text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !raw.isEmpty else { return [text] }
        return raw.map { chunk in
            chunk.hasSuffix(".") ? chunk : "\(chunk)."
        }
    }
}

private enum ReadAloudChunkState {
    case played, playing, upcoming
}

// MARK: - Top-level states

private struct IdleSourcePicker: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    private let rows: [(ReadAloudPlayer.SourceKind, String, String)] = [
        (.text, "Recent memo", "Conference Bio · 31w"),
        (.image, "Recent capture", "Scope dashboard notes"),
        (.pdf, "Library selection", "On Bullshit · Frankfurt"),
        (.url, "Ask AI response", "Daring Fireball · 2m ago")
    ]

    var body: some View {
        VStack(spacing: 12) {
            SectionHeader(text: "PICK A SOURCE")
            VStack(spacing: 8) {
                ForEach(rows.enumerated(), id: \.offset) { index, row in
                    Button {
                        player.selectSource(row.0)
                    } label: {
                        HStack(spacing: 12) {
                            Text("S\((index + 1), format: .number.precision(.integerLength(2)))")
                                .talkieType(.channelLabelTiny)
                                .foregroundStyle(theme.currentTheme.chrome.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.1)
                                    .talkieType(.preview)
                                    .foregroundStyle(theme.colors.textPrimary)
                                Text(row.2)
                                    .talkieType(.metaMono)
                                    .foregroundStyle(theme.colors.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(theme.colors.cardBackground)
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }
}

private struct NowReadingPanel: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOW READING")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Text(player.currentItem.title)
                .talkieType(.headline)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(player.currentItem.meta)
                .talkieType(.metaMono)
                .foregroundStyle(theme.colors.textTertiary)
            ReadAloudWaveformView(playedBarCount: player.playedBarCount)
            TransportView(player: player)
        }
        .padding(.top, 8)
    }
}

private struct ReadAloudWaveformView: View {
    let playedBarCount: Int
    @ObservedObject private var theme = ThemeManager.shared

    private let heights: [CGFloat] = (0..<32).map { index in
        let seed = (index * 9_301 + 49_297) % 233_280
        return CGFloat(20 + (seed % 26))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(heights.enumerated(), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(index < playedBarCount ? theme.currentTheme.chrome.accent : theme.colors.textTertiary.opacity(0.28))
                    .opacity(index < playedBarCount ? 0.9 : 1)
                    .frame(width: 4, height: height)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct TransportView: View {
    let player: ReadAloudPlayer
    @State private var speechService = SpeechSynthesisService.shared

    var body: some View {
        HStack(spacing: 28) {
            transportButton(systemImage: "backward.end.fill", size: 36) { player.skipBackward() }
            transportButton(systemImage: speechService.isSpeaking ? "pause.fill" : "play.fill", size: 56, primary: true) { player.togglePlayback() }
            transportButton(systemImage: "forward.end.fill", size: 36) { player.skipForward() }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func transportButton(systemImage: String, size: CGFloat, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: primary ? 20 : 15, weight: .semibold))
                .foregroundStyle(primary ? ThemeManager.shared.colors.cardBackground : ThemeManager.shared.colors.textPrimary)
                .frame(width: size, height: size)
                .background(Circle().fill(primary ? ThemeManager.shared.currentTheme.chrome.accent : Color.clear))
                .overlay(Circle().strokeBorder(primary ? Color.clear : ThemeManager.shared.currentTheme.chrome.edgeFaint, lineWidth: ThemeManager.shared.currentTheme.chrome.hairlineWidth))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Source viewer

private struct SourceViewer: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            Button {
                player.sourceExpanded.toggle()
            } label: {
                HStack {
                    Text("SOURCE · \(player.selectedKind.label)")
                        .talkieType(.channelLabel)
                        .foregroundStyle(theme.colors.textTertiary)
                    Spacer()
                    Text(player.sourceExpanded ? "HIDE" : "SHOW")
                        .talkieType(.chipLabel)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
                .padding(.top, 16)
                .padding(.bottom, 7)
                .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
            }
            .buttonStyle(.plain)

            if player.sourceExpanded {
                VStack(spacing: 0) {
                    SourceStamp(player: player)
                    if player.selectedKind == .text {
                        SourceTranscript(player: player)
                    } else {
                        SourceReference(player: player)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.colors.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.currentTheme.chrome.edgeFaint, lineWidth: theme.currentTheme.chrome.hairlineWidth))
                )
                .padding(.top, 12)
            }
        }
        .padding(.top, 4)
    }
}

private struct SourceStamp: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: player.selectedKind.icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(theme.currentTheme.chrome.accent)
                .frame(width: 20, height: 20)
            Text(player.currentItem.sourcePath)
                .talkieType(.fieldValue)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("OPEN ›") {
                player.openOriginal()
            }
            .talkieType(.chipLabel)
            .foregroundStyle(theme.currentTheme.chrome.accent)
            .buttonStyle(.plain)
            .disabled(player.currentItem.sourceURL == nil)
            .opacity(player.currentItem.sourceURL == nil ? 0.45 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
    }
}

private struct SourceTranscript: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(player.chunks.enumerated(), id: \.offset) { index, chunk in
                SourceChunk(text: chunk, state: player.chunkState(for: index))
            }
        }
        .padding(12)
    }
}

private struct SourceReference: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(player.currentItem.referenceEyebrow ?? "EXTRACTED TEXT")
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Text("“\(player.currentItem.text)… ”")
                .talkieType(.preview)
                .italic()
                .foregroundStyle(theme.colors.textTertiary)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}

private struct SourceChunk: View {
    let text: String
    let state: ReadAloudChunkState
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(state == .playing ? theme.currentTheme.chrome.accent : Color.clear)
                .frame(width: 2)
            Text(text)
                .talkieType(.preview)
                .foregroundStyle(color)
                .opacity(opacity)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var color: Color {
        switch state {
        case .played: return theme.colors.textTertiary
        case .playing: return theme.colors.textPrimary
        case .upcoming: return theme.colors.textTertiary
        }
    }

    private var opacity: Double {
        state == .upcoming ? 0.55 : 1
    }
}

// MARK: - Voice controls

private struct VoiceControls: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "VOICE")
                .padding(.top, 8)
            VoicePickerRow(player: player)
            SliderControlRow(label: "Rate", value: player.rate, range: 0.75...2.0, suffix: "×") { player.rate = $0 }
            SliderControlRow(label: "Pitch", value: player.pitch, range: 0.6...1.6, suffix: "") { player.pitch = $0 }
            Button {
                player.autoPause.toggle()
            } label: {
                ControlRowShell(label: "Auto-pause") {
                    Text(player.autoPause ? "On sentences" : "Off")
                        .talkieType(.fieldValue)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
}

private struct VoicePickerRow: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ControlRowShell(label: "Voice") {
            Menu {
                ForEach(player.voices, id: \.identifier) { voice in
                    Button("\(voice.name) · \(voice.language)") {
                        player.selectedVoiceIdentifier = voice.identifier
                    }
                }
            } label: {
                Text(player.selectedVoiceLabel)
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct SliderControlRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let suffix: String
    let onChange: (Double) -> Void
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        ControlRowShell(label: label) {
            HStack(spacing: 8) {
                Slider(value: Binding(get: { value }, set: onChange), in: range)
                    .tint(theme.currentTheme.chrome.accent)
                    .frame(width: 96)
                Text(valueLabel)
                    .talkieType(.fieldValue)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }

    private var valueLabel: String {
        let rounded = (value * 10).rounded() / 10
        return rounded.formatted(.number.precision(.fractionLength(1))) + suffix
    }
}

private struct ControlRowShell<Accessory: View>: View {
    let label: String
    @ViewBuilder let accessory: Accessory
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Text(label)
                .talkieType(.fieldLabel)
                .foregroundStyle(theme.colors.textPrimary)
            Spacer(minLength: 12)
            accessory
        }
        .frame(height: 44)
        .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
    }
}

// MARK: - Queue

private struct QueueList: View {
    let player: ReadAloudPlayer
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(text: "UP NEXT · \(player.queue.count)")
            ForEach(player.queue.enumerated(), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Text("\((index + 1), format: .number.precision(.integerLength(2)))")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.colors.textTertiary)
                    Text(item.title)
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(item.meta)
                        .talkieType(.timestamp)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .frame(height: 44)
                .overlay(Rectangle().fill(index < player.queue.count - 1 ? theme.currentTheme.chrome.edgeFaint : Color.clear).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
            }
        }
        .padding(.top, 8)
    }
}

private struct SectionHeader: View {
    let text: String
    @ObservedObject private var theme = ThemeManager.shared

    var body: some View {
        HStack {
            Text(text)
                .talkieType(.channelLabel)
                .foregroundStyle(theme.colors.textTertiary)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 7)
        .overlay(Rectangle().fill(theme.currentTheme.chrome.edgeFaint).frame(height: theme.currentTheme.chrome.hairlineWidth), alignment: .bottom)
    }
}
