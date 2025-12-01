//
//  VoiceMemoDetailView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CloudKit

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
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var aiService = OnDeviceAIService.shared

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

                            // Metadata row - date + sync status only
                            HStack(spacing: Spacing.xs) {
                                Text(formatDate(memoCreatedAt).uppercased())
                                    .font(.techLabelSmall)
                                    .tracking(1)

                                // Sync status: cloud + mac
                                if memo.cloudSyncedAt != nil {
                                    Text("·")
                                        .font(.labelSmall)

                                    HStack(spacing: 3) {
                                        Image(systemName: "checkmark.icloud.fill")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.success)

                                        if memo.macReceivedAt != nil {
                                            Image(systemName: "desktopcomputer")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.success)
                                        }
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
                                // Header with title and edit indicator
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
                                    Text(transcription)
                                        .font(.bodySmall)
                                        .foregroundColor(.textPrimary)
                                        .textSelection(.enabled)
                                        .lineSpacing(4)
                                        .padding(Spacing.md)
                                        .frame(maxWidth: .infinity, alignment: .leading)
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

                        // Quick Actions - Compact 4-button row
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Text("QUICK ACTIONS")
                                    .font(.techLabel)
                                    .tracking(2)
                                    .foregroundColor(.textSecondary)

                                Spacer()

                                // Show badges for available processing options
                                HStack(spacing: 6) {
                                    if aiService.isAvailable {
                                        Image(systemName: "apple.intelligence")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.active)
                                    }
                                    Image(systemName: "desktopcomputer")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(memo.macReceivedAt != nil ? .blue : .textTertiary.opacity(0.4))
                                }
                            }

                            // AI Error banner (if any)
                            if let error = aiError {
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

                            // Quick action buttons - only show AI buttons if available
                            HStack(spacing: Spacing.xs) {
                                // Local: Smart Title (on-device AI) - only if AI available
                                if aiService.isAvailable {
                                    QuickActionButton(
                                        icon: "wand.and.stars",
                                        label: "Title",
                                        badge: .local,
                                        isProcessing: isGeneratingTitle,
                                        hasContent: memo.title != nil && !memo.title!.isEmpty && memo.title != "New Memo",
                                        isAvailable: memo.currentTranscript != nil
                                    ) {
                                        generateSmartTitle()
                                    }

                                    // Local: Summary (on-device AI)
                                    QuickActionButton(
                                        icon: "doc.text",
                                        label: "Summary",
                                        badge: .local,
                                        isProcessing: memo.isProcessingSummary,
                                        hasContent: memo.summary != nil && !memo.summary!.isEmpty,
                                        isAvailable: memo.currentTranscript != nil
                                    ) {
                                        generateSummary()
                                    }
                                }

                                // Remote: Tasks (Mac workflow)
                                QuickActionButton(
                                    icon: "checklist",
                                    label: "Tasks",
                                    badge: .remote,
                                    isProcessing: memo.isProcessingTasks,
                                    hasContent: memo.tasks != nil && !memo.tasks!.isEmpty,
                                    isAvailable: memo.macReceivedAt != nil
                                ) {
                                    // View tasks if available
                                }

                                // Remote: Reminders (Mac workflow)
                                QuickActionButton(
                                    icon: "bell",
                                    label: "Reminders",
                                    badge: .remote,
                                    isProcessing: memo.isProcessingReminders,
                                    hasContent: memo.reminders != nil && !memo.reminders!.isEmpty,
                                    isAvailable: memo.macReceivedAt != nil
                                ) {
                                    // View reminders if available
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)

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
                // Fetch latest from CloudKit
                fetchLatestFromCloudKit()
            }
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
        formatter.dateStyle = .long
        formatter.timeStyle = .short
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
        let predicate = NSPredicate(format: "CD_id == %@", memoId as CVarArg)
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

                    if didUpdate {
                        try? memo.managedObjectContext?.save()
                        AppLogger.persistence.info("Updated memo from CloudKit: cloud=\(memo.cloudSyncedAt != nil), mac=\(memo.macReceivedAt != nil), summary=\(memo.summary != nil)")
                    }
                }

                // Also fetch workflow runs for this memo
                self.fetchWorkflowRuns(memoId: memoId, zoneID: zoneID, privateDB: privateDB)

            case .failure(let error):
                AppLogger.persistence.error("CloudKit fetch failed: \(error.localizedDescription)")
            }
        }
    }

    /// Fetch workflow runs from CloudKit for this memo
    private func fetchWorkflowRuns(memoId: UUID, zoneID: CKRecordZone.ID, privateDB: CKDatabase) {
        // WorkflowRun records are linked via CD_memo relationship
        // Query all WorkflowRun records and filter by memo relationship
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "CD_WorkflowRun", predicate: predicate)

        privateDB.fetch(withQuery: query, inZoneWith: zoneID) { result in
            switch result {
            case .success(let (matchResults, _)):
                DispatchQueue.main.async {
                    guard let context = self.memo.managedObjectContext else { return }

                    // Get existing workflow run IDs to avoid duplicates
                    let existingIds = (self.memo.workflowRuns as? Set<WorkflowRun>)?.compactMap { $0.id } ?? []

                    for matchResult in matchResults {
                        guard case .success(let record) = matchResult.1 else { continue }

                        // Check if this run belongs to our memo via the reference
                        guard record["CD_memo"] is CKRecord.Reference else { continue }

                        // The reference recordID contains the memo's CloudKit record name
                        // We need to match it - for Core Data + CloudKit, the record name format varies
                        // Try matching by checking if the workflow run's memo reference points to a record with our memo's ID

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

                        AppLogger.persistence.info("Added workflow run: \(workflowRun.workflowName ?? "unknown")")
                    }

                    try? context.save()
                }

            case .failure(let error):
                AppLogger.persistence.debug("WorkflowRun fetch: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Quick Action Button (compact, with local/remote badge)

enum ActionBadge {
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

    private var badgeIcon: String {
        badge == .local ? "apple.intelligence" : "desktopcomputer"
    }

    private var isDisabled: Bool {
        isProcessing || (!hasContent && !isAvailable)
    }

    private var statusColor: Color {
        if hasContent { return .success }
        if isAvailable { return badge == .local ? .active : .blue }
        return .textTertiary.opacity(0.4)
    }

    var body: some View {
        Button(action: {
            if hasContent {
                showingDetail = true
            } else if isAvailable && !isProcessing {
                action()
            }
        }) {
            VStack(spacing: 3) {
                // Icon
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(statusColor)

                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.4)
                    }
                }
                .frame(width: 24, height: 24)

                // Label
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(hasContent ? .textPrimary : (isAvailable ? .textSecondary : .textTertiary.opacity(0.5)))
                    .lineLimit(1)

                // Status dot
                Circle()
                    .fill(hasContent ? Color.success : (isProcessing ? Color.transcribing : Color.clear))
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(hasContent ? statusColor.opacity(0.08) : Color.surfaceSecondary.opacity(isDisabled ? 0.5 : 1))
            .cornerRadius(CornerRadius.sm)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(hasContent ? statusColor.opacity(0.3) : Color.borderPrimary.opacity(isDisabled ? 0.2 : 0.5), lineWidth: 0.5)
            )
            .opacity(isDisabled && !hasContent ? 0.5 : 1)
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

// MARK: - Workflow Run Row
struct WorkflowRunRow: View {
    let run: WorkflowRun
    @State private var showCopied = false
    @State private var showDetails = false

    private var statusColor: Color {
        switch run.status {
        case "completed": return .success
        case "failed": return .red
        case "running": return .transcribing
        default: return .textTertiary
        }
    }

    private var formattedDate: String {
        guard let date = run.runDate else { return "Unknown" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header: Workflow name + timestamp
            HStack {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: run.workflowIcon ?? "wand.and.stars")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(statusColor)

                    Text(run.workflowName ?? "Workflow")
                        .font(.techLabel)
                        .tracking(1)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                Text(formattedDate)
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
            }

            // Output - primary content, tap to copy
            if let output = run.output, !output.isEmpty {
                Button(action: {
                    UIPasteboard.general.string = output
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
                        Text(output)
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

            // Details toggle - provider/model info
            if let provider = run.providerName, let model = run.modelId {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showDetails.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                        Text(showDetails ? "HIDE DETAILS" : "DETAILS")
                            .font(.techLabelSmall)
                            .tracking(0.5)
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundColor(.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())

                if showDetails {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                        Text("\(provider) · \(model)")
                            .font(.techLabelSmall)
                    }
                    .foregroundColor(.textTertiary)
                    .padding(.leading, Spacing.xs)
                }
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(statusColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}
