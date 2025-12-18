//
//  VoiceMemoDetailView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CloudKit
import EventKit

struct VoiceMemoDetailView: View {
    @ObservedObject var memo: VoiceMemo
    @ObservedObject var audioPlayer: AudioPlayerManager
    var scrollToActivity: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var isEditMode = false
    @State private var isEditingTitle = false
    @State private var editedTitle = ""
    @State private var isEditingTranscript = false
    @State private var editedTranscript = ""
    @State private var showingVersionHistory = false
    @State private var showingShare = false
    @State private var showingDeleteConfirmation = false
    @State private var isGeneratingTitle = false
    @State private var aiError: String?
    @State private var reminderStatus: ReminderStatus = .idle
    @State private var showingReminderSheet = false
    @State private var showingReminderToast = false
    @State private var showingNoteShare = false
    @State private var reminderTitle: String = ""
    @State private var reminderDueDate: Date = Date().addingTimeInterval(3600) // 1 hour from now
    @State private var showingMacWorkflowToast = false
    @State private var tappedWorkflowName: String = ""
    @State private var showingCopiedToast = false
    @State private var isTranscriptExpanded = false
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var aiService = OnDeviceAIService.shared

    private enum ReminderStatus: Equatable {
        case idle
        case creating
        case success
        case error(String)
    }


    private var memoURL: URL? {
        guard let filename = memo.fileURL else { return nil }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent(filename)
    }

    private var isPlaying: Bool {
        // Check if audio player is playing
        // For audioData playback, currentPlayingURL is nil, so we just check isPlaying
        // This view is modal, so if audio is playing, it's this memo
        audioPlayer.isPlaying
    }

    private var memoTitle: String {
        memo.title ?? "Recording"
    }

    private var memoCreatedAt: Date {
        memo.createdAt ?? Date()
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(spacing: Spacing.md) {
                        // Header: Title + Metadata (compact)
                        VStack(spacing: Spacing.xs) {
                            // Title
                            if isEditingTitle {
                                TextField("Title", text: $editedTitle)
                                    .font(.bodyMedium)
                                    .padding(Spacing.sm)
                                    .background(Color.surfaceSecondary)
                                    .cornerRadius(CornerRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                                            .strokeBorder(Color.active, lineWidth: 1)
                                    )
                                    .padding(.horizontal, Spacing.md)
                            } else {
                                // Title with edit indicator in edit mode
                                HStack(spacing: Spacing.xs) {
                                    Text(memoTitle)
                                        .font(.bodyMedium)
                                        .fontWeight(.medium)
                                        .foregroundColor(.textPrimary)
                                        .multilineTextAlignment(.center)

                                    if isEditMode {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.active)
                                    }
                                }
                                .padding(.horizontal, Spacing.md)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isEditMode {
                                        editedTitle = memoTitle
                                        isEditingTitle = true
                                    }
                                }
                            }

                            HStack(spacing: Spacing.xs) {
                                Text(formatDate(memoCreatedAt).uppercased())
                                    .font(.techLabelSmall)
                                    .tracking(1)

                                Text("·").font(.labelSmall)

                                HStack(spacing: 4) {
                                    if memo.cloudSyncedAt != nil {
                                        Image(systemName: "checkmark.icloud.fill")
                                            .font(.system(size: 10, weight: .medium))
                                    }

                                    if memo.macReceivedAt != nil {
                                        Image(systemName: "desktopcomputer")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                }
                            }
                            .foregroundColor(.textSecondary)
                        }
                        .padding(.top, Spacing.xs)

                        // Playback: Waveform with play button centered below
                        VStack(spacing: Spacing.xs) {
                            // Interactive waveform with progress
                            if let waveformData = memo.waveformData,
                               let levels = try? JSONDecoder().decode([Float].self, from: waveformData) {
                                InteractiveWaveformView(
                                    levels: levels,
                                    height: 48,
                                    progress: playbackProgress,
                                    playedColor: .active,
                                    unplayedColor: .textTertiary.opacity(0.4)
                                ) { seekProgress in
                                    seekToProgress(seekProgress)
                                }
                            } else {
                                // Fallback: simple progress bar if no waveform
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.textTertiary.opacity(0.3))
                                            .frame(height: 4)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.active)
                                            .frame(width: geo.size.width * playbackProgress, height: 4)
                                    }
                                    .frame(maxHeight: .infinity, alignment: .center)
                                }
                                .frame(height: 48)
                            }

                            // Time + Play button row
                            HStack {
                                Text(formatDuration(isPlaying ? audioPlayer.currentTime : 0))
                                    .font(.monoSmall)
                                    .foregroundColor(.textTertiary)
                                    .frame(width: 40, alignment: .leading)

                                Spacer()

                                // Centered play button
                                Button(action: togglePlayback) {
                                    ZStack {
                                        if isPlaying {
                                            Circle()
                                                .fill(Color.active)
                                                .frame(width: 38, height: 38)
                                                .blur(radius: 8)
                                                .opacity(0.4)
                                        }

                                        Circle()
                                            .fill(isPlaying ? Color.active : Color.surfaceSecondary)
                                            .frame(width: 34, height: 34)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(isPlaying ? Color.active : Color.borderPrimary, lineWidth: 1.5)
                                            )

                                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(isPlaying ? .white : .textPrimary)
                                            .offset(x: isPlaying ? 0 : 1)
                                    }
                                }

                                Spacer()

                                Text(formatDuration(memo.duration))
                                    .font(.monoSmall)
                                    .foregroundColor(.textTertiary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, Spacing.md)

                        // Transcription section
                        if memo.isTranscribing {
                            HStack(spacing: Spacing.sm) {
                                PulsingDot(color: .transcribing, size: 10)
                                Text("TRANSCRIBING")
                                    .font(.techLabel)
                                    .tracking(2)
                                    .foregroundColor(.transcribing)
                            }
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity)
                            .background(Color.transcribing.opacity(0.08))
                            .cornerRadius(CornerRadius.sm)
                            .padding(.horizontal, Spacing.md)
                        } else if let transcription = memo.currentTranscript {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                // Header with title, copy button, and edit indicator
                                HStack {
                                    Text("TRANSCRIPT")
                                        .font(.techLabel)
                                        .tracking(2)
                                        .foregroundColor(.textSecondary)

                                    // Edit indicator shown in edit mode
                                    if isEditMode && !isEditingTranscript {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.active)
                                    }

                                    Spacer()

                                    // Quick copy button
                                    Button(action: {
                                        UIPasteboard.general.string = transcription
                                        showingCopiedToast = true
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                        impactFeedback.impactOccurred()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            showingCopiedToast = false
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: showingCopiedToast ? "checkmark" : "doc.on.doc")
                                                .font(.system(size: 11, weight: .medium))
                                            Text(showingCopiedToast ? "COPIED" : "COPY")
                                                .font(.techLabelSmall)
                                                .tracking(1)
                                        }
                                        .foregroundColor(showingCopiedToast ? .success : .textSecondary)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, Spacing.xs)
                                        .background(Color.surfaceSecondary)
                                        .cornerRadius(CornerRadius.sm)
                                    }
                                    .buttonStyle(.plain)
                                    .animation(.easeInOut(duration: 0.2), value: showingCopiedToast)

                                    // Expand/collapse button
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            isTranscriptExpanded.toggle()
                                        }
                                    }) {
                                        Image(systemName: isTranscriptExpanded ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.textSecondary)
                                            .padding(Spacing.xs)
                                            .background(Color.surfaceSecondary)
                                            .cornerRadius(CornerRadius.sm)
                                    }
                                    .buttonStyle(.plain)
                                }

                                // Transcript content or editor
                                if isEditingTranscript {
                                    VStack(spacing: Spacing.sm) {
                                        TextEditor(text: $editedTranscript)
                                            .font(.bodySmall)
                                            .foregroundColor(.textPrimary)
                                            .scrollContentBackground(.hidden)
                                            .lineSpacing(4)
                                            .padding(Spacing.sm)
                                            .frame(minHeight: 150, maxHeight: 300)
                                            .background(Color.surfaceSecondary)
                                            .cornerRadius(CornerRadius.sm)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                                    .strokeBorder(Color.active, lineWidth: 1)
                                            )

                                        HStack(spacing: Spacing.sm) {
                                            Button(action: {
                                                isEditingTranscript = false
                                                editedTranscript = ""
                                            }) {
                                                Text("CANCEL")
                                                    .font(.techLabel)
                                                    .tracking(1)
                                                    .foregroundColor(.textSecondary)
                                                    .padding(.horizontal, Spacing.md)
                                                    .padding(.vertical, Spacing.sm)
                                                    .background(Color.surfaceSecondary)
                                                    .cornerRadius(CornerRadius.sm)
                                            }

                                            Spacer()

                                            Button(action: saveTranscriptEdit) {
                                                Text("SAVE")
                                                    .font(.techLabel)
                                                    .tracking(1)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, Spacing.md)
                                                    .padding(.vertical, Spacing.sm)
                                                    .background(Color.active)
                                                    .cornerRadius(CornerRadius.sm)
                                            }
                                        }
                                    }
                                } else {
                                    // Scrollable transcript with conditional height
                                    ScrollView {
                                        Text(transcription)
                                            .font(.bodySmall)
                                            .foregroundColor(.textPrimary)
                                            .textSelection(.enabled)
                                            .lineSpacing(4)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(Spacing.md)
                                    .frame(maxWidth: .infinity)
                                    .frame(maxHeight: isTranscriptExpanded ? .infinity : 200)
                                    .background(Color.surfaceSecondary)
                                    .cornerRadius(CornerRadius.sm)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                                            .strokeBorder(isEditMode ? Color.active.opacity(0.5) : Color.borderPrimary, lineWidth: isEditMode ? 1 : 0.5)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isEditMode {
                                            editedTranscript = transcription
                                            isEditingTranscript = true
                                        }
                                    }
                                    .contextMenu {
                                        // Power user: access version history via long-press
                                        if memo.sortedTranscriptVersions.count > 1 {
                                            Button(action: { showingVersionHistory = true }) {
                                                Label("Version History", systemImage: "clock.arrow.circlepath")
                                            }
                                        }
                                        Button(action: {
                                            UIPasteboard.general.string = transcription
                                        }) {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                        }

                        // Quick Actions - Local iPhone actions
                        quickActionsSection

                        // Mac Actions - Remote AI workflows
                        macActionsSection

                        // Activity Section - Workflow outputs and runs
                        if memo.summary != nil || memo.tasks != nil || memo.reminders != nil ||
                           (memo.workflowRuns as? Set<WorkflowRun>)?.isEmpty == false {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                HStack {
                                    Text("ACTIVITY")
                                        .font(.techLabel)
                                        .tracking(2)
                                        .foregroundColor(.textSecondary)
                                        .id("activity-section")

                                    Spacer()

                                    if let workflowRuns = memo.workflowRuns as? Set<WorkflowRun>, !workflowRuns.isEmpty {
                                        HStack(spacing: 4) {
                                            Image(systemName: "desktopcomputer")
                                                .font(.system(size: 10))
                                            Text("\(workflowRuns.count)")
                                                .font(.techLabelSmall)
                                        }
                                        .foregroundColor(.textTertiary)
                                    }
                                }

                                // Workflow Outputs - Summary, Tasks, Reminders
                                if let summary = memo.summary, !summary.isEmpty {
                                    WorkflowOutputSection(
                                        title: "SUMMARY",
                                        icon: "doc.text",
                                        content: summary
                                    )
                                }

                                if let tasks = memo.tasks, !tasks.isEmpty {
                                    WorkflowOutputSection(
                                        title: "TASKS",
                                        icon: "checklist",
                                        content: tasks
                                    )
                                }

                                if let reminders = memo.reminders, !reminders.isEmpty {
                                    WorkflowOutputSection(
                                        title: "REMINDERS",
                                        icon: "bell",
                                        content: reminders
                                    )
                                }

                                // Workflow run history
                                if let workflowRuns = memo.workflowRuns as? Set<WorkflowRun>, !workflowRuns.isEmpty {
                                    ForEach(workflowRuns.sorted { ($0.runDate ?? .distantPast) > ($1.runDate ?? .distantPast) }, id: \.id) { run in
                                        WorkflowRunRow(run: run)
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                        }

                        // Delete button
                        Button(action: {
                            showingDeleteConfirmation = true
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .medium))
                                Text("DELETE MEMO")
                                    .font(.techLabel)
                                    .tracking(1)
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(CornerRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .strokeBorder(Color.red.opacity(0.3), lineWidth: 0.5)
                            )
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.lg)

                        Spacer(minLength: Spacing.xxl)
                    }
                    .padding(.vertical, Spacing.md)
                    }
                    .onAppear {
                        if scrollToActivity {
                            // Delay slightly to ensure view is laid out
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation {
                                    scrollProxy.scrollTo("activity-section", anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete Memo?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteMemo()
                }
            } message: {
                Text("This will permanently delete this memo and its recordings. This action cannot be undone.")
            }
            .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("MEMO DETAIL")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        // Save any pending edits before closing
                        if isEditingTitle {
                            saveTitle()
                        }
                        if isEditingTranscript {
                            saveTranscriptEdit()
                        }
                        dismiss()
                    }) {
                        Text("CLOSE")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(.textSecondary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        if isEditMode {
                            // Save any pending edits and exit edit mode
                            if isEditingTitle {
                                saveTitle()
                            }
                            if isEditingTranscript {
                                saveTranscriptEdit()
                            }
                            isEditMode = false
                        } else {
                            // Enter edit mode
                            isEditMode = true
                        }
                    }) {
                        Text(isEditMode ? "DONE" : "EDIT")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(.active)
                    }
                }
            }
            .sheet(isPresented: $showingShare) {
                ShareSheet(items: [memo.currentTranscript ?? ""])
            }
            .sheet(isPresented: $showingVersionHistory) {
                TranscriptVersionHistorySheet(memo: memo)
            }
            .onAppear {
                // Sync iCloud KVS to get latest pinned workflows from Mac
                NSUbiquitousKeyValueStore.default.synchronize()
                // Fetch latest from CloudKit
                fetchLatestFromCloudKit()
            }
            .overlay {
                // Rising toast for Mac workflow
                if showingMacWorkflowToast {
                    RisingToast(isShowing: $showingMacWorkflowToast) {
                        MacWorkflowToast(workflowName: tappedWorkflowName)
                    }
                }

                // Rising toast for reminder
                if showingReminderToast {
                    RisingToast(isShowing: $showingReminderToast, pauseDuration: 2.0) {
                        ReminderToast()
                    }
                }
            }
            #if DEBUG
            .overlay(alignment: .bottomTrailing) {
                DebugToolbarOverlay(
                    content: {
                        DetailViewDebugContent(
                            memo: memo,
                            onTriggerToast: {
                                tappedWorkflowName = "Test Workflow"
                                showingMacWorkflowToast = true
                            },
                            onTriggerReminderToast: {
                                showingReminderToast = true
                            }
                        )
                    },
                    debugInfo: {
                        var info: [String: String] = [:]
                        info["Memo"] = memo.id?.uuidString.prefix(8).description ?? "-"
                        info["Playing"] = audioPlayer.isPlaying ? "Yes" : "No"
                        if let pending = memo.pendingWorkflowIds, !pending.isEmpty {
                            let count = (try? JSONDecoder().decode([String].self, from: pending.data(using: .utf8) ?? Data()))?.count ?? 0
                            info["Pending"] = "\(count) workflow(s)"
                        }
                        info["Synced"] = memo.cloudSyncedAt != nil ? "Yes" : "No"
                        return info
                    }
                )
            }
            #endif
        }
    }

    private func togglePlayback() {
        AppLogger.playback.info("Toggle playback tapped")

        // Prefer audioData (CloudKit-synced) over local file
        if let audioData = memo.audioData {
            AppLogger.playback.info("Playing from audioData: \(audioData.count) bytes")
            audioPlayer.togglePlayPause(data: audioData)
        } else if let url = memoURL {
            AppLogger.playback.info("Playing from URL: \(url.path)")
            audioPlayer.togglePlayPause(url: url)
        } else {
            AppLogger.playback.warning("No audio data or URL available for playback")
        }
    }

    private func stopPlayback() {
        audioPlayer.stopPlayback()
    }

    private var playbackProgress: Double {
        guard isPlaying else { return 0 }
        let duration = audioPlayer.duration > 0 ? audioPlayer.duration : memo.duration
        guard duration > 0 else { return 0 }
        return audioPlayer.currentTime / duration
    }

    private func seekToProgress(_ progress: Double) {
        let duration = isPlaying ? audioPlayer.duration : memo.duration
        guard duration > 0 else { return }
        let targetTime = progress * duration

        if isPlaying {
            audioPlayer.seek(to: targetTime)
        } else {
            // Start playback at the tapped position
            if let url = memoURL {
                audioPlayer.playAudio(url: url)
                // Small delay to let playback start, then seek
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.audioPlayer.seek(to: targetTime)
                }
            }
        }
    }

    private func saveTitle() {
        guard !editedTitle.isEmpty else {
            isEditingTitle = false
            return
        }
        memo.title = editedTitle
        try? memo.managedObjectContext?.save()
        isEditingTitle = false
    }

    // MARK: - On-Device AI Actions

    private func generateSmartTitle() {
        guard !isGeneratingTitle else { return }
        isGeneratingTitle = true
        aiError = nil

        Task {
            do {
                try await aiService.applySmartTitle(to: memo, context: viewContext)
            } catch {
                aiError = error.localizedDescription
            }
            isGeneratingTitle = false
        }
    }

    private func generateSummary() {
        guard !memo.isProcessingSummary else { return }
        aiError = nil

        Task {
            do {
                try await aiService.applySummary(to: memo, context: viewContext)
            } catch {
                aiError = error.localizedDescription
            }
        }
    }

    private func generateTasks() {
        guard !memo.isProcessingTasks else { return }
        aiError = nil

        Task {
            do {
                try await aiService.applyTasks(to: memo, context: viewContext)
            } catch {
                aiError = error.localizedDescription
            }
        }
    }

    private func copyTranscript() {
        guard let transcript = memo.currentTranscript else { return }
        UIPasteboard.general.string = transcript

        // Brief haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func createReminder() {
        // Initialize with memo title and show configuration sheet
        reminderTitle = memo.title ?? "Voice Memo"
        reminderDueDate = Date().addingTimeInterval(3600) // 1 hour from now
        showingReminderSheet = true
    }

    private func confirmCreateReminder() {
        let eventStore = EKEventStore()
        reminderStatus = .creating

        // Request access to reminders
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToReminders { granted, error in
                DispatchQueue.main.async {
                    if granted && error == nil {
                        self.saveReminder(to: eventStore)
                    } else {
                        self.reminderStatus = .error("Permission denied")
                        self.resetReminderStatusAfterDelay()
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, error in
                DispatchQueue.main.async {
                    if granted && error == nil {
                        self.saveReminder(to: eventStore)
                    } else {
                        self.reminderStatus = .error("Permission denied")
                        self.resetReminderStatusAfterDelay()
                    }
                }
            }
        }
    }

    private func saveReminder(to eventStore: EKEventStore) {
        // Find or create "Talkie" reminder list
        let calendar = findOrCreateTalkieList(in: eventStore)
        guard let calendar = calendar else {
            reminderStatus = .error("No calendar found")
            resetReminderStatusAfterDelay()
            return
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = reminderTitle
        reminder.calendar = calendar

        // Add transcript as notes if available
        if let transcript = memo.currentTranscript {
            let maxLength = 2000
            if transcript.count > maxLength {
                reminder.notes = String(transcript.prefix(maxLength)) + "..."
            } else {
                reminder.notes = transcript
            }
        }

        // Set due date from picker
        let dateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminderDueDate
        )
        reminder.dueDateComponents = dateComponents

        // Add alarm at due time
        let alarm = EKAlarm(absoluteDate: reminderDueDate)
        reminder.addAlarm(alarm)

        do {
            try eventStore.save(reminder, commit: true)
            reminderStatus = .success

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            // Show toast notification
            showingReminderToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                showingReminderToast = false
            }

            resetReminderStatusAfterDelay()
        } catch {
            reminderStatus = .error("Failed to save")
            resetReminderStatusAfterDelay()
        }
    }

    private func resetReminderStatusAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            reminderStatus = .idle
        }
    }

    /// Find existing "Talkie" reminder list or create one
    private func findOrCreateTalkieList(in eventStore: EKEventStore) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .reminder)

        // Look for existing "Talkie" list
        if let existing = calendars.first(where: { $0.title == "Talkie" }) {
            return existing
        }

        // Create new "Talkie" list with orange color
        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = "Talkie"
        newCalendar.cgColor = UIColor.orange.cgColor

        // Find a source that supports reminders (prefer iCloud, then local)
        // Use the same source as the default reminders calendar
        if let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
            newCalendar.source = defaultCalendar.source
        } else {
            // Try to find iCloud or local source
            let sources = eventStore.sources
            if let iCloudSource = sources.first(where: { $0.sourceType == .calDAV }) {
                newCalendar.source = iCloudSource
            } else if let localSource = sources.first(where: { $0.sourceType == .local }) {
                newCalendar.source = localSource
            } else {
                // No valid source found
                return nil
            }
        }

        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            return newCalendar
        } catch {
            AppLogger.persistence.error("Failed to create Talkie reminder list: \(error.localizedDescription)")
            // Fallback to default
            return eventStore.defaultCalendarForNewReminders()
        }
    }

    private func createNote() {
        // Show share sheet with text + audio file for Notes/Quick Note
        showingNoteShare = true
    }

    /// Subtitle for share sheet (date + duration)
    private var noteSubtitle: String {
        let date = memo.createdAt ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: date)) · \(formatDuration(memo.duration))"
    }

    /// Audio URL for sharing (with nice filename)
    private var noteAudioURL: URL? {
        let safeTitle = (memo.title ?? "Voice Memo")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeTitle)
            .appendingPathExtension("m4a")

        // Get audio data from either audioData or file
        if let audioData = memo.audioData {
            try? audioData.write(to: tempURL)
            return tempURL
        } else if let originalURL = memoURL, FileManager.default.fileExists(atPath: originalURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.copyItem(at: originalURL, to: tempURL)
            return tempURL
        }

        return nil
    }

    /// Content to share to Notes app - includes transcript + all Mac workflow outputs
    private var noteContent: String {
        var content = ""
        let title = memo.title ?? "Voice Memo"
        let date = memo.createdAt ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        // Header
        content += "# \(title)\n"
        content += "Recorded: \(formatter.string(from: date))\n"
        content += "Duration: \(formatDuration(memo.duration))\n"
        content += "\n"

        // Transcript
        if let transcript = memo.currentTranscript, !transcript.isEmpty {
            content += "## Transcript\n"
            content += transcript
            content += "\n\n"
        }

        // Summary (from Mac workflow)
        if let summary = memo.summary, !summary.isEmpty {
            content += "## Summary\n"
            content += summary
            content += "\n\n"
        }

        // Tasks (from Mac workflow)
        if let tasks = memo.tasks, !tasks.isEmpty {
            content += "## Tasks\n"
            content += tasks
            content += "\n\n"
        }

        // Reminders (from Mac workflow)
        if let reminders = memo.reminders, !reminders.isEmpty {
            content += "## Reminders\n"
            content += reminders
            content += "\n"
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Extracted View Sections

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("QUICK ACTIONS")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textSecondary)

            HStack(spacing: Spacing.xs) {
                // Share
                QuickActionButton(
                    icon: "square.and.arrow.up",
                    label: "Share",
                    badge: .none,
                    isProcessing: false,
                    hasContent: false,
                    isAvailable: true
                ) {
                    showingShare = true
                }

                // Add to Notes (share sheet with text + audio)
                QuickActionButton(
                    icon: "note.text",
                    label: "Note",
                    badge: .none,
                    isProcessing: false,
                    hasContent: false,
                    isAvailable: memo.currentTranscript != nil
                ) {
                    createNote()
                }

                // Set Reminder (creates via EventKit)
                QuickActionButton(
                    icon: reminderStatusIcon,
                    label: reminderStatusLabel,
                    badge: .none,
                    isProcessing: reminderStatus == .creating,
                    hasContent: reminderStatus == .success,
                    isAvailable: reminderStatus != .creating
                ) {
                    createReminder()
                }
            }

            // Show reminder error if any
            if case .error(let message) = reminderStatus {
                Text(message)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, Spacing.md)
        .sheet(isPresented: $showingReminderSheet) {
            ReminderConfigSheet(
                title: $reminderTitle,
                dueDate: $reminderDueDate,
                onConfirm: {
                    showingReminderSheet = false
                    confirmCreateReminder()
                },
                onCancel: {
                    showingReminderSheet = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingNoteShare) {
            NoteShareSheet(
                title: memo.title ?? "Voice Memo",
                subtitle: noteSubtitle,
                textContent: noteContent,
                audioURL: noteAudioURL
            )
        }
    }

    private var reminderStatusIcon: String {
        switch reminderStatus {
        case .idle: return "bell"
        case .creating: return "bell"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var reminderStatusLabel: String {
        switch reminderStatus {
        case .idle: return "Remind"
        case .creating: return "Creating..."
        case .success: return "Added!"
        case .error: return "Error"
        }
    }

    /// Pinned workflows from Mac (synced via iCloud KVS)
    private var pinnedWorkflows: [[String: String]] {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: "pinnedWorkflows"),
              let info = try? JSONDecoder().decode([[String: String]].self, from: data) else {
            return []
        }
        return info
    }

    private var macActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("MAC ACTIONS")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textSecondary)

                Spacer()

                // Mac connection status
                macConnectionBadge
            }

            // AI Error banner (if any)
            if let error = aiError {
                aiErrorBanner(error: error)
            }

            // Show pinned workflows from Mac, or defaults if none pinned
            let pinned = pinnedWorkflows
            if pinned.isEmpty {
                HStack(spacing: Spacing.xs) {
                    QuickActionButton(
                        icon: "doc.text",
                        label: "Summary",
                        badge: .remote,
                        isProcessing: memo.isProcessingSummary,
                        hasContent: memo.summary != nil && !memo.summary!.isEmpty,
                        isAvailable: true
                    ) {
                    }

                    QuickActionButton(
                        icon: "checklist",
                        label: "Tasks",
                        badge: .remote,
                        isProcessing: memo.isProcessingTasks,
                        hasContent: memo.tasks != nil && !memo.tasks!.isEmpty,
                        isAvailable: true
                    ) {
                    }

                    QuickActionButton(
                        icon: "bell.badge",
                        label: "Reminders",
                        badge: .remote,
                        isProcessing: memo.isProcessingReminders,
                        hasContent: memo.reminders != nil && !memo.reminders!.isEmpty,
                        isAvailable: true
                    ) {
                    }
                }
            } else {
                HStack(spacing: Spacing.xs) {
                    ForEach(pinned.prefix(4), id: \.["id"]) { workflow in
                        let name = workflow["name"] ?? "Action"
                        let icon = workflow["icon"] ?? "gearshape"

                        QuickActionButton(
                            icon: icon,
                            label: name,
                            badge: .remote,
                            isProcessing: isPendingWorkflow(workflowId: workflow["id"]),
                            hasContent: hasWorkflowOutput(workflowId: workflow["id"]),
                            isAvailable: true
                        ) {
                            if let idString = workflow["id"], let workflowId = UUID(uuidString: idString) {
                                addPendingWorkflow(workflowId)
                            }
                            tappedWorkflowName = name
                            showingMacWorkflowToast = true
                        }
                    }
                }
            }

            if memo.macReceivedAt == nil {
                Text("Actions will run when Mac syncs")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    /// Check if we have output from a specific workflow
    private func hasWorkflowOutput(workflowId: String?) -> Bool {
        guard let idString = workflowId,
              let uuid = UUID(uuidString: idString),
              let runs = memo.workflowRuns as? Set<WorkflowRun> else {
            return false
        }
        return runs.contains { $0.workflowId == uuid && $0.status == "completed" }
    }

    /// Get pending workflow IDs as array
    private var pendingWorkflowIdArray: [UUID] {
        guard let jsonString = memo.pendingWorkflowIds,
              let data = jsonString.data(using: .utf8),
              let ids = try? JSONDecoder().decode([UUID].self, from: data) else {
            return []
        }
        return ids
    }

    /// Check if a workflow is pending
    private func isPendingWorkflow(workflowId: String?) -> Bool {
        guard let idString = workflowId,
              let uuid = UUID(uuidString: idString) else {
            return false
        }
        return pendingWorkflowIdArray.contains(uuid)
    }

    /// Add a workflow to the pending queue
    private func addPendingWorkflow(_ workflowId: UUID) {
        var ids = pendingWorkflowIdArray

        // Don't add duplicates
        guard !ids.contains(workflowId) else { return }

        ids.append(workflowId)

        if let data = try? JSONEncoder().encode(ids),
           let jsonString = String(data: data, encoding: .utf8) {
            memo.pendingWorkflowIds = jsonString
            try? memo.managedObjectContext?.save()
            AppLogger.persistence.info("Added pending workflow: \(workflowId)")
        }
    }

    private var macConnectionBadge: some View {
        Image(systemName: "desktopcomputer")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(memo.macReceivedAt != nil ? .green : .textTertiary)
    }

    private func aiErrorBanner(error: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10))
            Text(error)
                .font(.techLabelSmall)
                .lineLimit(1)
        }
        .foregroundColor(.red)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.1))
        .cornerRadius(CornerRadius.sm)
        .onTapGesture { aiError = nil }
    }

    private func saveTranscriptEdit() {
        guard !editedTranscript.isEmpty else { return }

        // Create a new user version (immutable - keeps history)
        memo.addUserTranscript(content: editedTranscript)
        try? memo.managedObjectContext?.save()

        isEditingTranscript = false
        editedTranscript = ""
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d h:mm a"
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func deleteMemo() {
        // Stop playback if playing
        audioPlayer.stopPlayback()

        // Delete audio file
        if let filename = memo.fileURL {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let filePath = documentsPath.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: filePath.path) {
                try? FileManager.default.removeItem(at: filePath)
            }
        }

        // Delete from Core Data
        viewContext.delete(memo)

        do {
            try viewContext.save()
            dismiss()
        } catch {
            AppLogger.persistence.error("Error deleting memo: \(error.localizedDescription)")
        }
    }

    /// Fetch latest memo data from CloudKit and update local Core Data
    private func fetchLatestFromCloudKit() {
        guard let memoId = memo.id else { return }

        let container = CKContainer(identifier: "iCloud.com.jdi.talkie")
        let privateDB = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        // Query for this specific memo by CD_id (Core Data uses CD_ prefix)
        // CloudKit requires UUID as string, not UUID object
        let predicate = NSPredicate(format: "CD_id == %@", memoId.uuidString)
        let query = CKQuery(recordType: "CD_VoiceMemo", predicate: predicate)

        privateDB.fetch(withQuery: query, inZoneWith: zoneID) { result in
            switch result {
            case .success(let (matchResults, _)):
                guard let firstMatch = matchResults.first,
                      case .success(let record) = firstMatch.1 else {
                    AppLogger.persistence.info("No CloudKit record found for memo")
                    return
                }

                // Update local memo with CloudKit values
                DispatchQueue.main.async {
                    var didUpdate = false

                    if let cloudSyncedAt = record["CD_cloudSyncedAt"] as? Date {
                        memo.cloudSyncedAt = cloudSyncedAt
                        didUpdate = true
                    }
                    if let macReceivedAt = record["CD_macReceivedAt"] as? Date {
                        memo.macReceivedAt = macReceivedAt
                        didUpdate = true
                    }
                    // Fetch workflow outputs from Mac
                    if let summary = record["CD_summary"] as? String, !summary.isEmpty {
                        memo.summary = summary
                        didUpdate = true
                    }
                    if let tasks = record["CD_tasks"] as? String, !tasks.isEmpty {
                        memo.tasks = tasks
                        didUpdate = true
                    }
                    if let reminders = record["CD_reminders"] as? String, !reminders.isEmpty {
                        memo.reminders = reminders
                        didUpdate = true
                    }

                    // Sync pending workflow queue (Mac clears this after running)
                    let pendingWorkflowIds = record["CD_pendingWorkflowIds"] as? String
                    if memo.pendingWorkflowIds != pendingWorkflowIds {
                        memo.pendingWorkflowIds = pendingWorkflowIds
                        didUpdate = true
                    }

                    if didUpdate {
                        try? memo.managedObjectContext?.save()
                        AppLogger.persistence.info("Updated memo from CloudKit: cloud=\(memo.cloudSyncedAt != nil), mac=\(memo.macReceivedAt != nil), summary=\(memo.summary != nil), pending=\(memo.pendingWorkflowIds ?? "nil")")
                    }
                }

                // Fetch WorkflowRuns for this memo
                self.fetchWorkflowRuns(memoId: memoId, zoneID: zoneID, privateDB: privateDB)

            case .failure(let error):
                AppLogger.persistence.error("CloudKit fetch failed: \(error.localizedDescription)")
            }
        }
    }

    /// Fetch workflow runs from CloudKit for this memo
    private func fetchWorkflowRuns(memoId: UUID, zoneID: CKRecordZone.ID, privateDB: CKDatabase) {
        // Query all WorkflowRun records - we'll filter by memo relationship
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "CD_WorkflowRun", predicate: predicate)

        privateDB.fetch(withQuery: query, inZoneWith: zoneID, resultsLimit: 100) { result in
            switch result {
            case .success(let (matchResults, _)):
                DispatchQueue.main.async {
                    guard let context = self.memo.managedObjectContext else { return }

                    // Get existing workflow run IDs to avoid duplicates
                    let existingRuns = (self.memo.workflowRuns as? Set<WorkflowRun>) ?? []
                    let existingIds = Set(existingRuns.compactMap { $0.id })

                    var addedCount = 0

                    for matchResult in matchResults {
                        guard case .success(let record) = matchResult.1 else { continue }

                        // Check if this run belongs to our memo via the reference
                        guard let memoRef = record["CD_memo"] as? CKRecord.Reference else { continue }

                        // The reference recordID should contain our memo's ID somewhere
                        // Core Data + CloudKit uses format like "CD_VoiceMemo_<UUID>"
                        let refName = memoRef.recordID.recordName
                        guard refName.contains(memoId.uuidString) else { continue }

                        guard let runId = record["CD_id"] as? UUID else { continue }

                        // Skip if we already have this run
                        if existingIds.contains(runId) { continue }

                        // Create new WorkflowRun
                        let workflowRun = WorkflowRun(context: context)
                        workflowRun.id = runId
                        workflowRun.workflowId = record["CD_workflowId"] as? UUID
                        workflowRun.workflowName = record["CD_workflowName"] as? String
                        workflowRun.workflowIcon = record["CD_workflowIcon"] as? String
                        workflowRun.runDate = record["CD_runDate"] as? Date
                        workflowRun.status = record["CD_status"] as? String
                        workflowRun.output = record["CD_output"] as? String
                        workflowRun.stepOutputsJSON = record["CD_stepOutputsJSON"] as? String
                        workflowRun.modelId = record["CD_modelId"] as? String
                        workflowRun.providerName = record["CD_providerName"] as? String
                        workflowRun.memo = self.memo

                        addedCount += 1
                    }

                    if addedCount > 0 {
                        try? context.save()
                        AppLogger.persistence.info("Added \(addedCount) workflow run(s) from CloudKit")
                    } else {
                        AppLogger.persistence.debug("No new workflow runs from CloudKit")
                    }
                }

            case .failure(let error):
                AppLogger.persistence.debug("WorkflowRun fetch: \(error.localizedDescription)")
            }
        }
    }

}

// MARK: - Quick Action Button (compact, with local/remote badge)

enum ActionBadge {
    case none    // No badge (local iPhone action)
    case local   // On-device AI
    case remote  // Mac workflow
}

struct QuickActionButton: View {
    let icon: String
    let label: String
    let badge: ActionBadge
    let isProcessing: Bool
    let hasContent: Bool
    let isAvailable: Bool
    let action: () -> Void

    @State private var showingDetail = false

    private var badgeIcon: String? {
        switch badge {
        case .none: return nil
        case .local: return "apple.intelligence"
        case .remote: return "desktopcomputer"
        }
    }

    private var isDisabled: Bool {
        isProcessing || (!hasContent && !isAvailable)
    }

    private var statusColor: Color {
        if hasContent { return .success }
        if isProcessing { return .blue }
        if isAvailable {
            switch badge {
            case .none: return .active
            case .local: return .active
            case .remote: return .blue
            }
        }
        return .textTertiary.opacity(0.4)
    }

    private var processingColor: Color {
        switch badge {
        case .remote: return .blue
        default: return .active
        }
    }

    var body: some View {
        Button(action: {
            // Tap: run action (or re-run if already has content)
            if isAvailable && !isProcessing {
                action()
            }
        }) {
            VStack(spacing: 3) {
                // Icon with processing state
                ZStack {
                    // Subtle glow when processing
                    if isProcessing {
                        Circle()
                            .fill(processingColor.opacity(0.2))
                            .frame(width: 32, height: 32)
                    }

                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(statusColor)
                }
                .frame(width: 32, height: 32)

                // Label
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isProcessing ? processingColor : (hasContent ? .textPrimary : (isAvailable ? .textSecondary : .textTertiary.opacity(0.5))))
                    .lineLimit(1)

                // Status indicator
                HStack(spacing: 3) {
                    if isProcessing {
                        // "Sending to Mac" indicator
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(processingColor)
                        Text("PENDING")
                            .font(.system(size: 7, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(processingColor)
                    } else if hasContent {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 4, height: 4)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(
                Group {
                    if isProcessing {
                        // Subtle animated gradient when processing
                        LinearGradient(
                            colors: [
                                processingColor.opacity(0.08),
                                processingColor.opacity(0.15),
                                processingColor.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else if hasContent {
                        statusColor.opacity(0.08)
                    } else {
                        Color.surfaceSecondary.opacity(isDisabled ? 0.5 : 1)
                    }
                }
            )
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(
                        isProcessing ? processingColor.opacity(0.5) : (hasContent ? statusColor.opacity(0.3) : Color.borderPrimary.opacity(isDisabled ? 0.2 : 0.5)),
                        lineWidth: isProcessing ? 1 : 0.5
                    )
            )
            .opacity(isDisabled && !hasContent && !isProcessing ? 0.5 : 1)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isDisabled)
    }
}

// MARK: - AI Action Cell (for actions like Smart Title)
struct AIActionCell: View {
    let icon: String
    let title: String
    let isProcessing: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isAvailable ? .active : .textTertiary)

                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }

                Text(title)
                    .font(.techLabelSmall)
                    .tracking(0.5)
                    .foregroundColor(isAvailable ? .textPrimary : .textTertiary)

                // AI badge
                HStack(spacing: 2) {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 8))
                    Text(isProcessing ? "..." : "AI")
                        .font(.techLabelSmall)
                }
                .foregroundColor(isProcessing ? .transcribing : (isAvailable ? .active : .textTertiary))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isAvailable ? Color.active.opacity(0.05) : Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(isAvailable ? Color.active.opacity(0.3) : Color.borderPrimary, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isAvailable || isProcessing)
    }
}

// MARK: - AI Workflow Cell (shows content OR generates with AI)
struct AIWorkflowCell: View {
    let icon: String
    let title: String
    let content: String?
    let isProcessing: Bool
    let isAIAvailable: Bool
    let generateAction: () -> Void

    @State private var isShowingDetail = false

    private var hasContent: Bool {
        content != nil && !content!.isEmpty
    }

    var body: some View {
        Button(action: {
            if hasContent {
                isShowingDetail = true
            } else if isAIAvailable {
                generateAction()
            }
        }) {
            VStack(spacing: Spacing.xs) {
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(hasContent ? .success : (isAIAvailable ? .active : .textTertiary))

                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }

                Text(title)
                    .font(.techLabelSmall)
                    .tracking(0.5)
                    .foregroundColor(hasContent ? .textPrimary : .textTertiary)

                // Status indicator
                if isProcessing {
                    Text("...")
                        .font(.techLabelSmall)
                        .foregroundColor(.transcribing)
                } else if hasContent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.success)
                } else if isAIAvailable {
                    // Show "Generate" hint
                    HStack(spacing: 2) {
                        Image(systemName: "apple.intelligence")
                            .font(.system(size: 8))
                        Text("Generate")
                            .font(.techLabelSmall)
                    }
                    .foregroundColor(.active)
                } else {
                    Text("—")
                        .font(.techLabelSmall)
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(hasContent ? Color.success.opacity(0.03) : (isAIAvailable ? Color.active.opacity(0.03) : Color.surfaceSecondary))
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(hasContent ? Color.success.opacity(0.3) : (isAIAvailable ? Color.active.opacity(0.2) : Color.borderPrimary), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isProcessing || (!hasContent && !isAIAvailable))
        .sheet(isPresented: $isShowingDetail) {
            WorkflowDetailSheet(title: title, icon: icon, content: content ?? "")
        }
    }
}

// MARK: - Compact Workflow Cell Component (Grid - view only)
struct CompactWorkflowCell: View {
    let icon: String
    let title: String
    let content: String?
    let isProcessing: Bool

    @State private var isShowingDetail = false

    private var hasContent: Bool {
        content != nil && !content!.isEmpty
    }

    var body: some View {
        Button(action: {
            if hasContent {
                isShowingDetail = true
            }
        }) {
            VStack(spacing: Spacing.xs) {
                // Icon with status
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(hasContent ? .success : .textTertiary)

                    // Processing indicator overlay
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
                }

                // Title
                Text(title)
                    .font(.techLabelSmall)
                    .tracking(0.5)
                    .foregroundColor(hasContent ? .textPrimary : .textTertiary)

                // Status indicator
                if isProcessing {
                    Text("...")
                        .font(.techLabelSmall)
                        .foregroundColor(.transcribing)
                } else if hasContent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.success)
                } else {
                    Text("—")
                        .font(.techLabelSmall)
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(hasContent ? Color.success.opacity(0.03) : Color.surfaceSecondary)
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(hasContent ? Color.success.opacity(0.3) : Color.borderPrimary, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!hasContent)
        .sheet(isPresented: $isShowingDetail) {
            WorkflowDetailSheet(title: title, icon: icon, content: content ?? "")
        }
    }
}

// MARK: - Workflow Detail Sheet
struct WorkflowDetailSheet: View {
    let title: String
    let icon: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text(content)
                            .font(.bodySmall)
                            .foregroundColor(.textPrimary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    .padding(Spacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.success)
                        Text(title.uppercased())
                            .font(.techLabel)
                            .tracking(2)
                            .foregroundColor(.textPrimary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") {
                        dismiss()
                    }
                    .font(.techLabel)
                    .tracking(1)
                    .foregroundColor(.active)
                }
            }
        }
    }
}

// MARK: - Workflow Output Card Component
struct WorkflowOutputCard: View {
    let icon: String
    let title: String
    let content: String?
    let isProcessing: Bool

    @State private var isExpanded = false

    private var hasContent: Bool {
        content != nil && !content!.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header - always visible
            Button(action: {
                if hasContent {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack {
                    // Icon and title
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(hasContent ? .success : .textTertiary)

                        Text(title)
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(hasContent ? .textPrimary : .textTertiary)
                    }

                    Spacer()

                    // Status indicator
                    if isProcessing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("PROCESSING")
                                .font(.techLabelSmall)
                                .tracking(1)
                                .foregroundColor(.transcribing)
                        }
                    } else if hasContent {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.success)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.textTertiary)
                        }
                    } else {
                        Text("AWAITING")
                            .font(.techLabelSmall)
                            .tracking(1)
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Content - expandable
            if isExpanded, let content = content {
                Text(content)
                    .font(.bodySmall)
                    .foregroundColor(.textPrimary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.sm)
                    .background(Color.surfacePrimary)
                    .cornerRadius(CornerRadius.sm)
                    .textSelection(.enabled)
            }
        }
        .padding(Spacing.md)
        .background(hasContent ? Color.success.opacity(0.03) : Color.surfaceSecondary)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(hasContent ? Color.success.opacity(0.3) : Color.borderPrimary, lineWidth: 0.5)
        )
    }
}

// MARK: - Workflow Output Section (tap to copy)
struct WorkflowOutputSection: View {
    let title: String
    let icon: String
    let content: String

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.success)

                Text(title)
                    .font(.techLabel)
                    .tracking(1)
                    .foregroundColor(.textSecondary)

                Spacer()
            }

            // Content - tap to copy
            Button(action: {
                UIPasteboard.general.string = content
                withAnimation {
                    showCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showCopied = false
                    }
                }
            }) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(content)
                        .font(.bodySmall)
                        .foregroundColor(.textPrimary)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)

                    // Tap to copy hint
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9, weight: .medium))
                            Text(showCopied ? "COPIED" : "TAP TO COPY")
                                .font(.techLabelSmall)
                                .tracking(0.5)
                        }
                        .foregroundColor(showCopied ? .success : .textTertiary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(Spacing.sm)
            .background(Color.surfacePrimary)
            .cornerRadius(CornerRadius.sm)
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(Color.success.opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Action Button Component (Legacy - kept for compatibility)
struct ActionButton: View {
    let icon: String
    let title: String
    let isProcessing: Bool
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: Spacing.xs) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(isCompleted ? .success : .textPrimary)
                    }

                    Text(title)
                        .font(.techLabelSmall)
                        .tracking(1)
                        .foregroundColor(isProcessing ? .transcribing : .textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(isCompleted ? Color.success.opacity(0.05) : Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .strokeBorder(isCompleted ? Color.success : Color.borderPrimary, lineWidth: 0.5)
                )

                // Completed indicator
                if isCompleted && !isProcessing {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.success)
                        .offset(x: -4, y: 4)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isProcessing)
    }
}

// MARK: - Transcript Version History Sheet
struct TranscriptVersionHistorySheet: View {
    @ObservedObject var memo: VoiceMemo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                if memo.sortedTranscriptVersions.isEmpty {
                    VStack(spacing: Spacing.md) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40))
                            .foregroundColor(.textTertiary)
                        Text("No version history")
                            .font(.bodyMedium)
                            .foregroundColor(.textSecondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.md) {
                            ForEach(memo.sortedTranscriptVersions, id: \.id) { version in
                                TranscriptVersionRow(version: version, isLatest: version == memo.latestTranscriptVersion)
                            }
                        }
                        .padding(Spacing.md)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("VERSION HISTORY")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textPrimary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") {
                        dismiss()
                    }
                    .font(.techLabel)
                    .foregroundColor(.active)
                }
            }
        }
    }
}

// MARK: - Transcript Version Row
struct TranscriptVersionRow: View {
    let version: TranscriptVersion
    let isLatest: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack {
                // Version badge
                HStack(spacing: 4) {
                    Text("v\(version.version)")
                        .font(.monoSmall)
                        .fontWeight(.semibold)
                    if isLatest {
                        Text("CURRENT")
                            .font(.techLabelSmall)
                            .tracking(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.active.opacity(0.15))
                            .foregroundColor(.active)
                            .cornerRadius(4)
                    }
                }

                Spacer()

                // Source type icon
                Image(systemName: sourceIcon)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
            }

            // Source and date info
            HStack(spacing: Spacing.xs) {
                Text(version.sourceDescription.uppercased())
                    .font(.techLabelSmall)
                    .tracking(1)

                Text("·")

                Text(version.formattedDate)
                    .font(.monoSmall)
            }
            .foregroundColor(.textTertiary)

            // Content preview or full (expandable)
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                Text(version.content ?? "")
                    .font(.bodySmall)
                    .foregroundColor(.textPrimary)
                    .lineLimit(isExpanded ? nil : 3)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(PlainButtonStyle())

            if !isExpanded && (version.content?.count ?? 0) > 150 {
                Text("TAP TO EXPAND")
                    .font(.techLabelSmall)
                    .tracking(1)
                    .foregroundColor(.active)
            }
        }
        .padding(Spacing.md)
        .background(isLatest ? Color.active.opacity(0.05) : Color.surfaceSecondary)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(isLatest ? Color.active.opacity(0.3) : Color.borderPrimary, lineWidth: 0.5)
        )
    }

    private var sourceIcon: String {
        guard let sourceType = version.sourceTypeEnum else {
            return "doc.text"
        }
        switch sourceType {
        case .systemIOS:
            return "iphone"
        case .systemMacOS:
            return "desktopcomputer"
        case .user:
            return "pencil"
        }
    }
}

// MARK: - Workflow Run Row (Compact)
struct WorkflowRunRow: View {
    let run: WorkflowRun
    @State private var showCopied = false
    @State private var isExpanded = false

    private var statusColor: Color {
        switch run.status {
        case "completed": return .success
        case "failed": return .red
        case "running": return .transcribing
        default: return .textTertiary
        }
    }

    private var formattedDate: String {
        guard let date = run.runDate else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// First line or truncated preview of output
    private var outputPreview: String? {
        guard let output = run.output, !output.isEmpty else { return nil }
        let firstLine = output.components(separatedBy: .newlines).first ?? output
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 60 {
            return String(trimmed.prefix(60)) + "..."
        }
        return trimmed
    }

    private var hasOutput: Bool {
        run.output?.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact header row - always visible
            Button(action: {
                guard hasOutput else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: Spacing.sm) {
                    // Status indicator dot
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)

                    // Workflow icon + name
                    Image(systemName: run.workflowIcon ?? "wand.and.stars")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)

                    Text(run.workflowName ?? "Workflow")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Time + expand indicator
                    HStack(spacing: 4) {
                        Text(formattedDate)
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)

                        if hasOutput {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .buttonStyle(PlainButtonStyle())

            // Preview line when collapsed (if has output)
            if !isExpanded, let preview = outputPreview {
                Text(preview)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .lineLimit(1)
                    .padding(.leading, 6 + Spacing.sm) // Align with text after dot
                    .padding(.bottom, Spacing.xs)
            }

            // Expanded output
            if isExpanded, let output = run.output, !output.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(output)
                        .font(.system(size: 13))
                        .foregroundColor(.textPrimary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6 + Spacing.sm) // Align with text after dot

                    // Copy button
                    HStack {
                        Spacer()
                        Button(action: {
                            UIPasteboard.general.string = output
                            withAnimation { showCopied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation { showCopied = false }
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9, weight: .medium))
                                Text(showCopied ? "COPIED" : "COPY")
                                    .font(.system(size: 10, weight: .medium))
                                    .tracking(0.5)
                            }
                            .foregroundColor(showCopied ? .success : .textTertiary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(Spacing.sm)
                .background(Color.surfacePrimary.opacity(0.5))
                .cornerRadius(CornerRadius.sm)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Reminder Configuration Sheet

struct ReminderConfigSheet: View {
    @Binding var title: String
    @Binding var dueDate: Date
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Title field
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("TITLE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.textTertiary)

                    TextField("Reminder title", text: $title)
                        .font(.system(size: 16, design: .monospaced))
                        .padding(Spacing.sm)
                        .background(Color.surfaceSecondary)
                        .cornerRadius(CornerRadius.sm)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

                // Due date picker
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("REMIND ME")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.textTertiary)

                    DatePicker(
                        "",
                        selection: $dueDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(.active)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)

                Spacer()

                // Quick time options
                VStack(spacing: Spacing.sm) {
                    Text("QUICK SET")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Spacing.xs) {
                        QuickTimeButton(label: "1h", date: Date().addingTimeInterval(3600), selection: $dueDate)
                        QuickTimeButton(label: "3h", date: Date().addingTimeInterval(10800), selection: $dueDate)
                        QuickTimeButton(label: "Tomorrow", date: tomorrowMorning, selection: $dueDate)
                        QuickTimeButton(label: "Next Week", date: nextWeek, selection: $dueDate)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.lg)
            }
            .background(Color.surfacePrimary)
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onConfirm()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var tomorrowMorning: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
    }

    private var nextWeek: Date {
        let calendar = Calendar.current
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: Date())!
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: nextWeek)!
    }
}

struct QuickTimeButton: View {
    let label: String
    let date: Date
    @Binding var selection: Date

    private var isSelected: Bool {
        abs(selection.timeIntervalSince(date)) < 60 // within 1 minute
    }

    var body: some View {
        Button(action: { selection = date }) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(isSelected ? .surfacePrimary : .textSecondary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(isSelected ? Color.active : Color.surfaceSecondary)
                .cornerRadius(CornerRadius.sm)
        }
    }
}

// MARK: - Talkie Toast (Standardized)

enum ToastStyle {
    case success
    case info
    case warning

    var iconColor: Color {
        switch self {
        case .success: return .green
        case .info: return .active
        case .warning: return .orange
        }
    }
}

struct TalkieToast: View {
    let icon: String
    let title: String
    let subtitle: String?
    let style: ToastStyle
    let action: (() -> Void)?
    let actionLabel: String?

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        style: ToastStyle = .info,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Icon with style color
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(style.iconColor)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.textPrimary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            // Optional action button
            if let actionLabel = actionLabel, let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.active)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.active.opacity(0.15))
                        .cornerRadius(CornerRadius.sm)
                }
            }
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.surfaceSecondary)
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .strokeBorder(Color.borderPrimary.opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Reminder Toast (uses TalkieToast)

struct ReminderToast: View {
    var body: some View {
        TalkieToast(
            icon: "checkmark.circle.fill",
            title: "Reminder added",
            subtitle: "Find it in Reminders → Talkie",
            style: .success,
            actionLabel: "Open"
        ) {
            if let url = URL(string: "x-apple-reminderkit://") {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Rising Toast Animation

/// A toast that rises from the bottom, pauses at center with dimmed backdrop, then continues up and fades out
/// User can tap backdrop or swipe up to dismiss early
struct RisingToast<Content: View>: View {
    @Binding var isShowing: Bool
    let pauseDuration: Double
    let content: () -> Content

    @State private var phase: AnimationPhase = .hidden
    @State private var dragOffset: CGFloat = 0
    @State private var dismissTimer: DispatchWorkItem?

    private enum AnimationPhase {
        case hidden      // Off screen at bottom
        case rising      // Moving up to center
        case paused      // Holding at center with backdrop
        case exiting     // Moving up and fading out
    }

    init(isShowing: Binding<Bool>, pauseDuration: Double = 4.5, @ViewBuilder content: @escaping () -> Content) {
        self._isShowing = isShowing
        self.pauseDuration = pauseDuration
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height

            ZStack {
                // Gradient backdrop behind toast area - tap to dismiss
                VStack {
                    LinearGradient(
                        colors: [
                            Color.black.opacity(gradientOpacity),
                            Color.black.opacity(gradientOpacity * 0.7),
                            Color.black.opacity(gradientOpacity * 0.3),
                            Color.black.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 350)

                    Spacer()
                }
                .ignoresSafeArea()
                .onTapGesture {
                    dismissEarly()
                }

                // Toast content - positioned absolutely from top
                VStack(spacing: 0) {
                    content()
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, 48) // Snug below nav bar

                    Spacer()
                }
                .offset(y: yOffset(for: phase, screenHeight: screenHeight) + dragOffset)
                .opacity(toastOpacity)
                .scaleEffect(scale(for: phase))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Only allow upward drag
                            if value.translation.height < 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            // If dragged up enough, dismiss
                            if value.translation.height < -50 || value.predictedEndTranslation.height < -100 {
                                dismissEarly()
                            } else {
                                // Snap back
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
        .onAppear {
            startAnimation()
        }
    }

    private var gradientOpacity: Double {
        switch phase {
        case .hidden: return 0
        case .rising: return 0.9
        case .paused: return 1.0
        case .exiting: return 0
        }
    }

    private var toastOpacity: Double {
        // Fade out as user drags up
        let dragFade = max(0, 1 + Double(dragOffset) / 150)

        switch phase {
        case .hidden: return 0
        case .rising: return 1
        case .paused: return dragFade
        case .exiting: return 0
        }
    }

    private func yOffset(for phase: AnimationPhase, screenHeight: CGFloat) -> CGFloat {
        switch phase {
        case .hidden:
            return screenHeight // Start from below screen
        case .rising, .paused:
            return 0 // Right at top, below nav bar
        case .exiting:
            return -150 // Exit above screen
        }
    }

    private func scale(for phase: AnimationPhase) -> CGFloat {
        switch phase {
        case .hidden: return 0.8
        case .rising: return 1.0
        case .paused: return 1.0
        case .exiting: return 0.9
        }
    }

    private func startAnimation() {
        // Phase 1: Rise to top (slower, smoother)
        withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) {
            phase = .rising
        }

        // Phase 2: Settle into pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                phase = .paused
            }
        }

        // Schedule auto-dismiss (cancellable)
        let timer = DispatchWorkItem { [self] in
            guard phase == .paused else { return }
            exitAndHide()
        }
        dismissTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + pauseDuration, execute: timer)
    }

    private func dismissEarly() {
        // Cancel the auto-dismiss timer
        dismissTimer?.cancel()
        exitAndHide()
    }

    private func exitAndHide() {
        // Phase 3: Exit upward
        withAnimation(.easeIn(duration: 0.3)) {
            phase = .exiting
            dragOffset = 0
        }

        // Phase 4: Hide and reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isShowing = false
            phase = .hidden
        }
    }
}

// MARK: - Mac Workflow Toast

struct MacWorkflowToast: View {
    let workflowName: String

    var body: some View {
        TalkieToast(
            icon: "desktopcomputer",
            title: "Run on Mac",
            subtitle: "\(workflowName) will run when your Mac receives this memo",
            style: .info
        )
    }
}

// MARK: - Note Share Sheet

/// Share sheet for adding content + audio to Notes
struct NoteShareSheet: UIViewControllerRepresentable {
    let title: String
    let subtitle: String
    let textContent: String
    let audioURL: URL?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        var items: [Any] = []

        // Add rich text item with metadata
        let textItem = ShareableTextItem(
            text: textContent,
            title: title,
            subtitle: subtitle
        )
        items.append(textItem)

        // Add audio file if available
        if let audioURL = audioURL {
            items.append(audioURL)
        }

        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        // Exclude activities that don't make sense for notes
        activityVC.excludedActivityTypes = [
            .assignToContact,
            .saveToCameraRoll,
            .addToReadingList
        ]

        return activityVC
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Shareable Text Item with Metadata

import LinkPresentation

/// Provides rich metadata for share sheet preview
final class ShareableTextItem: NSObject, UIActivityItemSource {
    private let text: String
    private let title: String
    private let subtitle: String

    init(text: String, title: String, subtitle: String) {
        self.text = text
        self.title = title
        self.subtitle = subtitle
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return text
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return text
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title

        // Use originalURL to show subtitle (there's no subtitle property)
        metadata.originalURL = URL(fileURLWithPath: subtitle)

        // Set app icon as the preview icon
        if let appIcon = UIImage(named: "AppIcon") ?? UIImage(systemName: "waveform.circle.fill") {
            metadata.iconProvider = NSItemProvider(object: appIcon)
        }

        return metadata
    }
}

