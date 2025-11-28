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
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var showingSummary = false
    @State private var showingTasks = false
    @State private var showingReminders = false
    @State private var showingShare = false

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

                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        // Header: Title + Metadata
                        VStack(spacing: Spacing.sm) {
                            // Title
                            if isEditing {
                                TextField("Title", text: $editedTitle)
                                    .font(.bodyMedium)
                                    .padding(Spacing.sm)
                                    .background(Color.surfaceSecondary)
                                    .cornerRadius(CornerRadius.sm)
                                    .padding(.horizontal, Spacing.md)
                            } else {
                                Text(memoTitle)
                                    .font(.bodyLarge)
                                    .foregroundColor(.textPrimary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, Spacing.md)
                            }

                            // Metadata row - tactical
                            HStack(spacing: Spacing.xs) {
                                Text(formatDate(memoCreatedAt).uppercased())
                                    .font(.techLabelSmall)
                                    .tracking(1)

                                Text("·")
                                    .font(.labelSmall)

                                Text(formatDuration(memo.duration))
                                    .font(.monoSmall)

                                // Sync status: cloud + mac (detailed view)
                                if memo.cloudSyncedAt != nil {
                                    Text("·")
                                        .font(.labelSmall)

                                    HStack(spacing: 3) {
                                        Image(systemName: "cloud.fill")
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
                        .padding(.top, Spacing.md)

                        // Waveform
                        if let waveformData = memo.waveformData,
                           let levels = try? JSONDecoder().decode([Float].self, from: waveformData) {
                            VStack(spacing: Spacing.xs) {
                                WaveformView(
                                    levels: levels,
                                    height: 100,
                                    color: isPlaying ? .active : .textTertiary
                                )
                                .padding(.horizontal, Spacing.md)
                                .background(Color.surfaceSecondary)
                                .cornerRadius(CornerRadius.sm)
                                .padding(.horizontal, Spacing.md)

                                Text("[\(levels.count) SAMPLES]")
                                    .font(.techLabelSmall)
                                    .tracking(1)
                                    .foregroundColor(.textTertiary)
                            }
                        }

                        // Playback controls
                        VStack(spacing: Spacing.md) {
                            // Progress slider - always show when we have audio
                            VStack(spacing: Spacing.xxs) {
                                Slider(
                                    value: Binding(
                                        get: { isPlaying ? audioPlayer.currentTime : 0 },
                                        set: { if isPlaying { audioPlayer.seek(to: $0) } }
                                    ),
                                    in: 0...max(isPlaying ? audioPlayer.duration : memo.duration, 1)
                                )
                                .tint(isPlaying ? .active : .textTertiary)
                                .disabled(!isPlaying)

                                HStack {
                                    Text(formatDuration(isPlaying ? audioPlayer.currentTime : 0))
                                        .font(.monoSmall)
                                        .foregroundColor(.textSecondary)

                                    Spacer()

                                    Text(formatDuration(isPlaying ? audioPlayer.duration : memo.duration))
                                        .font(.monoSmall)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                            .padding(.horizontal, Spacing.md)

                            // Play/Pause button
                            Button(action: togglePlayback) {
                                ZStack {
                                    // Glow when playing
                                    if isPlaying {
                                        Circle()
                                            .fill(Color.active)
                                            .frame(width: 72, height: 72)
                                            .blur(radius: 15)
                                            .opacity(0.4)
                                    }

                                    Circle()
                                        .fill(isPlaying ? Color.active : Color.surfaceSecondary)
                                        .frame(width: 72, height: 72)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(isPlaying ? Color.active : Color.borderPrimary, lineWidth: 2)
                                        )

                                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundColor(isPlaying ? .white : .textPrimary)
                                        .offset(x: isPlaying ? 0 : 2) // Optical centering for play icon
                                }
                            }
                        }

                        // Transcription section
                        if memo.isTranscribing {
                            HStack(spacing: Spacing.xs) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("PROCESSING TRANSCRIPT...")
                                    .font(.techLabel)
                                    .tracking(1)
                                    .foregroundColor(.transcribing)
                            }
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity)
                            .background(Color.transcribing.opacity(0.08))
                            .cornerRadius(CornerRadius.sm)
                            .padding(.horizontal, Spacing.md)
                        } else if let transcription = memo.transcription {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Text("TRANSCRIPT")
                                    .font(.techLabel)
                                    .tracking(2)
                                    .foregroundColor(.textSecondary)

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
                                            .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                                    )
                            }
                            .padding(.horizontal, Spacing.md)

                            // Workflow Actions
                            VStack(spacing: Spacing.xs) {
                                Text("ACTIONS")
                                    .font(.techLabel)
                                    .tracking(2)
                                    .foregroundColor(.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                LazyVGrid(columns: [
                                    GridItem(.flexible(), spacing: Spacing.xs),
                                    GridItem(.flexible(), spacing: Spacing.xs)
                                ], spacing: Spacing.xs) {
                                    ActionButton(
                                        icon: "list.bullet.clipboard",
                                        title: "SUMMARIZE",
                                        isProcessing: memo.isProcessingSummary,
                                        isCompleted: memo.summary != nil,
                                        action: { if memo.summary != nil { showingSummary = true } }
                                    )

                                    ActionButton(
                                        icon: "checkmark.square",
                                        title: "TASKIFY",
                                        isProcessing: memo.isProcessingTasks,
                                        isCompleted: memo.tasks != nil,
                                        action: { if memo.tasks != nil { showingTasks = true } }
                                    )

                                    ActionButton(
                                        icon: "bell",
                                        title: "REMIND",
                                        isProcessing: memo.isProcessingReminders,
                                        isCompleted: memo.reminders != nil,
                                        action: { if memo.reminders != nil { showingReminders = true } }
                                    )

                                    ActionButton(
                                        icon: "square.and.arrow.up",
                                        title: "SHARE",
                                        isProcessing: false,
                                        isCompleted: false,
                                        action: { showingShare = true }
                                    )
                                }
                            }
                            .padding(.horizontal, Spacing.md)
                        }

                        Spacer(minLength: Spacing.xxl)
                    }
                    .padding(.vertical, Spacing.md)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
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
                        if isEditing {
                            saveTitle()
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
                        if isEditing {
                            saveTitle()
                        } else {
                            editedTitle = memoTitle
                            isEditing = true
                        }
                    }) {
                        Text(isEditing ? "SAVE" : "EDIT")
                            .font(.techLabel)
                            .tracking(1)
                            .foregroundColor(.active)
                    }
                }
            }
            .sheet(isPresented: $showingSummary) {
                WorkflowActionSheet(
                    memo: memo,
                    title: "SUMMARY",
                    icon: "list.bullet.clipboard",
                    actionType: .summarize
                )
            }
            .sheet(isPresented: $showingTasks) {
                WorkflowActionSheet(
                    memo: memo,
                    title: "TASKS",
                    icon: "checkmark.square",
                    actionType: .taskify
                )
            }
            .sheet(isPresented: $showingReminders) {
                WorkflowActionSheet(
                    memo: memo,
                    title: "REMINDERS",
                    icon: "bell",
                    actionType: .reminders
                )
            }
            .sheet(isPresented: $showingShare) {
                ShareSheet(items: [memo.transcription ?? ""])
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

    private func saveTitle() {
        memo.title = editedTitle
        try? memo.managedObjectContext?.save()
        isEditing = false
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
                    AppLogger.persistence.info("📥 No CloudKit record found for memo")
                    return
                }

                // Update local memo with CloudKit values
                DispatchQueue.main.async {
                    if let cloudSyncedAt = record["CD_cloudSyncedAt"] as? Date {
                        memo.cloudSyncedAt = cloudSyncedAt
                    }
                    if let macReceivedAt = record["CD_macReceivedAt"] as? Date {
                        memo.macReceivedAt = macReceivedAt
                    }
                    try? memo.managedObjectContext?.save()
                    AppLogger.persistence.info("📥 Updated memo from CloudKit: cloud=\(memo.cloudSyncedAt != nil), mac=\(memo.macReceivedAt != nil)")
                }

            case .failure(let error):
                AppLogger.persistence.error("📥 CloudKit fetch failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Action Button Component
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
