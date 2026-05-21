//
//  ComposeStore.swift
//  Talkie iOS
//
//  M2 wire. Owns ComposeNextView state, loads/saves ComposeNote
//  documents, records inline dictation, and routes voice commands
//  through the configured Compose AI provider with a local fallback.
//

import CoreData
import Foundation
import SwiftUI
import TalkieMobileKit

@MainActor
final class ComposeStore: ObservableObject {
    @Published var state: ComposeState = .idle
    @Published var document: Document
    @Published var livePartialTranscript: String?
    @Published var lastCommandTranscript: String?
    @Published var generatingETA: String?
    @Published var pendingDiff: Diff?
    @Published var keyboardFocusRequested: Bool = false

    let modelLabel: String = "Sonnet 4.6"
    let documentID: String

    private let context: NSManagedObjectContext
    private let recorder = AudioRecorderManager()
    private var note: ComposeNote?
    private var dictationTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var voiceCommandTask: Task<Void, Never>?
    private var isVoiceCommandCapturing = false
    private var isMockDocument: Bool { documentID == "mock" }

    init(documentID: String) {
        self.documentID = documentID
        self.context = PersistenceController.shared.container.viewContext
        self.document = Self.mockDocument

        if documentID == "mock" {
            self.document = Self.mockDocument
        } else if let note = Self.fetchNote(id: documentID, context: context) {
            self.note = note
            self.document = Self.document(from: note)
        } else if let dictation = Self.fetchKeyboardDictation(id: documentID) {
            self.document = Self.document(from: dictation)
        } else if let capture = Self.fetchCapture(id: documentID) {
            let note = Self.createNote(from: capture, context: context)
            self.note = note
            self.document = Self.document(from: note)
        } else if let seed = AppShellRouter.shared.pendingComposeSeed {
            AppShellRouter.shared.pendingComposeSeed = nil
            let note = Self.createSeededNote(id: documentID, text: seed, context: context)
            self.note = note
            self.document = Self.document(from: note)
        } else if let note = Self.fetchLatestNote(context: context) {
            self.note = note
            self.document = Self.document(from: note)
        } else {
            let note = ComposeNote(context: context)
            note.id = UUID(uuidString: documentID) ?? UUID()
            note.createdAt = Date()
            note.lastModified = Date()
            note.title = "Untitled note"
            note.content = ""
            self.note = note
            self.document = Self.document(from: note)
            Self.save(context)
        }

        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--composeState"), i + 1 < args.count {
            switch args[i + 1].lowercased() {
            case "idle":       seed(.idle)
            case "dictating":  seed(.dictating)
            case "listening":  seed(.listening)
            case "generating": seed(.generating)
            case "diff":       seed(.diff)
            default: break
            }
        }
    }

    deinit {
        dictationTask?.cancel()
        commandTask?.cancel()
        voiceCommandTask?.cancel()
    }

    func toggleDictation() {
        if isMockDocument {
            if state == .dictating {
                state = .idle
                livePartialTranscript = nil
            } else {
                state = .dictating
                livePartialTranscript = "and that's when the model surfaced"
            }
            return
        }

        if state == .dictating {
            finishDictation()
        } else {
            beginDictation()
        }
    }


    func toggleVoiceCommand() {
        if isMockDocument {
            voiceCommandTask?.cancel()

            if state == .listening {
                voiceCommandReceived("tighten the second paragraph")
                return
            }

            pendingDiff = nil
            livePartialTranscript = nil
            lastCommandTranscript = "tighten the second paragraph"
            generatingETA = "~3s"
            state = .listening

            voiceCommandTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard let self, !Task.isCancelled, self.state == .listening else { return }
                self.voiceCommandReceived("tighten the second paragraph")
            }
            return
        }

        if isVoiceCommandCapturing {
            finishVoiceCommandCapture()
        } else {
            beginVoiceCommandCapture()
        }
    }

    func toggleKeyboard() {
        keyboardFocusRequested.toggle()
    }

    func voiceCommandReceived(_ text: String) {
        let command = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }

        commandTask?.cancel()
        lastCommandTranscript = command
        livePartialTranscript = nil
        pendingDiff = nil
        state = .listening
        generatingETA = "~3s"

        commandTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled, self.state == .listening else { return }
            self.state = .generating

            let targetIndex = self.targetParagraphIndex(for: command)
            let original = self.document.paragraphs.indices.contains(targetIndex)
                ? self.document.paragraphs[targetIndex]
                : self.document.paragraphs.first ?? ""
            let proposed = await self.revisedParagraph(original: original, command: command, targetIndex: targetIndex)

            guard !Task.isCancelled, self.state == .generating else { return }
            self.pendingDiff = Self.makeDiff(original: original, proposed: proposed)
            self.state = .diff
        }
    }

    func applyTransform(_ transform: QuickTransform) {
        voiceCommandReceived(transform.commandLabel)
    }

    func acceptDiff() {
        guard let diff = pendingDiff else { state = .idle; return }
        document = document.replacing(diff.original, with: diff.proposed)
        pendingDiff = nil
        lastCommandTranscript = nil
        state = .idle
        persistDocument()
    }

    func discardDiff() {
        pendingDiff = nil
        lastCommandTranscript = nil
        state = .idle
    }

    struct Document {
        let title: String
        var paragraphs: [String]

        func replacing(_ original: String, with proposed: String) -> Document {
            var copy = paragraphs
            if let idx = copy.firstIndex(of: original) {
                copy[idx] = proposed
            }
            return Document(title: title, paragraphs: copy)
        }
    }

    struct Diff {
        let original: String
        let proposed: String
        let removedCount: Int
        let addedCount: Int
    }

    enum QuickTransform: CaseIterable {
        case shorter, polish, connect, grammar

        var label: String {
            switch self {
            case .shorter: return "Shorter"
            case .polish:  return "Polish"
            case .connect: return "Connect"
            case .grammar: return "Fix grammar"
            }
        }

        var commandLabel: String {
            switch self {
            case .shorter: return "make it shorter"
            case .polish:  return "polish the tone"
            case .connect: return "connect the ideas more clearly"
            case .grammar: return "fix any grammar issues"
            }
        }
    }


    private func beginVoiceCommandCapture() {
        dictationTask?.cancel()
        voiceCommandTask?.cancel()
        pendingDiff = nil
        livePartialTranscript = nil
        lastCommandTranscript = nil
        generatingETA = "~3s"
        state = .listening
        isVoiceCommandCapturing = true

        voiceCommandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.recorder.startRecording()
        }
    }

    private func finishVoiceCommandCapture() {
        guard isVoiceCommandCapturing else { return }
        isVoiceCommandCapturing = false
        voiceCommandTask?.cancel()

        voiceCommandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.recorder.stopRecording()
            let recordingURL = self.recorder.currentRecordingURL
            self.recorder.finalizeRecording()

            guard let recordingURL else {
                self.state = .idle
                return
            }

            do {
                let transcript = try await TranscriptionService.shared.transcribe(audioURL: recordingURL, useCase: .keyboard)
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.state = .idle
                } else {
                    self.voiceCommandReceived(trimmed)
                }
            } catch {
                self.state = .idle
            }
        }
    }

    private func beginDictation() {
        dictationTask?.cancel()
        pendingDiff = nil
        livePartialTranscript = "Listening…"
        state = .dictating

        dictationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.recorder.startRecording()
        }
    }

    private func finishDictation() {
        livePartialTranscript = "Transcribing…"
        dictationTask?.cancel()

        dictationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.recorder.stopRecording()
            let recordingURL = self.recorder.currentRecordingURL
            self.recorder.finalizeRecording()

            guard let recordingURL else {
                self.livePartialTranscript = nil
                self.state = .idle
                return
            }

            do {
                let transcript = try await TranscriptionService.shared.transcribe(audioURL: recordingURL, useCase: .keyboard)
                self.appendDictation(transcript)
            } catch {
                self.livePartialTranscript = nil
                self.state = .idle
            }
        }
    }

    private func appendDictation(_ transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            livePartialTranscript = nil
            state = .idle
            return
        }

        var paragraphs = document.paragraphs.isEmpty ? [""] : document.paragraphs
        let index = paragraphs.indices.last ?? 0
        let existing = paragraphs[index].trimmingCharacters(in: .whitespacesAndNewlines)
        paragraphs[index] = existing.isEmpty ? trimmed : [existing, trimmed].joined(separator: " ")
        document = Document(title: document.title, paragraphs: paragraphs)
        livePartialTranscript = nil
        state = .idle
        persistDocument()
    }

    private func revisedParagraph(original: String, command: String, targetIndex: Int) async -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return localRevision(original: original, command: command) }

        if let provider = TalkieAIProviderResolver.shared.configuredProvider() {
            do {
                let result = try await ComposeLocalRevisionService.shared.revise(
                    text: trimmed,
                    instruction: command,
                    provider: provider,
                    fullDocument: document.paragraphs.joined(separator: "\n\n"),
                    editingScope: "Paragraph \(targetIndex + 1) of \(max(1, document.paragraphs.count)).",
                    revisionHistory: "No prior revisions."
                )
                let revised = result.revisedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !revised.isEmpty, revised != trimmed { return revised }
            } catch {
                // Keep compose testable without credentials/network; use local fallback below.
            }
        }

        return localRevision(original: original, command: command)
    }

    private func targetParagraphIndex(for command: String) -> Int {
        let lowered = command.lowercased()
        let ordinals: [(tokens: [String], index: Int)] = [
            (["first", "1st", "paragraph one", "para one"], 0),
            (["second", "2nd", "paragraph two", "para two"], 1),
            (["third", "3rd", "paragraph three", "para three"], 2),
            (["fourth", "4th", "paragraph four", "para four"], 3),
            (["fifth", "5th", "paragraph five", "para five"], 4),
        ]

        if let match = ordinals.first(where: { item in
            item.tokens.contains { lowered.localizedStandardContains($0) }
        }), document.paragraphs.indices.contains(match.index) {
            return match.index
        }

        return document.paragraphs.enumerated().max { lhs, rhs in
            lhs.element.count < rhs.element.count
        }?.offset ?? 0
    }

    private func localRevision(original: String, command: String) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = command.lowercased()

        if lowered.localizedStandardContains("short") || lowered.localizedStandardContains("tighten") {
            let clauses = trimmed
                .split(whereSeparator: { ".,;—–".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let candidate = clauses.prefix(max(1, min(2, clauses.count))).joined(separator: ", ")
            return candidate.isEmpty ? trimmed : candidate + "."
        }

        if lowered.localizedStandardContains("connect") {
            return "\(trimmed) Together, these ideas point toward a calmer, more dependable editing surface."
        }

        if lowered.localizedStandardContains("grammar") || lowered.localizedStandardContains("polish") {
            let cleaned = trimmed
                .replacing("  ", with: " ")
                .replacing(" ,", with: ",")
                .replacing(" .", with: ".")
            return cleaned == trimmed ? "\(trimmed)" : cleaned
        }

        return trimmed
    }

    private func persistDocument() {
        guard !isMockDocument else { return }
        let currentNote = note ?? Self.fetchNote(id: documentID, context: context)
        guard let currentNote else { return }

        currentNote.title = document.title
        currentNote.content = document.paragraphs.joined(separator: "\n\n")
        currentNote.lastModified = Date()
        Self.save(context)
        note = currentNote
    }

    private static func fetchNote(id: String, context: NSManagedObjectContext) -> ComposeNote? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let request: NSFetchRequest<ComposeNote> = ComposeNote.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }


    private static func fetchKeyboardDictation(id: String) -> KeyboardDictation? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        KeyboardDictationStore.shared.reload()
        return KeyboardDictationStore.shared.all().first { $0.id == uuid }
    }

    private static func document(from dictation: KeyboardDictation) -> Document {
        let text = dictation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = title(from: text, fallback: "Keyboard dictation")
        return Document(title: title, paragraphs: text.isEmpty ? [""] : [text])
    }

    private static func fetchCapture(id: String) -> Capture? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        CaptureStore.shared.reload()
        return CaptureStore.shared.all().first { $0.id == uuid }
    }

    private static func createNote(from capture: Capture, context: NSManagedObjectContext) -> ComposeNote {
        let note = ComposeNote(context: context)
        note.id = capture.id
        note.createdAt = capture.timestamp
        note.lastModified = Date()
        note.title = cleanCaptureTitle(capture)
        note.content = capture.text
        save(context)
        return note
    }

    private static func createSeededNote(id: String, text: String, context: NSManagedObjectContext) -> ComposeNote {
        let note = ComposeNote(context: context)
        note.id = UUID(uuidString: id) ?? UUID()
        note.createdAt = Date()
        note.lastModified = Date()
        note.title = title(from: text, fallback: "Untitled note")
        note.content = text
        save(context)
        return note
    }

    private static func cleanCaptureTitle(_ capture: Capture) -> String {
        if let title = capture.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }

        return title(from: capture.text, fallback: "Capture")
    }

    private static func title(from text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(64))
    }

    private static func fetchLatestNote(context: NSManagedObjectContext) -> ComposeNote? {
        let request: NSFetchRequest<ComposeNote> = ComposeNote.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ComposeNote.lastModified, ascending: false),
            NSSortDescriptor(keyPath: \ComposeNote.createdAt, ascending: false),
        ]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private static func document(from note: ComposeNote) -> Document {
        let rawTitle = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = rawTitle.isEmpty ? "Untitled note" : rawTitle
        let content = note.content ?? ""
        let paragraphs = content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Document(title: title, paragraphs: paragraphs.isEmpty ? [""] : paragraphs)
    }

    private static func save(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            context.rollback()
        }
    }

    private static func makeDiff(original: String, proposed: String) -> Diff {
        let removed = max(0, wordCount(original) - wordCount(proposed))
        let added = max(0, wordCount(proposed) - wordCount(original))
        return Diff(original: original, proposed: proposed, removedCount: removed, addedCount: added)
    }

    private static func wordCount(_ value: String) -> Int {
        value.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static let mockDocument = Document(
        title: "Bio",
        paragraphs: [
            "I build tools at the seam between people and the systems they rely on — the bits of an interface that quietly decide whether software feels obvious or hostile.",
            "Most of my work lately sits in two places: editor surfaces that take dictation seriously, and ambient AI that earns its place on a phone screen instead of grabbing for it.",
            "Before that, a stretch of years building infra most people never see. I learned to value boring reliability the hard way, on systems where every alert was someone's worst day."
        ]
    )

    private static let mockDiff = Diff(
        original: "Most of my work lately sits in two places: editor surfaces that take dictation seriously, and ambient AI that earns its place on a phone screen instead of grabbing for it.",
        proposed: "Lately my work splits cleanly: editor surfaces built around real dictation, and ambient AI that earns its place on a phone screen rather than grabbing for it.",
        removedCount: 9,
        addedCount: 6
    )

    private func seed(_ target: ComposeState) {
        if isMockDocument {
            document = Self.mockDocument
        }

        switch target {
        case .idle:
            state = .idle
        case .dictating:
            state = .dictating
            livePartialTranscript = "and that's when the model surfaced"
        case .listening:
            state = .listening
            lastCommandTranscript = "tighten the second paragraph"
        case .generating:
            state = .generating
            lastCommandTranscript = "tighten the second paragraph"
            generatingETA = "~3s"
        case .diff:
            state = .diff
            lastCommandTranscript = "tighten the second paragraph"
            pendingDiff = Self.mockDiff
        }
    }
}


extension TranscriptionService {
    func transcribe(audioURL: URL, useCase: TranscriptionUseCase) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            transcribe(audioURL: audioURL, useCase: useCase) { result in
                continuation.resume(with: result)
            }
        }
    }
}
