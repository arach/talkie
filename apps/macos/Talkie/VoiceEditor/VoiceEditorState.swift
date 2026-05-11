//
//  VoiceEditorState.swift
//  Talkie
//
//  Core state for the Voice Editor - an AI-assisted text editor where you
//  speak instructions to refine text, review proposed changes, and accept or reject.
//
//  Used by:
//  - ScratchPadView (in-app persistent editor)
//  - InterstitialManager (floating panel triggered from TalkieAgent)
//

import SwiftUI
import TalkieKit

private let log = Log(.workflow)

// MARK: - Voice Editor Mode

/// The current mode of the voice editor
enum VoiceEditorMode {
    case editing    // Normal text editing
    case reviewing  // Reviewing proposed AI changes (diff view)
}

// MARK: - Revision

/// A snapshot of a single revision in the editing session
struct Revision: Identifiable {
    let id = UUID()
    let timestamp: Date
    let instruction: String      // What the user asked for
    let textBefore: String       // Text before this revision
    let textAfter: String        // Text after this revision
    let changeCount: Int         // Number of changes in the diff

    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        return "\(minutes)m ago"
    }

    var shortInstruction: String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 30 { return trimmed }
        return String(trimmed.prefix(27)) + "..."
    }
}

// MARK: - Voice Editor State

/// Observable state for the Voice Editor
///
/// Manages:
/// - Current text and selection
/// - AI revision requests (via LLM)
/// - Diff preview (accept/reject workflow)
/// - Revision history for undo/restore
/// - Broadcasting to Draft Extension API for custom renderers
@MainActor
@Observable
final class VoiceEditorState {

    // MARK: - Text State

    var text: String = "" {
        didSet {
            if text != oldValue {
                broadcastState()
                scheduleNoteAutoSave()
            }
        }
    }
    var selectedRange: NSRange? = nil

    // MARK: - Note Persistence

    /// ID of the current note being edited (nil if no note yet)
    var currentNoteId: UUID?

    /// Timestamp of last auto-save
    private(set) var lastSavedAt: Date?

    /// Whether auto-save is enabled. Disable when a parent view owns persistence (e.g. TalkieView).
    var autoSaveEnabled: Bool = true

    /// Pending auto-save task
    private var autoSaveTask: Task<Void, Never>?

    // MARK: - Mode

    var mode: VoiceEditorMode = .editing

    // MARK: - Revision State

    var isProcessing: Bool = false
    var error: String?

    /// Text before the current pending revision (for diff)
    private(set) var textBeforeRevision: String = ""

    /// The instruction that triggered the current revision
    var currentInstruction: String?

    /// Active generation task (for cancellation)
    private var generationTask: Task<Void, Never>?

    // MARK: - LLM Configuration

    var providerId: String?
    var modelId: String?
    var temperature: Double = 0.3

    /// System prompt for the LLM
    var systemPrompt: String = SettingsManager.defaultComposeAssistantPrompt

    // MARK: - Transparency (what was used for last revision)

    private(set) var lastUsedProvider: String?
    private(set) var lastUsedModel: String?
    private(set) var lastPrompt: String?

    // MARK: - Revision History

    private(set) var revisions: [Revision] = []
    var previewingRevision: Revision? = nil

    // MARK: - Computed Properties

    /// Computed diff for review mode
    var currentDiff: TextDiff? {
        guard mode == .reviewing, !textBeforeRevision.isEmpty else { return nil }
        return DiffEngine.diff(original: textBeforeRevision, proposed: text)
    }

    /// Whether we're in review mode
    var isReviewing: Bool { mode == .reviewing }

    /// The text that will be transformed (selection or full text)
    var textToTransform: String {
        if let range = selectedRange,
           range.length > 0,
           let swiftRange = Range(range, in: text) {
            return String(text[swiftRange])
        }
        return text
    }

    /// Whether we're transforming a selection vs full text
    var isTransformingSelection: Bool {
        if let range = selectedRange, range.length > 0 {
            return true
        }
        return false
    }

    // MARK: - Accept / Reject

    /// Accept the proposed revision
    func acceptRevision() {
        // Record to history
        if !textBeforeRevision.isEmpty {
            let diff = DiffEngine.diff(original: textBeforeRevision, proposed: text)
            let instruction = currentInstruction ?? "Revision"

            let revision = Revision(
                timestamp: Date(),
                instruction: instruction,
                textBefore: textBeforeRevision,
                textAfter: text,
                changeCount: diff.changeCount
            )
            revisions.append(revision)
            log.info("Accepted revision: \(instruction.prefix(30))... (\(diff.changeCount) changes)")
        }

        mode = .editing
        textBeforeRevision = ""
        currentInstruction = nil
        selectedRange = nil

        // Broadcast to connected renderers
        broadcastResolved(accepted: true)
    }

    /// Reject the proposed revision and revert
    func rejectRevision() {
        text = textBeforeRevision
        mode = .editing
        textBeforeRevision = ""
        currentInstruction = nil
        log.info("Rejected revision, reverted to previous text")

        // Broadcast to connected renderers
        broadcastResolved(accepted: false)
    }

    // MARK: - History Actions

    func previewRevision(_ revision: Revision) {
        previewingRevision = revision
    }

    func dismissPreview() {
        previewingRevision = nil
    }

    func restoreFromRevision(_ revision: Revision) {
        let currentText = text

        // Record this restoration as a new revision
        let restorationRevision = Revision(
            timestamp: Date(),
            instruction: "Restored to: \(revision.shortInstruction)",
            textBefore: currentText,
            textAfter: revision.textAfter,
            changeCount: DiffEngine.diff(original: currentText, proposed: revision.textAfter).changeCount
        )
        revisions.append(restorationRevision)

        // Apply the restoration
        text = revision.textAfter
        previewingRevision = nil
        mode = .editing
        log.info("Restored from revision: \(revision.shortInstruction)")
    }

    func clearHistory() {
        revisions.removeAll()
        previewingRevision = nil
    }

    // MARK: - LLM Preferences

    /// Load persisted Compose/Interstitial LLM preferences (model + personality prompt).
    func initializeLLMSettings() async {
        let settings = SettingsManager.shared
        let registry = LLMProviderRegistry.shared

        self.systemPrompt = resolvedSystemPrompt

        if let savedProvider = settings.composeLLMProviderId,
           let savedModel = settings.composeLLMModelId,
           registry.provider(for: savedProvider) != nil,
           registry.allModels.contains(where: { $0.provider == savedProvider && $0.id == savedModel }) {
            self.providerId = savedProvider
            self.modelId = savedModel
            return
        }

        if let resolved = await registry.resolveProviderAndModel() {
            setLLMSelection(providerId: resolved.provider.id, modelId: resolved.modelId)
        }
    }

    /// Set active provider/model and persist for Compose + Interstitial sessions.
    func setLLMSelection(providerId: String, modelId: String) {
        self.providerId = providerId
        self.modelId = modelId
        let settings = SettingsManager.shared
        settings.composeLLMProviderId = providerId
        settings.composeLLMModelId = modelId
    }

    // MARK: - Request Revision (LLM Call)

    /// Request an AI revision with the given instruction
    func requestRevision(instruction: String) async {
        guard !isProcessing, !textToTransform.isEmpty else { return }

        isProcessing = true
        error = nil
        textBeforeRevision = text
        currentInstruction = instruction

        generationTask = Task { [weak self] in
            guard let self else { return }

            do {
                let registry = LLMProviderRegistry.shared
                let activeSystemPrompt = resolvedSystemPrompt

                // Resolve provider and model
                let resolved: (provider: LLMProvider, modelId: String)
                if let providerId = providerId,
                   let provider = registry.provider(for: providerId),
                   let modelId = modelId {
                    resolved = (provider, modelId)
                } else if let fallback = await registry.resolveProviderAndModel() {
                    resolved = fallback
                    setLLMSelection(providerId: fallback.provider.id, modelId: fallback.modelId)
                } else {
                    error = "No LLM provider configured"
                    isProcessing = false
                    textBeforeRevision = ""
                    return
                }

                try Task.checkCancellation()

                // Build the prompt — system prompt passed separately via options
                let prompt = """
                    User instruction:
                    \(instruction)

                    Editing scope:
                    \(isTransformingSelection ? "Selected excerpt of a larger document." : "Entire document.")

                    Current target text:
                    \(textToTransform)

                    Current full document:
                    \(text)

                    Revision history (oldest to newest):
                    \(revisionHistoryPromptContext())

                    Return only the revised text for the current target text.
                    """

                lastUsedProvider = resolved.provider.name
                lastUsedModel = resolved.modelId
                lastPrompt = prompt

                let options = GenerationOptions(
                    temperature: temperature,
                    maxTokens: 2048,
                    systemPrompt: activeSystemPrompt
                )

                let result = try await resolved.provider.generate(
                    prompt: prompt,
                    model: resolved.modelId,
                    options: options
                )

                try Task.checkCancellation()

                let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)

                // Apply to selection or full text
                if let range = selectedRange,
                   range.length > 0,
                   let swiftRange = Range(range, in: text) {
                    var newText = text
                    newText.replaceSubrange(swiftRange, with: trimmedResult)
                    text = newText
                } else {
                    text = trimmedResult
                }

                // Switch to review mode
                mode = .reviewing
                log.info("Revision complete via \(resolved.provider.name)/\(resolved.modelId)")

                // Broadcast revision to connected renderers
                broadcastRevision(before: textBeforeRevision, after: text, instruction: instruction)

            } catch is CancellationError {
                log.info("Generation cancelled by user")
                self.error = nil
                textBeforeRevision = ""
            } catch {
                log.error("Revision failed: \(error)")
                self.error = error.localizedDescription
                textBeforeRevision = ""

                // Broadcast error to connected renderers
                broadcastError(error.localizedDescription)
            }

            isProcessing = false
            currentInstruction = nil
            generationTask = nil
        }

        await generationTask?.value
    }

    /// Cancel an in-progress generation
    func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        isProcessing = false
        currentInstruction = nil
        textBeforeRevision = ""
        log.info("Generation cancelled")
    }

    // MARK: - Prompt Helpers

    private var resolvedSystemPrompt: String {
        let configured = SettingsManager.shared.composeAssistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if configured.isEmpty {
            return SettingsManager.defaultComposeAssistantPrompt
        }
        return SettingsManager.shared.composeAssistantPrompt
    }

    /// Full in-session revision context for idempotent "refer back to version N" instructions.
    private func revisionHistoryPromptContext() -> String {
        guard !revisions.isEmpty else { return "No prior revisions." }

        return revisions.enumerated().map { index, revision in
            """
            Revision \(index + 1)
            - Timestamp: \(ISO8601DateFormatter().string(from: revision.timestamp))
            - Instruction: \(revision.instruction)
            - Text Before:
            \(revision.textBefore)
            - Text After:
            \(revision.textAfter)
            """
        }.joined(separator: "\n\n")
    }

    // MARK: - Note Auto-Save

    /// Schedule a debounced auto-save (2 seconds after last edit)
    private func scheduleNoteAutoSave() {
        guard autoSaveEnabled else { return }

        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.autoSaveNote()
        }
    }

    /// Persist current text as a note recording
    private func autoSaveNote() async {
        let currentText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't save empty notes
        guard !currentText.isEmpty else { return }

        let repo = TalkieObjectRepository()
        let noteId = currentNoteId ?? UUID()
        let title = extractTitle(from: currentText)

        do {
            // Check if note actually exists in DB (currentNoteId can be set
            // before the note is created, e.g. by dictation segment recording)
            var exists = false
            if currentNoteId != nil {
                exists = try await repo.fetchRecording(id: noteId) != nil
            }

            if exists {
                // Note already exists — partial update to avoid overwriting audio/assets set by recording
                try await repo.updateTitleAndText(id: noteId, title: title, text: currentText)
            } else {
                // New note — full insert
                var note = TalkieObject.newNote(id: noteId, text: currentText, title: title)
                note.lastModified = Date()
                try await repo.saveRecording(note)
            }
            currentNoteId = noteId
            lastSavedAt = Date()
            log.debug("Note auto-saved: \(noteId.uuidString.prefix(8)), \(currentText.count) chars")
        } catch {
            log.error("Note auto-save failed: \(error)")
        }
    }

    /// Extract a title from the first line or first few words
    private func extractTitle(from text: String) -> String {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? text
        let words = firstLine.split(separator: " ").prefix(8).joined(separator: " ")
        if words.count > 50 {
            return String(words.prefix(47)) + "..."
        }
        return words
    }

    /// Load an existing note into the editor
    func loadNote(_ recording: TalkieObject) {
        guard recording.isNote else { return }
        autoSaveEnabled = false
        currentNoteId = recording.id
        text = recording.text ?? ""
        selectedRange = nil
        mode = .editing
        error = nil
        clearHistory()
        autoSaveEnabled = true
        log.info("Loaded note: \(recording.id.uuidString.prefix(8))")
    }

    /// Promote the current note to a memo
    func promoteNoteToMemo() async {
        let currentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentText.isEmpty else { return }

        let repo = TalkieObjectRepository()
        let noteId = currentNoteId ?? UUID()

        let title = extractTitle(from: currentText)
        var recording = TalkieObject.newNote(id: noteId, text: currentText, title: title)
        recording.promoteNoteToMemo()

        do {
            try await repo.saveRecording(recording)
            log.info("Note promoted to memo: \(noteId.uuidString.prefix(8))")

            // Clean up segments — the note text is the consolidated result
            try await repo.deleteSegments(forNoteId: noteId)

            // Clear the editor
            autoSaveEnabled = false
            currentNoteId = nil
            text = ""
            selectedRange = nil
            mode = .editing
            lastSavedAt = nil
            clearHistory()
            autoSaveEnabled = true
        } catch {
            log.error("Note promotion failed: \(error)")
            self.error = "Failed to save as memo: \(error.localizedDescription)"
        }
    }

    /// Delete the current note
    func deleteCurrentNote() async {
        guard let noteId = currentNoteId else { return }

        let repo = TalkieObjectRepository()
        do {
            // Delete segments and their audio first
            try await repo.deleteSegments(forNoteId: noteId)
            // Then delete the note itself
            try await repo.hardDeleteRecording(id: noteId)
            log.info("Note deleted (with segments): \(noteId.uuidString.prefix(8))")
        } catch {
            log.error("Note deletion failed: \(error)")
        }

        autoSaveEnabled = false
        currentNoteId = nil
        lastSavedAt = nil
        autoSaveEnabled = true
    }

    // MARK: - Reset

    /// Reset all state (for dismissing/closing)
    func reset() {
        autoSaveTask?.cancel()
        autoSaveEnabled = false
        text = ""
        selectedRange = nil
        mode = .editing
        isProcessing = false
        error = nil
        textBeforeRevision = ""
        currentInstruction = nil
        currentNoteId = nil
        lastSavedAt = nil
        clearHistory()
        autoSaveEnabled = true
    }

    // MARK: - Extension API Broadcasting (Legacy v1 format)
    // Note: Extension server moved to TalkieServer (port 8765)
    // These methods are kept as no-ops for call site compatibility

    private func broadcastState() {
        // No-op: Extensions now connect to TalkieServer
    }

    private func broadcastRevision(before: String, after: String, instruction: String) {
        // No-op: Extensions now connect to TalkieServer
    }

    private func broadcastResolved(accepted: Bool) {
        // No-op: Extensions now connect to TalkieServer
    }

    private func broadcastError(_ message: String) {
        // No-op: Extensions now connect to TalkieServer
    }
}
