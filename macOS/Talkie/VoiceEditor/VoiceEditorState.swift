//
//  VoiceEditorState.swift
//  Talkie
//
//  Core state for the Voice Editor - an AI-assisted text editor where you
//  speak instructions to refine text, review proposed changes, and accept or reject.
//
//  Used by:
//  - ScratchPadView (in-app persistent editor)
//  - InterstitialManager (floating panel triggered from TalkieLive)
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
            }
        }
    }
    var selectedRange: NSRange? = nil

    // MARK: - Mode

    var mode: VoiceEditorMode = .editing

    // MARK: - Revision State

    var isProcessing: Bool = false
    var error: String?

    /// Text before the current pending revision (for diff)
    private(set) var textBeforeRevision: String = ""

    /// The instruction that triggered the current revision
    var currentInstruction: String?

    // MARK: - LLM Configuration

    var providerId: String?
    var modelId: String?
    var temperature: Double = 0.3

    /// System prompt for the LLM
    var systemPrompt: String = """
        You are helping edit transcribed speech. Apply the user's instruction to transform the text.
        Return only the transformed text, nothing else. Preserve the original meaning unless asked otherwise.
        """

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

    // MARK: - Request Revision (LLM Call)

    /// Request an AI revision with the given instruction
    func requestRevision(instruction: String) async {
        guard !isProcessing, !textToTransform.isEmpty else { return }

        isProcessing = true
        error = nil
        textBeforeRevision = text
        currentInstruction = instruction

        do {
            let registry = LLMProviderRegistry.shared

            // Resolve provider and model
            let resolved: (provider: LLMProvider, modelId: String)
            if let providerId = providerId,
               let provider = registry.provider(for: providerId),
               let modelId = modelId {
                resolved = (provider, modelId)
            } else if let fallback = await registry.resolveProviderAndModel() {
                resolved = fallback
            } else {
                error = "No LLM provider configured"
                isProcessing = false
                textBeforeRevision = ""
                return
            }

            // Build the prompt
            let prompt = """
                \(systemPrompt)

                Instruction: \(instruction)

                Text:
                \(textToTransform)
                """

            lastUsedProvider = resolved.provider.name
            lastUsedModel = resolved.modelId
            lastPrompt = prompt

            let options = GenerationOptions(
                temperature: temperature,
                maxTokens: 2048
            )

            let result = try await resolved.provider.generate(
                prompt: prompt,
                model: resolved.modelId,
                options: options
            )

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

        } catch {
            log.error("Revision failed: \(error)")
            self.error = error.localizedDescription
            textBeforeRevision = ""
        }

        isProcessing = false
    }

    // MARK: - Reset

    /// Reset all state (for dismissing/closing)
    func reset() {
        text = ""
        selectedRange = nil
        mode = .editing
        isProcessing = false
        error = nil
        textBeforeRevision = ""
        currentInstruction = nil
        clearHistory()
    }

    // MARK: - Draft Extension API Broadcasting

    /// Broadcast current state to connected renderers
    private func broadcastState() {
        let modeString = mode == .editing ? "editing" : "reviewing"
        DraftExtensionServer.shared.broadcastState(content: text, mode: modeString)
    }

    /// Broadcast a completed revision with diff to connected renderers
    private func broadcastRevision(before: String, after: String, instruction: String) {
        let diff = DiffEngine.diff(original: before, proposed: after)

        // Convert diff operations to tuples for the server
        let diffOps: [(type: String, text: String)] = diff.operations.map { op in
            switch op {
            case .equal(let text): return ("equal", text)
            case .insert(let text): return ("insert", text)
            case .delete(let text): return ("delete", text)
            }
        }

        DraftExtensionServer.shared.broadcastRevision(
            before: before,
            after: after,
            diff: diffOps,
            instruction: instruction,
            provider: lastUsedProvider ?? "unknown",
            model: lastUsedModel ?? "unknown"
        )
    }

    /// Broadcast that a revision was resolved (accepted or rejected)
    private func broadcastResolved(accepted: Bool) {
        DraftExtensionServer.shared.broadcastResolved(accepted: accepted, content: text)
    }
}
