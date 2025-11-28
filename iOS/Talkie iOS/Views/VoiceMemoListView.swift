//
//  VoiceMemoListView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData

enum SortOption: String, CaseIterable {
    case dateNewest = "Newest First"
    case dateOldest = "Oldest First"
    case title = "Title (A-Z)"
    case duration = "Duration"

    var descriptor: NSSortDescriptor {
        switch self {
        case .dateNewest:
            return NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        case .dateOldest:
            return NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: true)
        case .title:
            return NSSortDescriptor(keyPath: \VoiceMemo.title, ascending: true)
        case .duration:
            return NSSortDescriptor(keyPath: \VoiceMemo.duration, ascending: false)
        }
    }

    var menuIcon: String {
        switch self {
        case .dateNewest: return "arrow.down"
        case .dateOldest: return "arrow.up"
        case .title: return "textformat"
        case .duration: return "clock"
        }
    }
}

struct VoiceMemoListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \VoiceMemo.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \VoiceMemo.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var allVoiceMemos: FetchedResults<VoiceMemo>

    @StateObject private var audioPlayer = AudioPlayerManager()
    @StateObject private var pushToTalkRecorder = AudioRecorderManager()
    @State private var showingRecordingView = false
    @State private var displayLimit = 10
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var isPushToTalkActive = false
    @State private var pushToTalkScale: CGFloat = 1.0

    private var filteredMemos: [VoiceMemo] {
        if searchText.isEmpty {
            return Array(allVoiceMemos)
        }
        return allVoiceMemos.filter { memo in
            let titleMatch = memo.title?.localizedCaseInsensitiveContains(searchText) ?? false
            let transcriptionMatch = memo.transcription?.localizedCaseInsensitiveContains(searchText) ?? false
            return titleMatch || transcriptionMatch
        }
    }

    private var voiceMemos: [VoiceMemo] {
        Array(filteredMemos.prefix(displayLimit))
    }

    private var hasMore: Bool {
        filteredMemos.count > displayLimit
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Color.surfacePrimary
                    .ignoresSafeArea()

                if allVoiceMemos.isEmpty {
                    // Empty state - no memos at all
                    EmptyStateView(onRecordTapped: {
                        showingRecordingView = true
                    })
                } else {
                    // List of voice memos
                    VStack(spacing: 0) {
                        // Search bar
                        HStack(spacing: Spacing.sm) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textTertiary)

                                TextField("SEARCH", text: $searchText)
                                    .font(.bodySmall)
                                    .foregroundColor(.textPrimary)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .onTapGesture {
                                        isSearching = true
                                    }

                                if !searchText.isEmpty {
                                    Button(action: {
                                        searchText = ""
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(Color.surfaceSecondary)
                            .cornerRadius(CornerRadius.sm)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                            )

                            if isSearching {
                                Button(action: {
                                    searchText = ""
                                    isSearching = false
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }) {
                                    Text("ESC")
                                        .font(.techLabel)
                                        .tracking(1)
                                        .foregroundColor(.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)

                        // Results count when searching
                        if !searchText.isEmpty {
                            HStack {
                                Text("\(filteredMemos.count) RESULT\(filteredMemos.count == 1 ? "" : "S")")
                                    .font(.techLabelSmall)
                                    .tracking(1)
                                    .foregroundColor(.textTertiary)
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.bottom, Spacing.xs)
                        }

                    if voiceMemos.isEmpty && !searchText.isEmpty {
                        // No search results
                        VStack(spacing: Spacing.md) {
                            Spacer()
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(.textTertiary)
                            Text("NO MATCHES")
                                .font(.techLabel)
                                .tracking(2)
                                .foregroundColor(.textSecondary)
                            Text("Try a different search term")
                                .font(.bodySmall)
                                .foregroundColor(.textTertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.xxl)
                    }

                    List {
                        ForEach(voiceMemos) { memo in
                            VoiceMemoRow(
                                memo: memo,
                                audioPlayer: audioPlayer,
                                onDelete: { deleteMemo(memo) }
                            )
                            .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.md, bottom: Spacing.xs, trailing: Spacing.md))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: deleteMemos)
                        .onMove(perform: moveMemos)

                        // Load More button
                        if hasMore {
                            Button(action: {
                                withAnimation(TalkieAnimation.spring) {
                                    displayLimit += 10
                                }
                            }) {
                                HStack(spacing: Spacing.xs) {
                                    Spacer()
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("LOAD +\(min(10, allVoiceMemos.count - displayLimit))")
                                        .font(.techLabel)
                                        .tracking(1)
                                    Spacer()
                                }
                                .foregroundColor(.textSecondary)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.surfaceSecondary)
                                .cornerRadius(CornerRadius.sm)
                                .overlay(
                                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                                        .strokeBorder(Color.borderPrimary, lineWidth: 0.5)
                                )
                            }
                            .listRowInsets(EdgeInsets(top: Spacing.xs, leading: Spacing.md, bottom: Spacing.xs, trailing: Spacing.md))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }

                        // Small bottom padding so last item doesn't touch record area
                        Color.clear
                            .frame(height: Spacing.sm)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await refreshMemos()
                    }
                    } // end VStack

                    // Record button area with distinct background
                    VStack(spacing: 0) {
                        Spacer()

                        // Record area container - expands for push-to-talk
                        VStack(spacing: 0) {
                            // Push-to-talk visualization when active
                            if isPushToTalkActive {
                                VStack(spacing: Spacing.sm) {
                                    // Quick memo indicator
                                    Text("QUICK MEMO")
                                        .font(.techLabelSmall)
                                        .tracking(2)
                                        .foregroundColor(.textTertiary)

                                    // Live waveform - particles style
                                    LiveWaveformView(
                                        levels: pushToTalkRecorder.audioLevels,
                                        height: 60,
                                        color: .recording,
                                        style: .particles
                                    )
                                    .padding(.horizontal, Spacing.sm)
                                    .background(Color.surfacePrimary.opacity(0.5))
                                    .cornerRadius(CornerRadius.md)
                                    .padding(.horizontal, Spacing.lg)

                                    // Duration
                                    Text(formatPushToTalkDuration(pushToTalkRecorder.recordingDuration))
                                        .font(.monoMedium)
                                        .foregroundColor(.textPrimary)

                                    Text("RELEASE TO SAVE")
                                        .font(.techLabelSmall)
                                        .tracking(1)
                                        .foregroundColor(.textTertiary)
                                }
                                .padding(.top, Spacing.md)
                                .padding(.bottom, Spacing.xs)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            // Centered record button - smaller, minimal glow
                            ZStack {
                                // Subtle glow - only when recording
                                if isPushToTalkActive {
                                    Circle()
                                        .fill(Color.recording)
                                        .frame(width: 60, height: 60)
                                        .blur(radius: 20)
                                        .opacity(0.6)
                                }

                                // Main button
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.recording, Color.recordingGlow],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 52, height: 52)
                                    .scaleEffect(pushToTalkScale)

                                // Icon changes based on state
                                if isPushToTalkActive {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.white)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "mic.fill")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.white)
                                }
                            }
                            .scaleEffect(isPushToTalkActive ? 1.15 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPushToTalkActive)
                            .onTapGesture {
                                // Short tap opens the sheet
                                showingRecordingView = true
                            }
                            .onLongPressGesture(minimumDuration: 0.2, pressing: { pressing in
                                if pressing {
                                    // Started long press - begin push-to-talk
                                    startPushToTalk()
                                } else if isPushToTalkActive {
                                    // Released - stop and save
                                    stopPushToTalk()
                                }
                            }, perform: {
                                // Long press completed (finger still down) - do nothing, handled in pressing
                            })
                            .padding(.vertical, Spacing.md)
                        }
                        .frame(maxWidth: .infinity)
                        .background(
                            Color.surfaceSecondary.opacity(0.85)
                        )
                        .background(
                            // Top edge highlight
                            VStack {
                                Rectangle()
                                    .fill(Color.borderPrimary)
                                    .frame(height: 0.5)
                                Spacer()
                            }
                        )
                    }
                    .animation(.easeInOut(duration: 0.2), value: isPushToTalkActive)
                }
            }
            .navigationTitle("TALKIE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surfacePrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("TALKIE")
                            .font(.techLabel)
                            .tracking(2)
                            .foregroundColor(.textPrimary)
                        Text("\(allVoiceMemos.count) MEMOS")
                            .font(.techLabelSmall)
                            .tracking(1)
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .sheet(isPresented: $showingRecordingView) {
                RecordingView()
                    .environment(\.managedObjectContext, viewContext)
            }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - Pull to Refresh

    private func refreshMemos() async {
        AppLogger.persistence.info("📲 Pull-to-refresh - refreshing all memos")

        // Refresh all registered VoiceMemo objects to get latest from store
        await MainActor.run {
            for object in viewContext.registeredObjects {
                if object is VoiceMemo {
                    viewContext.refresh(object, mergeChanges: true)
                }
            }
        }

        // Small delay so user sees the refresh indicator
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private func deleteMemo(_ memo: VoiceMemo) {
        withAnimation {
            // Delete audio file
            if let filename = memo.fileURL {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let filePath = documentsPath.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: filePath.path) {
                    try? FileManager.default.removeItem(at: filePath)
                }
            }

            viewContext.delete(memo)

            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                AppLogger.persistence.error("Error deleting memo: \(nsError.localizedDescription)")
            }
        }
    }

    private func deleteMemos(offsets: IndexSet) {
        withAnimation {
            offsets.map { voiceMemos[$0] }.forEach { memo in
                deleteMemo(memo)
            }
        }
    }

    private func moveMemos(from source: IndexSet, to destination: Int) {
        // Get memos to move
        var memos = voiceMemos
        memos.move(fromOffsets: source, toOffset: destination)

        // Update sortOrder for all memos
        for (index, memo) in memos.enumerated() {
            memo.sortOrder = Int32(index)
        }

        do {
            try viewContext.save()
        } catch {
            AppLogger.persistence.error("Error moving memos: \(error.localizedDescription)")
        }
    }

    // MARK: - Push-to-Talk

    private func startPushToTalk() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            isPushToTalkActive = true
            pushToTalkScale = 0.9
        }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        pushToTalkRecorder.startRecording()
    }

    private func stopPushToTalk() {
        pushToTalkRecorder.stopRecording()

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        // Save if we have a recording
        if let url = pushToTalkRecorder.currentRecordingURL,
           pushToTalkRecorder.recordingDuration > 0.5 { // Minimum 0.5s to save
            savePushToTalkRecording(url: url)
        } else {
            // Too short, delete it
            if let url = pushToTalkRecorder.currentRecordingURL {
                try? FileManager.default.removeItem(at: url)
            }
        }

        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            isPushToTalkActive = false
            pushToTalkScale = 1.0
        }
    }

    private func savePushToTalkRecording(url: URL) {
        let newMemo = VoiceMemo(context: viewContext)
        newMemo.id = UUID()
        newMemo.title = "Quick memo \(formatPushToTalkDate(Date()))"
        newMemo.createdAt = Date()
        newMemo.duration = pushToTalkRecorder.recordingDuration
        newMemo.fileURL = url.lastPathComponent
        newMemo.isTranscribing = false
        newMemo.sortOrder = Int32(Date().timeIntervalSince1970 * -1)

        // Load audio data
        do {
            let audioData = try Data(contentsOf: url)
            newMemo.audioData = audioData
        } catch {
            AppLogger.recording.warning("Failed to load audio data: \(error.localizedDescription)")
        }

        // Save waveform
        if let waveformData = try? JSONEncoder().encode(pushToTalkRecorder.audioLevels) {
            newMemo.waveformData = waveformData
        }

        do {
            try viewContext.save()
            AppLogger.persistence.info("Push-to-talk memo saved")

            let memoObjectID = newMemo.objectID

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                if let savedMemo = viewContext.object(with: memoObjectID) as? VoiceMemo {
                    TranscriptionService.shared.transcribeVoiceMemo(savedMemo, context: viewContext)
                }
            }
        } catch {
            AppLogger.persistence.error("Error saving push-to-talk memo: \(error.localizedDescription)")
        }
    }

    private func formatPushToTalkDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatPushToTalkDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    VoiceMemoListView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
