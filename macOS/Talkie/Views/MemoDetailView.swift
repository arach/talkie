//
//  MemoDetailView.swift
//  Talkie macOS
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import AVFoundation
import AppKit

struct MemoDetailView: View {
    @ObservedObject var memo: VoiceMemo
    @ObservedObject private var settings = SettingsManager.shared
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
    @StateObject private var workflowManager = WorkflowManager.shared
    @State private var processingWorkflowIDs: Set<UUID> = []
    @State private var showingWorkflowPicker = false

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
    private var quickActionItems: [QuickActionItem] {
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

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Header with title and edit toggle (optional)
                if showHeader {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            if isEditing {
                                TextField("Recording title", text: $editedTitle)
                                    .font(settings.fontTitleMedium)
                                    .textFieldStyle(.plain)
                                    .focused($titleFieldFocused)
                            } else {
                                Text(memoTitle)
                                    .font(settings.fontTitleMedium)
                                    .foregroundColor(.primary)
                            }

                            HStack(spacing: Spacing.xs) {
                                Text(formatDate(memoCreatedAt).uppercased())
                                    .font(.techLabelSmall)
                                    .tracking(Tracking.normal)

                                Text("·")
                                    .font(.techLabelSmall)

                                Text(formatDuration(memo.duration))
                                    .font(.monoXSmall)
                            }
                            .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Edit/Done button
                        if isEditing {
                            Button(action: toggleEditMode) {
                                Text("Done")
                            }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.return, modifiers: .command)
                        } else {
                            Button(action: toggleEditMode) {
                                Text("Edit")
                            }
                            .buttonStyle(.bordered)
                            .tint(.accentColor)
                            .keyboardShortcut("e", modifiers: .command)
                        }
                    }
                } else {
                    // Compact header when embedded in inspector
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        // Title row
                        HStack {
                            if isEditing {
                                TextField("Recording title", text: $editedTitle)
                                    .font(settings.fontTitleMedium)
                                    .textFieldStyle(.plain)
                                    .focused($titleFieldFocused)
                            } else {
                                Text(memoTitle)
                                    .font(settings.fontTitleMedium)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Edit/Done button
                            if isEditing {
                                Button(action: toggleEditMode) {
                                    Text("Done")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .keyboardShortcut(.return, modifiers: .command)
                            } else {
                                Button(action: toggleEditMode) {
                                    Text("Edit")
                                        .font(settings.fontSMMedium)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .keyboardShortcut("e", modifiers: .command)
                            }
                        }

                        // Date and duration
                        HStack(spacing: Spacing.xs) {
                            Text(formatDate(memoCreatedAt).uppercased())
                                .font(.techLabelSmall)
                                .tracking(Tracking.normal)
                            Text("·")
                                .font(.techLabelSmall)
                            Text(formatDuration(memo.duration))
                                .font(.monoXSmall)
                        }
                        .foregroundColor(.secondary)
                    }
                }

                // Playback controls with waveform
                VStack(spacing: Spacing.xs) {
                    // Waveform visualization (full width, with background)
                    WaveformView(
                        progress: memo.duration > 0 ? currentTime / memo.duration : 0,
                        isPlaying: isPlaying
                    )
                    .frame(height: 40)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(settings.surfaceAlternate)
                    .overlay(
                        Rectangle()
                            .strokeBorder(settings.borderDefault, lineWidth: 0.5)
                    )

                    // Controls: start time, play button, end time - aligned with waveform edges
                    HStack(alignment: .center, spacing: 0) {
                        Text(formatDuration(currentTime))
                            .font(.monoXSmall)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: togglePlayback) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(settings.fontTitle)
                                .foregroundColor(.primary)
                                .offset(x: isPlaying ? 0 : 1) // Optical centering for play triangle
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)

                        Text(formatDuration(memo.duration))
                            .font(.monoXSmall)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                // Transcript Section
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("TRANSCRIPT")
                        .font(.techLabel)
                        .tracking(Tracking.wide)
                        .foregroundColor(.secondary)

                    transcriptView
                }

                // AI Results Section (only show if there are results)
                if !sortedWorkflowRuns.isEmpty || memo.summary != nil || memo.tasks != nil {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("AI RESULTS")
                            .font(.techLabel)
                            .tracking(Tracking.wide)
                            .foregroundColor(.secondary)

                        aiResultsView
                    }
                }

                // Transcribe Action (only if no transcript yet)
                #if arch(arm64)
                if (memo.currentTranscript == nil || memo.currentTranscript?.isEmpty == true) && memo.audioData != nil {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("ACTIONS")
                            .font(.techLabel)
                            .tracking(Tracking.wide)
                            .foregroundColor(.secondary)

                        ActionButtonMac(
                            icon: "waveform.and.mic",
                            title: "TRANSCRIBE",
                            isProcessing: memo.isTranscribing,
                            isCompleted: memo.currentTranscript != nil,
                            runCount: 0,
                            action: { executeTranscribeAction() }
                        )
                    }
                }
                #endif

                // Quick Actions (3x2 grid)
                if memo.currentTranscript != nil && !memo.isTranscribing {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("QUICK ACTIONS")
                            .font(.techLabel)
                            .tracking(Tracking.wide)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            // Dynamic quick action items (pinned + defaults)
                            ForEach(quickActionItems) { item in
                                quickActionButton(for: item)
                            }

                            // 6th slot is always "MORE"
                            BrowseWorkflowsButton(action: { browseWorkflows() })
                        }
                    }
                }

                // Notes Section (moved below quick actions)
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack {
                        Text("NOTES")
                            .font(.techLabel)
                            .tracking(Tracking.wide)
                            .foregroundColor(.secondary)

                        Spacer()

                        if showNotesSaved {
                            Image(systemName: "checkmark.circle.fill")
                                .font(settings.fontXS)
                                .foregroundColor(.secondary.opacity(0.5))
                                .transition(.opacity)
                        }
                    }

                    TextEditor(text: $editedNotes)
                        .font(settings.contentFontBody)
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .onChange(of: editedNotes) { _, _ in
                            debouncedSaveNotes()
                        }
                }

                // Recent Workflow Runs
                if !sortedWorkflowRuns.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack {
                            Text("RECENT RUNS")
                                .font(.techLabel)
                                .tracking(Tracking.wide)
                                .foregroundColor(.secondary)

                            Spacer()

                            if sortedWorkflowRuns.count > 3 {
                                Text("\(sortedWorkflowRuns.count) runs")
                                    .font(.techLabelSmall)
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(spacing: 6) {
                            ForEach(Array(sortedWorkflowRuns.prefix(3)), id: \.id) { run in
                                Button(action: {
                                    selectedWorkflowRun = run
                                }) {
                                    HStack(spacing: 8) {
                                        // Workflow icon
                                        Image(systemName: run.workflowIcon ?? "bolt.fill")
                                            .font(settings.fontSM)
                                            .foregroundColor(.accentColor)
                                            .frame(width: 20)

                                        // Workflow name
                                        Text(run.workflowName ?? "Workflow")
                                            .font(settings.fontBodyMedium)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        // Status indicator
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
                                                .scaleEffect(0.5)
                                                .frame(width: 12, height: 12)
                                        }

                                        // Time ago
                                        Text(formatTimeAgo(run.runDate))
                                            .font(settings.fontXS)
                                            .foregroundColor(.secondary)

                                        Image(systemName: "chevron.right")
                                            .font(settings.fontXS)
                                            .foregroundColor(.secondary.opacity(0.5))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Walkie Conversation (AI responses and user replies)
                if let memoId = memo.id?.uuidString {
                    WalkieConversationView(memoId: memoId)
                }

                // Danger Zone
                Divider()

                HStack(spacing: 8) {
                    Spacer()

                    // Delete memo
                    Button(action: deleteMemo) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(settings.fontSM)
                            Text("DELETE MEMO")
                                .font(settings.fontSMMedium)
                        }
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsManager.shared.tacticalBackground)
        .onAppear {
            editedTitle = memoTitle
            editedNotes = memo.notes ?? ""
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
            // Re-enable after memo change settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                notesInitialized = true
            }
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
                print("⚠️ No audio data available (not yet synced from iOS)")
                return
            }

            do {
                audioPlayer = try AVAudioPlayer(data: audioData)
                audioPlayer?.prepareToPlay()
                duration = audioPlayer?.duration ?? 0
                audioPlayer?.play()
                startPlaybackTimer()
                isPlaying = true
                print("✅ Playing synced audio: \(audioData.count) bytes, duration: \(duration)s")
            } catch {
                print("❌ Failed to play audio: \(error)")
            }
        }
    }

    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
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

    private func formatTimeAgo(_ date: Date?) -> String {
        guard let date = date else { return "" }
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
                    print("[Transcribe] No audio data available")
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
        print("📋 Transcript copied to clipboard")
    }

    private func addToAppleNotes() {
        guard let transcript = memo.currentTranscript else {
            print("⚠️ No transcript to add to Notes")
            return
        }

        let title = memo.title ?? "Voice Memo"
        let dateStr = formatDate(memoCreatedAt)

        print("📝 Adding to Apple Notes: \(title)")

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
                print("❌ AppleScript error: \(errorMessage)")
            } else {
                print("✅ Note created successfully!")
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

    @ViewBuilder
    private func quickActionButton(for item: QuickActionItem) -> some View {
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
                print("✅ \(actionType.rawValue) completed with \(providerName)/\(modelId)")
            } catch {
                print("❌ Action error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Tab Views

    @ViewBuilder
    private var transcriptView: some View {
        if memo.isTranscribing {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("PROCESSING...")
                    .font(settings.fontXSBold)
                    .tracking(1)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(settings.surfaceAlternate)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(settings.borderDefault, lineWidth: 0.5)
            )
        } else if let transcript = memo.currentTranscript {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if isEditing {
                    // Edit mode: TextEditor
                    TextEditor(text: $editedTranscript)
                        .font(settings.contentFontBody)
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 150)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                        )
                } else {
                    // Read mode
                    Text(transcript)
                        .font(settings.contentFontBody)
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .lineSpacing(4)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .contextMenu {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(transcript, forType: .string)
                            }
                            if memo.sortedTranscriptVersions.count > 1 {
                                Divider()
                                Button("Version History (\(memo.sortedTranscriptVersions.count))") {
                                    // TODO: Show version history sheet
                                }
                            }
                        }
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle")
                    .font(settings.fontDisplay)
                    .foregroundColor(.secondary.opacity(0.5))
                Text("NO TRANSCRIPT AVAILABLE")
                    .font(settings.fontSMBold)
                    .tracking(1)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }

    @ViewBuilder
    private var aiResultsView: some View {
        let workflowRuns = sortedWorkflowRuns
        let hasLegacyResults = memo.summary != nil || memo.tasks != nil || memo.reminders != nil

        if !workflowRuns.isEmpty || hasLegacyResults {
            if let selectedRun = selectedWorkflowRun {
                // Detail view for selected run
                WorkflowRunDetailView(
                    run: selectedRun,
                    onBack: { selectedWorkflowRun = nil },
                    onNavigateToWorkflow: { navigateToWorkflow(selectedRun.workflowId) },
                    onDelete: {
                        deleteWorkflowRun(selectedRun)
                        selectedWorkflowRun = nil
                    }
                )
            } else {
                // List of workflow runs
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(workflowRuns, id: \.id) { run in
                        WorkflowRunListItem(
                            run: run,
                            onSelect: { selectedWorkflowRun = run },
                            onNavigateToWorkflow: { navigateToWorkflow(run.workflowId) }
                        )
                    }

                    // Legacy results (for backward compatibility)
                    if hasLegacyResults && workflowRuns.isEmpty {
                        if let summary = memo.summary {
                            AIResultSection(title: "Summary", icon: "list.bullet.clipboard") {
                                Text(summary)
                                    .font(settings.contentFontBody)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                        }

                        if let tasksJSON = memo.tasks,
                           let data = tasksJSON.data(using: .utf8),
                           let tasks = try? JSONDecoder().decode([TaskItem].self, from: data) {
                            AIResultSection(title: "Tasks", icon: "checkmark.square") {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(tasks) { task in
                                        HStack(spacing: 8) {
                                            Text(taskPriorityIndicator(task.priority))
                                                .font(settings.fontXSBold)
                                                .foregroundColor(.secondary)
                                            Text(task.title)
                                                .font(settings.contentFontBody)
                                        }
                                    }
                                }
                            }
                        }

                        if let remindersJSON = memo.reminders {
                            AIResultSection(title: "Reminders", icon: "bell") {
                                Text(remindersJSON)
                                    .font(settings.contentFontBody)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "wand.and.rays")
                    .font(settings.fontHeadline)
                    .foregroundColor(.secondary.opacity(0.3))
                Text("NO RESULTS")
                    .font(settings.fontSMBold)
                    .tracking(1)
                    .foregroundColor(.secondary)
                Text("Run workflows to generate AI results")
                    .font(settings.fontSM)
                    .foregroundColor(.secondary.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }

    private func navigateToWorkflow(_ workflowId: UUID?) {
        // TODO: Implement navigation to workflow definition
        // This would require a callback or notification to switch to the Workflows view
        print("Navigate to workflow: \(workflowId?.uuidString ?? "unknown")")
    }

    private var sortedWorkflowRuns: [WorkflowRun] {
        guard let runs = memo.workflowRuns as? Set<WorkflowRun> else { return [] }
        return runs.sorted { ($0.runDate ?? Date.distantPast) > ($1.runDate ?? Date.distantPast) }
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

struct AIResultSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.techLabel)
                Text(title.uppercased())
                    .font(.techLabel)
                    .tracking(Tracking.wide)
            }
            .foregroundColor(.secondary)

            content()
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsManager.shared.surface1)
                .cornerRadius(CornerRadius.xs)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.xs)
                        .strokeBorder(SettingsManager.shared.borderDefault, lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Action Button for macOS
struct ActionButtonMac: View {
    let icon: String
    let title: String
    let isProcessing: Bool
    let isCompleted: Bool
    var runCount: Int = 0  // Number of times this action has been run
    let action: () -> Void

    @State private var triggered = false

    var body: some View {
        Button(action: triggerAction) {
            VStack(spacing: 6) {
                ZStack {
                    // Main icon
                    Image(systemName: icon)
                        .font(SettingsManager.shared.fontTitle)
                        .foregroundColor(triggered ? .accentColor : .secondary)
                        .frame(width: 20, height: 20)
                        .scaleEffect(triggered ? 1.2 : 1.0)

                    // Triggered flash overlay
                    if triggered {
                        Circle()
                            .fill(Color.accentColor.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .scaleEffect(triggered ? 1.5 : 0.5)
                            .opacity(triggered ? 0 : 1)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: triggered)

                Text(title)
                    .font(SettingsManager.shared.fontXSMedium)
                    .foregroundColor(triggered ? .accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            // Run count badge
            if runCount > 0 {
                Text("\(runCount)")
                    .font(.techLabelSmall)
                    .foregroundColor(.primary.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(SettingsManager.shared.surfaceSelected)
                    .clipShape(Capsule())
                    .offset(x: -4, y: 4)
            }
        }
    }

    private func triggerAction() {
        // Visual feedback
        withAnimation(.easeOut(duration: 0.15)) {
            triggered = true
        }

        // Reset after brief moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.2)) {
                triggered = false
            }
        }

        // Fire the action (async, non-blocking)
        action()
    }
}

// MARK: - Workflow Run List Item (compact row for selection)
struct WorkflowRunListItem: View {
    let run: WorkflowRun
    let onSelect: () -> Void
    let onNavigateToWorkflow: () -> Void

    @State private var isHovering = false

    private var runDate: Date { run.runDate ?? Date() }
    private var workflowName: String { run.workflowName ?? "Workflow" }
    private var workflowIcon: String { run.workflowIcon ?? "wand.and.stars" }
    private var modelInfo: String? { run.modelId }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                // Icon
                Image(systemName: workflowIcon)
                    .font(SettingsManager.shared.fontBody)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(SettingsManager.shared.surfaceAlternate)
                    .cornerRadius(4)

                // Workflow name (clickable to navigate)
                Button(action: onNavigateToWorkflow) {
                    Text(workflowName)
                        .font(SettingsManager.shared.fontBodyMedium)
                        .foregroundColor(.primary)
                        .underline(isHovering)
                }
                .buttonStyle(.plain)

                // Model badge
                if let model = modelInfo {
                    Text(model)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(3)
                }

                Spacer()

                // Timestamp
                Text(formatRunDate(runDate))
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary.opacity(0.6))

                // Chevron
                Image(systemName: "chevron.right")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovering ? SettingsManager.shared.surfaceHover : SettingsManager.shared.surface1)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(SettingsManager.shared.borderDefault, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private func formatRunDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Workflow Run Detail View (full execution details)
struct WorkflowRunDetailView: View {
    let run: WorkflowRun
    let onBack: () -> Void
    let onNavigateToWorkflow: () -> Void
    let onDelete: () -> Void

    private var runDate: Date { run.runDate ?? Date() }
    private var workflowName: String { run.workflowName ?? "Workflow" }
    private var workflowIcon: String { run.workflowIcon ?? "wand.and.stars" }
    private var providerName: String? { run.providerName }
    private var modelId: String? { run.modelId }

    private var stepExecutions: [WorkflowExecutor.StepExecution] {
        guard let json = run.stepOutputsJSON,
              let data = json.data(using: .utf8),
              let steps = try? JSONDecoder().decode([WorkflowExecutor.StepExecution].self, from: data)
        else { return [] }
        return steps
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Image(systemName: workflowIcon)
                    .font(SettingsManager.shared.fontBody)
                    .foregroundColor(.secondary)

                Button(action: onNavigateToWorkflow) {
                    Text(workflowName)
                        .font(SettingsManager.shared.fontBodyMedium)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                if let model = modelId {
                    Text(model)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(3)
                }

                Spacer()

                Text(formatFullDate(runDate))
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary.opacity(0.6))

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(SettingsManager.shared.surface1)

            Divider()
                .opacity(0.5)

            // Step-by-step execution
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if stepExecutions.isEmpty {
                        // Fallback to simple output if no step data
                        if let output = run.output, !output.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("OUTPUT")
                                    .font(SettingsManager.shared.fontSMBold)
                                    .tracking(1)
                                    .foregroundColor(.secondary)

                                Text(output)
                                    .font(SettingsManager.shared.contentFontBody)
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .lineSpacing(3)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(SettingsManager.shared.surface1)
                                    .cornerRadius(6)
                            }
                        }
                    } else {
                        ForEach(Array(stepExecutions.enumerated()), id: \.offset) { index, step in
                            StepExecutionCard(step: step, isLast: index == stepExecutions.count - 1)

                            if index < stepExecutions.count - 1 {
                                // Connector between steps
                                HStack {
                                    Spacer()
                                        .frame(width: 14)
                                    VStack(spacing: 2) {
                                        ForEach(0..<3, id: \.self) { _ in
                                            Circle()
                                                .fill(SettingsManager.shared.surfaceAlternate)
                                                .frame(width: 3, height: 3)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(SettingsManager.shared.surfaceInput)
    }

    private func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Step Execution Card
struct StepExecutionCard: View {
    let step: WorkflowExecutor.StepExecution
    let isLast: Bool

    @State private var showInput = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Step header
            HStack(spacing: 8) {
                Text("\(step.stepNumber)")
                    .font(SettingsManager.shared.fontSMBold)
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue)
                    .cornerRadius(4)

                Image(systemName: step.stepIcon)
                    .font(SettingsManager.shared.fontBody)
                    .foregroundColor(.secondary)

                Text(step.stepType.uppercased())
                    .font(SettingsManager.shared.fontSMBold)
                    .tracking(0.5)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { withAnimation { showInput.toggle() } }) {
                    Text(showInput ? "HIDE INPUT" : "SHOW INPUT")
                        .font(SettingsManager.shared.fontXSMedium)
                        .tracking(0.3)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }

            // Input (collapsible)
            if showInput {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INPUT")
                        .font(SettingsManager.shared.fontXSBold)
                        .tracking(0.5)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(step.input)
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .lineLimit(10)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(4)
                }
            }

            // Output
            OutputCard(step.output, label: "output → {{\(step.outputKey)}}", isHighlighted: isLast)
        }
        .padding(12)
        .background(SettingsManager.shared.surface2)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(SettingsManager.shared.borderDefault, lineWidth: 0.5)
        )
    }
}

// MARK: - Browse Workflows Button (special CTA style)
struct BrowseWorkflowsButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(SettingsManager.shared.fontTitle)
                    .foregroundColor(.accentColor)

                Text("MORE")
                    .font(SettingsManager.shared.fontXSMedium)
                    .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(isHovering ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Browse all workflows")
    }
}

// MARK: - Waveform View
struct WaveformView: View {
    let progress: Double
    let isPlaying: Bool

    // Generate pseudo-random but consistent waveform bars
    private let barCount = 60

    private func barHeight(at index: Int) -> CGFloat {
        // Use sine waves with different frequencies to create natural-looking waveform
        let x = Double(index) / Double(barCount)
        let h1 = sin(x * .pi * 3) * 0.3
        let h2 = sin(x * .pi * 7 + 1) * 0.2
        let h3 = sin(x * .pi * 13 + 2) * 0.15
        let h4 = cos(x * .pi * 5) * 0.2
        let base = 0.3 + abs(h1 + h2 + h3 + h4)
        return CGFloat(min(1.0, max(0.15, base)))
    }

    var body: some View {
        GeometryReader { geometry in
            let barWidth = (geometry.size.width - CGFloat(barCount - 1) * 2) / CGFloat(barCount)

            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let barProgress = Double(index) / Double(barCount)
                    let isPast = barProgress < progress

                    Rectangle()
                        .fill(isPast ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: max(1, barWidth), height: geometry.size.height * barHeight(at: index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

// MARK: - Output Card (clean card with copy button)
struct OutputCard: View {
    let content: String
    let label: String?
    var isHighlighted: Bool = false

    @State private var copied = false
    @State private var isExpanded = false

    private var isLong: Bool { content.count > 300 }
    private var displayContent: String {
        if isLong && !isExpanded {
            return String(content.prefix(280)) + "..."
        }
        return content
    }

    init(_ content: String, label: String? = nil, isHighlighted: Bool = false) {
        self.content = content
        self.label = label
        self.isHighlighted = isHighlighted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header with label and copy button
            if label != nil || true {
                HStack {
                    if let label = label {
                        Text(label.uppercased())
                            .font(.techLabelSmall)
                            .tracking(Tracking.normal)
                            .foregroundColor(.secondary.opacity(0.6))
                    }

                    Spacer()

                    Button(action: copyToClipboard) {
                        HStack(spacing: 4) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(SettingsManager.shared.fontXSMedium)
                                .foregroundColor(copied ? .green : .secondary.opacity(0.5))
                            if copied {
                                Text("COPIED")
                                    .font(.techLabelSmall)
                                    .tracking(Tracking.tight)
                            }
                        }
                        .foregroundColor(copied ? .green : .secondary.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(copied ? SettingsManager.shared.surfaceSuccess : SettingsManager.shared.surfaceAlternate)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Content
            Text(displayContent)
                .font(.bodySmall)
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Expand button for long content
            if isLong {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "SHOW LESS" : "SHOW MORE")
                            .font(.techLabelSmall)
                            .tracking(Tracking.normal)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(SettingsManager.shared.fontXSBold)
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(SettingsManager.shared.surface1)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(isHighlighted ? SettingsManager.shared.surfaceSuccess : SettingsManager.shared.borderDefault, lineWidth: isHighlighted ? 1 : 0.5)
        )
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)

        withAnimation(.easeInOut(duration: 0.15)) {
            copied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.2)) {
                copied = false
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let browseWorkflows = Notification.Name("browseWorkflows")
}

// MARK: - Workflow Picker Sheet

struct WorkflowPickerSheet: View {
    let memo: VoiceMemo
    let onSelect: (WorkflowDefinition) -> Void
    let onCancel: () -> Void

    @StateObject private var workflowManager = WorkflowManager.shared
    @State private var selectedWorkflow: WorkflowDefinition?
    @State private var searchText = ""

    /// Workflows available to run (exclude system workflows like Hey Talkie)
    private var availableWorkflows: [WorkflowDefinition] {
        workflowManager.workflows.filter { workflow in
            workflow.id != WorkflowDefinition.heyTalkieWorkflowId &&
            workflow.isEnabled
        }
    }

    private var filteredWorkflows: [WorkflowDefinition] {
        if searchText.isEmpty {
            return availableWorkflows
        }
        let query = searchText.lowercased()
        return availableWorkflows.filter {
            $0.name.lowercased().contains(query) ||
            $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run Workflow")
                        .font(SettingsManager.shared.fontTitleBold)
                    Text(memo.title ?? "Untitled Memo")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(SettingsManager.shared.fontHeadline)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(SettingsManager.shared.fontSM)
                    .foregroundColor(.secondary)

                TextField("Search workflows...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(SettingsManager.shared.fontBody)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(SettingsManager.shared.fontSM)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(SettingsManager.shared.surface1)
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if availableWorkflows.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "flowchart")
                        .font(SettingsManager.shared.fontDisplay)
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No Workflows")
                        .font(SettingsManager.shared.fontBodyMedium)
                        .foregroundColor(.secondary)

                    Text("Create a workflow in Settings → Workflows")
                        .font(SettingsManager.shared.fontSM)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredWorkflows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(SettingsManager.shared.fontTitle)
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("No matching workflows")
                        .font(SettingsManager.shared.fontBody)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedWorkflow) {
                    ForEach(filteredWorkflows) { workflow in
                        WorkflowPickerRow(workflow: workflow, isSelected: selectedWorkflow?.id == workflow.id)
                            .tag(workflow)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                onSelect(workflow)
                            }
                            .onTapGesture(count: 1) {
                                selectedWorkflow = workflow
                            }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Footer
            HStack {
                Text("\(filteredWorkflows.count) workflow\(filteredWorkflows.count == 1 ? "" : "s")")
                    .font(SettingsManager.shared.fontXS)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Run") {
                    if let workflow = selectedWorkflow {
                        onSelect(workflow)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedWorkflow == nil)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(16)
        }
        .frame(width: 450, height: 450)
        .background(SettingsManager.shared.surfaceInput)
    }
}

struct WorkflowPickerRow: View {
    let workflow: WorkflowDefinition
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: workflow.icon)
                .font(SettingsManager.shared.fontTitle)
                .foregroundColor(workflow.color.color)
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(workflow.name)
                    .font(SettingsManager.shared.fontBodyMedium)
                    .foregroundColor(.primary)

                if !workflow.description.isEmpty {
                    Text(workflow.description)
                        .font(SettingsManager.shared.fontXS)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Step count
            Text("\(workflow.steps.count) step\(workflow.steps.count == 1 ? "" : "s")")
                .font(SettingsManager.shared.fontXS)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
