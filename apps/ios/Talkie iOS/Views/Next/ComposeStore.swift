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
    @Published var revisionPath: RevisionPath
    @Published var appliedRevisions: [ComposeNoteStore.RevisionRecord] = []

    let documentID: String

    var modelLabel: String {
        switch revisionPath {
        case .direct:
            if let provider = TalkieAIProviderResolver.shared.configuredProvider() {
                return "\(provider.providerName) · \(provider.modelId)"
            }
            return "Direct API"
        case .mac:
            return "Mac Bridge"
        }
    }

    private let context: NSManagedObjectContext
    private let inlineDictationController = InlineDictationController()
    private let voiceCommandController = InlineDictationController()
    private var note: ComposeNote?
    private var dictationTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var voiceCommandTask: Task<Void, Never>?
    private var isVoiceCommandCapturing = false
    private var voiceCommandDidSubmit = false
    private var lastRevisionProviderName = "Local fallback"
    private var lastRevisionModelId = "local"
    private var isMockDocument: Bool { documentID == "mock" }

    init(documentID: String) {
        self.documentID = documentID
        self.context = PersistenceController.shared.container.viewContext
        self.document = Self.mockDocument
        self.revisionPath = RevisionPath(rawValue: TalkieAppSettings.shared.composeRevisionPath) ?? .direct

        configureDictationControllers()
        loadDocument(documentID: documentID)
        loadAppliedRevisions()
        seedFromLaunchArgumentsIfNeeded()
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

        switch inlineDictationController.currentState {
        case .idle:
            beginDictation()
        case .recording:
            finishDictation()
        case .transcribing:
            inlineDictationController.cancel()
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

        if isVoiceCommandCapturing || voiceCommandController.currentState != .idle {
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
        let originalIndex = document.paragraphs.firstIndex(of: diff.original)
        document = document.replacing(diff.original, with: diff.proposed)
        persistDocument()
        recordRevision(for: diff, originalIndex: originalIndex)
        pendingDiff = nil
        lastCommandTranscript = nil
        state = .idle
    }

    func discardDiff() {
        pendingDiff = nil
        lastCommandTranscript = nil
        state = .idle
    }

    func autosave() {
        persistDocument()
    }

    func selectRevisionPath(_ path: RevisionPath) {
        revisionPath = path
        TalkieAppSettings.shared.composeRevisionPath = path.rawValue
    }

    func restoreRevision(_ revision: ComposeNoteStore.RevisionRecord) {
        pendingDiff = nil
        lastCommandTranscript = nil
        livePartialTranscript = nil
        state = .idle
        document = Document(
            title: document.title,
            paragraphs: Self.paragraphs(from: revision.documentText)
        )
        persistDocument()
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

    enum RevisionPath: String, CaseIterable, Identifiable {
        case direct
        case mac

        var id: String { rawValue }

        var title: String {
            switch self {
            case .direct: return "API"
            case .mac: return "Mac"
            }
        }

        var systemImage: String {
            switch self {
            case .direct: return "network"
            case .mac: return "desktopcomputer"
            }
        }
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

    private func loadDocument(documentID: String) {
        if documentID == "mock" {
            document = Self.mockDocument
        } else if let note = Self.fetchNote(id: documentID, context: context) {
            self.note = note
            document = Self.document(from: note)
        } else if let capture = Self.fetchCapture(id: documentID) {
            let note = ComposeNoteStore.create(from: capture, context: context)
            self.note = note
            document = Self.document(from: note)
        } else if let seed = AppShellRouter.shared.pendingComposeSeed {
            AppShellRouter.shared.pendingComposeSeed = nil
            let note = ComposeNoteStore.create(
                title: Self.title(from: seed, fallback: "Draft"),
                content: seed,
                context: context
            )
            self.note = note
            document = Self.document(from: note)
        } else if let dictation = Self.fetchKeyboardDictation(id: documentID) {
            document = Self.document(from: dictation)
        } else if let note = Self.fetchLatestNote(context: context) {
            self.note = note
            document = Self.document(from: note)
        } else {
            let note = ComposeNoteStore.create(
                title: "Untitled note",
                content: "",
                id: UUID(uuidString: documentID) ?? UUID(),
                context: context
            )
            self.note = note
            document = Self.document(from: note)
        }
    }

    private func configureDictationControllers() {
        inlineDictationController.onStateChange = { [weak self] state in
            self?.applyInlineDictationState(state)
        }
        inlineDictationController.onTranscript = { [weak self] transcript in
            self?.appendDictation(transcript)
        }
        inlineDictationController.onError = { [weak self] _ in
            self?.livePartialTranscript = nil
            self?.state = .idle
        }

        voiceCommandController.onStateChange = { [weak self] state in
            self?.applyVoiceCommandDictationState(state)
        }
        voiceCommandController.onTranscript = { [weak self] transcript in
            self?.voiceCommandDidSubmit = true
            self?.voiceCommandReceived(transcript)
        }
        voiceCommandController.onError = { [weak self] _ in
            self?.isVoiceCommandCapturing = false
            self?.voiceCommandDidSubmit = false
            self?.lastCommandTranscript = nil
            self?.state = .idle
        }
    }

    private func beginDictation() {
        dictationTask?.cancel()
        pendingDiff = nil
        livePartialTranscript = "Listening…"
        state = .dictating

        dictationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.inlineDictationController.start()
        }
    }

    private func finishDictation() {
        livePartialTranscript = "Transcribing…"
        inlineDictationController.stop(insertTranscript: true)
    }

    private func applyInlineDictationState(_ controllerState: InlineDictationController.State) {
        switch controllerState {
        case .idle:
            if state == .dictating {
                livePartialTranscript = nil
                state = .idle
            }
        case .recording:
            livePartialTranscript = "Listening…"
            state = .dictating
        case .transcribing:
            livePartialTranscript = "Transcribing…"
            state = .dictating
        }
    }

    private func beginVoiceCommandCapture() {
        voiceCommandTask?.cancel()
        pendingDiff = nil
        livePartialTranscript = nil
        lastCommandTranscript = "Listening…"
        generatingETA = "~3s"
        state = .listening
        isVoiceCommandCapturing = true
        voiceCommandDidSubmit = false

        voiceCommandTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.voiceCommandController.start()
        }
    }

    private func finishVoiceCommandCapture() {
        guard isVoiceCommandCapturing || voiceCommandController.currentState != .idle else { return }
        lastCommandTranscript = "Transcribing…"
        voiceCommandController.stop(insertTranscript: true)
    }

    private func applyVoiceCommandDictationState(_ controllerState: InlineDictationController.State) {
        switch controllerState {
        case .idle:
            isVoiceCommandCapturing = false
            if !voiceCommandDidSubmit, state == .listening {
                lastCommandTranscript = nil
                generatingETA = nil
                state = .idle
            }
            voiceCommandDidSubmit = false
        case .recording:
            isVoiceCommandCapturing = true
            voiceCommandDidSubmit = false
            lastCommandTranscript = "Listening…"
            state = .listening
        case .transcribing:
            if isVoiceCommandCapturing {
                lastCommandTranscript = "Transcribing…"
                state = .listening
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

        let fullDocument = document.paragraphs.joined(separator: "\n\n")
        let editingScope = "Paragraph \(targetIndex + 1) of \(max(1, document.paragraphs.count))."

        if revisionPath == .mac {
            do {
                let result = try await BridgeManager.shared.composeRevision(
                    text: trimmed,
                    instruction: macInstruction(command, editingScope: editingScope, fullDocument: fullDocument)
                )
                let revised = result.revisedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !revised.isEmpty, revised != trimmed {
                    lastRevisionProviderName = result.providerName
                    lastRevisionModelId = result.modelId
                    return revised
                }
            } catch {
                // Keep compose testable without a paired Mac; use local fallback below.
            }
        } else if let provider = TalkieAIProviderResolver.shared.configuredProvider() {
            do {
                let result = try await ComposeLocalRevisionService.shared.revise(
                    text: trimmed,
                    instruction: command,
                    provider: provider,
                    fullDocument: fullDocument,
                    editingScope: editingScope,
                    revisionHistory: revisionHistoryPromptContext()
                )
                let revised = result.revisedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !revised.isEmpty, revised != trimmed {
                    lastRevisionProviderName = result.providerName
                    lastRevisionModelId = result.modelId
                    return revised
                }
            } catch {
                // Keep compose testable without credentials/network; use local fallback below.
            }
        }

        lastRevisionProviderName = "Local fallback"
        lastRevisionModelId = "local"
        return localRevision(original: original, command: command)
    }

    private func revisionHistoryPromptContext() -> String {
        guard !appliedRevisions.isEmpty else { return "No prior revisions." }

        return appliedRevisions.reversed().enumerated().map { index, revision in
            [
                "Revision \(index + 1)",
                "- Timestamp: \(Self.revisionDateFormatter.string(from: revision.createdAt))",
                "- Scope: \(revision.scope)",
                "- Instruction: \(revision.instruction)",
                "- Revised text:",
                revision.revisedText,
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func macInstruction(_ command: String, editingScope: String, fullDocument: String) -> String {
        [
            "User instruction:",
            command,
            "",
            "Editing scope:",
            editingScope,
            "",
            "Current full document:",
            fullDocument,
            "",
            "Revision history (oldest to newest):",
            revisionHistoryPromptContext(),
            "",
            "Return only the revised text for the current target paragraph.",
        ].joined(separator: "\n")
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
        let noteID = persistentNoteID ?? UUID(uuidString: documentID) ?? UUID()
        let content = document.paragraphs.joined(separator: "\n\n")
        if ComposeNoteStore.save(id: noteID, title: document.title, content: content, context: context) {
            note = ComposeNoteStore.fetch(id: noteID, context: context)
        }
    }

    private func recordRevision(for diff: Diff, originalIndex: Int?) {
        guard !isMockDocument, let noteID = persistentNoteID else { return }
        let scope = originalIndex.map { "Paragraph \($0 + 1)" } ?? "Document"
        let record = ComposeNoteStore.RevisionRecord(
            instruction: lastCommandTranscript ?? "Quick transform",
            scope: scope,
            revisedText: diff.proposed,
            documentText: document.paragraphs.joined(separator: "\n\n"),
            providerName: lastRevisionProviderName,
            modelId: lastRevisionModelId
        )
        appliedRevisions.insert(record, at: 0)
        ComposeNoteStore.saveRevisions(appliedRevisions, for: noteID)
    }

    private func loadAppliedRevisions() {
        guard !isMockDocument, let noteID = persistentNoteID else { return }
        appliedRevisions = ComposeNoteStore.revisions(for: noteID)
    }

    private var persistentNoteID: UUID? {
        if let id = note?.id { return id }
        return UUID(uuidString: documentID)
    }

    private static func fetchNote(id: String, context: NSManagedObjectContext) -> ComposeNote? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return ComposeNoteStore.fetch(id: uuid, context: context)
    }

    private static func fetchCapture(id: String) -> Capture? {
        let rawID = id.hasPrefix("capture:") ? String(id.dropFirst("capture:".count)) : id
        guard let uuid = UUID(uuidString: rawID) else { return nil }
        CaptureStore.shared.reload()
        return CaptureStore.shared.all().first { $0.id == uuid }
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

    private static func createNote(from capture: Capture, context: NSManagedObjectContext) -> ComposeNote {
        let note = ComposeNote(context: context)
        note.id = capture.id
        note.createdAt = capture.timestamp
        note.lastModified = Date()
        note.title = cleanCaptureTitle(capture)
        note.content = capture.text
        try? context.save()
        return note
    }

    private static func createSeededNote(id: String, text: String, context: NSManagedObjectContext) -> ComposeNote {
        let note = ComposeNote(context: context)
        note.id = UUID(uuidString: id) ?? UUID()
        note.createdAt = Date()
        note.lastModified = Date()
        note.title = title(from: text, fallback: "Untitled note")
        note.content = text
        try? context.save()
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
        return Document(title: title, paragraphs: paragraphs(from: content))
    }

    private static func paragraphs(from content: String) -> [String] {
        let paragraphs = content
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paragraphs.isEmpty ? [""] : paragraphs
    }

    private static func makeDiff(original: String, proposed: String) -> Diff {
        let removed = max(0, wordCount(original) - wordCount(proposed))
        let added = max(0, wordCount(proposed) - wordCount(original))
        return Diff(original: original, proposed: proposed, removedCount: removed, addedCount: added)
    }

    private static func wordCount(_ value: String) -> Int {
        value.split { $0.isWhitespace || $0.isNewline }.count
    }

    private static let revisionDateFormatter = ISO8601DateFormatter()

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

    private func seedFromLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--composeState"), i + 1 < args.count else { return }
        switch args[i + 1].lowercased() {
        case "idle":       seed(.idle)
        case "dictating":  seed(.dictating)
        case "listening":  seed(.listening)
        case "generating": seed(.generating)
        case "diff":       seed(.diff)
        default: break
        }
    }

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
