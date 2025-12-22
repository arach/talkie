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
struct MemoDetailView: View {
    @ObservedObject var memo: VoiceMemo
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
    @State private var selectedWorkflowRun: WorkflowRun?
    @FocusState private var titleFieldFocused: Bool

    @Environment(\.managedObjectContext) private var viewContext
    private let workflowManager = WorkflowManager.shared
    @State private var processingWorkflowIDs: Set<UUID> = []
    @State private var showingWorkflowPicker = false
    @State private var cachedQuickActionItems: [QuickActionItem] = []
    @State private var cachedWorkflowRuns: [WorkflowRun] = []
    @State private var showingRetranscribeSheet = false
    @State private var isRetranscribing = false

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

    /// Compute sorted workflow runs from memo (deduplicated by ID to handle CloudKit sync duplicates)
    private func computeSortedWorkflowRuns() -> [WorkflowRun] {
        guard let runs = memo.workflowRuns as? Set<WorkflowRun> else { return [] }
        // Deduplicate by ID, keeping the most recent one
        var uniqueRuns: [UUID: WorkflowRun] = [:]
        for run in runs {
            guard let id = run.id else { continue }
            if let existing = uniqueRuns[id] {
                if (run.runDate ?? .distantPast) > (existing.runDate ?? .distantPast) {
                    uniqueRuns[id] = run
                }
            } else {
                uniqueRuns[id] = run
            }
        }
        return uniqueRuns.values.sorted { ($0.runDate ?? Date.distantPast) > ($1.runDate ?? Date.distantPast) }
    }

    /// Refresh cached data (called on appear and memo change)
    private func refreshCachedData() {
        cachedQuickActionItems = computeQuickActionItems()
        cachedWorkflowRuns = computeSortedWorkflowRuns()
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
                    memoSource: memo.source,
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
                        onSelect: { selectedWorkflowRun = $0 },
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
        .onChange(of: memo.workflowRuns?.count) { _, _ in
            // Refresh workflow runs when they change
            cachedWorkflowRuns = computeSortedWorkflowRuns()
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
        guard let context = memo.managedObjectContext else { return }

        // Save title if changed
        if editedTitle != memoTitle {
            memo.title = editedTitle
        }

        // Save transcript if changed (creates new version)
        if let currentTranscript = memo.currentTranscript,
           editedTranscript != currentTranscript,
           !editedTranscript.isEmpty {
            memo.addUserTranscript(content: editedTranscript)
        }

        // Save notes
        memo.notes = editedNotes

        try? context.save()
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
        guard let context = memo.managedObjectContext else { return }
        context.perform {
            memo.notes = editedNotes
            try? context.save()

            // Show checkmark briefly
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showNotesSaved = true
                }

                // Hide after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showNotesSaved = false
                    }
                }
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
                guard let audioData = memo.audioData else {
                    logger.debug("[Transcribe] No audio data available")
                    return
                }

                // Set transcribing state
                await MainActor.run {
                    memo.isTranscribing = true
                    try? viewContext.save()
                }

                // Transcribe using WhisperKit (using small model as default)
                let transcript = try await WhisperService.shared.transcribe(
                    audioData: audioData,
                    model: .small
                )

                // Save the transcript
                await MainActor.run {
                    memo.addSystemTranscript(
                        content: transcript,
                        fromMacOS: true,
                        engine: TranscriptEngines.whisperKit
                    )
                    memo.isTranscribing = false
                    try? viewContext.save()
                    // Force SwiftUI to pick up Core Data relationship changes
                    viewContext.refresh(memo, mergeChanges: true)
                }
            } catch {
                await MainActor.run {
                    memo.isTranscribing = false
                    try? viewContext.save()
                }
            }
        }
        #endif
    }

    private func deleteMemo() {
        guard let context = memo.managedObjectContext else { return }
        context.perform {
            context.delete(memo)
            try? context.save()
        }
    }

    private func retranscribe(with modelId: String) {
        guard let audioData = memo.audioData else {
            logger.error("Cannot retranscribe: no audio data")
            return
        }

        isRetranscribing = true

        Task {
            do {
                let engineClient = EngineClient.shared
                let transcript = try await engineClient.transcribe(audioData: audioData, modelId: modelId)

                // Save new transcript
                await MainActor.run {
                    if let context = memo.managedObjectContext {
                        context.perform {
                            self.memo.transcription = transcript
                            self.memo.lastModified = Date()
                            try? context.save()
                        }
                    }
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
        guard let runs = memo.workflowRuns as? Set<WorkflowRun> else { return false }
        return runs.contains { $0.workflowId == workflow.id && $0.status == "completed" }
    }

    /// Count how many times this workflow has been run (completed) on this memo
    private func runCount(for workflow: WorkflowDefinition) -> Int {
        guard let runs = memo.workflowRuns as? Set<WorkflowRun> else { return 0 }
        return runs.filter { $0.workflowId == workflow.id && $0.status == "completed" }.count
    }

    /// Execute a custom workflow definition
    private func executeCustomWorkflow(_ workflow: WorkflowDefinition) {
        processingWorkflowIDs.insert(workflow.id)

        Task {
            do {
                _ = try await WorkflowExecutor.shared.executeWorkflow(
                    workflow,
                    for: memo,
                    context: viewContext
                )
            } catch {
                await SystemEventManager.shared.log(.error, "Workflow failed: \(workflow.name)", detail: error.localizedDescription)
            }

            _ = await MainActor.run {
                processingWorkflowIDs.remove(workflow.id)
            }
        }
    }

    /// Execute a legacy built-in action
    private func executeLegacyAction(_ actionType: WorkflowActionType) {
        Task {
            do {
                let settings = SettingsManager.shared
                let (providerName, modelId) = resolveProviderAndModel(from: settings)

                try await WorkflowExecutor.shared.execute(
                    action: actionType,
                    for: memo,
                    providerName: providerName,
                    modelId: modelId,
                    context: viewContext
                )
                logger.debug("✅ \(actionType.rawValue) completed with \(providerName)/\(modelId)")
            } catch {
                logger.debug("❌ Action error: \(error.localizedDescription)")
            }
        }
    }

    private func navigateToWorkflow(_ workflowId: UUID?) {
        // TODO: Implement navigation to workflow definition
        // This would require a callback or notification to switch to the Workflows view
        logger.debug("Navigate to workflow: \(workflowId?.uuidString ?? "unknown")")
    }


    private func deleteWorkflowRun(_ run: WorkflowRun) {
        guard let context = memo.managedObjectContext else { return }
        context.perform {
            context.delete(run)
            try? context.save()
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
        .foregroundColor(.secondary)
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
                VStack(alignment: .leading, spacing: 6) {
                    if isEditing {
                        TextField("Recording title", text: $editedTitle)
                            .font(Theme.current.fontTitleMedium)
                            .textFieldStyle(.plain)
                            .focused($titleFieldFocused)
                    } else {
                        Text(memoTitle)
                            .font(Theme.current.fontTitleMedium)
                            .foregroundColor(.primary)
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
                            .foregroundColor(.primary)
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
    @ObservedObject var memo: VoiceMemo
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
            .foregroundColor(.secondary)
    }
}

private struct MemoDetailTranscriptContent: View {
    @ObservedObject var memo: VoiceMemo
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
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(isRetranscribing ? "RETRANSCRIBING..." : "PROCESSING...")
                .font(Theme.current.fontXSBold)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Theme.current.surfaceAlternate)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(settings.borderDefault, lineWidth: 0.5)
        )
    }
}

private struct MemoDetailTranscriptTextSection: View {
    @ObservedObject var memo: VoiceMemo
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
            .foregroundColor(.primary)
            .lineSpacing(4)
            .scrollContentBackground(.hidden)
            .padding(12)
            .frame(minHeight: 150)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
            )
    }
}

private struct MemoDetailTranscriptDisplayView: View {
    @ObservedObject var memo: VoiceMemo
    let settings: SettingsManager
    let transcript: String
    let onRetranscribe: (String) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(transcript)
                .font(settings.contentFontBody)
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .padding(14)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .contextMenu {
                    MemoDetailTranscriptContextMenu(
                        memo: memo,
                        transcript: transcript,
                        onRetranscribe: onRetranscribe
                    )
                }

            InlineQuickOpenBar(transcript: transcript)
                .padding(8)
        }
    }
}

private struct MemoDetailTranscriptContextMenu: View {
    @ObservedObject var memo: VoiceMemo
    let transcript: String
    let onRetranscribe: (String) -> Void

    var body: some View {
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
        }

        Divider()

        if memo.audioData != nil {
            Menu("Retranscribe") {
                Button("whisper-small (Fast)") {
                    onRetranscribe("whisper:openai_whisper-small")
                }
                Button("whisper-medium") {
                    onRetranscribe("whisper:openai_whisper-medium")
                }
                Button("whisper-large-v3 (Best)") {
                    onRetranscribe("whisper:openai_whisper-large-v3")
                }
            }
        }

        if memo.sortedTranscriptVersions.count > 1 {
            Divider()
            Button("Version History (\(memo.sortedTranscriptVersions.count))") {
                // TODO: Show version history sheet
            }
        }
    }
}

private struct MemoDetailTranscriptEmptyState: View {
    let settings: SettingsManager

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.circle")
                .font(settings.fontDisplay)
                .foregroundColor(.secondary.opacity(0.5))
            Text("NO TRANSCRIPT AVAILABLE")
                .font(Theme.current.fontSMBold)
                .foregroundColor(.secondary)
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
                .foregroundColor(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(items) { item in
                    buttonProvider(item)
                }
                BrowseWorkflowsButton(action: onBrowseWorkflows)
            }
        }
    }
}

private struct MemoDetailRecentRunsSection: View {
    let runs: [WorkflowRun]
    let settings: SettingsManager
    let onSelect: (WorkflowRun) -> Void
    let formatTimeAgo: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("RECENT RUNS")
                    .font(.techLabel)
                    .foregroundColor(.secondary)

                Spacer()

                if runs.count > 3 {
                    Text("\(runs.count) runs")
                        .font(.techLabelSmall)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 6) {
                ForEach(Array(runs.prefix(3)), id: \.id) { run in
                    Button(action: { onSelect(run) }) {
                        HStack(spacing: 8) {
                            Image(systemName: run.workflowIcon ?? "bolt.fill")
                                .font(settings.fontSM)
                                .foregroundColor(.accentColor)
                                .frame(width: 20)

                            Text(run.workflowName ?? "Workflow")
                                .font(Theme.current.fontBodyMedium)
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()

                            if run.status == "completed" {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(settings.fontSM)
                                    .foregroundColor(.green)
                            } else if run.status == "failed" {
                                Image(systemName: "xmark.circle.fill")
                                    .font(settings.fontSM)
                                    .foregroundColor(.red)
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                            }

                            RelativeTimeLabel(
                                date: run.runDate ?? Date(),
                                formatter: formatTimeAgo
                            )
                            .font(settings.fontXS)
                            .foregroundColor(.secondary)

                            Image(systemName: "chevron.right")
                                .font(settings.fontXS)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
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
                    .foregroundColor(.secondary)

                Spacer()

                if showNotesSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(settings.fontXS)
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }

            TextEditor(text: $editedNotes)
                .font(settings.contentFontBody)
                .foregroundColor(.primary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
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
                .foregroundColor(.secondary)

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

        HStack(spacing: 8) {
            Spacer()

            Button(action: onDelete) {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(settings.fontSM)
                    Text("DELETE MEMO")
                        .font(Theme.current.fontSMMedium)
                }
                .foregroundColor(.red.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }
}
