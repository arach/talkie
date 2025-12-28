//
//  TextPolishEditor.swift
//  Talkie
//
//  Shared text editor with LLM polish and diff preview
//  Used by both ScratchPadView (in-app) and InterstitialEditorView (floating panel)
//

import SwiftUI

// MARK: - View State

enum TextPolishViewState {
    case editing      // Normal text editing mode
    case reviewing    // Diff review mode after polish
}

// MARK: - Edit Snapshot (for history)

struct EditSnapshot: Identifiable {
    let id = UUID()
    let timestamp: Date
    let instruction: String      // What prompt/instruction was used
    let textBefore: String       // Text before this edit
    let textAfter: String        // Text after this edit
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

// MARK: - Polish Editor State

@MainActor
@Observable
final class TextPolishState {
    var text: String = ""
    var selectedRange: NSRange? = nil

    // View state (editing vs reviewing)
    var viewState: TextPolishViewState = .editing

    // Polish state
    var isPolishing: Bool = false
    var polishError: String?

    // Pre-polish text for diff comparison
    private(set) var prePolishText: String = ""

    // Voice instruction (what user said)
    var voiceInstruction: String?

    // LLM settings
    var providerId: String?
    var modelId: String?
    var temperature: Double = 0.3

    // Last generation info (for transparency)
    private(set) var lastUsedProvider: String?
    private(set) var lastUsedModel: String?
    private(set) var lastPrompt: String?

    // MARK: - Edit History

    private(set) var editHistory: [EditSnapshot] = []
    var previewingSnapshot: EditSnapshot? = nil

    // MARK: - Computed Properties

    /// Computed diff for review
    var currentDiff: TextDiff? {
        guard viewState == .reviewing, !prePolishText.isEmpty else { return nil }
        return DiffEngine.diff(original: prePolishText, proposed: text)
    }

    /// Whether we're in review mode
    var isReviewing: Bool { viewState == .reviewing }

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

    // MARK: - Actions

    func acceptChanges() {
        // Record to history before clearing prePolishText
        if !prePolishText.isEmpty {
            let diff = DiffEngine.diff(original: prePolishText, proposed: text)
            let instruction = voiceInstruction ?? "Polish"

            let snapshot = EditSnapshot(
                timestamp: Date(),
                instruction: instruction,
                textBefore: prePolishText,
                textAfter: text,
                changeCount: diff.changeCount
            )
            editHistory.append(snapshot)
        }

        viewState = .editing
        prePolishText = ""
        voiceInstruction = nil
        selectedRange = nil
    }

    func rejectChanges() {
        text = prePolishText
        viewState = .editing
        prePolishText = ""
        voiceInstruction = nil
    }

    // MARK: - History Actions

    func previewSnapshot(_ snapshot: EditSnapshot) {
        previewingSnapshot = snapshot
    }

    func dismissPreview() {
        previewingSnapshot = nil
    }

    func restoreFromSnapshot(_ snapshot: EditSnapshot) {
        let currentText = text

        // Record this restoration as a new edit
        let restorationSnapshot = EditSnapshot(
            timestamp: Date(),
            instruction: "Restored to: \(snapshot.shortInstruction)",
            textBefore: currentText,
            textAfter: snapshot.textAfter,
            changeCount: DiffEngine.diff(original: currentText, proposed: snapshot.textAfter).changeCount
        )
        editHistory.append(restorationSnapshot)

        // Apply the restoration
        text = snapshot.textAfter
        previewingSnapshot = nil
        viewState = .editing
    }

    func clearHistory() {
        editHistory.removeAll()
        previewingSnapshot = nil
    }

    // MARK: - Polish

    func polish(instruction: String) async {
        guard !isPolishing, !textToTransform.isEmpty else { return }

        isPolishing = true
        polishError = nil
        prePolishText = text
        voiceInstruction = instruction

        do {
            let registry = LLMProviderRegistry.shared

            let resolved: (provider: LLMProvider, modelId: String)
            if let providerId = providerId,
               let provider = registry.provider(for: providerId),
               let modelId = modelId {
                resolved = (provider, modelId)
            } else if let fallback = await registry.resolveProviderAndModel() {
                resolved = fallback
            } else {
                polishError = "No LLM provider configured"
                isPolishing = false
                prePolishText = ""
                return
            }

            let systemPrompt = """
                You are helping edit transcribed speech. Apply the user's instruction to transform the text.
                Return only the transformed text, nothing else. Preserve the original meaning unless asked otherwise.
                """

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

            let polished = try await resolved.provider.generate(
                prompt: prompt,
                model: resolved.modelId,
                options: options
            )

            let trimmedResult = polished.trimmingCharacters(in: .whitespacesAndNewlines)

            // Apply to selection or full text
            if let range = selectedRange,
               range.length > 0,
               let swiftRange = Range(range, in: text) {
                // Replace just the selection
                var newText = text
                newText.replaceSubrange(swiftRange, with: trimmedResult)
                text = newText
            } else {
                text = trimmedResult
            }

            // Switch to review mode
            viewState = .reviewing

        } catch {
            polishError = error.localizedDescription
            prePolishText = ""
        }

        isPolishing = false
    }
}
