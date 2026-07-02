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
    @Published var document: Document {
        didSet { clampCursorParagraphIndex() }
    }
    @Published var livePartialTranscript: String?
    @Published var lastCommandTranscript: String?
    @Published var generatingETA: String?
    @Published var pendingDiff: Diff?
    @Published var revisionPath: RevisionPath
    @Published var appliedRevisions: [ComposeNoteStore.RevisionRecord] = []
    @Published var cursorParagraphIndex: Int = 0 {
        didSet { clampCursorParagraphIndex() }
    }

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
        case .apple:
            return "Apple Intelligence"
        }
    }

    /// Structured form of `modelLabel` so the header can render the
    /// family / version / variant with distinct typography instead of
    /// a flat string. `providerName` and `modelId` are nil when no
    /// credentials are configured for the Direct path.
    struct ModelDisplay {
        let providerName: String?
        let modelId: String?
        /// Special-case label that bypasses the model-id parser (e.g.
        /// "Mac Bridge" — no version glyph to extract).
        let standaloneLabel: String?
    }

    var modelDisplay: ModelDisplay {
        switch revisionPath {
        case .direct:
            if let provider = TalkieAIProviderResolver.shared.configuredProvider() {
                return ModelDisplay(
                    providerName: provider.providerName,
                    modelId: provider.modelId,
                    standaloneLabel: nil
                )
            }
            return ModelDisplay(providerName: nil, modelId: nil, standaloneLabel: nil)
        case .mac:
            return ModelDisplay(providerName: nil, modelId: nil, standaloneLabel: "Mac Bridge")
        case .apple:
            return ModelDisplay(providerName: nil, modelId: nil, standaloneLabel: "Apple Intelligence")
        }
    }

    /// A pickable model — one per provider that has an API key saved on
    /// this device and is supported by the direct resolver. Backs the
    /// header's model menu so it lists "what you can actually run" rather
    /// than abstract routes.
    struct ModelOption: Identifiable, Equatable {
        let providerId: String
        let modelId: String

        var id: String { "\(providerId):\(modelId)" }
        var providerName: String { TalkieAIProviderCredentialPayload.displayName(for: providerId) }
        /// e.g. "OpenAI · gpt-5.5"
        var menuLabel: String { "\(providerName) · \(modelId)" }
    }

    /// Configured direct models — credentials that are both saved in the
    /// Keychain and resolvable by the direct path. Empty when the user
    /// hasn't added a key yet (header routes them to AI Keys).
    var configuredModelOptions: [ModelOption] {
        // Resolve through TalkieAIProviderResolver (not a single store) so a key
        // saved via *any* path — AI Keys editor, QR/bridge import, or the legacy
        // OpenAI speech key — surfaces as a pickable model. The header already
        // resolves this way; the list previously read only AICredentialStore,
        // which is why "I set my key" didn't show up here.
        return TalkieAIProviderCredentialPayload.supportedProviderIds
            .sorted()
            .compactMap { providerId in
                guard let provider = TalkieAIProviderResolver.shared.provider(providerId: providerId) else { return nil }
                return ModelOption(providerId: provider.providerId, modelId: provider.modelId)
            }
    }

    /// The provider id the direct path currently resolves to — used to
    /// mark the active row in the model menu.
    var activeDirectProviderId: String {
        TalkieAIProviderResolver.shared.configuredProvider()?.providerId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        ?? TalkieAppSettings.shared.composeDirectProviderId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var activeDirectModelId: String {
        TalkieAIProviderResolver.shared.configuredProvider()?.modelId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? TalkieAppSettings.shared.composeDirectModelId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var runningModelLabel: String {
        switch revisionPath {
        case .direct:
            guard let provider = TalkieAIProviderResolver.shared.configuredProvider() else { return "Direct API" }
            return Self.displayModelName(for: provider.modelId)
        case .mac:
            return "Mac Bridge"
        case .apple:
            return "Apple"
        }
    }

    /// Pick a specific direct model. Pins the provider/model in settings
    /// and snaps the revision path back to `.direct` so the header glyph
    /// refreshes immediately.
    func selectDirectModel(_ option: ModelOption) {
        TalkieAppSettings.shared.composeDirectProviderId = option.providerId
        TalkieAppSettings.shared.composeDirectModelId = option.modelId
        revisionPath = .direct
        TalkieAppSettings.shared.composeRevisionPath = RevisionPath.direct.rawValue
        objectWillChange.send()
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
        cursorParagraphIndex = max(0, document.paragraphs.count - 1)
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

    var documentBodyText: String {
        document.paragraphs.joined(separator: "\n\n")
    }

    func updateDocumentBodyText(_ text: String) {
        document = Document(title: document.title, paragraphs: Self.paragraphs(from: text))
        persistDocument()
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

            if Self.isDocumentFormatIntent(command), self.explicitParagraphIndex(for: command) == nil {
                let original = self.documentBodyText
                let proposed = await self.formattedDocument(original: original, command: command)
                guard !Task.isCancelled, self.state == .generating else { return }
                if proposed != original, self.passesFormatSanity(original: original, proposed: proposed) {
                    self.pendingDiff = Self.makeDiff(scope: .document, original: original, proposed: proposed)
                    self.state = .diff
                } else {
                    self.state = .idle
                }
                return
            }

            let targetIndex = self.targetParagraphIndex(for: command)
            let original = self.document.paragraphs.indices.contains(targetIndex)
                ? self.document.paragraphs[targetIndex]
                : self.document.paragraphs.first ?? ""
            let proposed = await self.revisedParagraph(original: original, command: command, targetIndex: targetIndex)

            guard !Task.isCancelled, self.state == .generating else { return }
            self.pendingDiff = Self.makeDiff(scope: .paragraph, original: original, proposed: proposed)
            self.state = .diff
        }
    }

    func applyTransform(_ transform: QuickTransform) {
        switch transform {
        case .format:
            formatDocument()
        default:
            voiceCommandReceived(transform.commandLabel)
        }
    }

    func formatDocument() {
        voiceCommandReceived(QuickTransform.format.commandLabel)
    }

    func acceptDiff() {
        guard let diff = pendingDiff else { state = .idle; return }
        let documentTextBefore = documentBodyText

        let originalIndex: Int?
        switch diff.scope {
        case .document:
            originalIndex = nil
            updateDocumentBodyText(diff.proposed)
        case .paragraph:
            originalIndex = document.paragraphs.firstIndex(of: diff.original)
            document = document.replacing(diff.original, with: diff.proposed)
            persistDocument()
        }

        recordRevision(for: diff, originalIndex: originalIndex, documentTextBefore: documentTextBefore)
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
        enum Scope {
            case document
            case paragraph
        }

        let scope: Scope
        let original: String
        let proposed: String
        let removedCount: Int
        let addedCount: Int
        let unchangedCount: Int
    }

    enum RevisionPath: String, CaseIterable, Identifiable {
        case direct
        case mac
        case apple

        var id: String { rawValue }

        var title: String {
            switch self {
            case .direct: return "API"
            case .mac: return "Mac"
            case .apple: return "Apple"
            }
        }

        var systemImage: String {
            switch self {
            case .direct: return "network"
            case .mac: return "desktopcomputer"
            case .apple: return "sparkles"
            }
        }
    }

    enum QuickTransform: CaseIterable {
        case format, shorter, polish, connect, grammar

        var label: String {
            switch self {
            case .format: return "Format"
            case .shorter: return "Shorter"
            case .polish:  return "Polish"
            case .connect: return "Connect"
            case .grammar: return "Fix grammar"
            }
        }

        var commandLabel: String {
            switch self {
            case .format: return "format this memo"
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
            FeedbackToastCenter.shared.showError("Dictation didn't come through. Tap the mic to try again.")
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
            FeedbackToastCenter.shared.showError("Voice command didn't come through. Try again.")
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

        var body = documentBodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        body = body.isEmpty ? trimmed : "\(body) \(trimmed)"
        updateDocumentBodyText(body)
        cursorParagraphIndex = max(0, document.paragraphs.count - 1)
        livePartialTranscript = nil
        state = .idle
    }

    private func revisedParagraph(original: String, command: String, targetIndex: Int) async -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return localRevision(original: original, command: command) }

        let fullDocument = document.paragraphs.joined(separator: "\n\n")
        let editingScope = "Paragraph \(targetIndex + 1) of \(max(1, document.paragraphs.count))."

        if Self.isDocumentFormatIntent(command) || revisionPath == .apple {
            do {
                let revised = try await OnDeviceAIService.shared.formatMemo(trimmed, instruction: command)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !revised.isEmpty, revised != trimmed, passesFormatSanity(original: trimmed, proposed: revised) {
                    lastRevisionProviderName = "Apple"
                    lastRevisionModelId = "Foundation Models"
                    return revised
                }
            } catch {
                // Fall through to the selected route when Apple Intelligence is unavailable.
            }
        }

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

    private func formattedDocument(original: String, command: String) async -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return original }

        do {
            let revised = try await OnDeviceAIService.shared.formatMemo(trimmed, instruction: command)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !revised.isEmpty, revised != trimmed, passesFormatSanity(original: trimmed, proposed: revised) {
                lastRevisionProviderName = "Apple"
                lastRevisionModelId = "Foundation Models"
                return revised
            }
        } catch {
            // Apple Intelligence is opportunistic here; keep the selected route usable.
        }

        if revisionPath == .mac {
            do {
                let result = try await BridgeManager.shared.composeRevision(
                    text: trimmed,
                    instruction: macDocumentFormatInstruction(command, fullDocument: trimmed)
                )
                let revised = result.revisedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !revised.isEmpty, revised != trimmed, passesFormatSanity(original: trimmed, proposed: revised) {
                    lastRevisionProviderName = result.providerName
                    lastRevisionModelId = result.modelId
                    return revised
                }
            } catch {
                // Keep formatting available without a paired Mac.
            }
        } else if let provider = TalkieAIProviderResolver.shared.configuredProvider() {
            do {
                let result = try await ComposeLocalRevisionService.shared.revise(
                    text: trimmed,
                    instruction: documentFormatInstruction(command),
                    provider: provider,
                    fullDocument: trimmed,
                    editingScope: "Entire memo.",
                    revisionHistory: revisionHistoryPromptContext()
                )
                let revised = result.revisedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !revised.isEmpty, revised != trimmed, passesFormatSanity(original: trimmed, proposed: revised) {
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
        return localDocumentFormat(original: original)
    }

    private func revisionHistoryPromptContext() -> String {
        guard !appliedRevisions.isEmpty else { return "No prior revisions." }

        return appliedRevisions.reversed().enumerated().map { index, revision in
            [
                "Revision \(index + 1)",
                "- Timestamp: \(Self.revisionDateFormatter.string(from: revision.createdAt))",
                "- Scope: \(revision.scope)",
                "- Instruction: \(revision.instruction)",
                revision.originalText.map { "- Original text:\n\($0)" },
                "- Revised text:",
                revision.revisedText,
            ].compactMap { $0 }.joined(separator: "\n")
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

    private func documentFormatInstruction(_ command: String) -> String {
        [
            "User instruction:",
            command,
            "",
            "Format the entire memo transcript.",
            "Fix capitalization, punctuation, spacing, and paragraph breaks.",
            "Remove filler words only where they add nothing.",
            "Do not summarize, reword, reorder, translate, or add content.",
            "Preserve the speaker's wording, meaning, and sequence.",
            "Return only the full formatted memo text.",
        ].joined(separator: "\n")
    }

    private func macDocumentFormatInstruction(_ command: String, fullDocument: String) -> String {
        [
            documentFormatInstruction(command),
            "",
            "Current full memo:",
            fullDocument,
        ].joined(separator: "\n")
    }

    private func targetParagraphIndex(for command: String) -> Int {
        if let explicitIndex = explicitParagraphIndex(for: command) {
            return explicitIndex
        }

        return document.paragraphs.enumerated().max { lhs, rhs in
            lhs.element.count < rhs.element.count
        }?.offset ?? 0
    }

    private func explicitParagraphIndex(for command: String) -> Int? {
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

        return nil
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

    private func localDocumentFormat(original: String) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        var cleaned = trimmed
            .replacing("  ", with: " ")
            .replacing(" ,", with: ",")
            .replacing(" .", with: ".")
            .replacing(" ?", with: "?")
            .replacing(" !", with: "!")
            .replacing(" um, ", with: " ")
            .replacing(" uh, ", with: " ")
            .replacing(" Um, ", with: " ")
            .replacing(" Uh, ", with: " ")

        while cleaned.contains("  ") {
            cleaned = cleaned.replacing("  ", with: " ")
        }

        return cleaned
    }

    private func passesFormatSanity(original: String, proposed: String) -> Bool {
        let originalWords = Self.normalizedDiffWords(in: original)
        let proposedWords = Self.normalizedDiffWords(in: proposed)
        guard max(originalWords.count, proposedWords.count) >= 20 else { return true }

        let unchanged = Self.lcsCount(originalWords, proposedWords)
        let largestSide = max(originalWords.count, proposedWords.count)
        guard largestSide > 0 else { return true }
        return Double(unchanged) / Double(largestSide) >= 0.60
    }

    private static func isDocumentFormatIntent(_ command: String) -> Bool {
        let lowered = command.lowercased()
        let tokens = [
            "format",
            "clean this up",
            "clean it up",
            "clean up",
            "tidy",
            "paragraph break",
            "paragraphs",
            "punctuation",
            "remove filler",
            "filler words",
        ]
        return tokens.contains { lowered.localizedStandardContains($0) }
    }

    private func clampedCursorIndex(in paragraphs: [String]) -> Int {
        guard !paragraphs.isEmpty else { return 0 }
        return min(max(0, cursorParagraphIndex), paragraphs.count - 1)
    }

    private func clampCursorParagraphIndex() {
        let clamped = clampedCursorIndex(in: document.paragraphs)
        if cursorParagraphIndex != clamped {
            cursorParagraphIndex = clamped
        }
    }

    private func persistDocument() {
        guard !isMockDocument else { return }
        let noteID = persistentNoteID ?? UUID(uuidString: documentID) ?? UUID()
        let content = document.paragraphs.joined(separator: "\n\n")
        if ComposeNoteStore.save(id: noteID, title: document.title, content: content, context: context) {
            note = ComposeNoteStore.fetch(id: noteID, context: context)
        }
    }

    private func recordRevision(for diff: Diff, originalIndex: Int?, documentTextBefore: String) {
        guard !isMockDocument, let noteID = persistentNoteID else { return }
        let scope: String
        switch diff.scope {
        case .document:
            scope = "Document"
        case .paragraph:
            scope = originalIndex.map { "Paragraph \($0 + 1)" } ?? "Paragraph"
        }
        let record = ComposeNoteStore.RevisionRecord(
            instruction: lastCommandTranscript ?? "Quick transform",
            scope: scope,
            originalText: diff.original,
            revisedText: diff.proposed,
            documentTextBefore: documentTextBefore,
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
        // MUST be lossless: this round-trips through the editor binding on
        // every keystroke (documentBodyText get = joined("\n\n"), set =
        // paragraphs(from:)), so it has to satisfy
        //   paragraphs(from: t).joined(separator: "\n\n") == t
        // The old version trimmed each paragraph and dropped empties, which
        // silently ate trailing spaces and newlines as they were typed — the
        // "can't type space/enter in Compose" bug. `components(separatedBy:)`
        // is the exact inverse of `joined(separator:)`, so this is identity.
        // Any cosmetic normalization belongs at an explicit commit boundary,
        // not on the live editing path.
        content.components(separatedBy: "\n\n")
    }

    private static func makeDiff(scope: Diff.Scope = .paragraph, original: String, proposed: String) -> Diff {
        let counts = diffWordCounts(original: original, proposed: proposed)
        return Diff(
            scope: scope,
            original: original,
            proposed: proposed,
            removedCount: counts.removed,
            addedCount: counts.added,
            unchangedCount: counts.unchanged
        )
    }

    private static func diffWordCounts(original: String, proposed: String) -> (removed: Int, added: Int, unchanged: Int) {
        let originalWords = normalizedDiffWords(in: original)
        let proposedWords = normalizedDiffWords(in: proposed)
        let unchanged = lcsCount(originalWords, proposedWords)
        return (
            removed: max(0, originalWords.count - unchanged),
            added: max(0, proposedWords.count - unchanged),
            unchanged: unchanged
        )
    }

    private static func normalizedDiffWords(in value: String) -> [String] {
        value
            .split(whereSeparator: \.isWhitespace)
            .map {
                String($0)
                    .trimmingCharacters(in: diffTrimCharacters)
                    .lowercased()
            }
            .filter { !$0.isEmpty }
    }

    private static func lcsCount(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }

        var previous = Array(repeating: 0, count: rhs.count + 1)
        var current = previous

        for leftIndex in lhs.indices {
            current[0] = 0
            for rightIndex in rhs.indices {
                if lhs[leftIndex] == rhs[rightIndex] {
                    current[rightIndex + 1] = previous[rightIndex] + 1
                } else {
                    current[rightIndex + 1] = max(previous[rightIndex + 1], current[rightIndex])
                }
            }
            swap(&previous, &current)
        }

        return previous[rhs.count]
    }

    private static func displayModelName(for modelId: String) -> String {
        let cleaned = modelId
            .replacing("/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let noise: Set<String> = ["chat", "latest", "instruct", "preview", "versatile", "turbo"]
        let pieces = cleaned
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
            .filter { !noise.contains($0) }

        guard let head = pieces.first else { return modelId }

        if head == "claude" {
            let rest = Array(pieces.dropFirst())
            let family = rest.first(where: { ["sonnet", "opus", "haiku"].contains($0) })?.capitalized ?? "Claude"
            let numeric = rest.filter { $0.first?.isNumber == true }
            return numeric.isEmpty ? family : "\(family) \(numeric.joined(separator: "."))"
        }

        let family: String
        switch head {
        case "gpt": family = "GPT"
        case "llama": family = "Llama"
        case "mistral": family = "Mistral"
        case "mixtral": family = "Mixtral"
        case "gemini": family = "Gemini"
        case "qwen": family = "Qwen"
        case "sonnet": family = "Sonnet"
        case "opus": family = "Opus"
        case "haiku": family = "Haiku"
        default: family = head.capitalized
        }

        if let version = pieces.dropFirst().first(where: { $0.first?.isNumber == true }) {
            return "\(family) \(version)"
        }
        return family
    }

    private static let diffTrimCharacters = CharacterSet.whitespacesAndNewlines
        .union(.punctuationCharacters)
        .union(.symbols)

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
        scope: .paragraph,
        original: "Most of my work lately sits in two places: editor surfaces that take dictation seriously, and ambient AI that earns its place on a phone screen instead of grabbing for it.",
        proposed: "Lately my work splits cleanly: editor surfaces built around real dictation, and ambient AI that earns its place on a phone screen rather than grabbing for it.",
        removedCount: 9,
        addedCount: 6,
        unchangedCount: 17
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
