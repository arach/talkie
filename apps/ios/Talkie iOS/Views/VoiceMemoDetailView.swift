//
//  VoiceMemoDetailView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CloudKit
import CoreData
import EventKit
import Photos
import PhotosUI
import UIKit
import TalkieMobileKit

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
    @State private var macWorkflowToastSubtitle: String = ""
    @State private var showingCopiedToast = false
    @State private var isTranscriptExpanded = false
    @State private var auth = AuthManager.shared
    @State private var bridgeManager = BridgeManager.shared
    @State private var liveWorkflowStatuses: [String: LiveWorkflowStatus] = [:]
    @State private var liveWorkflowPollingTasks: [String: Task<Void, Never>] = [:]
    @State private var pinnedMacWorkflows: [TalkieAppConfiguration.PinnedWorkflow] = TalkieAppSettings.shared.pinnedMacWorkflows
    @State private var showingAttachmentPickerSheet = false
    @State private var showingAttachmentPhotoPicker = false
    @State private var showingAttachmentCamera = false
    @State private var selectedAttachmentItems: [PhotosPickerItem] = []
    @State private var memoAttachments: [MemoImageAttachment] = []
    @State private var selectedAttachmentPreview: MemoImageAttachment?
    @State private var isImportingAttachments = false
    @State private var attachmentError: String?
    @State private var isSendingAttachmentsToMac = false
    @State private var lastSentAttachmentFingerprint: String?
    @State private var showingSendToMacAlert = false
    @State private var sendToMacAlertTitle = ""
    @State private var sendToMacAlertMessage = ""
    @State private var recentAttachmentAssets: [PHAsset] = []
    @State private var attachmentPhotoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @State private var hasLoadedRecentAttachmentAssets = false
    @State private var showingOCRPhotoPicker = false
    @State private var ocrPhotoPickerItems: [PhotosPickerItem] = []
    @State private var isRunningOCR = false
    @State private var ocrResultText: String?
    @State private var showingAgentSheet = false
    @State private var showingCLISheet = false
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var aiService = OnDeviceAIService.shared
    @StateObject private var sidecarStore = RecordingSidecarStore.shared
    private let liveWorkflowClient = LiveWorkflowClient()
    private let memoAttachmentStore = MemoAttachmentStore.shared

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

    private var memoSidecarRequests: [RecordingSidecarRequest] {
        guard let memoId = memo.id?.uuidString else { return [] }
        return sidecarStore.requests(for: memoId)
    }

    private var hasQueuedSidecarRequests: Bool {
        memoSidecarRequests.contains { $0.status == .queued }
    }

    private var hasFailedSidecarRequests: Bool {
        memoSidecarRequests.contains { $0.status == .failed }
    }

    private var isAnySidecarProcessing: Bool {
        memoSidecarRequests.contains { $0.status == .processing }
    }

    private var canResolveSidecars: Bool {
        memo.currentTranscript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && (hasQueuedSidecarRequests || hasFailedSidecarRequests)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.surfacePrimary
                    .ignoresSafeArea()

                ScrollViewReader { scrollProxy in
                    detailScrollView(scrollProxy: scrollProxy)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .photosPicker(
                isPresented: $showingAttachmentPhotoPicker,
                selection: $selectedAttachmentItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .alert("Delete Memo?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteMemo()
                }
            } message: {
                Text("This will permanently delete this memo and its recordings. This action cannot be undone.")
            }
            .alert(sendToMacAlertTitle, isPresented: $showingSendToMacAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(sendToMacAlertMessage)
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
            .sheet(isPresented: $showingAttachmentCamera) {
                CameraImagePicker { image in
                    Task {
                        await importCapturedImage(image)
                    }
                }
            }
            .sheet(isPresented: $showingAttachmentPickerSheet) {
                MemoAttachmentPickerSheet(
                    recentAssets: recentAttachmentAssets,
                    photoAuthorizationStatus: attachmentPhotoAuthorizationStatus,
                    onChooseFromLibrary: {
                        showingAttachmentPickerSheet = false
                        showingAttachmentPhotoPicker = true
                    },
                    onTakePhoto: {
                        showingAttachmentPickerSheet = false
                        showingAttachmentCamera = true
                    },
                    onScanText: {
                        showingAttachmentPickerSheet = false
                        showingOCRPhotoPicker = true
                    },
                    onSelectRecentAsset: { asset in
                        showingAttachmentPickerSheet = false
                        Task {
                            await importRecentAttachmentAsset(asset)
                        }
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .photosPicker(
                isPresented: $showingOCRPhotoPicker,
                selection: $ocrPhotoPickerItems,
                maxSelectionCount: 1,
                matching: .images
            )
            .onChange(of: ocrPhotoPickerItems) { _, newItems in
                guard let item = newItems.first else { return }
                ocrPhotoPickerItems = []
                Task {
                    await performOCR(from: item)
                }
            }
            .alert("Scanned Text", isPresented: Binding(
                get: { ocrResultText != nil },
                set: { if !$0 { ocrResultText = nil } }
            )) {
                Button("Append to Notes") {
                    appendOCRTextToNotes()
                }
                Button("Cancel", role: .cancel) {
                    ocrResultText = nil
                }
            } message: {
                if let ocrResultText {
                    let preview = ocrResultText.prefix(200)
                    Text(preview + (ocrResultText.count > 200 ? "..." : ""))
                }
            }
            .sheet(isPresented: $showingVersionHistory) {
                TranscriptVersionHistorySheet(memo: memo)
            }
            .sheet(isPresented: $showingAgentSheet) {
                MemoAgentSheet(
                    memoTitle: memoTitle,
                    memoTranscript: memo.transcription ?? "",
                    memoId: memo.id?.uuidString
                )
            }
            .sheet(isPresented: $showingCLISheet) {
                MemoCLISheet(
                    memoTitle: memoTitle,
                    memoId: memo.id?.uuidString
                )
            }
            .sheet(item: $selectedAttachmentPreview) { attachment in
                NavigationStack {
                    ZStack {
                        Color.black.ignoresSafeArea()

                        if let image = memoAttachmentStore.image(for: attachment) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(Spacing.md)
                        } else {
                            ContentUnavailableView(
                                "Image unavailable",
                                systemImage: "photo.slash",
                                description: Text("This attachment could not be loaded.")
                            )
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") {
                                selectedAttachmentPreview = nil
                            }
                            .foregroundColor(.white)
                        }
                    }
                    .toolbarBackground(.hidden, for: .navigationBar)
                }
            }
            .task(id: memo.currentTranscript ?? "") {
                await maybeProcessSidecarsAutomatically()
            }
            .onAppear {
                refreshPinnedMacWorkflows()
                refreshMemoAttachments()
                DirectMacRegistry.shared.refresh()
                if bridgeManager.shouldConnect {
                    Task {
                        await bridgeManager.connect()
                    }
                }
                // Fetch latest from CloudKit
                fetchLatestFromCloudKit()
                refreshLiveWorkflowRuns()

                // Release memo's faulted data when playback finishes to free memory
                audioPlayer.onPlaybackFinished = { [weak memo] in
                    guard let memo = memo else { return }
                    PersistenceController.releaseMemoData(memo, context: viewContext)
                }
            }
            .onDisappear {
                // Stop playback and release memo data when leaving the view
                audioPlayer.stopPlayback()
                audioPlayer.onPlaybackFinished = nil
                cancelLiveWorkflowPolling()
                PersistenceController.releaseMemoData(memo, context: viewContext)
            }
            .onChange(of: selectedAttachmentItems) { _, newItems in
                guard !newItems.isEmpty else { return }

                Task {
                    await importSelectedAttachmentItems(newItems)
                }
            }
            .onChange(of: showingAttachmentPickerSheet) { _, isPresented in
                if isPresented {
                    loadRecentAttachmentAssetsIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                refreshPinnedMacWorkflows()
            }
            .overlay {
                // Rising toast for Mac workflow
                if showingMacWorkflowToast {
                    RisingToast(isShowing: $showingMacWorkflowToast) {
                        MacWorkflowToast(
                            workflowName: tappedWorkflowName,
                            subtitle: macWorkflowToastSubtitle
                        )
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
                if !ProcessInfo.processInfo.arguments.contains("-FASTLANE_SNAPSHOT") {
                DebugToolbarOverlay(
                    content: {
                        DetailViewDebugContent(
                            memo: memo,
                            onTriggerToast: {
                                presentMacWorkflowToast(
                                    workflowName: "Test Workflow",
                                    subtitle: "Queued for your next available Mac."
                                )
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
                        info["Synced"] = memo.cloudSyncedAt != nil ? "Yes" : "No"
                        return info
                    }
                )
                }
            }
            #endif
        }
    }

    @ViewBuilder
    private func detailScrollView(scrollProxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                detailHeaderSection()
                playbackSection()
                transcriptSection()
                quickActionsSection
                memoAttachmentsSection
                macActionsSection
                activitySection()
                deleteMemoSection()

                Spacer(minLength: Spacing.xxl)
            }
            .padding(.vertical, Spacing.md)
        }
        .onAppear {
            if scrollToActivity {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        scrollProxy.scrollTo("activity-section", anchor: .top)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailHeaderSection() -> some View {
        VStack(spacing: Spacing.xs) {
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

                if memo.hasLocation {
                    Text("|")
                        .font(.system(size: 9, weight: .ultraLight))
                        .opacity(0.5)

                    HStack(spacing: 2) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9, weight: .medium))
                        Text(formatCoordinates(lat: memo.latitude, lon: memo.longitude))
                            .font(.techLabelSmall)
                            .tracking(0.5)
                    }
                }

                if let tz = memo.timezone, tz != TimeZone.current.identifier {
                    Text("|")
                        .font(.system(size: 9, weight: .ultraLight))
                        .opacity(0.5)
                    Text(tz.components(separatedBy: "/").last?.replacingOccurrences(of: "_", with: " ") ?? tz)
                        .font(.techLabelSmall)
                        .tracking(0.5)
                }

                if memo.cloudSyncedAt != nil || memo.macReceivedAt != nil {
                    Text("|")
                        .font(.system(size: 9, weight: .ultraLight))
                        .opacity(0.5)

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
            }
            .foregroundColor(.textSecondary)
        }
        .padding(.top, Spacing.xs)
    }

    @ViewBuilder
    private func playbackSection() -> some View {
        VStack(spacing: Spacing.xs) {
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

            HStack {
                Text(formatDuration(isPlaying ? audioPlayer.currentTime : 0))
                    .font(.monoSmall)
                    .foregroundColor(.textTertiary)
                    .frame(width: 40, alignment: .leading)

                Spacer()

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
                                    .strokeBorder(
                                        isPlaying ? Color.active : Color.borderPrimary,
                                        lineWidth: 1.5
                                    )
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
    }

    @ViewBuilder
    private func transcriptSection() -> some View {
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
                HStack {
                    Text("TRANSCRIPT")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textSecondary)

                    if isEditMode && !isEditingTranscript {
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.active)
                    }

                    Spacer()

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

                if isEditingTranscript {
                    TranscriptEditorView(
                        text: $editedTranscript,
                        onCancel: {
                            isEditingTranscript = false
                            editedTranscript = ""
                        },
                        onSave: saveTranscriptEdit
                    )
                } else {
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
                            .strokeBorder(
                                isEditMode ? Color.active.opacity(0.5) : Color.borderPrimary,
                                lineWidth: isEditMode ? 1 : 0.5
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isEditMode {
                            editedTranscript = transcription
                            isEditingTranscript = true
                        }
                    }
                    .contextMenu {
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
    }

    @ViewBuilder
    private func activitySection() -> some View {
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

                if let workflowRuns = memo.workflowRuns as? Set<WorkflowRun>, !workflowRuns.isEmpty {
                    ForEach(
                        workflowRuns.sorted { ($0.runDate ?? .distantPast) > ($1.runDate ?? .distantPast) },
                        id: \.id
                    ) { run in
                        WorkflowRunRow(run: run)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    @ViewBuilder
    private func deleteMemoSection() -> some View {
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
                // Readout
                QuickActionButton(
                    icon: SpeechSynthesisService.shared.isSpeaking ? "stop.fill" : "speaker.wave.2.fill",
                    label: SpeechSynthesisService.shared.isSpeaking ? "Stop" : "Read",
                    badge: .none,
                    isProcessing: false,
                    hasContent: SpeechSynthesisService.shared.isSpeaking,
                    isAvailable: memo.currentTranscript != nil
                ) {
                    if let text = memo.currentTranscript {
                        SpeechSynthesisService.shared.toggleReadout(text)
                    }
                }

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

    private var sidecarSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("SIDECAR")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textSecondary)

                Spacer()

                if canResolveSidecars {
                    Button {
                        Task {
                            await resolveSidecars(retryFailed: true)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isAnySidecarProcessing {
                                ProgressView()
                                    .scaleEffect(0.65)
                            } else {
                                Image(systemName: hasFailedSidecarRequests ? "arrow.clockwise" : "sparkles")
                                    .font(.system(size: 11, weight: .medium))
                            }

                            Text(hasFailedSidecarRequests ? "RETRY" : "RESOLVE")
                                .font(.techLabelSmall)
                                .tracking(1)
                        }
                        .foregroundColor(.textPrimary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(Color.surfaceSecondary)
                        .cornerRadius(CornerRadius.sm)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAnySidecarProcessing)
                }
            }

            if memo.isTranscribing && hasQueuedSidecarRequests {
                Text("Queued sidecars will resolve once transcription finishes.")
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
            } else if !aiService.isAvailable && canResolveSidecars {
                Text("Queued sidecars need Apple Intelligence enabled to resolve on-device.")
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
            }

            ForEach(memoSidecarRequests) { request in
                RecordingSidecarResultCard(request: request)
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private var memoAttachmentsSection: some View {
        MemoAttachmentsSection(
            attachments: memoAttachments,
            imageProvider: { attachment in
                memoAttachmentStore.image(for: attachment)
            },
            onAdd: {
                showingAttachmentPickerSheet = true
            },
            onSelect: { attachment in
                selectedAttachmentPreview = attachment
            },
            onRemove: { attachment in
                removeAttachment(attachment)
            }
        )
        .overlay(alignment: .bottomLeading) {
            if let attachmentError {
                Text(attachmentError)
                    .font(.techLabelSmall)
                    .foregroundColor(.red)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 4)
                    .offset(y: 24)
            }
        }
        .padding(.bottom, attachmentError == nil ? 0 : 24)
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

            // 4-slot action bar: Workflow 1, Workflow 2, Agent, CLI
            HStack(spacing: Spacing.xs) {
                // Slot 1 & 2: Pinned workflows
                let pinned = pinnedMacWorkflows
                if pinned.count >= 1 {
                    QuickActionButton(
                        icon: pinned[0].icon,
                        label: pinned[0].name,
                        badge: .remote,
                        isProcessing: isWorkflowInFlight(workflowId: pinned[0].id),
                        hasContent: hasWorkflowOutput(workflowId: pinned[0].id),
                        isAvailable: auth.isSignedIn && memo.id != nil
                    ) {
                        runPinnedWorkflow(pinned[0])
                    }
                } else {
                    QuickActionButton(
                        icon: "wand.and.stars",
                        label: "Workflow",
                        badge: .remote,
                        isProcessing: false,
                        hasContent: false,
                        isAvailable: false
                    ) { }
                }

                if pinned.count >= 2 {
                    QuickActionButton(
                        icon: pinned[1].icon,
                        label: pinned[1].name,
                        badge: .remote,
                        isProcessing: isWorkflowInFlight(workflowId: pinned[1].id),
                        hasContent: hasWorkflowOutput(workflowId: pinned[1].id),
                        isAvailable: auth.isSignedIn && memo.id != nil
                    ) {
                        runPinnedWorkflow(pinned[1])
                    }
                } else {
                    QuickActionButton(
                        icon: "arrow.triangle.2.circlepath",
                        label: "Workflow",
                        badge: .remote,
                        isProcessing: false,
                        hasContent: false,
                        isAvailable: false
                    ) { }
                }

                // Slot 3: AI Agent
                QuickActionButton(
                    icon: "bubble.left.and.text.bubble.right",
                    label: "Agent",
                    badge: .remote,
                    isProcessing: false,
                    hasContent: memo.id.map { AgentSessionStore.shared.hasConversation(forMemoId: $0.uuidString) } ?? false,
                    isAvailable: bridgeManager.status == .connected
                ) {
                    showingAgentSheet = true
                }

                // Slot 4: CLI
                QuickActionButton(
                    icon: "terminal",
                    label: "CLI",
                    badge: .remote,
                    isProcessing: false,
                    hasContent: false,
                    isAvailable: bridgeManager.status == .connected
                ) {
                    showingCLISheet = true
                }
            }

            if !hasBridgePairingForAttachments && pinnedMacWorkflows.isEmpty {
                Text("Pair your Mac to run workflows, ask the AI agent, and execute CLI commands.")
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.md)
                    .background(Color.surfaceSecondary)
                    .cornerRadius(CornerRadius.sm)
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

    private func isWorkflowInFlight(workflowId: String?) -> Bool {
        guard let workflowId else { return false }
        if liveWorkflowStatuses[workflowId]?.isInFlight == true {
            return true
        }

        guard let uuid = UUID(uuidString: workflowId),
              let runs = memo.workflowRuns as? Set<WorkflowRun> else {
            return false
        }

        return runs.contains { run in
            guard run.workflowId == uuid else { return false }
            return run.status == "queued" || run.status == "claimed" || run.status == "running"
        }
    }

    private func presentMacWorkflowToast(workflowName: String, subtitle: String) {
        tappedWorkflowName = workflowName
        macWorkflowToastSubtitle = subtitle
        showingMacWorkflowToast = true
    }

    private func runPinnedWorkflow(_ workflow: TalkieAppConfiguration.PinnedWorkflow) {
        let workflowName = workflow.name.isEmpty ? "Action" : workflow.name

        guard auth.isSignedIn else {
            presentMacWorkflowToast(
                workflowName: workflowName,
                subtitle: "Sign into Talkie on your iPhone and Mac to run live workflows."
            )
            return
        }

        guard let memoId = memo.id?.uuidString,
              !workflow.id.isEmpty else {
            presentMacWorkflowToast(
                workflowName: workflowName,
                subtitle: "This memo is not ready for live workflow execution yet."
            )
            return
        }

        let workflowId = workflow.id
        liveWorkflowStatuses[workflowId] = .init(runId: nil, status: "queued")
        presentMacWorkflowToast(workflowName: workflowName, subtitle: "Waiting for one of your Macs.")

        Task {
            do {
                guard let authToken = await auth.authToken else {
                    throw LiveWorkflowClient.ClientError.missingAuthToken
                }

                let run = try await liveWorkflowClient.createRun(
                    authToken: authToken,
                    workflowId: workflowId,
                    workflowName: workflowName,
                    workflowIcon: workflow.icon,
                    memoId: memoId,
                    requestedByDeviceId: UIDevice.current.identifierForVendor?.uuidString
                )

                await MainActor.run {
                    upsertLiveWorkflowRun(run)
                    trackLiveWorkflow(run)
                }
            } catch {
                await MainActor.run {
                    liveWorkflowStatuses.removeValue(forKey: workflowId)
                    presentMacWorkflowToast(
                        workflowName: workflowName,
                        subtitle: error.localizedDescription
                    )
                }
                AppLogger.persistence.error("Live workflow create failed: \(error.localizedDescription)")
            }
        }
    }

    private func refreshPinnedMacWorkflows() {
        let settings = TalkieAppSettings.shared
        settings.refreshPinnedWorkflowMirror()
        pinnedMacWorkflows = settings.pinnedMacWorkflows
    }

    private func refreshLiveWorkflowRuns() {
        guard auth.isSignedIn, let memoId = memo.id?.uuidString else { return }

        Task {
            do {
                guard let authToken = await auth.authToken else {
                    throw LiveWorkflowClient.ClientError.missingAuthToken
                }

                let runs = try await liveWorkflowClient.listRuns(authToken: authToken, memoId: memoId)
                await MainActor.run {
                    for run in runs {
                        upsertLiveWorkflowRun(run)
                        trackLiveWorkflow(run)
                    }
                }
            } catch {
                AppLogger.persistence.debug("Live workflow refresh skipped: \(error.localizedDescription)")
            }
        }
    }

    private func trackLiveWorkflow(_ run: LiveWorkflowRunSnapshot) {
        if run.isTerminal {
            liveWorkflowStatuses.removeValue(forKey: run.workflowId)
            liveWorkflowPollingTasks[run.id]?.cancel()
            liveWorkflowPollingTasks.removeValue(forKey: run.id)
            return
        }

        liveWorkflowStatuses[run.workflowId] = .init(runId: run.id, status: run.status)

        guard liveWorkflowPollingTasks[run.id] == nil else { return }
        liveWorkflowPollingTasks[run.id] = Task {
            await pollLiveWorkflowRun(runId: run.id, workflowId: run.workflowId, workflowName: run.workflowName)
        }
    }

    private func pollLiveWorkflowRun(runId: String, workflowId: String, workflowName: String) async {
        while !Task.isCancelled {
            do {
                guard let authToken = await auth.authToken else {
                    throw LiveWorkflowClient.ClientError.missingAuthToken
                }

                let run = try await liveWorkflowClient.getRun(authToken: authToken, runId: runId)
                await MainActor.run {
                    upsertLiveWorkflowRun(run)
                    if run.isTerminal {
                        liveWorkflowStatuses.removeValue(forKey: workflowId)
                        liveWorkflowPollingTasks[runId]?.cancel()
                        liveWorkflowPollingTasks.removeValue(forKey: runId)

                        let subtitle: String
                        if run.status == "completed" {
                            subtitle = "Completed on your Mac."
                        } else if let errorMessage = run.errorMessage, !errorMessage.isEmpty {
                            subtitle = errorMessage
                        } else {
                            subtitle = "The workflow failed on your Mac."
                        }
                        presentMacWorkflowToast(workflowName: workflowName, subtitle: subtitle)
                    } else {
                        liveWorkflowStatuses[workflowId] = .init(runId: run.id, status: run.status)
                    }
                }

                if run.isTerminal {
                    return
                }

                let delay: Duration = run.status == "queued" ? .seconds(4) : .seconds(2)
                try await Task.sleep(for: delay)
            } catch is CancellationError {
                return
            } catch {
                AppLogger.persistence.debug("Live workflow poll retry: \(error.localizedDescription)")
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func cancelLiveWorkflowPolling() {
        for task in liveWorkflowPollingTasks.values {
            task.cancel()
        }
        liveWorkflowPollingTasks.removeAll()
    }

    private func upsertLiveWorkflowRun(_ snapshot: LiveWorkflowRunSnapshot) {
        guard let memoId = memo.id,
              let runId = UUID(uuidString: snapshot.id) else {
            return
        }

        let request = NSFetchRequest<WorkflowRun>(entityName: "WorkflowRun")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", runId as CVarArg)

        let existingRun = (try? viewContext.fetch(request))?.first
        let workflowRun = existingRun ?? WorkflowRun(context: viewContext)
        workflowRun.id = runId
        workflowRun.memoId = memoId
        workflowRun.workflowId = UUID(uuidString: snapshot.workflowId)
        workflowRun.workflowName = snapshot.workflowName
        workflowRun.workflowIcon = snapshot.workflowIcon
        workflowRun.runDate = snapshot.runDateValue ?? snapshot.updatedAtValue ?? snapshot.createdAtValue ?? Date()
        workflowRun.status = snapshot.status
        workflowRun.output = snapshot.output ?? snapshot.errorMessage
        workflowRun.stepOutputsJSON = snapshot.stepOutputsJSON
        workflowRun.memo = memo

        do {
            try viewContext.save()
        } catch {
            AppLogger.persistence.error("Failed to save live workflow run: \(error.localizedDescription)")
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

    private func formatCoordinates(lat: Double, lon: Double) -> String {
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%.2f°%@ %.2f°%@", abs(lat), latDir, abs(lon), lonDir)
    }

    private func maybeProcessSidecarsAutomatically() async {
        guard hasQueuedSidecarRequests else { return }
        await resolveSidecars(retryFailed: false)
    }

    private func resolveSidecars(retryFailed: Bool) async {
        guard let memoId = memo.id?.uuidString,
              let transcript = memo.currentTranscript?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transcript.isEmpty else {
            return
        }

        await RecordingSidecarProcessor.shared.processQueuedRequests(
            memoId: memoId,
            memoTitle: memoTitle,
            transcript: transcript,
            duration: memo.duration,
            retryFailed: retryFailed
        )
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

        if let memoID = memo.id {
            memoAttachmentStore.deleteAll(for: memoID)
            sidecarStore.deleteSession(for: memoID.uuidString)
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

    private func refreshMemoAttachments() {
        guard let memoID = memo.id else {
            memoAttachments = []
            return
        }

        memoAttachments = memoAttachmentStore.attachments(for: memoID)
    }

    private var currentAttachmentFingerprint: String {
        memoAttachments
            .map { $0.id.uuidString }
            .sorted()
            .joined(separator: "|")
    }

    private var canAttemptSendAttachmentsToMac: Bool {
        memo.id != nil && !memoAttachments.isEmpty
    }

    private var hasBridgePairingForAttachments: Bool {
        bridgeManager.isPaired
    }

    private var hasSentCurrentAttachmentsToMac: Bool {
        !currentAttachmentFingerprint.isEmpty && lastSentAttachmentFingerprint == currentAttachmentFingerprint
    }

    private var sendToMacHintText: String {
        if !bridgeManager.isPaired {
            let knownMacs = DirectMacRegistry.shared.macs
            if knownMacs.contains(where: \.hasTerminalAccess) {
                return "Direct send needs Talkie Mac pairing. Terminal access alone doesn't authorize file transfer."
            }
            if !knownMacs.isEmpty {
                return "Direct send needs Talkie Mac pairing on this iPhone."
            }
            return "Scan a Talkie Mac QR to enable direct send."
        }
        if memoAttachments.isEmpty {
            return "Add an attachment to send it directly to your Mac."
        }
        if memo.id == nil {
            return "This memo is still getting ready."
        }
        return "Send attachments directly to your paired Mac."
    }

    private func removeAttachment(_ attachment: MemoImageAttachment) {
        guard let memoID = memo.id else { return }
        memoAttachmentStore.delete(attachment, memoID: memoID)
        memoAttachments.removeAll { $0.id == attachment.id }
    }

    private func importSelectedAttachmentItems(_ items: [PhotosPickerItem]) async {
        guard let memoID = memo.id else { return }

        await MainActor.run {
            isImportingAttachments = true
            attachmentError = nil
        }

        var importedCount = 0

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                if memoAttachmentStore.saveImage(data: data, memoID: memoID) != nil {
                    importedCount += 1
                }
            } catch {
                await MainActor.run {
                    attachmentError = "Couldn’t import one of the selected images."
                }
            }
        }

        await MainActor.run {
            refreshMemoAttachments()
            selectedAttachmentItems = []
            isImportingAttachments = false

            if importedCount > 0 && attachmentError == nil {
                attachmentError = nil
            }
        }
    }

    private func importCapturedImage(_ image: UIImage) async {
        guard let memoID = memo.id else { return }

        await MainActor.run {
            isImportingAttachments = true
            attachmentError = nil
        }

        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.92) else {
            await MainActor.run {
                isImportingAttachments = false
                attachmentError = "Couldn’t prepare the captured photo."
            }
            return
        }

        let preferredName = "Camera_\(Int(Date().timeIntervalSince1970))"
        let saved = memoAttachmentStore.saveImage(data: data, preferredName: preferredName, memoID: memoID)

        await MainActor.run {
            isImportingAttachments = false

            if saved != nil {
                refreshMemoAttachments()
            } else {
                attachmentError = "Couldn’t attach the captured photo."
            }
        }
    }

    // MARK: - OCR

    private func performOCR(from pickerItem: PhotosPickerItem) async {
        guard let data = try? await pickerItem.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            await MainActor.run {
                attachmentError = "Couldn't load the selected image."
            }
            return
        }

        await MainActor.run { isRunningOCR = true }

        do {
            let result = try await ScreenshotOCRService.extractText(from: image)

            // Save the image as an attachment too
            if let memoID = memo.id {
                memoAttachmentStore.saveImage(
                    data: data,
                    preferredName: "OCR_\(Int(Date().timeIntervalSince1970))",
                    memoID: memoID
                )
                await MainActor.run { refreshMemoAttachments() }
            }

            await MainActor.run {
                isRunningOCR = false
                ocrResultText = result.text
            }
        } catch {
            await MainActor.run {
                isRunningOCR = false
                attachmentError = error.localizedDescription
            }
        }
    }

    private func appendOCRTextToNotes() {
        guard let text = ocrResultText else { return }

        let separator = "\n\n--- Scanned Text ---\n"
        let currentNotes = memo.notes ?? ""

        if currentNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            memo.notes = text
        } else {
            memo.notes = currentNotes + separator + text
        }
        memo.lastModified = Date()

        do {
            try viewContext.save()
            AppLogger.persistence.info("Appended OCR text to memo notes")
        } catch {
            AppLogger.persistence.error("Failed to save OCR text to notes: \(error.localizedDescription)")
        }

        ocrResultText = nil
    }

    private func loadRecentAttachmentAssetsIfNeeded(force: Bool = false) {
        if hasLoadedRecentAttachmentAssets && !force { return }

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        attachmentPhotoAuthorizationStatus = currentStatus

        switch currentStatus {
        case .authorized, .limited:
            hasLoadedRecentAttachmentAssets = true
            recentAttachmentAssets = fetchRecentAttachmentAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                Task { @MainActor in
                    attachmentPhotoAuthorizationStatus = status
                    if status == .authorized || status == .limited {
                        hasLoadedRecentAttachmentAssets = true
                        recentAttachmentAssets = fetchRecentAttachmentAssets()
                    }
                }
            }
        default:
            recentAttachmentAssets = []
        }
    }

    private func fetchRecentAttachmentAssets(limit: Int = 12) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit

        let screenshotCollections = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .smartAlbumScreenshots,
            options: nil
        )

        if let screenshots = screenshotCollections.firstObject {
            let screenshotAssets = PHAsset.fetchAssets(in: screenshots, options: options)
            if screenshotAssets.count > 0 {
                return screenshotAssets.objects(at: IndexSet(integersIn: 0..<screenshotAssets.count))
            }
        }

        let imageAssets = PHAsset.fetchAssets(with: .image, options: options)
        guard imageAssets.count > 0 else { return [] }
        return imageAssets.objects(at: IndexSet(integersIn: 0..<imageAssets.count))
    }

    private func importRecentAttachmentAsset(_ asset: PHAsset) async {
        guard let memoID = memo.id else { return }

        await MainActor.run {
            isImportingAttachments = true
            attachmentError = nil
        }

        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 2000, height: 2000),
                contentMode: .aspectFit,
                options: options
            ) { result, _ in
                defer { continuation.resume() }

                guard let image = result,
                      let data = image.pngData() ?? image.jpegData(compressionQuality: 0.92) else {
                    Task { @MainActor in
                        isImportingAttachments = false
                        attachmentError = "That photo isn’t available on this iPhone yet."
                    }
                    return
                }

                let preferredName = asset.value(forKey: "filename") as? String
                let saved = memoAttachmentStore.saveImage(data: data, preferredName: preferredName, memoID: memoID)

                Task { @MainActor in
                    isImportingAttachments = false

                    if saved != nil {
                        refreshMemoAttachments()
                    } else {
                        attachmentError = "Couldn’t attach that image."
                    }
                }
            }
        }
    }

    private func sendAttachmentsToPairedMac() {
        DirectMacRegistry.shared.refresh()

        guard let memoID = memo.id?.uuidString else {
            presentSendToMacAlert(
                title: "To Mac",
                message: "This memo is not ready yet."
            )
            return
        }

        guard !memoAttachments.isEmpty else {
            presentSendToMacAlert(
                title: "To Mac",
                message: "Add an attachment first."
            )
            return
        }

        guard bridgeManager.isPaired else {
            let subtitle: String
            let knownMacs = DirectMacRegistry.shared.macs
            if knownMacs.contains(where: \.hasTerminalAccess) {
                subtitle = "This iPhone can reach your Mac for terminal access, but direct file send still needs Talkie Mac pairing."
            } else if !knownMacs.isEmpty {
                subtitle = "Direct send needs a Talkie Mac pairing on this iPhone."
            } else {
                subtitle = "Scan a Talkie Mac QR first to enable direct send."
            }
            presentSendToMacAlert(title: "To Mac", message: subtitle)
            return
        }

        let fingerprint = currentAttachmentFingerprint
        isSendingAttachmentsToMac = true

        Task {
            do {
                let request = try buildMemoAttachmentUploadRequest()
                let response = try await bridgeManager.sendMemoAttachments(memoId: memoID, body: request)

                await MainActor.run {
                    isSendingAttachmentsToMac = false
                    lastSentAttachmentFingerprint = fingerprint

                    let macName = bridgeManager.pairedMacName ?? "your Mac"
                    let noun = response.savedCount == 1 ? "attachment" : "attachments"
                    presentSendToMacAlert(
                        title: "Sent to Mac",
                        message: "Sent \(response.savedCount) \(noun) directly to \(macName)."
                    )
                }
            } catch {
                await MainActor.run {
                    isSendingAttachmentsToMac = false
                    presentSendToMacAlert(title: "To Mac", message: error.localizedDescription)
                }
                AppLogger.persistence.error("Direct attachment send failed: \(error.localizedDescription)")
            }
        }
    }

    private func presentSendToMacAlert(title: String, message: String) {
        sendToMacAlertTitle = title
        sendToMacAlertMessage = message
        showingSendToMacAlert = true
    }

    private func buildMemoAttachmentUploadRequest() throws -> MemoAttachmentUploadRequest {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let items = try memoAttachments.map { attachment in
            let data = try Data(contentsOf: memoAttachmentStore.url(for: attachment))
            return MemoAttachmentUploadItem(
                id: attachment.id.uuidString,
                originalName: attachment.originalName,
                addedAt: formatter.string(from: attachment.addedAt),
                fileSizeBytes: attachment.fileSizeBytes,
                pixelWidth: attachment.pixelWidth,
                pixelHeight: attachment.pixelHeight,
                recordingOffsetSeconds: nil,
                mimeType: mimeType(for: attachment.originalName),
                dataBase64: data.base64EncodedString()
            )
        }

        return MemoAttachmentUploadRequest(
            memoTitle: memo.title,
            memoCreatedAt: formatter.string(from: memoCreatedAt),
            attachments: items
        )
    }

    private func mimeType(for filename: String) -> String {
        switch URL(fileURLWithPath: filename).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "heic", "heif":
            return "image/heic"
        default:
            return "image/jpeg"
        }
    }

    /// Fetch latest memo data from CloudKit and update local Core Data
    private func fetchLatestFromCloudKit() {
        guard let memoId = memo.id else { return }

        guard let container = CloudKitContainerProvider.container() else {
            let reason = CloudKitContainerProvider.unavailableReason ?? "CloudKit unavailable"
            AppLogger.persistence.warning("Memo CloudKit fetch skipped: \(reason)")
            return
        }

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

                    if didUpdate {
                        try? memo.managedObjectContext?.save()
                        AppLogger.persistence.info("Updated memo from CloudKit: cloud=\(memo.cloudSyncedAt != nil), mac=\(memo.macReceivedAt != nil), summary=\(memo.summary != nil)")
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
                        BrailleSpinner(size: 10)
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
                        BrailleSpinner(size: 10)
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
                        BrailleSpinner(size: 10)
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
                            BrailleSpinner(size: 12)
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

private struct RecordingSidecarResultCard: View {
    let request: RecordingSidecarRequest

    private var offsetText: String {
        let totalSeconds = max(Int(request.queuedAtOffset.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }

    private var statusLabel: String {
        switch request.status {
        case .queued:
            return "QUEUED"
        case .processing:
            return "WORKING"
        case .completed:
            return "READY"
        case .failed:
            return "FAILED"
        }
    }

    private var statusColor: Color {
        switch request.status {
        case .queued:
            return .textTertiary
        case .processing:
            return .transcribing
        case .completed:
            return .success
        case .failed:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: request.kind.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Text(request.kind.displayName.uppercased())
                    .font(.techLabel)
                    .tracking(1)
                    .foregroundColor(.textSecondary)

                Text(offsetText)
                    .font(.monoSmall)
                    .foregroundColor(.textTertiary)

                Spacer()

                Text(statusLabel)
                    .font(.techLabelSmall)
                    .tracking(1)
                    .foregroundColor(statusColor)
            }

            if let output = request.output,
               request.status == .completed,
               !output.isEmpty {
                Text(output)
                    .font(.bodySmall)
                    .foregroundColor(.textPrimary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            } else if request.status == .processing {
                Text("Resolving this bookmarked moment now.")
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
            } else if let message = request.failureMessage,
                      request.status == .failed,
                      !message.isEmpty {
                Text(message)
                    .font(.techLabelSmall)
                    .foregroundColor(.red)
            } else {
                Text("Captured during recording and waiting for transcript-backed resolution.")
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
            }

            if let excerpt = request.transcriptExcerpt,
               !excerpt.isEmpty,
               request.status == .completed {
                Text(excerpt)
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                    .lineLimit(4)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfacePrimary)
                    .cornerRadius(CornerRadius.sm)
            }
        }
        .padding(Spacing.md)
        .background(Color.surfaceSecondary)
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(statusColor.opacity(0.25), lineWidth: 0.5)
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
                        BrailleSpinner()
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
        case "claimed", "running": return .transcribing
        case "queued": return .active
        default: return .textTertiary
        }
    }

    private var statusLabel: String {
        switch run.status {
        case "queued":
            return "Waiting for Mac"
        case "claimed", "running":
            return "Running on Mac"
        case "failed":
            return "Failed"
        case "completed":
            return "Completed"
        default:
            return "Status Unknown"
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
            } else if !isExpanded {
                Text(statusLabel.uppercased())
                    .font(.techLabelSmall)
                    .foregroundColor(statusColor)
                    .padding(.leading, 6 + Spacing.sm)
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
    let subtitle: String

    var body: some View {
        TalkieToast(
            icon: "desktopcomputer",
            title: workflowName,
            subtitle: subtitle,
            style: .info
        )
    }
}

// MARK: - Transcript Editor (isolated from ObservedObject rebuilds)

/// Extracted into its own view so that Core Data / CloudKit sync
/// notifications on the parent's @ObservedObject don't rebuild the
/// TextEditor mid-keystroke.
private struct TranscriptEditorView: View {
    @Binding var text: String
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        VStack(spacing: Spacing.sm) {
            TextEditor(text: $text)
                .font(.bodySmall)
                .foregroundStyle(Color.textPrimary)
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
                Button(action: onCancel) {
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

                Button(action: onSave) {
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

private struct LiveWorkflowStatus {
    let runId: String?
    let status: String

    var isInFlight: Bool {
        status == "queued" || status == "claimed" || status == "running"
    }
}

private struct LiveWorkflowRunSnapshot: Codable, Sendable {
    let id: String
    let workflowId: String
    let workflowName: String
    let workflowIcon: String?
    let memoId: String
    let status: String
    let createdAt: String
    let updatedAt: String
    let runDate: String
    let output: String?
    let stepOutputsJSON: String?
    let errorMessage: String?

    var isTerminal: Bool {
        status == "completed" || status == "failed" || status == "cancelled"
    }

    var createdAtValue: Date? {
        ISO8601DateFormatter().date(from: createdAt)
    }

    var updatedAtValue: Date? {
        ISO8601DateFormatter().date(from: updatedAt)
    }

    var runDateValue: Date? {
        ISO8601DateFormatter().date(from: runDate)
    }
}

private struct LiveWorkflowRunResponse: Codable {
    let run: LiveWorkflowRunSnapshot
}

private struct LiveWorkflowRunListResponse: Codable {
    let runs: [LiveWorkflowRunSnapshot]
}

private struct LiveWorkflowClient {
    enum ClientError: LocalizedError {
        case invalidURL
        case missingAuthToken
        case invalidResponse
        case server(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "The Talkie API URL is invalid."
            case .missingAuthToken:
                return "Sign into Talkie to run live Mac workflows."
            case .invalidResponse:
                return "The Talkie API returned an invalid response."
            case .server(let message):
                return message
            }
        }
    }

    private let endpointBase = TalkieWorkflowAPIConfiguration.baseURL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func createRun(
        authToken: String,
        workflowId: String,
        workflowName: String,
        workflowIcon: String?,
        memoId: String,
        requestedByDeviceId: String?
    ) async throws -> LiveWorkflowRunSnapshot {
        let body = CreateRunRequest(
            workflowId: workflowId,
            workflowName: workflowName,
            workflowIcon: workflowIcon,
            memoId: memoId,
            requestedByDeviceId: requestedByDeviceId
        )

        let response: LiveWorkflowRunResponse = try await send(
            authToken: authToken,
            method: "POST",
            path: "/api/workflow-runs",
            body: body
        )
        return response.run
    }

    func getRun(authToken: String, runId: String) async throws -> LiveWorkflowRunSnapshot {
        let response: LiveWorkflowRunResponse = try await send(
            authToken: authToken,
            url: try endpointURL(path: "/api/workflow-runs/\(runId)"),
            responseType: LiveWorkflowRunResponse.self
        )
        return response.run
    }

    func listRuns(authToken: String, memoId: String) async throws -> [LiveWorkflowRunSnapshot] {
        var components = URLComponents(url: try endpointURL(path: "/api/workflow-runs"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "memoId", value: memoId),
        ]

        guard let url = components?.url else {
            throw ClientError.invalidURL
        }

        let response: LiveWorkflowRunListResponse = try await send(
            authToken: authToken,
            url: url,
            responseType: LiveWorkflowRunListResponse.self
        )
        return response.runs
    }

    private func endpointURL(path: String) throws -> URL {
        guard let baseURL = URL(string: endpointBase) else {
            throw ClientError.invalidURL
        }
        return baseURL.appending(path: path)
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        authToken: String,
        method: String,
        path: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        var request = try authorizedRequest(url: endpointURL(path: path), authToken: authToken)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(body)
        return try await send(request, responseType: ResponseBody.self)
    }

    private func send<ResponseBody: Decodable>(
        authToken: String,
        url: URL,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        var request = try authorizedRequest(url: url, authToken: authToken)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await send(request, responseType: responseType)
    }

    private func authorizedRequest(url: URL, authToken: String) throws -> URLRequest {
        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw ClientError.missingAuthToken
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send<ResponseBody: Decodable>(
        _ request: URLRequest,
        responseType: ResponseBody.Type
    ) async throws -> ResponseBody {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.server(Self.decodeErrorMessage(from: data) ?? "Live workflow request failed.")
        }

        return try decoder.decode(ResponseBody.self, from: data)
    }

    private static func decodeErrorMessage(from data: Data) -> String? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = json["error"] as? String
        else {
            return nil
        }

        return error
    }
}

private struct CreateRunRequest: Encodable {
    let workflowId: String
    let workflowName: String
    let workflowIcon: String?
    let memoId: String
    let requestedByDeviceId: String?
}
