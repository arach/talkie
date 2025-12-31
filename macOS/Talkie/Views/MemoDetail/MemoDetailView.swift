//
//  MemoDetailView.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import AVFoundation
import AppKit
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Views")

/// MemoDetailView - displays and edits a memo from GRDB (local source of truth)
/// Views never touch CoreData - sync layer handles cloud separately
struct MemoDetailView: View {
    /// The memo from GRDB - source of truth for display
    let memo: MemoModel

    // Use direct access to SettingsManager.shared instead of @ObservedObject
    // to avoid unnecessary view rebuilds on any published property change
    private let settings = SettingsManager.shared
    var showHeader: Bool = true  // Set to false when embedded in inspector

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var editedTitle: String = ""
    @State private var editedNotes: String = ""
    @State private var editedTranscript: String = ""
    @State private var isEditing = false
    @State private var notesSaveTimer: Timer?
    @State private var showNotesSaved = false
    @State private var playbackTimer: Timer?
    @State private var notesInitialized = false
    @State private var selectedWorkflowRunID: UUID?
    @FocusState private var titleFieldFocused: Bool

    // Repository for GRDB operations - views save here, sync layer handles cloud
    private let repository = LocalRepository()
    private let workflowManager = WorkflowManager.shared
    @State private var processingWorkflowIDs: Set<UUID> = []
    @State private var showingWorkflowPicker = false
    @State private var cachedQuickActionItems: [QuickActionItem] = []
    @State private var cachedWorkflowRuns: [WorkflowRunModel] = []
    @State private var showingRetranscribeSheet = false
    @State private var isRetranscribing = false
    @State private var isTranscribingLocal = false  // Local UI state for transcription

    // MARK: - Quick Actions Logic

    /// Represents a quick action slot (either pinned workflow or built-in action)
    enum QuickActionItem: Identifiable {
        case workflow(WorkflowDefinition)
        case builtIn(BuiltInAction)

        var id: String {
            switch self {
            case .workflow(let wf): return wf.id.uuidString
            case .builtIn(let action): return action.id
            }
        }

        enum BuiltInAction: String, CaseIterable {
            case summarize, taskify, remind, toNotes, copy

            var id: String { rawValue }
            var icon: String {
                switch self {
                case .summarize: return "list.bullet.clipboard"
                case .taskify: return "checkmark.square"
                case .remind: return "bell"
                case .toNotes: return "note.text"
                case .copy: return "doc.on.doc"
                }
            }
            var title: String {
                switch self {
                case .summarize: return "SUMMARIZE"
                case .taskify: return "TASKIFY"
                case .remind: return "REMIND"
                case .toNotes: return "TO NOTES"
                case .copy: return "COPY"
                }
            }
        }
    }

    /// Build the quick actions list: pinned workflows first, then defaults, max 5 items
    private func computeQuickActionItems() -> [QuickActionItem] {
        var items: [QuickActionItem] = []

        // Add pinned workflows first (up to 5)
        let pinnedWorkflows = workflowManager.workflows
            .filter { $0.isPinned && $0.isEnabled }
            .prefix(5)
        for workflow in pinnedWorkflows {
            items.append(.workflow(workflow))
        }

        // Fill remaining slots with defaults
        let defaultActions: [QuickActionItem.BuiltInAction] = [.summarize, .taskify, .remind, .toNotes, .copy]
        for action in defaultActions where items.count < 5 {
            items.append(.builtIn(action))
        }

        return items
    }

    /// Fetch workflow runs from GRDB (sorted by date, deduplicated)
    private func fetchWorkflowRuns() async {
        do {
            let runs = try await repository.fetchWorkflowRuns(for: memo.id)
            await MainActor.run {
                cachedWorkflowRuns = runs
            }
        } catch {
            logger.error("Failed to fetch workflow runs: \(error.localizedDescription)")
        }
    }

    /// Refresh cached data (called on appear and memo change)
    private func refreshCachedData() {
        cachedQuickActionItems = computeQuickActionItems()
        Task {
            await fetchWorkflowRuns()
        }
    }

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                MemoDetailHeaderSection(
                    showHeader: showHeader,
                    memoTitle: memoTitle,
                    memoSource: memo.source.asMemoSource,
                    dateText: formatDate(memoCreatedAt).uppercased(),
                    durationText: formatDuration(memo.duration),
                    isEditing: $isEditing,
                    editedTitle: $editedTitle,
                    titleFieldFocused: $titleFieldFocused,
                    onToggleEdit: toggleEditMode
                )

                MemoDetailTranscriptSection(
                    memo: memo,
                    settings: settings,
                    isEditing: $isEditing,
                    editedTranscript: $editedTranscript,
                    isRetranscribing: isRetranscribing,
                    onRetranscribe: retranscribe
                )

                #if arch(arm64)
                if (memo.currentTranscript == nil || memo.currentTranscript?.isEmpty == true) && memo.audioData != nil {
                    MemoDetailTranscribeActionSection(
                        isProcessing: memo.isTranscribing,
                        isCompleted: memo.currentTranscript != nil,
                        onTranscribe: executeTranscribeAction
                    )
                }
                #endif

                if memo.currentTranscript != nil && !memo.isTranscribing {
                    MemoDetailQuickActionsSection(
                        items: cachedQuickActionItems,
                        onBrowseWorkflows: browseWorkflows,
                        buttonProvider: quickActionButton
                    )
                }

                if !cachedWorkflowRuns.isEmpty {
                    MemoDetailRecentRunsSection(
                        runs: cachedWorkflowRuns,
                        settings: settings,
                        onSelect: { selectedWorkflowRunID = $0.id },
                        formatTimeAgo: formatTimeAgo
                    )
                }

                MemoDetailNotesSection(
                    settings: settings,
                    editedNotes: $editedNotes,
                    showNotesSaved: showNotesSaved,
                    onNotesChange: debouncedSaveNotes
                )

                if memo.audioData != nil {
                    MemoDetailPlaybackSection(
                        settings: settings,
                        isPlaying: $isPlaying,
                        currentTime: $currentTime,
                        duration: duration > 0 ? duration : memo.duration,
                        onTogglePlayback: togglePlayback,
                        onSeek: seekTo,
                        onVolumeChange: { newVolume in
                            audioPlayer?.volume = newVolume
                        }
                    )
                }

                MemoDetailDangerZoneSection(
                    settings: settings,
                    onDelete: deleteMemo
                )

                Spacer()
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.current.background)
        .quickOpenShortcuts(content: memo.currentTranscript ?? "", enabled: memo.currentTranscript != nil)
        .onAppear {
            editedTitle = memoTitle
            editedNotes = memo.notes ?? ""
            refreshCachedData()
            // Delay to avoid triggering save on initial load
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                notesInitialized = true
            }
        }
        .onChange(of: memo.id) { _, _ in
            // Reset state when memo changes
            notesInitialized = false
            editedTitle = memo.title ?? "Recording"
            editedNotes = memo.notes ?? ""
            editedTranscript = ""
            isEditing = false
            isPlaying = false
            audioPlayer?.stop()
            audioPlayer = nil
            currentTime = 0
            refreshCachedData()
            // Re-enable after memo change settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                notesInitialized = true
            }
        }
        .onChange(of: workflowManager.workflows) { _, _ in
            // Refresh quick actions when workflows change
            cachedQuickActionItems = computeQuickActionItems()
        }
        .onExitCommand {
            // Escape cancels edit mode
            if isEditing {
                isEditing = false
            }
        }
        .sheet(isPresented: $showingWorkflowPicker) {
            WorkflowPickerSheet(
                memo: memo,
                onSelect: { workflow in
                    showingWorkflowPicker = false
                    executeCustomWorkflow(workflow)
                },
                onCancel: {
                    showingWorkflowPicker = false
                }
            )
        }
    }

    private func toggleEditMode() {
        if isEditing {
            // Save changes
            saveAllEdits()
            isEditing = false
        } else {
            // Enter edit mode - populate fields
            editedTitle = memoTitle
            editedTranscript = memo.currentTranscript ?? ""
            isEditing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                titleFieldFocused = true
            }
        }
    }

    private func saveAllEdits() {
        // Create updated memo with edits
        var updatedMemo = memo

        // Update title if changed
        if editedTitle != memoTitle {
            updatedMemo.title = editedTitle
        }

        // Update notes
        updatedMemo.notes = editedNotes
        updatedMemo.lastModified = Date()

        // Save to GRDB
        Task {
            do {
                try await repository.saveMemo(updatedMemo)

                // Save transcript version if changed
                if let currentTranscript = memo.transcription,
                   editedTranscript != currentTranscript,
                   !editedTranscript.isEmpty {
                    let version = TranscriptVersionModel(
                        id: UUID(),
                        memoId: memo.id,
                        version: 1,  // Will be incremented by repository if needed
                        content: editedTranscript,
                        sourceType: "user",
                        engine: "user_edit",
                        createdAt: Date()
                    )
                    try await repository.saveTranscriptVersion(version)
                }
            } catch {
                logger.error("Failed to save memo: \(error.localizedDescription)")
            }
        }
    }

    private func debouncedSaveNotes() {
        // Skip on initial load
        guard notesInitialized else { return }

        // Cancel previous timer
        notesSaveTimer?.invalidate()

        // Hide checkmark while typing
        withAnimation { showNotesSaved = false }

        // Start new timer - save after 10 seconds of no typing
        notesSaveTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { _ in
            saveNotes()
        }
    }

    private func saveNotes() {
        var updatedMemo = memo
        updatedMemo.notes = editedNotes
        updatedMemo.lastModified = Date()

        Task {
            do {
                try await repository.saveMemo(updatedMemo)

                // Show checkmark briefly
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showNotesSaved = true
                    }
                }

                // Hide after 2 seconds
                try? await Task.sleep(for: .seconds(2))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showNotesSaved = false
                    }
                }
            } catch {
                logger.error("Failed to save notes: \(error.localizedDescription)")
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            stopPlaybackTimer()
            isPlaying = false
        } else if audioPlayer != nil {
            audioPlayer?.play()
            startPlaybackTimer()
            isPlaying = true
        } else {
            // Initialize player with synced audio data
            guard let audioData = memo.audioData else {
                logger.debug("⚠️ No audio data available (not yet synced from iOS)")
                return
            }

            do {
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.volume = SettingsManager.shared.playbackVolume
                audioPlayer?.prepareToPlay()
                duration = audioPlayer?.duration ?? 0
                audioPlayer?.play()
                startPlaybackTimer()
                isPlaying = true
                logger.debug("✅ Playing synced audio: \(audioData.count) bytes, duration: \(duration)s, volume: \(SettingsManager.shared.playbackVolume)")
            } catch {
                logger.debug("❌ Failed to play audio: \(error)")
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if let player = audioPlayer {
                currentTime = player.currentTime
                // Check if playback finished
                if !player.isPlaying && currentTime >= duration - 0.1 {
                    stopPlaybackTimer()
                    isPlaying = false
                    currentTime = 0
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func seekTo(_ progress: Double) {
        guard let player = audioPlayer else { return }
        let time = progress * player.duration
        player.currentTime = time
        currentTime = time
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatTimeAgo(_ date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)

        if diff < 60 {
            return "just now"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "\(mins)m ago"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours)h ago"
        } else if diff < 604800 {
            let days = Int(diff / 86400)
            return "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    private func copyTranscript() {
        guard let transcript = memo.currentTranscript else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
    }

    /// Transcribe audio using local WhisperKit (Apple Silicon only)
    private func executeTranscribeAction() {
        #if arch(arm64)
        Task {
            do {
                // Load audio from file path
                guard let audioPath = memo.audioFilePath else {
                    logger.debug("[Transcribe] No audio file path")
                    return
                }

                let audioURL = AudioStorage.url(for: audioPath)
                guard let audioData = try? Data(contentsOf: audioURL) else {
                    logger.debug("[Transcribe] Could not load audio data")
                    return
                }

                // Set local UI state
                await MainActor.run {
                    isTranscribingLocal = true
                }

                // Update memo state in GRDB
                var updatedMemo = memo
                updatedMemo.isTranscribing = true
                try await repository.saveMemo(updatedMemo)

                // Transcribe using WhisperKit
                let transcript = try await WhisperService.shared.transcribe(
                    audioData: audioData,
                    model: .small
                )

                // Save transcript version to GRDB
                let version = TranscriptVersionModel(
                    id: UUID(),
                    memoId: memo.id,
                    version: 1,
                    content: transcript,
                    sourceType: "system_macos",
                    engine: TranscriptEngines.whisperKit,
                    createdAt: Date()
                )
                try await repository.saveTranscriptVersion(version)

                // Update memo with transcript and clear transcribing state
                updatedMemo.transcription = transcript
                updatedMemo.isTranscribing = false
                updatedMemo.lastModified = Date()
                try await repository.saveMemo(updatedMemo)

                await MainActor.run {
                    isTranscribingLocal = false
                }
            } catch {
                // Clear transcribing state on error
                var updatedMemo = memo
                updatedMemo.isTranscribing = false
                try? await repository.saveMemo(updatedMemo)

                await MainActor.run {
                    isTranscribingLocal = false
                }
                logger.error("Transcription failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    private func deleteMemo() {
        Task {
            do {
                try await repository.deleteMemo(id: memo.id)
            } catch {
                logger.error("Failed to delete memo: \(error.localizedDescription)")
            }
        }
    }

    private func retranscribe(with modelId: String) {
        // Load audio from file path
        guard let audioPath = memo.audioFilePath else {
            logger.error("Cannot retranscribe: no audio file path")
            return
        }

        let audioURL = AudioStorage.url(for: audioPath)
        guard let audioData = try? Data(contentsOf: audioURL) else {
            logger.error("Cannot retranscribe: could not load audio data")
            return
        }

        isRetranscribing = true

        Task {
            do {
                let engineClient = EngineClient.shared
                let transcript = try await engineClient.transcribe(
                    audioData: audioData,
                    modelId: modelId,
                    priority: .userInitiated
                )

                // Save new transcript to GRDB
                var updatedMemo = memo
                updatedMemo.transcription = transcript
                updatedMemo.lastModified = Date()
                try await repository.saveMemo(updatedMemo)

                // Also save as transcript version
                let version = TranscriptVersionModel(
                    id: UUID(),
                    memoId: memo.id,
                    version: 1,
                    content: transcript,
                    sourceType: "system_macos",
                    engine: modelId,
                    createdAt: Date()
                )
                try await repository.saveTranscriptVersion(version)

                await MainActor.run {
                    isRetranscribing = false
                }

                logger.info("Successfully retranscribed memo with \(modelId)")
            } catch {
                logger.error("Failed to retranscribe: \(error.localizedDescription)")
                await MainActor.run {
                    isRetranscribing = false
                }
            }
        }
    }

    private func resolveProviderAndModel(from settings: SettingsManager) -> (String, String) {
        // Check selected model to determine provider
        let selectedModel = settings.selectedModel

        if selectedModel.hasPrefix("gpt-") && settings.openaiApiKey != nil {
            return ("openai", selectedModel)
        } else if selectedModel.hasPrefix("claude-") && settings.anthropicApiKey != nil {
            return ("anthropic", selectedModel)
        } else if (selectedModel.hasPrefix("llama") || selectedModel.hasPrefix("mixtral") || selectedModel.hasPrefix("gemma")) && settings.groqApiKey != nil {
            return ("groq", selectedModel)
        } else if !settings.geminiApiKey.isEmpty {
            // Default to gemini if key is set
            let defaultGemini = LLMConfig.shared.defaultModel(for: "gemini") ?? ""
            return ("gemini", selectedModel.hasPrefix("gemini") ? selectedModel : defaultGemini)
        }

        // Ultimate fallback - use first configured provider from config
        let defaultGemini = LLMConfig.shared.defaultModel(for: "gemini") ?? ""
        return ("gemini", defaultGemini)
    }

    private func shareTranscript() {
        guard let transcript = memo.currentTranscript else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
        logger.debug("📋 Transcript copied to clipboard")
    }

    private func addToAppleNotes() {
        guard let transcript = memo.currentTranscript else {
            logger.debug("⚠️ No transcript to add to Notes")
            return
        }

        let title = memo.title ?? "Voice Memo"
        let dateStr = formatDate(memoCreatedAt)

        logger.debug("📝 Adding to Apple Notes: \(title)")
        // Format content
        let content = "\(title)\n\(dateStr)\n\n---\n\n\(transcript)"

        // Escape for AppleScript
        let escapedTitle = escapeForAppleScript(title)
        let escapedContent = escapeForAppleScript(content)

        // Create note in "Talkie" folder (creates folder if needed), without bringing Notes to foreground
        let script = """
        tell application "Notes"
            tell account "iCloud"
                if not (exists folder "Talkie") then
                    make new folder with properties {name:"Talkie"}
                end if
                make new note at folder "Talkie" with properties {name:"\(escapedTitle)", body:"\(escapedContent)"}
            end tell
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                logger.debug("❌ AppleScript error: \(errorMessage)")
            } else {
                logger.debug("✅ Note created successfully!")
            }
        }
    }

    private func escapeForAppleScript(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    private func browseWorkflows() {
        showingWorkflowPicker = true
    }

    // MARK: - Quick Action Button Builder

    private func quickActionButton(for item: QuickActionItem) -> ActionButtonMac {
        switch item {
        case .workflow(let workflow):
            // Custom workflow button
            ActionButtonMac(
                icon: workflow.icon,
                title: workflow.name.uppercased(),
                isProcessing: processingWorkflowIDs.contains(workflow.id),
                isCompleted: hasCompletedRun(for: workflow),
                runCount: runCount(for: workflow),
                action: { executeCustomWorkflow(workflow) }
            )

        case .builtIn(let action):
            // Built-in action button
            switch action {
            case .summarize:
                ActionButtonMac(
                    icon: action.icon,
                    title: action.title,
                    isProcessing: memo.isProcessingSummary,
                    isCompleted: memo.summary != nil,
                    runCount: memo.summary != nil ? 1 : 0,
                    action: { executeLegacyAction(.summarize) }
                )
            case .taskify:
                ActionButtonMac(
                    icon: action.icon,
                    title: action.title,
                    isProcessing: memo.isProcessingTasks,
                    isCompleted: memo.tasks != nil,
                    runCount: memo.tasks != nil ? 1 : 0,
                    action: { executeLegacyAction(.extractTasks) }
                )
            case .remind:
                ActionButtonMac(
                    icon: action.icon,
                    title: action.title,
                    isProcessing: memo.isProcessingReminders,
                    isCompleted: memo.reminders != nil,
                    runCount: memo.reminders != nil ? 1 : 0,
                    action: { executeLegacyAction(.reminders) }
                )
            case .toNotes:
                ActionButtonMac(
                    icon: action.icon,
                    title: action.title,
                    isProcessing: false,
                    isCompleted: false,
                    runCount: 0,
                    action: { addToAppleNotes() }
                )
            case .copy:
                ActionButtonMac(
                    icon: action.icon,
                    title: action.title,
                    isProcessing: false,
                    isCompleted: false,
                    runCount: 0,
                    action: { copyTranscript() }
                )
            }
        }
    }

    /// Check if this workflow has been run on this memo
    private func hasCompletedRun(for workflow: WorkflowDefinition) -> Bool {
        cachedWorkflowRuns.contains { $0.workflowId == workflow.id && $0.status == .completed }
    }

    /// Count how many times this workflow has been run (completed) on this memo
    private func runCount(for workflow: WorkflowDefinition) -> Int {
        cachedWorkflowRuns.filter { $0.workflowId == workflow.id && $0.status == .completed }.count
    }

    /// Execute a custom workflow definition
    private func executeCustomWorkflow(_ workflow: WorkflowDefinition) {
        processingWorkflowIDs.insert(workflow.id)

        Task {
            do {
                _ = try await WorkflowExecutor.shared.executeWorkflow(
                    workflow,
                    for: memo
                )
                // Refresh workflow runs after execution
                await fetchWorkflowRuns()
            } catch {
                await SystemEventManager.shared.log(.error, "Workflow failed: \(workflow.name)", detail: error.localizedDescription)
            }

            await MainActor.run {
                processingWorkflowIDs.remove(workflow.id)
            }
        }
    }

    /// Execute a legacy built-in action using GRDB (no CoreData)
    private func executeLegacyAction(_ actionType: WorkflowActionType) {
        guard let transcript = memo.transcription, !transcript.isEmpty else {
            logger.debug("❌ No transcript available for \(actionType.rawValue)")
            return
        }

        Task {
            do {
                let settings = SettingsManager.shared
                let (providerName, modelId) = resolveProviderAndModel(from: settings)

                // Get LLM provider
                guard let provider = LLMProviderRegistry.shared.provider(for: providerName) else {
                    logger.debug("❌ Provider not available: \(providerName)")
                    return
                }

                // Set processing state
                var updatedMemo = memo
                switch actionType {
                case .summarize:
                    updatedMemo.isProcessingSummary = true
                case .extractTasks:
                    updatedMemo.isProcessingTasks = true
                case .reminders:
                    updatedMemo.isProcessingReminders = true
                default:
                    break
                }
                try await repository.saveMemo(updatedMemo)

                // Build prompt and generate
                let prompt = actionType.systemPrompt.replacingOccurrences(of: "{{TRANSCRIPT}}", with: transcript)
                let options = GenerationOptions(temperature: 0.7, topP: 0.9, maxTokens: 1024)
                let output = try await provider.generate(prompt: prompt, model: modelId, options: options)

                // Save result
                switch actionType {
                case .summarize:
                    updatedMemo.summary = output
                    updatedMemo.isProcessingSummary = false
                case .extractTasks:
                    updatedMemo.tasks = output
                    updatedMemo.isProcessingTasks = false
                case .reminders:
                    updatedMemo.reminders = output
                    updatedMemo.isProcessingReminders = false
                default:
                    break
                }
                updatedMemo.lastModified = Date()
                try await repository.saveMemo(updatedMemo)

                logger.debug("✅ \(actionType.rawValue) completed with \(providerName)/\(modelId)")
            } catch {
                // Clear processing state on error
                var updatedMemo = memo
                switch actionType {
                case .summarize:
                    updatedMemo.isProcessingSummary = false
                case .extractTasks:
                    updatedMemo.isProcessingTasks = false
                case .reminders:
                    updatedMemo.isProcessingReminders = false
                default:
                    break
                }
                try? await repository.saveMemo(updatedMemo)
                logger.debug("❌ Action error: \(error.localizedDescription)")
            }
        }
    }

    private func navigateToWorkflow(_ workflowId: UUID?) {
        // TODO: Implement navigation to workflow definition
        // This would require a callback or notification to switch to the Workflows view
        logger.debug("Navigate to workflow: \(workflowId?.uuidString ?? "unknown")")
    }


    private func deleteWorkflowRun(_ run: WorkflowRunModel) {
        Task {
            do {
                let db = try await DatabaseManager.shared.database()
                try await db.write { db in
                    _ = try WorkflowRunModel.deleteOne(db, key: run.id)
                }
                // Refresh the list
                await fetchWorkflowRuns()
            } catch {
                logger.error("Failed to delete workflow run: \(error.localizedDescription)")
            }
        }
    }

    private func taskPriorityIndicator(_ priority: TaskItem.Priority) -> String {
        switch priority {
        case .high: return "!"
        case .medium: return "-"
        case .low: return "·"
        }
    }
}

private struct MemoMetadataView: View {
    let source: MemoSource
    let dateText: String
    let durationText: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if source != .unknown {
                MemoSourceBadge(source: source, showLabel: true, size: .small)
            }

            Text(dateText)
                .font(.techLabelSmall)

            Text("·")
                .font(.techLabelSmall)

            Text(durationText)
                .font(.monoXSmall)
        }
        .foregroundColor(Theme.current.foregroundSecondary)
    }
}

private struct MemoDetailHeaderSection: View {
    let showHeader: Bool
    let memoTitle: String
    let memoSource: MemoSource
    let dateText: String
    let durationText: String
    @Binding var isEditing: Bool
    @Binding var editedTitle: String
    @FocusState.Binding var titleFieldFocused: Bool
    let onToggleEdit: () -> Void

    var body: some View {
        if showHeader {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if isEditing {
                        TextField("Recording title", text: $editedTitle)
                            .font(Theme.current.fontTitleMedium)
                            .textFieldStyle(.plain)
                            .focused($titleFieldFocused)
                    } else {
                        Text(memoTitle)
                            .font(Theme.current.fontTitleMedium)
                            .foregroundColor(Theme.current.foreground)
                    }

                    MemoMetadataView(
                        source: memoSource,
                        dateText: dateText,
                        durationText: durationText
                    )
                }

                Spacer()

                if isEditing {
                    Button(action: onToggleEdit) {
                        Text("Done")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                } else {
                    Button(action: onToggleEdit) {
                        Text("Edit")
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .keyboardShortcut("e", modifiers: .command)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    if isEditing {
                        TextField("Recording title", text: $editedTitle)
                            .font(Theme.current.fontTitleMedium)
                            .textFieldStyle(.plain)
                            .focused($titleFieldFocused)
                    } else {
                        Text(memoTitle)
                            .font(Theme.current.fontTitleMedium)
                            .foregroundColor(Theme.current.foreground)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isEditing {
                        Button(action: onToggleEdit) {
                            Text("Done")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .keyboardShortcut(.return, modifiers: .command)
                    } else {
                        Button(action: onToggleEdit) {
                            Text("Edit")
                                .font(Theme.current.fontSMMedium)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .keyboardShortcut("e", modifiers: .command)
                    }
                }

                MemoMetadataView(
                    source: memoSource,
                    dateText: dateText,
                    durationText: durationText
                )
            }
        }
    }
}

private struct MemoDetailTranscriptSection: View {
    let memo: MemoModel
    let settings: SettingsManager
    @Binding var isEditing: Bool
    @Binding var editedTranscript: String
    let isRetranscribing: Bool
    let onRetranscribe: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            MemoDetailTranscriptHeader()

            MemoDetailTranscriptContent(
                memo: memo,
                settings: settings,
                isEditing: $isEditing,
                editedTranscript: $editedTranscript,
                isRetranscribing: isRetranscribing,
                onRetranscribe: onRetranscribe
            )
        }
    }
}

private struct MemoDetailTranscriptHeader: View {
    var body: some View {
        Text("TRANSCRIPT")
            .font(.techLabel)
            .foregroundColor(Theme.current.foregroundSecondary)
    }
}

private struct MemoDetailTranscriptContent: View {
    let memo: MemoModel
    let settings: SettingsManager
    @Binding var isEditing: Bool
    @Binding var editedTranscript: String
    let isRetranscribing: Bool
    let onRetranscribe: (String) -> Void

    var body: some View {
        if memo.isTranscribing || isRetranscribing {
            MemoDetailTranscriptProgressView(
                settings: settings,
                isRetranscribing: isRetranscribing
            )
        } else if let transcript = memo.currentTranscript {
            MemoDetailTranscriptTextSection(
                memo: memo,
                settings: settings,
                isEditing: $isEditing,
                editedTranscript: $editedTranscript,
                transcript: transcript,
                onRetranscribe: onRetranscribe
            )
        } else {
            MemoDetailTranscriptEmptyState(settings: settings)
        }
    }
}

private struct MemoDetailTranscriptProgressView: View {
    let settings: SettingsManager
    let isRetranscribing: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text(isRetranscribing ? "RETRANSCRIBING..." : "PROCESSING...")
                .font(Theme.current.fontXSBold)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Theme.current.surfaceAlternate)
        .cornerRadius(CornerRadius.xs)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xs)
                .strokeBorder(settings.borderDefault, lineWidth: 0.5)
        )
    }
}

private struct MemoDetailTranscriptTextSection: View {
    let memo: MemoModel
    let settings: SettingsManager
    @Binding var isEditing: Bool
    @Binding var editedTranscript: String
    let transcript: String
    let onRetranscribe: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isEditing {
                MemoDetailTranscriptEditorView(
                    settings: settings,
                    editedTranscript: $editedTranscript
                )
            } else {
                MemoDetailTranscriptDisplayView(
                    memo: memo,
                    settings: settings,
                    transcript: transcript,
                    onRetranscribe: onRetranscribe
                )
            }
        }
    }
}

private struct MemoDetailTranscriptEditorView: View {
    let settings: SettingsManager
    @Binding var editedTranscript: String

    var body: some View {
        TextEditor(text: $editedTranscript)
            .font(settings.contentFontBody)
            .foregroundColor(Theme.current.foreground)
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .padding(Spacing.sm)
            .frame(minHeight: 150)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: CornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .strokeBorder(Color.accentColor.opacity(Opacity.strong), lineWidth: 1)
            )
    }
}

private struct MemoDetailTranscriptDisplayView: View {
    let memo: MemoModel
    let settings: SettingsManager
    let transcript: String
    let onRetranscribe: (String) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(transcript)
                .font(settings.contentFontBody)
                .foregroundColor(Theme.current.foreground)
                .textSelection(.enabled)
                .lineSpacing(4)
                .padding(14)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: CornerRadius.md))
                .contextMenu {
                    MemoDetailTranscriptContextMenu(
                        memo: memo,
                        transcript: transcript,
                        onRetranscribe: onRetranscribe
                    )
                }

            InlineQuickOpenBar(transcript: transcript)
                .padding(Spacing.sm)
        }
    }
}

private struct MemoDetailTranscriptContextMenu: View {
    let memo: MemoModel
    let transcript: String
    let onRetranscribe: (String) -> Void

    var body: some View {
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
        }

        Divider()

        if memo.hasAudio {
            Menu("Retranscribe") {
                Section("Parakeet (Recommended)") {
                    Button("Parakeet v3 (Fast, 25 languages)") {
                        onRetranscribe("parakeet:v3")
                    }
                    Button("Parakeet v2 (English, most accurate)") {
                        onRetranscribe("parakeet:v2")
                    }
                }

                Divider()

                Section("Whisper") {
                    Button("whisper-small (Fast)") {
                        onRetranscribe("whisper:openai_whisper-small")
                    }
                    Button("whisper-large-v3 (Best)") {
                        onRetranscribe("whisper:openai_whisper-large-v3")
                    }
                }
            }
        }
    }
}

private struct MemoDetailTranscriptEmptyState: View {
    let settings: SettingsManager

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "waveform.circle")
                .font(settings.fontDisplay)
                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
            Text("NO TRANSCRIPT AVAILABLE")
                .font(Theme.current.fontSMBold)
                .foregroundColor(Theme.current.foregroundSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private struct MemoDetailTranscribeActionSection: View {
    let isProcessing: Bool
    let isCompleted: Bool
    let onTranscribe: () -> Void

    var body: some View {
        ActionButtonMac(
            icon: "waveform.and.mic",
            title: "TRANSCRIBE",
            isProcessing: isProcessing,
            isCompleted: isCompleted,
            runCount: 0,
            action: onTranscribe
        )
    }
}

private struct MemoDetailQuickActionsSection: View {
    let items: [MemoDetailView.QuickActionItem]
    let onBrowseWorkflows: () -> Void
    let buttonProvider: (MemoDetailView.QuickActionItem) -> ActionButtonMac

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("QUICK ACTIONS")
                .font(.techLabel)
                .foregroundColor(Theme.current.foregroundSecondary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm),
                GridItem(.flexible(), spacing: Spacing.sm)
            ], spacing: Spacing.sm) {
                ForEach(items) { item in
                    buttonProvider(item)
                }
                BrowseWorkflowsButton(action: onBrowseWorkflows)
            }
        }
    }
}

private struct MemoDetailRecentRunsSection: View {
    let runs: [WorkflowRunModel]
    let settings: SettingsManager
    let onSelect: (WorkflowRunModel) -> Void
    let formatTimeAgo: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("RECENT RUNS")
                    .font(.techLabel)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if runs.count > 3 {
                    Text("\(runs.count) runs")
                        .font(.techLabelSmall)
                        .foregroundColor(Theme.current.foregroundSecondary)
                }
            }

            VStack(spacing: Spacing.xs) {
                ForEach(Array(runs.prefix(3)), id: \.id) { run in
                    Button(action: { onSelect(run) }) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: run.workflowIcon ?? "bolt.fill")
                                .font(Theme.current.fontSM)
                                .foregroundColor(.accentColor)
                                .frame(width: 20)

                            Text(run.workflowName)
                                .font(Theme.current.fontBodyMedium)
                                .foregroundColor(Theme.current.foreground)
                                .lineLimit(1)

                            Spacer()

                            if run.status == .completed {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(.green)
                            } else if run.status == .failed {
                                Image(systemName: "xmark.circle.fill")
                                    .font(Theme.current.fontSM)
                                    .foregroundColor(.red)
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                            }

                            RelativeTimeLabel(
                                date: run.runDate,
                                formatter: formatTimeAgo
                            )
                            .font(Theme.current.fontXS)
                            .foregroundColor(Theme.current.foregroundSecondary)

                            Image(systemName: "chevron.right")
                                .font(Theme.current.fontXS)
                                .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
                        }
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.sm)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct MemoDetailNotesSection: View {
    let settings: SettingsManager
    @Binding var editedNotes: String
    let showNotesSaved: Bool
    let onNotesChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("NOTES")
                    .font(.techLabel)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if showNotesSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Theme.current.fontXS)
                        .foregroundColor(Theme.current.foregroundSecondary.opacity(Opacity.half))
                }
            }

            TextEditor(text: $editedNotes)
                .font(settings.contentFontBody)
                .foregroundColor(Theme.current.foreground)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(Spacing.sm)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                .onChange(of: editedNotes) { _, _ in
                    onNotesChange()
                }
        }
    }
}

private struct MemoDetailPlaybackSection: View {
    let settings: SettingsManager
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    let duration: TimeInterval
    let onTogglePlayback: () -> Void
    let onSeek: (Double) -> Void
    var onVolumeChange: ((Float) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("PLAYBACK")
                .font(.techLabel)
                .foregroundColor(Theme.current.foregroundSecondary)

            AudioPlayerCard(
                isPlaying: isPlaying,
                currentTime: currentTime,
                duration: duration,
                onTogglePlayback: onTogglePlayback,
                onSeek: onSeek,
                onVolumeChange: onVolumeChange
            )
        }
    }
}

private struct MemoDetailDangerZoneSection: View {
    let settings: SettingsManager
    let onDelete: () -> Void

    var body: some View {
        Divider()

        HStack(spacing: Spacing.sm) {
            Spacer()

            Button(action: onDelete) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(Theme.current.fontSM)
                    Text("DELETE MEMO")
                        .font(Theme.current.fontSMMedium)
                }
                .foregroundColor(.red.opacity(Opacity.prominent))
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: CornerRadius.sm))
            }
            .buttonStyle(.plain)
        }
    }
}
