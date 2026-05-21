//
//  ReadAloudPlayer.swift
//  Talkie iOS
//
//  Shared AVSpeechSynthesizer-backed player for the Read Aloud surface.
//

import AVFoundation
import Foundation
import UIKit

@MainActor
final class ReadAloudPlayer: NSObject, ObservableObject {
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

    static let shared = ReadAloudPlayer()

    @Published var variant: Variant = .playing
    @Published var selectedKind: SourceKind = .text
    @Published var sourceExpanded = true
    @Published var selectedVoiceIdentifier: String?
    @Published var rate = 1.0
    @Published var pitch = 1.0
    @Published var autoPause = true
    @Published private(set) var currentRange: NSRange?
    @Published private(set) var isPlaying = false
    @Published private(set) var currentSource: ReadAloudSource?
    @Published private(set) var voices: [AVSpeechSynthesisVoice] = []

    private let synthesizer = AVSpeechSynthesizer()
    private let minimumPlaybackRate: Float = 0.75
    private let maximumPlaybackRate: Float = 2.0
    private var isPaused = false
    private var chunksCache: [TextChunk] = []

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

    private override init() {
        super.init()
        synthesizer.delegate = self
        configureAudio()
    }

    var currentItem: Item {
        if let currentSource {
            return Item(
                kind: .text,
                title: currentSource.title,
                meta: currentSource.meta ?? Self.metaLabel(for: currentSource.text),
                sourcePath: currentSource.sourceURL?.absoluteString ?? currentSource.title,
                text: currentSource.text,
                sourceURL: currentSource.sourceURL,
                referenceEyebrow: currentSource.meta,
                duration: Self.estimatedDuration(for: currentSource.text)
            )
        }
        return items[selectedKind] ?? fallbackItem
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
        refreshChunksIfNeeded()
        return chunksCache.map(\.text)
    }

    var progress: Double {
        guard currentItem.text.count > 0 else { return 0 }
        guard let currentRange else { return 0 }
        let location = min(currentItem.text.count, max(0, currentRange.location + currentRange.length))
        return min(1, max(0, Double(location) / Double(currentItem.text.count)))
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

    func configureAudio() {
        voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.starts(with: "en") }
            .sorted { lhs, rhs in lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
        selectedVoiceIdentifier = selectedVoiceIdentifier ?? preferredVoiceIdentifier
        refreshChunks()
    }

    func bind(source: ReadAloudSource?) {
        guard let source else {
            refreshChunks()
            return
        }
        stop()
        currentSource = source
        selectedKind = .text
        variant = .playing
        sourceExpanded = true
        refreshChunks()
    }

    func selectSource(_ kind: SourceKind, variant nextVariant: Variant = .playing) {
        stop()
        currentSource = nil
        selectedKind = kind
        variant = nextVariant
        refreshChunks()
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        if isPaused, synthesizer.continueSpeaking() {
            isPaused = false
            isPlaying = true
            return
        }

        let text = currentItem.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if variant == .idle { variant = .playing }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        currentRange = nil
        refreshChunks()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = mappedSpeechRate(for: Float(rate))
        utterance.pitchMultiplier = Float(pitch)
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2

        isPaused = false
        isPlaying = true
        synthesizer.speak(utterance)
    }

    func pause() {
        guard synthesizer.isSpeaking else {
            isPlaying = false
            return
        }
        isPaused = synthesizer.pauseSpeaking(at: .word)
        isPlaying = !isPaused
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPaused = false
        isPlaying = false
        currentRange = nil
    }

    func skipBackward() {
        stop()
    }

    func skipForward() {
        stop()
    }

    func openOriginal() {
        guard let url = currentItem.sourceURL else { return }
        UIApplication.shared.open(url)
    }

    func chunkState(for index: Int) -> ReadAloudChunkState {
        refreshChunksIfNeeded()
        guard chunksCache.indices.contains(index) else { return .upcoming }
        guard let currentRange else { return index == 0 && isPlaying ? .playing : .upcoming }

        let chunkRange = chunksCache[index].range
        let spokenLocation = currentRange.location
        if NSIntersectionRange(chunkRange, currentRange).length > 0 || NSLocationInRange(spokenLocation, chunkRange) {
            return .playing
        }
        if chunkRange.location + chunkRange.length <= spokenLocation {
            return .played
        }
        return .upcoming
    }

    private var selectedVoice: AVSpeechSynthesisVoice? {
        guard let selectedVoiceIdentifier else { return nil }
        return AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
    }

    private var preferredVoiceIdentifier: String? {
        if let samantha = voices.first(where: { $0.name.contains("Samantha") && $0.quality == .enhanced }) {
            return samantha.identifier
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced.identifier
        }
        return voices.first?.identifier
    }

    private func mappedSpeechRate(for playbackRate: Float) -> Float {
        let clampedRate = min(max(playbackRate, minimumPlaybackRate), maximumPlaybackRate)
        if clampedRate <= 1 {
            let progress = (clampedRate - minimumPlaybackRate) / (1 - minimumPlaybackRate)
            return AVSpeechUtteranceMinimumSpeechRate + progress * (AVSpeechUtteranceDefaultSpeechRate - AVSpeechUtteranceMinimumSpeechRate)
        }
        let progress = (clampedRate - 1) / (maximumPlaybackRate - 1)
        return AVSpeechUtteranceDefaultSpeechRate + progress * (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceDefaultSpeechRate)
    }

    private func refreshChunksIfNeeded() {
        if chunksCache.map(\.text).joined(separator: " ") != chunks(for: currentItem.text).map(\.text).joined(separator: " ") {
            refreshChunks()
        }
    }

    private func refreshChunks() {
        chunksCache = chunks(for: currentItem.text)
    }

    private func chunks(for text: String) -> [TextChunk] {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        let regex = try? NSRegularExpression(pattern: "[^.!?\\n]+[.!?]?", options: [])
        let matches = regex?.matches(in: text, range: fullRange) ?? []
        let chunks = matches.compactMap { match -> TextChunk? in
            let chunkText = (text as NSString).substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !chunkText.isEmpty else { return nil }
            return TextChunk(text: chunkText.hasSuffix(".") || chunkText.hasSuffix("!") || chunkText.hasSuffix("?") ? chunkText : "\(chunkText).", range: match.range)
        }
        return chunks.isEmpty ? [TextChunk(text: text, range: fullRange)] : chunks
    }

    private static func metaLabel(for text: String) -> String {
        let wordCount = text.split { $0.isWhitespace || $0.isNewline }.count
        return "SOURCE · \(wordCount) WORDS · READY"
    }

    private static func estimatedDuration(for text: String) -> TimeInterval {
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        return max(1, TimeInterval(words) / 2.6)
    }
}

extension ReadAloudPlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            currentRange = characterRange
            isPlaying = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            currentRange = NSRange(location: (utterance.speechString as NSString).length, length: 0)
            isPaused = false
            isPlaying = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            currentRange = nil
            isPaused = false
            isPlaying = false
        }
    }
}

enum ReadAloudChunkState {
    case played, playing, upcoming
}

private struct TextChunk {
    let text: String
    let range: NSRange
}
