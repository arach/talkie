//
//  InterstitialOnlyApp.swift
//  Talkie
//
//  LITE MODE: Blazing fast interstitial panel with LLM polish and quick actions.
//
//  WHAT WE LOAD (safe, fast):
//    - SettingsManager (UserDefaults + Keychain - instant)
//    - LLMProviderRegistry (lazy provider registration - instant)
//    - LLMConfig (JSON from bundle - instant)
//    - DatabaseManager (GRDB - fast, async init)
//    - SmartAction.builtIn (static array - instant)
//
//  WHAT WE SKIP (heavy, slow):
//    - CloudKit / CoreData sync
//    - ServiceManager (helper app launching)
//    - WorkflowService (workflow loading)
//    - Full SwiftUI WindowGroup
//    - StartupCoordinator phases 3 & 4
//
//  Text is passed via temp file from TalkieAgent (secure, no CLI exposure).
//  Target: <100ms from process start to panel visible
//
//  Instrumented with os_signpost for Instruments profiling
//

import AppKit
import SwiftUI
import GRDB
import os.signpost
import TalkieKit

// MARK: - Performance Instrumentation

/// Signpost log for lite interstitial performance profiling in Instruments
private let liteInterstitialLog = OSLog(subsystem: "to.talkie.app.performance", category: "LiteInterstitial")

/// Signposter for lite interstitial workflow intervals
private let liteSignposter = OSSignposter(subsystem: "to.talkie.app.performance", category: "LiteInterstitial")

// MARK: - Lite Mode Entry Point

enum InterstitialOnlyApp {

    /// Run the minimal interstitial app
    /// - Parameters:
    ///   - app: Pre-initialized NSApplication
    ///   - text: The transcription text (passed directly, not fetched)
    ///   - recordId: Optional database record ID (from LiveDictation table)
    ///   - audioFilename: Audio filename for reliable recordings table lookup
    @MainActor
    static func run(app: NSApplication, text: String, recordId: Int64?, audioFilename: String?) {
        let start = CFAbsoluteTimeGetCurrent()

        // Begin signpost for full lite launch
        let launchSignpostID = liteSignposter.makeSignpostID()
        let launchState = liteSignposter.beginInterval("LiteLaunch", id: launchSignpostID)

        TalkieConsole.critical("[LITE] Starting with text: \(text.prefix(50))...")
        if let audioFilename = audioFilename {
            TalkieConsole.critical("[LITE] Audio filename: \(audioFilename)")
        }

        // Step 1: Create the panel immediately (no waiting for DB)
        let viewModel = LiteInterstitialViewModel(
            initialText: text,
            recordId: recordId,
            audioFilename: audioFilename,
            onDismiss: {
                TalkieConsole.critical("[LITE] Dismissed")
                NSApplication.shared.terminate(nil)
            }
        )
        let panel = createPanel(viewModel: viewModel)

        // Step 2: Show it
        panel.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        // End launch signpost
        liteSignposter.endInterval("LiteLaunch", launchState,
                                   "panel_visible \(text.count)chars \(Int(elapsed))ms")

        os_signpost(.event, log: liteInterstitialLog, name: "LiteInterstitial",
                    "launch_complete")

        TalkieConsole.critical("[LITE] Panel visible in \(String(format: "%.1f", elapsed))ms")

        // Step 3: Initialize database in background (for persistence)
        Task {
            do {
                try await DatabaseManager.shared.initialize()
                await MainActor.run {
                    viewModel.databaseReady = true
                }
                TalkieConsole.critical("[LITE] Database initialized")
            } catch {
                TalkieConsole.critical("[LITE] Database init failed: \(error.localizedDescription)")
                await MainActor.run {
                    viewModel.databaseError = error.localizedDescription
                }
            }
        }

        // Step 4: Run the event loop
        app.run()
    }

    // MARK: - Panel Creation

    @MainActor
    private static func createPanel(viewModel: LiteInterstitialViewModel) -> NSPanel {
        let view = LiteInterstitialView(viewModel: viewModel)
            .environment(SettingsManager.shared)
        let hostingView = NSHostingView(rootView: view)

        let width: CGFloat = 560
        let height: CGFloat = 400

        // Borderless panel - no titlebar, no traffic lights
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.center()

        // Visual polish - transparent window so SwiftUI can draw rounded corners
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        // Round corners - layer clips content, SwiftUI draws the actual background
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true

        // Quit when closed
        panel.isReleasedWhenClosed = false
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { _ in
            NSApplication.shared.terminate(nil)
        }

        return panel
    }
}

// MARK: - View Model

/// Local revision type for lite mode (avoids collision with VoiceEditorState.Revision)
private struct LiteRevision: Identifiable {
    let id = UUID()
    let timestamp: Date
    let instruction: String      // What prompt/instruction was used
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

/// View state for lite interstitial (matches InterstitialManager)
private enum LiteViewState {
    case editing
    case reviewing
}

@MainActor
@Observable
private final class LiteInterstitialViewModel {
    var text: String
    let originalText: String
    let recordId: Int64?
    let audioFilename: String?
    let onDismiss: () -> Void

    // View state (editing vs reviewing diff)
    var viewState: LiteViewState = .editing

    // Database state
    var databaseReady = false
    var databaseError: String?

    // Polish state
    var isPolishing = false
    var polishError: String?

    // Diff review state
    var currentDiff: TextDiff?
    var proposedText: String = ""
    var lastInstruction: String = ""

    // Save state
    var saveError: String?
    var saveSuccess = false

    // LLM selection (persisted via SettingsManager)
    var selectedProviderId: String?
    var selectedModelId: String?

    // Revision history (matches InterstitialManager pattern)
    private(set) var revisions: [LiteRevision] = []
    private(set) var prePolishText: String = ""
    var previewingRevision: LiteRevision? = nil

    init(initialText: String, recordId: Int64?, audioFilename: String?, onDismiss: @escaping () -> Void) {
        self.text = initialText
        self.originalText = initialText
        self.recordId = recordId
        self.audioFilename = audioFilename
        self.onDismiss = onDismiss

        // Initialize with user's saved preferences or first available
        Task { @MainActor in
            if await applySavedLLMSelectionIfAvailable() {
                return
            }
            if let resolved = await LLMProviderRegistry.shared.resolveProviderAndModel() {
                setLLMSelection(providerId: resolved.provider.id, modelId: resolved.modelId)
            }
        }
    }

    func setLLMSelection(providerId: String, modelId: String) {
        selectedProviderId = providerId
        selectedModelId = modelId
        let settings = SettingsManager.shared
        settings.composeLLMProviderId = providerId
        settings.composeLLMModelId = modelId
    }

    private func applySavedLLMSelectionIfAvailable() async -> Bool {
        let settings = SettingsManager.shared
        guard let providerId = settings.composeLLMProviderId,
              let modelId = settings.composeLLMModelId else {
            return false
        }

        let registry = LLMProviderRegistry.shared
        guard registry.provider(for: providerId) != nil,
              registry.allModels.contains(where: { $0.provider == providerId && $0.id == modelId }) else {
            return false
        }

        setLLMSelection(providerId: providerId, modelId: modelId)
        return true
    }

    // MARK: - Diff Review Actions

    /// Accept the proposed changes
    func acceptRevision() {
        guard let diff = currentDiff else { return }

        // Record revision to history
        let revision = LiteRevision(
            timestamp: Date(),
            instruction: lastInstruction,
            textBefore: prePolishText,
            textAfter: proposedText,
            changeCount: diff.changeCount
        )
        revisions.append(revision)

        // Apply the changes
        text = proposedText

        // Emit signpost event
        os_signpost(.event, log: liteInterstitialLog, name: "LiteInterstitial",
                    "revision_accepted")

        // Reset review state
        currentDiff = nil
        proposedText = ""
        prePolishText = ""
        lastInstruction = ""
        viewState = .editing

        TalkieConsole.critical("[LITE] Accepted revision: \(revision.shortInstruction)")
    }

    /// Reject the proposed changes
    func rejectRevision() {
        let changeCount = currentDiff?.changeCount ?? 0

        // Emit signpost event
        os_signpost(.event, log: liteInterstitialLog, name: "LiteInterstitial",
                    "revision_rejected")

        // Discard proposed changes, keep original
        currentDiff = nil
        proposedText = ""
        prePolishText = ""
        lastInstruction = ""
        viewState = .editing

        TalkieConsole.critical("[LITE] Rejected revision")
    }

    // MARK: - Revision History (matches InterstitialManager)

    /// Restore from a revision (creates a new history entry)
    func restoreFromRevision(_ revision: LiteRevision) {
        let currentText = text

        // Record this restoration as a new revision
        let restorationRevision = LiteRevision(
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

        TalkieConsole.critical("[LITE] Restored from revision: \(revision.shortInstruction)")
    }

    // MARK: - Actions

    func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        TalkieConsole.critical("[LITE] Copied to clipboard: \(text.count) chars")
    }

    func saveAndDismiss() {
        copyToClipboard()

        if databaseReady {
            saveToDatabase()
        } else {
            TalkieConsole.critical("[LITE] Warning: Closing without save (DB not ready)")
            // Text is already copied to clipboard, so user won't lose it
        }

        onDismiss()
    }

    func dismiss() {
        onDismiss()
    }

    func resetText() {
        text = originalText
        saveError = nil
        saveSuccess = false
    }

    // MARK: - Voice Input (using EphemeralTranscriber - matches InterstitialManager)

    // Voice guidance state (exactly like InterstitialManager)
    var isRecordingInstruction: Bool = false
    var isTranscribingInstruction: Bool = false
    var voiceInstruction: String?
    var audioLevel: Float = 0

    func startVoiceInstruction() {
        guard !isRecordingInstruction else { return }

        os_signpost(.event, log: liteInterstitialLog, name: "LiteInterstitial",
                    "voice_instruction_start")

        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .interstitialCommand)
            isRecordingInstruction = true
            voiceInstruction = nil
            TalkieConsole.critical("[LITE] Started voice instruction capture")

            // Monitor audio level
            Task {
                while isRecordingInstruction {
                    audioLevel = EphemeralTranscriber.shared.audioLevel
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        } catch {
            polishError = error.localizedDescription
            TalkieConsole.critical("[LITE] Failed to start voice capture: \(error)")
        }
    }

    func stopVoiceInstruction() async {
        guard isRecordingInstruction else { return }

        // Begin signpost for voice → polish flow
        let voiceFlowSignpostID = liteSignposter.makeSignpostID()
        let voiceFlowState = liteSignposter.beginInterval("LiteVoiceToPolish", id: voiceFlowSignpostID)
        let voiceFlowStart = CFAbsoluteTimeGetCurrent()

        isRecordingInstruction = false
        isTranscribingInstruction = true
        audioLevel = 0

        do {
            let instruction = try await EphemeralTranscriber.shared.stopAndTranscribe()
            isTranscribingInstruction = false

            if !instruction.isEmpty {
                voiceInstruction = instruction
                TalkieConsole.critical("[LITE] Voice instruction: \(instruction)")
                await polish(instruction: instruction)

                // End voice → polish flow signpost
                let voiceFlowDuration = CFAbsoluteTimeGetCurrent() - voiceFlowStart
                let wordCount = instruction.split(separator: " ").count
                liteSignposter.endInterval("LiteVoiceToPolish", voiceFlowState,
                                           "complete \(wordCount)words \(Int(voiceFlowDuration * 1000))ms")
            } else {
                liteSignposter.endInterval("LiteVoiceToPolish", voiceFlowState, "empty_instruction")
            }
        } catch {
            isTranscribingInstruction = false
            polishError = error.localizedDescription

            liteSignposter.endInterval("LiteVoiceToPolish", voiceFlowState, "failed")
            TalkieConsole.critical("[LITE] Voice instruction failed: \(error)")
        }
    }

    func cancelVoiceInstruction() {
        EphemeralTranscriber.shared.cancel()
        isRecordingInstruction = false
        isTranscribingInstruction = false
        audioLevel = 0
    }

    // MARK: - Database Persistence

    private func saveToDatabase() {
        saveError = nil
        saveSuccess = false

        guard databaseReady else {
            saveError = "Database not ready"
            TalkieConsole.critical("[LITE] Skipping DB save: database not ready")
            return
        }

        // Prefer audioFilename lookup (more reliable than Int64 ID which is from different table)
        guard let audioFilename = audioFilename else {
            TalkieConsole.critical("[LITE] Skipping DB save: no audioFilename")
            saveError = "No audio filename for lookup"
            return
        }

        do {
            let db = try DatabaseManager.shared.database()
            try db.write { db in
                // Look up recording by audioFilename (unique key)
                try db.execute(
                    sql: """
                        UPDATE recordings
                        SET text = ?, lastModified = ?
                        WHERE audioFilename = ?
                    """,
                    arguments: [text, Date(), audioFilename]
                )

                let changedRows = db.changesCount
                if changedRows > 0 {
                    TalkieConsole.critical("[LITE] Updated recording in database (audioFilename: \(audioFilename))")
                    saveSuccess = true
                } else {
                    TalkieConsole.critical("[LITE] Recording not found for audioFilename: \(audioFilename)")
                    saveError = "Recording not found"
                }
            }
        } catch {
            saveError = error.localizedDescription
            TalkieConsole.critical("[LITE] DB save failed: \(error.localizedDescription)")
        }
    }

    // MARK: - LLM Polish

    func polish(instruction: String) async {
        guard !isPolishing else { return }

        isPolishing = true
        polishError = nil

        // Save pre-polish text for diff/history (matches InterstitialManager)
        prePolishText = text

        // Begin signpost for polish operation
        let polishSignpostID = liteSignposter.makeSignpostID()
        let polishState = liteSignposter.beginInterval("LitePolish", id: polishSignpostID)
        let polishStart = CFAbsoluteTimeGetCurrent()

        os_signpost(.event, log: liteInterstitialLog, name: "LiteInterstitial",
                    "polish_start")

        TalkieConsole.critical("[LITE] Polishing with instruction: \(instruction.prefix(50))...")

        do {
            let registry = LLMProviderRegistry.shared

            // Resolve provider and model
            let resolved: (provider: LLMProvider, modelId: String)
            if let providerId = selectedProviderId,
               let provider = registry.provider(for: providerId),
               let modelId = selectedModelId {
                resolved = (provider, modelId)
            } else if let fallback = await registry.resolveProviderAndModel() {
                resolved = fallback
                setLLMSelection(providerId: resolved.provider.id, modelId: resolved.modelId)
            } else {
                polishError = "No LLM provider configured. Add an API key in Settings."
                isPolishing = false
                prePolishText = ""
                TalkieConsole.critical("[LITE] No LLM provider available")
                return
            }

            // Build prompt
            let systemPrompt = SettingsManager.shared.composeAssistantPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? SettingsManager.defaultComposeAssistantPrompt
                : SettingsManager.shared.composeAssistantPrompt

            let prompt = """
                \(systemPrompt)

                User instruction:
                \(instruction)

                Current full document:
                \(text)

                Revision history (oldest to newest):
                \(revisionHistoryPromptContext())

                Return only the revised text.
                """

            let options = GenerationOptions(
                temperature: 0.3,
                maxTokens: 2048
            )

            let polished = try await resolved.provider.generate(
                prompt: prompt,
                model: resolved.modelId,
                options: options
            )

            let polishedText = polished.trimmingCharacters(in: .whitespacesAndNewlines)

            // Compute diff and show review (matches InterstitialManager pattern)
            let diff = DiffEngine.diff(original: prePolishText, proposed: polishedText)

            // End signpost with success
            let polishDuration = CFAbsoluteTimeGetCurrent() - polishStart
            liteSignposter.endInterval("LitePolish", polishState,
                                       "success \(resolved.provider.name) \(diff.changeCount)changes \(Int(polishDuration * 1000))ms")

            // Report to performance monitor (if available in full mode)
            await MainActor.run {
                PerformanceMonitor.shared.addOperation(
                    category: .llm,
                    name: "Lite Polish (\(resolved.provider.name))",
                    duration: polishDuration
                )
            }

            if diff.hasChanges {
                // Store for review
                proposedText = polishedText
                lastInstruction = voiceInstruction ?? instruction
                currentDiff = diff
                viewState = .reviewing
                TalkieConsole.critical("[LITE] Polish ready for review: \(diff.changeCount) changes via \(resolved.provider.name)/\(resolved.modelId) in \(String(format: "%.0f", polishDuration * 1000))ms")
            } else {
                // No changes - just clear state
                TalkieConsole.critical("[LITE] Polish produced no changes")
            }
            voiceInstruction = nil

        } catch {
            // End signpost with error
            let polishDuration = CFAbsoluteTimeGetCurrent() - polishStart
            liteSignposter.endInterval("LitePolish", polishState, "failed \(Int(polishDuration * 1000))ms")

            polishError = error.localizedDescription
            prePolishText = ""  // Clear on error
            TalkieConsole.critical("[LITE] Polish failed: \(error.localizedDescription)")
        }

        isPolishing = false
    }

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
}

// MARK: - SwiftUI View

private struct LiteInterstitialView: View {
    @Bindable var viewModel: LiteInterstitialViewModel
    @Environment(\.colorScheme) var colorScheme
    @Environment(SettingsManager.self) private var settings
    @FocusState private var isTextFocused: Bool
    @State private var copiedFeedback = false

    // Dictation pill state (floating overlay for ephemeral dictation)
    @State private var dictationPillState: DictationPillState = .idle
    @State private var dictationDuration: TimeInterval = 0
    @State private var dictationTimerRef: Task<Void, Never>?

    // MARK: - Design Constants (matching InterstitialEditorView)
    // Spacing
    private let spacingXS: CGFloat = 4
    private let spacingSM: CGFloat = 8
    private let spacingMD: CGFloat = 12
    private let spacingLG: CGFloat = 16

    // Corner Radius
    private let cornerRadiusXS: CGFloat = 4
    private let cornerRadiusSM: CGFloat = 6
    private let cornerRadiusMD: CGFloat = 8
    private let cornerRadiusLG: CGFloat = 12

    // MARK: - Theme-aware colors (matching InterstitialEditorView exactly)
    private var isDark: Bool { colorScheme == .dark }

    private var panelBackground: Color {
        isDark ? Color(white: 0.1) : Color(white: 0.98)
    }
    private var contentBackground: Color {
        isDark ? Color(white: 0.12) : Color.white
    }
    private var inputBackground: Color {
        isDark ? Color(white: 0.15) : Color(white: 0.95)
    }
    private var borderColor: Color {
        isDark ? Color(white: 0.2) : Color(white: 0.88)
    }
    private var textPrimary: Color {
        isDark ? Color.white : Color(white: 0.1)
    }
    private var textSecondary: Color {
        isDark ? Color(white: 0.7) : Color(white: 0.4)
    }
    private var textMuted: Color {
        isDark ? Color(white: 0.5) : Color(white: 0.55)
    }
    private var accentColor: Color { settings.resolvedAccentColor }

    // Diff review colors (semantic colors)
    private var deleteColor: Color { SemanticColor.error }
    private var insertColor: Color { SemanticColor.success }

    var body: some View {
        Group {
            switch viewModel.viewState {
            case .editing:
                editingView
            case .reviewing:
                reviewingView
            }
        }
        .frame(minWidth: 480, idealWidth: 560, maxWidth: 900,
               minHeight: 340, idealHeight: 400, maxHeight: 700)
        .background(
            RoundedRectangle(cornerRadius: cornerRadiusLG)
                .fill(panelBackground)
                // Lightweight shadow - single layer, smaller radius
                .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadiusLG)
                .stroke(borderColor, lineWidth: 1)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFocused = true
            }
        }
    }

    // MARK: - Editing View

    private var editingView: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            // Content
            contentArea

            // Footer
            footerBar
        }
    }

    // MARK: - Reviewing View (Diff)

    private var reviewingView: some View {
        VStack(spacing: 0) {
            // Review header
            reviewHeader

            // Side-by-side diff
            if let diff = viewModel.currentDiff {
                diffContent(diff: diff)
            }

            // Review footer with accept/reject
            reviewFooter
        }
    }

    private var reviewHeader: some View {
        HStack(spacing: spacingSM) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textMuted)

            Text("REVIEW CHANGES")
                .font(.system(size: 10, weight: .bold, design: .default))
                .foregroundColor(textMuted)

            Spacer()

            // Change count badge
            if let diff = viewModel.currentDiff, diff.changeCount > 0 {
                Text("\(diff.changeCount) change\(diff.changeCount == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
                    .padding(.horizontal, spacingSM)
                    .padding(.vertical, spacingXS)
                    .background(
                        Capsule()
                            .fill(inputBackground)
                    )
            }

            // Close button (same style as editing view)
            Button(action: { viewModel.rejectRevision() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textSecondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(inputBackground)
                    )
            }
            .buttonStyle(.plain)
            .help("Discard changes (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, spacingLG)
        .padding(.top, spacingMD)
        .padding(.bottom, spacingSM)
    }

    private func diffContent(diff: TextDiff) -> some View {
        HStack(spacing: 0) {
            // Original (left)
            diffPane(
                title: "ORIGINAL",
                indicatorColor: deleteColor,
                content: diff.attributedOriginal(baseColor: textPrimary, deleteColor: deleteColor)
            )

            // Divider
            Rectangle()
                .fill(borderColor)
                .frame(width: 1)

            // Proposed (right)
            diffPane(
                title: "PROPOSED",
                indicatorColor: insertColor,
                content: diff.attributedProposed(baseColor: textPrimary, insertColor: insertColor)
            )
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadiusMD)
                .fill(contentBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadiusMD)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .padding(.horizontal, spacingLG)
        .padding(.bottom, spacingSM)
    }

    private func diffPane(title: String, indicatorColor: Color, content: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pane header
            HStack(spacing: spacingSM - 2) {
                Circle()
                    .fill(indicatorColor)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(textMuted)
                Spacer()
            }
            .padding(.horizontal, spacingSM + 2)
            .padding(.vertical, spacingSM - 2)
            .background(isDark ? Color(white: 0.08) : Color(white: 0.94))

            // Pane content
            ScrollView {
                Text(content)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(spacingSM + 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var reviewFooter: some View {
        HStack(spacing: spacingMD) {
            // Voice instruction display
            if !viewModel.lastInstruction.isEmpty {
                HStack(spacing: spacingXS) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 9))
                        .foregroundColor(accentColor)
                    Text(viewModel.lastInstruction.prefix(40) + (viewModel.lastInstruction.count > 40 ? "..." : ""))
                        .font(.system(size: 10))
                        .foregroundColor(textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, spacingSM)
                .padding(.vertical, spacingXS + 2)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadiusSM)
                        .fill(accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadiusSM)
                                .stroke(accentColor.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            Spacer()

            // Reject button
            Button(action: { viewModel.rejectRevision() }) {
                HStack(spacing: spacingXS) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                    Text("REJECT")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(deleteColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(deleteColor.opacity(0.1))
                        .overlay(
                            Capsule()
                                .stroke(deleteColor, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)

            // Accept button
            Button(action: { viewModel.acceptRevision() }) {
                HStack(spacing: spacingXS) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                    Text("ACCEPT")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(insertColor)
                )
                .shadow(color: insertColor.opacity(0.25), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, spacingLG)
        .padding(.vertical, spacingMD)
    }

    // MARK: - Header

    @State private var showHistory = false

    private var headerBar: some View {
        HStack(spacing: spacingSM) {
            // Status indicators (left side)
            statusIndicators

            Spacer()

            // History button (only show if there's history)
            if !viewModel.revisions.isEmpty {
                historyButton
            }

            // Close button (compact)
            Button(action: { viewModel.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(textSecondary)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(inputBackground)
                    )
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, spacingLG)
        .padding(.top, spacingMD)
        .padding(.bottom, spacingSM)
    }

    // MARK: - History Button

    private var historyButton: some View {
        Button(action: { showHistory.toggle() }) {
            HStack(spacing: spacingXS) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .medium))
                Text("\(viewModel.revisions.count)")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(textMuted)
            .padding(.horizontal, spacingSM)
            .padding(.vertical, spacingXS)
            .background(
                Capsule()
                    .fill(inputBackground)
                    .overlay(
                        Capsule()
                            .stroke(showHistory ? accentColor : borderColor, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .help("Edit history (\(viewModel.revisions.count) edits)")
        .popover(isPresented: $showHistory) {
            historyPopover
        }
    }

    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("EDIT HISTORY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textMuted)
                Spacer()
                Text("\(viewModel.revisions.count) edits")
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, spacingMD)
            .padding(.vertical, spacingSM)

            Divider()

            // Timeline list
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.revisions.reversed()) { revision in
                        historyRow(revision)
                    }
                }
                .padding(spacingSM)
            }
            .frame(maxHeight: 200)
        }
        .frame(width: 320)
        .background(panelBackground)
    }

    private func historyRow(_ revision: LiteRevision) -> some View {
        Button(action: {
            viewModel.restoreFromRevision(revision)
            showHistory = false
        }) {
            HStack(spacing: spacingSM) {
                // Timeline dot
                Circle()
                    .fill(accentColor)
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 2) {
                    // Instruction (truncated)
                    Text(revision.shortInstruction)
                        .font(.system(size: 11))
                        .foregroundColor(textPrimary)
                        .lineLimit(1)

                    // Metadata
                    HStack(spacing: spacingSM - 2) {
                        Text("\(revision.changeCount) changes")
                            .font(.system(size: 9))
                            .foregroundColor(textMuted)
                        Text("•")
                            .foregroundColor(textMuted)
                        Text(revision.timeAgo)
                            .font(.system(size: 9))
                            .foregroundColor(textMuted)
                    }
                }

                Spacer()

                // View hint
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, spacingSM)
            .padding(.vertical, spacingXS + 2)
            .background(
                RoundedRectangle(cornerRadius: cornerRadiusSM)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Restore to this version")
    }

    @State private var showModelPicker = false

    private var modelSelector: some View {
        Menu {
            // Provider sections
            ForEach(LLMProviderRegistry.shared.providers, id: \.id) { provider in
                Section(provider.name) {
                    ForEach(LLMProviderRegistry.shared.recommendedModels(for: provider.id), id: \.id) { model in
                        Button(action: {
                            viewModel.setLLMSelection(providerId: provider.id, modelId: model.id)
                        }) {
                            HStack {
                                Text(model.displayName)
                                if viewModel.selectedProviderId == provider.id && viewModel.selectedModelId == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: spacingSM - 2) {
                // Provider icon
                providerIcon
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(providerColor)

                // Model name
                Text(displayModelName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(textPrimary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, spacingSM + 2)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: cornerRadiusSM)
                    .fill(inputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadiusSM)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .help("Select LLM model")
    }

    private var providerIcon: Image {
        guard let providerId = viewModel.selectedProviderId else {
            return Image(systemName: "cpu")
        }
        switch providerId {
        case "openai": return Image(systemName: "sparkle")
        case "anthropic": return Image(systemName: "brain")
        case "google", "gemini": return Image(systemName: "diamond")
        case "groq": return Image(systemName: "bolt")
        default: return Image(systemName: "cpu")
        }
    }

    private var providerColor: Color {
        guard let providerId = viewModel.selectedProviderId else { return textMuted }
        switch providerId {
        case "openai": return Color(red: 0.3, green: 0.7, blue: 0.5)
        case "anthropic": return Color(red: 0.85, green: 0.55, blue: 0.35)
        case "google", "gemini": return Color(red: 0.3, green: 0.5, blue: 0.9)
        case "groq": return Color(red: 0.9, green: 0.4, blue: 0.3)
        default: return textMuted
        }
    }

    private var displayModelName: String {
        if let model = viewModel.selectedModelId {
            return model
                .replacingOccurrences(of: "claude-opus-4-6", with: "opus 4.6")
                .replacingOccurrences(of: "claude-sonnet-4-6", with: "sonnet 4.6")
                .replacingOccurrences(of: "claude-sonnet-4-5-20250929", with: "sonnet 4.5")
                .replacingOccurrences(of: "claude-haiku-4-5-20251001", with: "haiku 4.5")
                .replacingOccurrences(of: "gpt-4o-mini", with: "4o-mini")
                .replacingOccurrences(of: "gpt-4o", with: "4o")
                .replacingOccurrences(of: "claude-3-5-sonnet", with: "sonnet")
                .replacingOccurrences(of: "claude-3-haiku", with: "haiku")
                .replacingOccurrences(of: "gemini-1.5-flash", with: "flash")
                .replacingOccurrences(of: "llama-3.1-70b-versatile", with: "llama-70b")
        }
        return "Select model"
    }

    @ViewBuilder
    private var statusIndicators: some View {
        // Polish status - minimal pill (matching InterstitialEditorView)
        if viewModel.isPolishing {
            HStack(spacing: spacingXS) {
                BrailleSpinner(size: 10)
                Text("REVISING")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, spacingSM)
            .padding(.vertical, spacingXS)
            .background(
                Capsule()
                    .fill(inputBackground)
            )
        }

        // Database status
        if !viewModel.databaseReady {
            HStack(spacing: spacingXS) {
                if viewModel.databaseError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                } else {
                    BrailleSpinner(size: 10)
                }
                Text(viewModel.databaseError != nil ? "DB Error" : "Loading...")
                    .font(.system(size: 10))
                    .foregroundColor(textMuted)
            }
            .help(viewModel.databaseError ?? "Database initializing...")
        }
    }

    // MARK: - Content

    private var contentArea: some View {
        VStack(spacing: 0) {
            // Content header: label + model selector
            HStack(spacing: spacingSM) {
                // Left: label
                HStack(spacing: spacingXS) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(textMuted)
                    Text("DICTATION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(textMuted)
                }

                Spacer()

                // Right: model selector + word count
                HStack(spacing: spacingSM) {
                    // Model selector (compact)
                    compactModelSelector

                    // Word count
                    Text("\(viewModel.text.split(separator: " ").count) words")
                        .font(.system(size: 9))
                        .foregroundColor(textMuted)
                }
            }
            .padding(.horizontal, spacingSM + 2)
            .padding(.vertical, spacingXS + 2)
            .background(isDark ? Color(white: 0.08) : Color(white: 0.94))

            // Text editor with floating dictation pill
            ZStack(alignment: .bottom) {
                TextEditor(text: $viewModel.text)
                    .font(.system(size: 14))  // Slightly larger for readability
                    .foregroundColor(textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(spacingMD)
                    .padding(.bottom, 40) // Space for floating pill
                    .focused($isTextFocused)
                    .frame(maxHeight: .infinity)

                // Floating dictation pill (centered at bottom of text area)
                DictationPill(
                    state: $dictationPillState,
                    duration: $dictationDuration,
                    onTap: handleDictationPillTap
                )
                .padding(.bottom, spacingSM)
            }

            // Subtle separator
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)

            // Quick actions row
            quickActionsBar
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadiusMD)
                .fill(contentBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadiusMD)
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadiusMD))
        .padding(.horizontal, spacingLG)
        .padding(.bottom, spacingSM)
    }

    // MARK: - Dictation Pill Actions

    private func handleDictationPillTap() {
        switch dictationPillState {
        case .idle:
            startDictationRecording()
        case .recording:
            stopDictationRecording()
        case .transcribing, .success:
            // Ignore taps during these states
            break
        }
    }

    private func startDictationRecording() {
        do {
            try EphemeralTranscriber.shared.startCapture(purpose: .interstitialDictation)
            dictationPillState = .recording
            dictationDuration = 0

            // Start timer
            dictationTimerRef = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    dictationDuration += 0.1
                }
            }
        } catch {
            viewModel.polishError = error.localizedDescription
        }
    }

    private func stopDictationRecording() {
        dictationTimerRef?.cancel()
        dictationTimerRef = nil

        dictationPillState = .transcribing

        Task {
            do {
                let transcribedText = try await EphemeralTranscriber.shared.stopAndTranscribe()

                // Append to text with smart spacing
                if !transcribedText.isEmpty {
                    let needsSpace = !viewModel.text.isEmpty &&
                                     !viewModel.text.hasSuffix(" ") &&
                                     !viewModel.text.hasSuffix("\n")
                    if needsSpace {
                        viewModel.text += " "
                    }
                    viewModel.text += transcribedText
                }

                // Show success briefly
                dictationPillState = .success
                try? await Task.sleep(for: .milliseconds(800))
                dictationPillState = .idle

            } catch {
                viewModel.polishError = error.localizedDescription
                dictationPillState = .idle
            }
        }
    }

    // MARK: - Quick Actions

    @State private var isPulsing = false

    private var quickActionsBar: some View {
        VStack(spacing: spacingSM) {
            // Row: Command + Quick actions (all left-aligned)
            HStack(spacing: spacingSM - 2) {
                // Command button (prominent, slightly larger)
                commandButton

                // Show first 2 quick actions inline
                ForEach(SmartAction.builtIn.prefix(2)) { action in
                    quickActionButton(action)
                }

                // Ellipsis menu for remaining actions
                if SmartAction.builtIn.count > 2 {
                    moreActionsMenu
                }

                Spacer()
            }

            // Voice instruction display (if any)
            if let instruction = viewModel.voiceInstruction {
                HStack(spacing: spacingXS) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 10))
                        .foregroundColor(accentColor)
                    Text(instruction)
                        .font(.system(size: 11))
                        .foregroundColor(textPrimary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { viewModel.voiceInstruction = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(textMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, spacingSM)
                .padding(.vertical, spacingXS + 2)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadiusSM)
                        .fill(accentColor.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadiusSM)
                                .stroke(accentColor.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            // Error message
            if let error = viewModel.polishError {
                HStack(spacing: spacingXS) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(SemanticColor.error)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundColor(SemanticColor.error)
                        .lineLimit(1)
                }
            }
        }
        .padding(spacingSM)
    }

    // MARK: - Command Button (Voice → AI)

    private var commandButton: some View {
        Button(action: {
            if viewModel.isRecordingInstruction {
                Task { await viewModel.stopVoiceInstruction() }
            } else {
                viewModel.startVoiceInstruction()
            }
        }) {
            HStack(spacing: spacingXS) {
                if viewModel.isTranscribingInstruction {
                    BrailleSpinner(size: 10)
                        .foregroundColor(.white)
                } else if viewModel.isRecordingInstruction {
                    // Recording state: stop icon
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    // Idle state: mic with sparkle
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "sparkle")
                            .font(.system(size: 6, weight: .bold))
                            .offset(x: 3, y: -2)
                    }
                }

                // Label: "Command" when idle, "Stop" when recording
                Text(viewModel.isRecordingInstruction ? "Stop" : (viewModel.isTranscribingInstruction ? "..." : "Command"))
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, spacingSM + 4)
            .padding(.vertical, spacingSM - 2)
            .background(
                Capsule()
                    .fill(viewModel.isRecordingInstruction ? SemanticColor.error : accentColor)
            )
            // Pulsing ring when recording
            .overlay(
                Capsule()
                    .stroke(SemanticColor.error.opacity(isPulsing ? 0.6 : 0), lineWidth: 2)
                    .scaleEffect(isPulsing ? 1.12 : 1.0)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isTranscribingInstruction || viewModel.isPolishing)
        .help("Speak to tell the AI what to do with your text")
        .onChange(of: viewModel.isRecordingInstruction) { _, isRecording in
            if isRecording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    isPulsing = false
                }
            }
        }
    }

    // MARK: - More Actions Menu (Ellipsis)

    private var moreActionsMenu: some View {
        Menu {
            ForEach(SmartAction.builtIn.dropFirst(2)) { action in
                Button(action: {
                    Task { await viewModel.polish(instruction: action.defaultPrompt) }
                }) {
                    Label(action.name, systemImage: action.icon)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(textSecondary)
                .frame(width: 28, height: 24)
                .background(
                    Capsule()
                        .fill(inputBackground)
                        .overlay(
                            Capsule()
                                .stroke(borderColor, lineWidth: 1)
                        )
                )
        }
        .menuStyle(.borderlessButton)
        .disabled(viewModel.isPolishing)
        .help("More actions")
    }

    private func quickActionButton(_ action: SmartAction) -> some View {
        Button(action: {
            Task { await viewModel.polish(instruction: action.defaultPrompt) }
        }) {
            HStack(spacing: spacingXS) {
                Image(systemName: action.icon)
                    .font(.system(size: 9))
                Text(action.name)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(textSecondary)
            .padding(.horizontal, spacingSM)
            .padding(.vertical, spacingXS + 1)
            .background(
                Capsule()
                    .fill(inputBackground)
                    .overlay(
                        Capsule()
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isPolishing)
        .help(action.name)
    }

    // MARK: - Footer

    // App version for display
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    private var footerBar: some View {
        VStack(spacing: 0) {
            // Main footer row
            HStack(spacing: spacingSM) {
                // Left side: Reset button (if text changed) + status
                HStack(spacing: spacingXS) {
                    // Reset button - subtle
                    if viewModel.text != viewModel.originalText {
                        Button(action: { viewModel.resetText() }) {
                            HStack(spacing: spacingXS) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10))
                                Text("Reset")
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(textSecondary)
                            .padding(.horizontal, spacingSM)
                            .padding(.vertical, spacingXS)
                        }
                        .buttonStyle(.plain)
                        .help("Reset to original")
                    }

                    // Save error/success indicator
                    if let error = viewModel.saveError {
                        HStack(spacing: spacingXS) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(.orange)
                        }
                    }

                    // Database warning if not ready
                    if !viewModel.databaseReady && viewModel.text != viewModel.originalText {
                        Text("Changes may not save")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                // Right side: Quick open apps + Save + Copy
                HStack(spacing: spacingSM - 2) {
                    // Quick open buttons
                    quickOpenButtons

                    // Save as Memo button
                    Button(action: { viewModel.saveAndDismiss() }) {
                        HStack(spacing: spacingXS) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 10))
                            Text("Save as Memo")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(textSecondary)
                        .padding(.horizontal, spacingSM + 2)
                        .padding(.vertical, spacingXS + 2)
                        .background(
                            Capsule()
                                .fill(inputBackground)
                                .overlay(Capsule().stroke(borderColor, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("s", modifiers: .command)
                    .help("Save transcription as a Memo (⌘S)")

                    // Copy button (icon only for compactness)
                    Button(action: {
                        viewModel.copyToClipboard()
                        copiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedFeedback = false
                        }
                    }) {
                        Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(copiedFeedback ? SemanticColor.success : textSecondary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(inputBackground)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("c", modifiers: .command)
                    .help("Copy (⌘C)")

                    // Copy & Close button (primary action - rightmost)
                    Button(action: {
                        viewModel.copyToClipboard()
                        viewModel.dismiss()
                    }) {
                        HStack(spacing: spacingXS) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Copy & Close")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(accentColor)
                        )
                        .shadow(color: accentColor.opacity(0.25), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Copy to clipboard and close (⌘↩)")
                }
            }
            .padding(.horizontal, spacingLG)
            .padding(.vertical, spacingSM + 2)

            // Status bar (version tag)
            statusBar
        }
    }

    // MARK: - Status Bar

    private var statusBarBackground: Color {
        isDark ? Color(white: 0.06) : Color(white: 0.92)
    }

    private var statusBar: some View {
        VStack(spacing: 0) {
            // 1px divider
            Rectangle()
                .fill(borderColor)
                .frame(height: 1)

            // Status bar content
            HStack(spacing: spacingSM) {
                // Version tag
                Text("v\(appVersion)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(textMuted)

                #if DEBUG
                Text("LITE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, spacingXS)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(accentColor.opacity(0.15))
                    )
                #endif

                Spacer()

                // Character count
                Text("\(viewModel.text.count) chars")
                    .font(.system(size: 9))
                    .foregroundColor(textMuted)
            }
            .padding(.horizontal, spacingLG)
            .padding(.vertical, spacingSM - 2)
            .background(statusBarBackground)
        }
    }

    // MARK: - Compact Model Selector

    private var compactModelSelector: some View {
        Menu {
            // Provider sections
            ForEach(LLMProviderRegistry.shared.providers, id: \.id) { provider in
                Section(provider.name) {
                    ForEach(LLMProviderRegistry.shared.recommendedModels(for: provider.id), id: \.id) { model in
                        Button(action: {
                            viewModel.setLLMSelection(providerId: provider.id, modelId: model.id)
                        }) {
                            HStack {
                                Text(model.displayName)
                                if viewModel.selectedProviderId == provider.id && viewModel.selectedModelId == model.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: spacingXS - 1) {
                // Provider icon
                providerIcon
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(providerColor)

                // Model name (compact)
                Text(displayModelName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(textSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundColor(textMuted)
            }
        }
        .menuStyle(.borderlessButton)
        .help("Select LLM model")
    }

    // MARK: - Quick Open

    @State private var activeQuickOpenTarget: String? = nil

    @ViewBuilder
    private var quickOpenButtons: some View {
        let targets = QuickOpenService.shared.enabledTargets.prefix(3)
        if !targets.isEmpty {
            QuickOpenBar(
                content: viewModel.text,
                showCopyButton: false,
                compactMode: true
            )
        }
    }
}
