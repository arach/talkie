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

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var audioPlayer: AVAudioPlayer?
    @State private var editedTitle: String = ""
    @State private var editedNotes: String = ""
    @State private var editedTranscript: String = ""
    @State private var isEditing = false
    @State private var selectedTab: DetailTab = .transcript
    @State private var selectedWorkflowRun: WorkflowRun?
    @FocusState private var titleFieldFocused: Bool

    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var workflowManager = WorkflowManager.shared

    enum DetailTab: String, CaseIterable {
        case transcript = "Transcript"
        case aiResults = "AI Results"
    }

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header with title and edit toggle
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        if isEditing {
                            TextField("Recording title", text: $editedTitle)
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .textFieldStyle(.plain)
                                .focused($titleFieldFocused)
                        } else {
                            Text(memoTitle)
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .foregroundColor(.primary)
                        }

                        HStack(spacing: 6) {
                            Text(formatDate(memoCreatedAt).uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(1)

                            Text("·")
                                .font(.system(size: 9))

                            Text(formatDuration(memo.duration))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
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

                // Playback controls
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button(action: togglePlayback) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDuration(currentTime))
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(.primary)

                            Text(formatDuration(memo.duration))
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Tabs
                Picker("", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Tab Content
                Group {
                    switch selectedTab {
                    case .transcript:
                        transcriptView
                    case .aiResults:
                        aiResultsView
                    }
                }

                // Notes Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTES")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.secondary)

                    TextEditor(text: $editedNotes)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .onChange(of: editedNotes) { newValue in
                            saveNotes()
                        }
                }

                // Workflow Actions
                if memo.currentTranscript != nil && !memo.isTranscribing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACTIONS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ], spacing: 8) {
                            ActionButtonMac(
                                icon: "list.bullet.clipboard",
                                title: "SUMMARIZE",
                                isProcessing: memo.isProcessingSummary,
                                isCompleted: memo.summary != nil,
                                action: { executeWorkflow(.summarize) }
                            )

                            ActionButtonMac(
                                icon: "checkmark.square",
                                title: "TASKIFY",
                                isProcessing: memo.isProcessingTasks,
                                isCompleted: memo.tasks != nil,
                                action: { executeWorkflow(.extractTasks) }
                            )

                            ActionButtonMac(
                                icon: "bell",
                                title: "REMIND",
                                isProcessing: memo.isProcessingReminders,
                                isCompleted: memo.reminders != nil,
                                action: { executeWorkflow(.reminders) }
                            )

                            ActionButtonMac(
                                icon: "note.text",
                                title: "ADD TO NOTES",
                                isProcessing: false,
                                isCompleted: false,
                                action: { addToAppleNotes() }
                            )
                        }
                    }
                }

                // Quick Actions
                Divider()

                HStack(spacing: 8) {
                    // Copy transcript
                    Button(action: copyTranscript) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 10))
                            Text("COPY")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(memo.currentTranscript == nil)

                    // Delete memo
                    Button(action: deleteMemo) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("DELETE")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onAppear {
            editedTitle = memoTitle
            editedNotes = memo.notes ?? ""
        }
        .onChange(of: memo.id) { _ in
            // Reset state when memo changes
            editedTitle = memo.title ?? "Recording"
            editedNotes = memo.notes ?? ""
            editedTranscript = ""
            isEditing = false
            isPlaying = false
            audioPlayer?.stop()
            audioPlayer = nil
            currentTime = 0
        }
        .onExitCommand {
            // Escape cancels edit mode
            if isEditing {
                isEditing = false
            }
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

    private func saveNotes() {
        guard let context = memo.managedObjectContext else { return }
        // Debounce: save after 500ms of no typing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            context.perform {
                memo.notes = editedNotes
                try? context.save()
            }
        }
    }

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.pause()
            isPlaying = false
        } else if audioPlayer != nil {
            audioPlayer?.play()
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
                isPlaying = true
                print("✅ Playing synced audio: \(audioData.count) bytes, duration: \(duration)s")
            } catch {
                print("❌ Failed to play audio: \(error)")
            }
        }
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

    private func copyTranscript() {
        guard let transcript = memo.currentTranscript else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
    }

    private func deleteMemo() {
        guard let context = memo.managedObjectContext else { return }
        context.perform {
            context.delete(memo)
            try? context.save()
        }
    }

    private func executeWorkflow(_ actionType: WorkflowActionType) {
        Task {
            do {
                // Get provider/model from settings, with fallback to gemini
                let settings = SettingsManager.shared
                let (providerName, modelId) = resolveProviderAndModel(from: settings)

                try await WorkflowExecutor.shared.execute(
                    action: actionType,
                    for: memo,
                    providerName: providerName,
                    modelId: modelId,
                    context: viewContext
                )
                print("✅ \(actionType.rawValue) workflow completed with \(providerName)/\(modelId)")
            } catch {
                print("❌ Workflow error: \(error.localizedDescription)")
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
            return ("gemini", selectedModel.hasPrefix("gemini") ? selectedModel : "gemini-1.5-flash-latest")
        }

        // Ultimate fallback
        return ("gemini", "gemini-1.5-flash-latest")
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

    // MARK: - Tab Views

    @ViewBuilder
    private var transcriptView: some View {
        if memo.isTranscribing {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("PROCESSING...")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
        } else if let transcript = memo.currentTranscript {
            VStack(alignment: .leading, spacing: 8) {
                if isEditing {
                    // Edit mode: TextEditor
                    TextEditor(text: $editedTranscript)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
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
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
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
                    .font(.system(size: 32))
                    .foregroundColor(.secondary.opacity(0.5))
                Text("NO TRANSCRIPT AVAILABLE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                VStack(alignment: .leading, spacing: 8) {
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
                                    .font(.system(size: 11, design: .monospaced))
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
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Text(task.title)
                                                .font(.system(size: 11, design: .monospaced))
                                        }
                                    }
                                }
                            }
                        }

                        if let remindersJSON = memo.reminders {
                            AIResultSection(title: "Reminders", icon: "bell") {
                                Text(remindersJSON)
                                    .font(.system(size: 11, design: .monospaced))
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
                    .font(.system(size: 24))
                    .foregroundColor(.secondary.opacity(0.3))
                Text("NO RESULTS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.secondary)
                Text("Run workflows to generate AI results")
                    .font(.system(size: 9, design: .monospaced))
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(.secondary)

            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(isCompleted ? .accentColor : .secondary)
                }

                Text(title)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isCompleted ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
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
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)

                // Workflow name (clickable to navigate)
                Button(action: onNavigateToWorkflow) {
                    Text(workflowName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                        .underline(isHovering)
                }
                .buttonStyle(.plain)

                // Model badge
                if let model = modelInfo {
                    Text(model)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(3)
                }

                Spacer()

                // Timestamp
                Text(formatRunDate(runDate))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.4))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isHovering ? Color.primary.opacity(0.05) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
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
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9))
                        Text("BACK")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Divider()
                    .frame(height: 16)

                Image(systemName: workflowIcon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                Button(action: onNavigateToWorkflow) {
                    Text(workflowName)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)

                if let model = modelId {
                    Text(model)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(3)
                }

                Spacer()

                Text(formatFullDate(runDate))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

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
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .tracking(1)
                                    .foregroundColor(.secondary)

                                Text(output)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .textSelection(.enabled)
                                    .lineSpacing(3)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(NSColor.controlBackgroundColor))
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
                                                .fill(Color.secondary.opacity(0.2))
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
        .background(Color(NSColor.textBackgroundColor))
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
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.blue)
                    .cornerRadius(4)

                Image(systemName: step.stepIcon)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text(step.stepType.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { withAnimation { showInput.toggle() } }) {
                    Text(showInput ? "HIDE INPUT" : "SHOW INPUT")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .tracking(0.3)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }

            // Input (collapsible)
            if showInput {
                VStack(alignment: .leading, spacing: 4) {
                    Text("INPUT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(step.input)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineSpacing(2)
                        .lineLimit(10)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(4)
                }
            }

            // Output
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("OUTPUT")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundColor(.secondary.opacity(0.6))

                    Text("→ {{\(step.outputKey)}}")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.blue.opacity(0.7))
                }

                Text(step.output)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isLast ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.1), lineWidth: 0.5)
        )
    }
}
