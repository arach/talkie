//
//  InterstitialState.swift
//  TalkieAgent
//
//  State management for the interstitial editor
//

import SwiftUI
import AppKit
import TalkieKit

/// View mode for the interstitial panel
public enum InterstitialViewMode: Sendable {
    case editing      // Normal text editing mode
    case reviewing    // Diff review mode after revision
}

/// A snapshot of a revision in the session
public struct InterstitialRevision: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let instruction: String      // What prompt/instruction was used
    public let textBefore: String       // Text before this revision
    public let textAfter: String        // Text after this revision
    public let changeCount: Int         // Number of changes in the diff

    public var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(timestamp))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        return "\(minutes)m ago"
    }

    public var shortInstruction: String {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 30 { return trimmed }
        return String(trimmed.prefix(27)) + "..."
    }
}

/// Main state for the interstitial editor
@MainActor
@Observable
public final class InterstitialState {
    // MARK: - Core State

    var isVisible: Bool = false
    var currentDictationId: UUID?
    var editedText: String = ""
    var originalText: String = ""
    var prePolishText: String = ""

    // Selection replacement context (for Command+Enter)
    var originalSelectedText: String?
    var sourceAppBundleID: String?
    var hasSelectionContext: Bool { originalSelectedText != nil && sourceAppBundleID != nil }

    // Context rule prompt (auto-applied when interstitial opens via context rule)
    var contextPrompt: String?
    var contextRuleName: String?

    // View state
    var viewState: InterstitialViewMode = .editing
    var showDismissConfirmation: Bool = false

    // LLM Polish state
    var isPolishing: Bool = false
    var polishError: String?

    // Voice command state (LLM instructions like "make this professional")
    var isRecordingCommand: Bool = false
    var isTranscribingCommand: Bool = false
    var voiceCommand: String?
    var commandAudioLevel: Float = 0

    // Dictation state (verbatim text input)
    var isRecordingDictation: Bool = false
    var isTranscribingDictation: Bool = false
    var dictationAudioLevel: Float = 0

    // Text selection for targeted voice commands
    var selectedTextRange: Range<String.Index>?
    var selectedText: String?

    // LLM Settings
    var showLLMSettings: Bool = false
    var llmTemperature: Double = 0.3
    var llmMaxTokens: Int = 2048
    var llmProviderId: String?
    var llmModelId: String?

    var systemPrompt: String = """
        You are helping edit transcribed speech. Apply the user's instruction to transform the text.
        Return only the transformed text, nothing else. Preserve the original meaning unless asked otherwise.
        """

    // Last generation info (for transparency)
    private(set) var lastUsedProvider: String?
    private(set) var lastUsedModel: String?
    private(set) var lastPrompt: String?
    private(set) var lastTokenCount: Int?

    // MARK: - Revision History

    private(set) var revisions: [InterstitialRevision] = []
    var previewingRevision: InterstitialRevision?

    /// Computed diff between pre-polish and current edited text
    var currentDiff: TextDiff? {
        guard viewState == .reviewing, !prePolishText.isEmpty else { return nil }
        return DiffEngine.diff(original: prePolishText, proposed: editedText)
    }

    // MARK: - Initialization

    init() {
        // Initialize with registry defaults if available
        Task { @MainActor in
            if let resolved = await LLMProviderRegistry.shared.resolveProviderAndModel() {
                llmProviderId = resolved.provider.id
                llmModelId = resolved.modelId
            }
        }
    }

    // MARK: - State Management

    func reset() {
        isVisible = false
        currentDictationId = nil
        editedText = ""
        originalText = ""
        prePolishText = ""
        viewState = .editing
        isPolishing = false
        polishError = nil
        voiceCommand = nil
        isRecordingCommand = false
        isTranscribingCommand = false
        commandAudioLevel = 0
        isRecordingDictation = false
        isTranscribingDictation = false
        dictationAudioLevel = 0
        selectedTextRange = nil
        selectedText = nil
        originalSelectedText = nil
        sourceAppBundleID = nil
        contextPrompt = nil
        contextRuleName = nil
        showDismissConfirmation = false
        clearHistory()
    }

    func load(dictationId: UUID, text: String, metadata: [String: String]?) {
        currentDictationId = dictationId
        originalText = text
        editedText = text
        originalSelectedText = metadata?["originalSelectedText"]
        sourceAppBundleID = metadata?["sourceAppBundleID"]
        contextPrompt = metadata?["contextPrompt"]
        contextRuleName = metadata?["contextRuleName"]
        viewState = .editing
    }

    // MARK: - Selection Tracking

    /// Update selection state from TextEditor's TextSelection
    /// Note: SwiftUI's TextSelection has limited API access. For now, we use
    /// NSTextView's selection via the responder chain when needed.
    func updateSelection(_ selection: TextSelection?, in text: String) {
        // SwiftUI's TextSelection doesn't expose the selected range directly.
        // We'll get the selection from the focused NSTextView when needed.
        // For now, clear the cached selection when called.
        selectedTextRange = nil
        selectedText = nil
    }

    /// Get current selection from the active NSTextView (if any)
    func captureCurrentSelection() {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            selectedTextRange = nil
            selectedText = nil
            return
        }

        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0,
              let text = textView.string as NSString? else {
            selectedTextRange = nil
            selectedText = nil
            return
        }

        // Convert NSRange to Range<String.Index>
        let string = text as String
        guard let range = Range(selectedRange, in: string) else {
            selectedTextRange = nil
            selectedText = nil
            return
        }

        selectedTextRange = range
        selectedText = String(string[range])
    }

    /// Whether there's text currently selected for targeted commands
    var hasTextSelection: Bool {
        selectedText != nil && !(selectedText?.isEmpty ?? true)
    }

    // MARK: - History Management

    func previewRevision(_ revision: InterstitialRevision) {
        previewingRevision = revision
    }

    func dismissPreview() {
        previewingRevision = nil
    }

    func restoreFromRevision(_ revision: InterstitialRevision) {
        let currentText = editedText

        // Record this restoration as a new revision
        let restorationRevision = InterstitialRevision(
            timestamp: Date(),
            instruction: "Restored to: \(revision.shortInstruction)",
            textBefore: currentText,
            textAfter: revision.textAfter,
            changeCount: DiffEngine.diff(original: currentText, proposed: revision.textAfter).changeCount
        )
        revisions.append(restorationRevision)

        // Apply the restoration
        editedText = revision.textAfter
        previewingRevision = nil
        viewState = .editing
    }

    private func clearHistory() {
        revisions.removeAll()
        previewingRevision = nil
    }

    // MARK: - LLM Polish

    func polishText(instruction: String? = nil) async {
        guard !isPolishing else { return }

        isPolishing = true
        polishError = nil

        // Capture current selection from NSTextView before starting
        captureCurrentSelection()

        // Determine what text to polish: selection or full text
        let textToPolish: String
        let polishingSelection = hasTextSelection
        let selectionRange = selectedTextRange

        if polishingSelection, let selected = selectedText {
            textToPolish = selected
            prePolishText = selected  // For diff comparison
        } else {
            textToPolish = editedText
            prePolishText = editedText
        }

        do {
            let registry = LLMProviderRegistry.shared

            // Use user-selected provider/model or fall back to registry resolution
            let resolved: (provider: any LLMProvider, modelId: String)
            if let providerId = llmProviderId,
               let provider = registry.provider(for: providerId),
               let modelId = llmModelId {
                resolved = (provider, modelId)
            } else if let fallback = await registry.resolveProviderAndModel() {
                resolved = fallback
            } else {
                polishError = "No LLM provider configured"
                isPolishing = false
                return
            }

            let userInstruction: String
            if let instruction = instruction, !instruction.isEmpty {
                userInstruction = instruction
            } else {
                userInstruction = "Fix grammar, remove filler words (um, uh, like), and make it clearer while preserving the original meaning and tone."
            }

            let prompt = """
            \(systemPrompt)

            Instruction: \(userInstruction)

            Text:
            \(textToPolish)
            """

            let options = LLMGenerationOptions(
                temperature: llmTemperature,
                maxTokens: llmMaxTokens
            )

            lastUsedProvider = resolved.provider.name
            lastUsedModel = resolved.modelId
            lastPrompt = prompt
            lastTokenCount = prompt.split(separator: " ").count * 2

            let polished = try await resolved.provider.generate(
                prompt: prompt,
                model: resolved.modelId,
                options: options
            )

            let trimmedPolished = polished.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if there are actual changes
            if trimmedPolished == textToPolish.trimmingCharacters(in: .whitespacesAndNewlines) {
                // No changes - stay in editing mode and show feedback
                polishError = "No changes proposed"
                prePolishText = ""
            } else {
                // Changes detected
                if polishingSelection, let range = selectionRange {
                    // Replace only the selected portion
                    var newText = editedText
                    newText.replaceSubrange(range, with: trimmedPolished)
                    editedText = newText
                } else {
                    // Replace full text
                    editedText = trimmedPolished
                }
                viewState = .reviewing
            }

        } catch {
            polishError = error.localizedDescription
            prePolishText = ""
        }

        isPolishing = false
    }

    // MARK: - Diff Review Actions

    func acceptRevision() {
        if !prePolishText.isEmpty {
            let diff = DiffEngine.diff(original: prePolishText, proposed: editedText)
            let command = voiceCommand ?? "Revision"

            let revision = InterstitialRevision(
                timestamp: Date(),
                instruction: command,
                textBefore: prePolishText,
                textAfter: editedText,
                changeCount: diff.changeCount
            )
            revisions.append(revision)
        }

        viewState = .editing
        prePolishText = ""
        voiceCommand = nil
    }

    func rejectRevision() {
        editedText = prePolishText
        viewState = .editing
        prePolishText = ""
        voiceCommand = nil
    }

    func resetText() {
        editedText = originalText
    }
}
