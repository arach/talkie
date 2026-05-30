//
//  RecordingView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData
import Photos
import PhotosUI
import UIKit
import TalkieMobileKit

struct RecordingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = AudioRecorderManager()
    @ObservedObject private var theme = ThemeManager.shared
    @State private var recordingTitle = ""
    @State private var defaultTitle = ""
    @State private var recPulse = false
    @State private var waveformStyle: WaveformStyle = .particles
    @State private var sheetDetent: PresentationDetent = .height(280)
    @State private var hasAppeared = false
    @State private var isCancelling = false
    @State private var appSettings = TalkieAppSettings.shared
    @State private var selectedAttachmentItems: [PhotosPickerItem] = []
    @State private var showingAttachmentPhotoPicker = false
    @State private var showingAttachmentCamera = false
    @State private var recentVisualAssets: [PHAsset] = []
    @State private var pendingAttachments: [PendingRecordingAttachment] = []
    @State private var pendingSidecarRequests: [RecordingSidecarRequest] = []
    @State private var attachmentError: String?
    @State private var hasLoadedRecentVisuals = false
    @State private var photoAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private let compactHeight: CGFloat = 280
    private let expandedHeight: CGFloat = 600
    private let thumbnailManager = PHCachingImageManager()
    private let memoAttachmentStore = MemoAttachmentStore.shared

    private var isExpandedDetailsMode: Bool {
        sheetDetent == .height(expandedHeight)
    }

    private var totalQueuedContextCount: Int {
        pendingAttachments.count + pendingSidecarRequests.count
    }

    var body: some View {
        ZStack {
            // Clear - using presentationBackground for transparency
            Color.clear

            VStack(spacing: 0) {
                // Drag indicator
                Capsule()
                    .fill(Color.textTertiary.opacity(0.5))
                    .frame(width: 36, height: 4)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.md)

                if isCancelling {
                    // CANCELLING STATE - show nothing during dismiss
                    Color.clear
                } else if recorder.isRecording {
                    // RECORDING STATE
                    recordingContent
                } else if recorder.currentRecordingURL != nil {
                    // STOPPED STATE - ready to save
                    stoppedContent
                } else {
                    // STARTING STATE - brief moment before recording starts
                    startingContent
                }
            }
        }
        .presentationDetents([.height(compactHeight), .height(expandedHeight)], selection: $sheetDetent)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(CornerRadius.xl)
        .presentationBackground(Color.surfaceSecondary.opacity(0.85))
        .presentationBackgroundInteraction(.disabled)
        .interactiveDismissDisabled(recorder.isRecording || recorder.currentRecordingURL != nil)
        .photosPicker(
            isPresented: $showingAttachmentPhotoPicker,
            selection: $selectedAttachmentItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .sheet(isPresented: $showingAttachmentCamera) {
            CameraImagePicker { image in
                addPendingAttachment(image: image, preferredName: "Camera_\(Int(Date().timeIntervalSince1970))")
            }
        }
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                defaultTitle = "Recording \(formatDate(Date()))"
                // Start recording immediately - no delay needed
                // (watchOS version and push-to-talk both work without delay)
                recorder.startRecording()
                // Request location fix during recording (no permission prompt here)
                if appSettings.tagLocationEnabled {
                    LocationService.shared.requestLocationIfAuthorized()
                }
            }
        }
        .onDisappear {
            // Safety net: if the sheet is dismissed while still actively
            // recording (e.g. dismissAllSheets flips the binding, or some other
            // path bypasses cancel/save/delete), make sure we stop the recorder
            // and release the AVAudioSession so the iOS mic indicator turns
            // off. We do NOT touch the file in the paused/ready-to-save state
            // since saveRecording keeps the file on disk for playback; finalize
            // is idempotent in that branch (audioRecorder is already nil).
            if recorder.isRecording {
                let leakedURL = recorder.currentRecordingURL
                recorder.finalizeRecording()
                if let url = leakedURL {
                    try? FileManager.default.removeItem(at: url)
                    AppLogger.recording.info("RecordingView disappeared mid-recording; discarded \(url.lastPathComponent)")
                }
            }
        }
        .onChange(of: sheetDetent) { _, newValue in
            if newValue == .height(expandedHeight) {
                loadRecentVisualsIfNeeded()
            }
        }
        .onChange(of: selectedAttachmentItems) { _, newItems in
            guard !newItems.isEmpty else { return }

            Task {
                await importSelectedAttachmentItems(newItems)
            }
        }
    }

    // MARK: - Recording Content

    private var recordingContent: some View {
        VStack(spacing: Spacing.sm) {
            // Top row: ESC on left, REC indicator centered
            HStack {
                Button(action: {
                    cancelRecording()
                }) {
                    Text("ESC")
                        .font(.techLabelSmall)
                        .tracking(1)
                        .foregroundColor(.textTertiary)
                }
                .accessibilityIdentifier("recording.cancel")

                Spacer()

                // REC indicator (universal red, with theme-aware glow)
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(Color.recording)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.recording.opacity(0.55), radius: theme.chrome.glowRadius)
                        .scaleEffect(recPulse ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true),
                            value: recPulse
                        )

                    Text("REC")
                        .font(.techLabelSmall)
                        .fontWeight(.bold)
                        .foregroundColor(.recording)
                        .tracking(1)
                }
                .onAppear { recPulse = true }

                Spacer()

                // Placeholder for symmetry
                Text("ESC")
                    .font(.techLabelSmall)
                    .tracking(1)
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, Spacing.lg)

            // Waveform style switcher in expanded mode only
            if isExpandedDetailsMode {
                waveformStyleSwitcher
            }

            // Live waveform (recording red on particles, theme accent otherwise)
            LiveWaveformView(
                levels: recorder.audioLevels,
                height: isExpandedDetailsMode ? 120 : 60,
                color: waveformStyle == .particles ? .recording : theme.chrome.accent,
                style: waveformStyle
            )
            .padding(.horizontal, Spacing.sm)
            .background(Color.surfacePrimary.opacity(0.5))
            .cornerRadius(CornerRadius.md)
            .padding(.horizontal, Spacing.lg)

            // Duration - always below waveform
            Text(formatDuration(recorder.recordingDuration))
                .font(isExpandedDetailsMode ? .monoLarge : .monoMedium)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)

            if isExpandedDetailsMode {
                recordingDetailsPanel
                    .padding(.horizontal, Spacing.lg)
            } else {
                compactDetailsPrompt
                    .padding(.horizontal, Spacing.lg)
            }

            Spacer(minLength: Spacing.sm)

            // Stop button — theme-aware accent ring + glow
            Button(action: {
                recorder.stopRecording()
            }) {
                ZStack {
                    Circle()
                        .fill(theme.chrome.accentGlow)
                        .frame(width: 76, height: 76)
                        .blur(radius: 20)
                        .opacity(0.5)

                    Circle()
                        .strokeBorder(theme.chrome.accent, lineWidth: 3)
                        .frame(width: 70, height: 70)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.chrome.accent)
                        .frame(width: 22, height: 22)
                }
            }
            .accessibilityIdentifier("recording.stop")
            .padding(.top, Spacing.xs)
            .padding(.bottom, 20) // Match ActionDock bottom padding
        }
    }

    // MARK: - Stopped Content (Ready to Save)

    private var stoppedContent: some View {
        VStack(spacing: Spacing.sm) {
            // Top row: Trash | Title | READY
            HStack(spacing: Spacing.sm) {
                Button(action: {
                    deleteRecording()
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textTertiary)
                        .frame(width: 32, height: 32)
                }

                // Title input - expands to fill
                TextField("", text: $recordingTitle, prompt: Text(defaultTitle).foregroundColor(.textSecondary))
                    .font(.bodySmall)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.textPrimary)
                    .padding(.vertical, Spacing.xs)
                    .padding(.horizontal, Spacing.sm)
                    .background(Color.surfacePrimary.opacity(0.8))
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Color.borderPrimary.opacity(0.5), lineWidth: 0.5)
                    )

                // READY indicator — theme accent + phosphor glow
                HStack(spacing: 4) {
                    TalkieStatusDot(diameter: 6, pulses: true)

                    Text("READY")
                        .font(.techLabelSmall)
                        .tracking(1)
                        .foregroundColor(theme.chrome.accent)
                }
                .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, Spacing.md)

            // Waveform preview - taller
            WaveformView(
                levels: recorder.audioLevels.map { $0 * 1.5 }, // Amplify levels
                height: 56,
                color: .textTertiary.opacity(0.5)
            )
            .background(Color.surfacePrimary.opacity(0.6))
            .cornerRadius(CornerRadius.sm)
            .padding(.horizontal, Spacing.lg)

            // Duration centered below waveform
            Text(formatDuration(recorder.recordingDuration))
                .font(.monoMedium)
                .foregroundColor(.textPrimary)

            if isExpandedDetailsMode {
                stoppedDetailsPanel
                    .padding(.horizontal, Spacing.lg)
            } else {
                compactDetailsPrompt
                    .padding(.horizontal, Spacing.lg)
            }

            Spacer(minLength: Spacing.xs)

            // Action buttons - Resume left, Save center
            HStack(spacing: Spacing.lg) {
                // Resume button — secondary, theme-aware
                Button(action: {
                    resumeRecording()
                }) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(theme.chrome.accent.opacity(0.7))
                        .frame(width: 48, height: 48)
                        .background(theme.colors.cardBackground.opacity(0.6))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(theme.chrome.accent.opacity(0.3), lineWidth: 1)
                        )
                }

                // Save button — primary action, theme accent
                Button(action: {
                    saveRecording()
                    dismiss()
                }) {
                    ZStack {
                        Circle()
                            .fill(theme.chrome.accent)
                            .frame(width: 70, height: 70)
                            .overlay(
                                Circle()
                                    .strokeBorder(theme.chrome.panelInk.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: theme.chrome.accentGlow.opacity(0.45), radius: 8, x: 0, y: 4)

                        Image(systemName: "checkmark")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(theme.chrome.panelInk)
                    }
                }
                .accessibilityIdentifier("recording.save")

                // Balance spacer for resume button
                Color.clear.frame(width: 48, height: 48)
            }
            .padding(.bottom, 20) // Match ActionDock bottom padding
        }
    }

    private func resumeRecording() {
        // Resume appends to existing recording
        recorder.resumeRecording()
    }

    // MARK: - Starting Content

    private var startingContent: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            BrailleSpinner(color: theme.chrome.accent)

            TalkieEyebrow(text: "Starting", showLeader: false)

            Spacer()
        }
    }

    // MARK: - Waveform Style Switcher

    private var waveformStyleSwitcher: some View {
        HStack(spacing: Spacing.xs) {
            ForEach([WaveformStyle.wave, .spectrum, .particles], id: \.self) { style in
                Button(action: { waveformStyle = style }) {
                    Text(styleName(style))
                        .font(.techLabelSmall)
                        .tracking(0.5)
                        .foregroundColor(waveformStyle == style ? theme.chrome.panelInk : .textTertiary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(waveformStyle == style ? theme.chrome.accent.opacity(0.85) : Color.clear)
                        .cornerRadius(CornerRadius.sm)
                }
            }
        }
        .padding(.bottom, Spacing.xs)
    }

    private var compactDetailsPrompt: some View {
        Button {
            withAnimation(.snappy(duration: 0.28)) {
                sheetDetent = .height(expandedHeight)
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(totalQueuedContextCount == 0 ? "DETAILS" : "DETAILS READY")
                        .font(.techLabel)
                        .tracking(1.6)
                        .foregroundColor(.textSecondary)

                    Text(compactDetailsPromptCopy)
                        .font(.techLabelSmall)
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: Spacing.sm)

                HStack(spacing: 6) {
                    if !pendingAttachments.isEmpty {
                        compactDetailsCountBadge(
                            icon: "photo",
                            count: pendingAttachments.count,
                            tint: .active
                        )
                    }

                    if !pendingSidecarRequests.isEmpty {
                        compactDetailsCountBadge(
                            icon: "bookmark.fill",
                            count: pendingSidecarRequests.count,
                            tint: .memoAccent
                        )
                    }
                }

                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(Color.surfacePrimary.opacity(0.5))
            .cornerRadius(CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .strokeBorder(Color.borderPrimary.opacity(0.45), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("recording.details")
    }

    private var compactDetailsPromptCopy: String {
        if totalQueuedContextCount == 0 {
            if recorder.isRecording {
                return "Photos, snapshots, and bookmarks are available while you record."
            }

            return "Photos, snapshots, and bookmarks are available before you save."
        }

        let itemLabel = totalQueuedContextCount == 1 ? "item" : "items"
        if recorder.isRecording {
            return "\(totalQueuedContextCount) \(itemLabel) queued for this memo."
        }

        return "\(totalQueuedContextCount) \(itemLabel) queued for this memo."
    }

    @ViewBuilder
    private func compactDetailsCountBadge(icon: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(count.formatted())
                .font(.techLabelSmall)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .cornerRadius(CornerRadius.sm)
    }

    private var recordingDetailsPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            detailsPanelHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    recordingVisualContextSection

                    RecordingSidecarSection(
                        requests: pendingSidecarRequests,
                        showsDetails: true,
                        showsActions: true,
                        onQueue: queueSidecarRequest,
                        onRemove: removeSidecarRequest
                    )
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 240)
        }
    }

    private var stoppedDetailsPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            detailsPanelHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    recordingVisualContextSection

                    if !pendingSidecarRequests.isEmpty {
                        RecordingSidecarSection(
                            requests: pendingSidecarRequests,
                            showsDetails: true,
                            showsActions: false,
                            onQueue: queueSidecarRequest,
                            onRemove: removeSidecarRequest
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 240)
        }
    }

    private var detailsPanelHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            TalkieEyebrow(text: "Detail Mode")
            Spacer()
        }
    }

    private var recordingVisualContextSection: some View {
        RecordingVisualContextSection(
            recentAssets: recentVisualAssets,
            pendingAttachments: pendingAttachments,
            thumbnailManager: thumbnailManager,
            photoAuthorizationStatus: photoAuthorizationStatus,
            onChooseFromPhotos: {
                showPhotosPicker()
            },
            onTakePhoto: {
                showingAttachmentCamera = true
            },
            onAddRecentAsset: { asset in
                Task {
                    await addRecentAsset(asset)
                }
            },
            onRemoveAttachment: removePendingAttachment,
            attachmentError: attachmentError
        )
    }

    // MARK: - Actions

    private func cancelRecording() {
        isCancelling = true
        recorder.finalizeRecording()
        if let url = recorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
            AppLogger.recording.info("Cancelled recording: \(url.lastPathComponent)")
        }
        dismiss()
    }

    private func deleteRecording() {
        recorder.finalizeRecording()
        if let url = recorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
            AppLogger.recording.info("Deleted unsaved recording: \(url.lastPathComponent)")
        }
    }

    private func saveRecording() {
        // Finalize the recording (stop the recorder properly)
        recorder.finalizeRecording()

        guard let url = recorder.currentRecordingURL else { return }

        let newMemo = VoiceMemo(context: viewContext)
        newMemo.id = UUID()
        newMemo.title = recordingTitle.isEmpty ? defaultTitle : recordingTitle
        newMemo.createdAt = Date()
        newMemo.lastModified = Date()
        newMemo.duration = recorder.recordingDuration
        newMemo.fileURL = url.lastPathComponent
        newMemo.isTranscribing = false
        newMemo.sortOrder = Int32(Date().timeIntervalSince1970 * -1)
        newMemo.originDeviceId = PersistenceController.deviceId
        newMemo.autoProcessed = false  // Mark for macOS auto-run processing

        // Location metadata (only if user opted in)
        if appSettings.tagLocationEnabled, let location = LocationService.shared.lastLocation {
            newMemo.hasLocation = true
            newMemo.latitude = location.coordinate.latitude
            newMemo.longitude = location.coordinate.longitude
            newMemo.altitude = location.altitude
        }
        newMemo.timezone = TimeZone.current.identifier
        newMemo.deviceModel = UIDevice.modelIdentifier

        // Audio environment (derived from existing waveform data)
        if !recorder.audioLevels.isEmpty {
            let avg = recorder.audioLevels.reduce(0, +) / Float(recorder.audioLevels.count)
            let peak = recorder.audioLevels.max() ?? 0
            newMemo.averageAmplitude = avg
            newMemo.peakAmplitude = peak
        }

        // Load and store audio data for CloudKit sync
        do {
            let audioData = try Data(contentsOf: url)
            newMemo.audioData = audioData
            AppLogger.recording.info("Audio data loaded: \(audioData.count) bytes")
        } catch {
            AppLogger.recording.warning("Failed to load audio data: \(error.localizedDescription)")
        }

        // Save waveform data
        if let waveformData = try? JSONEncoder().encode(recorder.audioLevels) {
            newMemo.waveformData = waveformData
        }

        do {
            try viewContext.save()
            AppLogger.persistence.info("Memo saved with audio data for CloudKit sync")

            if let memoID = newMemo.id {
                for attachment in pendingAttachments {
                    if memoAttachmentStore.saveImage(
                        data: attachment.data,
                        preferredName: attachment.preferredName,
                        memoID: memoID
                    ) == nil {
                        AppLogger.persistence.warning("Failed to persist recording attachment for memo \(memoID.uuidString)")
                    }
                }

                RecordingSidecarStore.shared.attachRequests(
                    pendingSidecarRequests,
                    to: memoID.uuidString,
                    memoTitle: newMemo.title ?? defaultTitle
                )
            }

            VoiceMemoStore.publishChange(context: viewContext)

            let memoObjectID = newMemo.objectID

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))

                if let savedMemo = viewContext.object(with: memoObjectID) as? VoiceMemo {
                    AppLogger.transcription.info("Starting transcription for persisted memo")
                    TranscriptionService.shared.transcribeVoiceMemo(savedMemo, context: viewContext)
                }
            }
        } catch {
            let nsError = error as NSError
            AppLogger.persistence.error("Error saving memo: \(nsError.localizedDescription)")
        }
    }

    private func loadRecentVisualsIfNeeded(force: Bool = false) {
        if hasLoadedRecentVisuals && !force { return }

        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        photoAuthorizationStatus = currentStatus

        switch currentStatus {
        case .authorized, .limited:
            hasLoadedRecentVisuals = true
            recentVisualAssets = fetchRecentVisualAssets()
        case .notDetermined:
            recentVisualAssets = []
        default:
            recentVisualAssets = []
        }
    }

    private func fetchRecentVisualAssets(limit: Int = 8) -> [PHAsset] {
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

    private func addRecentAsset(_ asset: PHAsset) async {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                contentMode: .aspectFit,
                options: options
            ) { result, _ in
                defer { continuation.resume() }

                guard let image = result else {
                    Task { @MainActor in
                        attachmentError = "That image isn’t available on this device yet."
                    }
                    return
                }

                let filename = asset.value(forKey: "filename") as? String
                Task { @MainActor in
                    addPendingAttachment(image: image, preferredName: filename)
                }
            }
        }
    }

    private func importSelectedAttachmentItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { continue }
                await MainActor.run {
                    addPendingAttachment(image: image, preferredName: nil)
                }
            } catch {
                await MainActor.run {
                    attachmentError = "Couldn’t import one of those images."
                }
            }
        }

        await MainActor.run {
            selectedAttachmentItems = []
        }
    }

    private func addPendingAttachment(image: UIImage, preferredName: String?) {
        guard let data = image.pngData() ?? image.jpegData(compressionQuality: 0.92) else {
            attachmentError = "Couldn’t prepare that image."
            return
        }

        let name = preferredName ?? "Image_\(Int(Date().timeIntervalSince1970))"
        pendingAttachments.insert(
            PendingRecordingAttachment(
                image: image,
                data: data,
                preferredName: name
            ),
            at: 0
        )
        attachmentError = nil
    }

    private func removePendingAttachment(_ attachment: PendingRecordingAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    private func queueSidecarRequest(_ kind: RecordingSidecarKind) {
        let request = RecordingSidecarRequest(
            kind: kind,
            queuedAtOffset: recorder.recordingDuration
        )
        pendingSidecarRequests.append(request)
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
    }

    private func removeSidecarRequest(_ request: RecordingSidecarRequest) {
        pendingSidecarRequests.removeAll { $0.id == request.id }
    }

    private func showPhotosPicker() {
        showingAttachmentPhotoPicker = true
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func styleName(_ style: WaveformStyle) -> String {
        switch style {
        case .wave: return "WAVE"
        case .spectrum: return "SPECTRUM"
        case .particles: return "PARTICLES"
        }
    }
}

private struct PendingRecordingAttachment: Identifiable {
    let id = UUID()
    let image: UIImage
    let data: Data
    let preferredName: String
}

private struct RecordingSidecarSection: View {
    let requests: [RecordingSidecarRequest]
    let showsDetails: Bool
    let showsActions: Bool
    let onQueue: (RecordingSidecarKind) -> Void
    let onRemove: (RecordingSidecarRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if showsDetails {
                HStack {
                    Text("SIDECAR")
                        .font(.techLabel)
                        .tracking(2)
                        .foregroundColor(.textSecondary)

                    Spacer()

                    if !requests.isEmpty {
                        Text("\(requests.count)")
                            .font(.techLabelSmall)
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, 4)
                            .background(Color.surfacePrimary.opacity(0.6))
                            .cornerRadius(CornerRadius.sm)
                    }
                }

                Text(
                    showsActions
                        ? "Bookmark this moment for feedback or research without stopping the recording."
                        : "These queued sidecars will resolve after the transcript is ready."
                )
                .font(.techLabelSmall)
                .foregroundColor(.textTertiary)
            }

            if showsActions {
                HStack(spacing: Spacing.xs) {
                    ForEach(RecordingSidecarKind.allCases, id: \.self) { kind in
                        RecordingSidecarActionButton(kind: kind) {
                            onQueue(kind)
                        }
                    }
                }
            }

            if !requests.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(requests) { request in
                            RecordingSidecarQueuedCard(
                                request: request,
                                onRemove: { onRemove(request) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(showsDetails ? Spacing.sm : Spacing.xs)
        .background(Color.surfacePrimary.opacity(0.5))
        .cornerRadius(CornerRadius.md)
    }
}

private struct RecordingSidecarActionButton: View {
    let kind: RecordingSidecarKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 14, weight: .semibold))
                Text(kind.displayName.uppercased())
                    .font(.techLabelSmall)
                    .tracking(0.8)
            }
            .foregroundColor(.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(Color.surfaceSecondary.opacity(0.85))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .strokeBorder(Color.borderPrimary.opacity(0.5), lineWidth: 0.5)
            )
            .cornerRadius(CornerRadius.sm)
        }
        .buttonStyle(.plain)
    }
}

private struct RecordingSidecarQueuedCard: View {
    let request: RecordingSidecarRequest
    let onRemove: () -> Void

    private var offsetText: String {
        let totalSeconds = max(Int(request.queuedAtOffset.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return "\(minutes):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: request.kind.iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.kind.displayName.uppercased())
                        .font(.techLabelSmall)
                        .tracking(0.8)
                        .foregroundColor(.textPrimary)

                    Text(offsetText)
                        .font(.monoSmall)
                        .foregroundColor(.textTertiary)
                }

                Spacer(minLength: 8)

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Text(request.kind.hint)
                .font(.techLabelSmall)
                .foregroundColor(.textTertiary)
                .lineLimit(3)
        }
        .padding(Spacing.sm)
        .frame(width: 180, alignment: .leading)
        .background(Color.surfaceSecondary.opacity(0.75))
        .cornerRadius(CornerRadius.sm)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .strokeBorder(Color.borderPrimary.opacity(0.5), lineWidth: 0.5)
        )
    }
}

private struct RecordingVisualContextSection: View {
    let recentAssets: [PHAsset]
    let pendingAttachments: [PendingRecordingAttachment]
    let thumbnailManager: PHCachingImageManager
    let photoAuthorizationStatus: PHAuthorizationStatus
    let onChooseFromPhotos: () -> Void
    let onTakePhoto: () -> Void
    let onAddRecentAsset: (PHAsset) -> Void
    let onRemoveAttachment: (PendingRecordingAttachment) -> Void
    let attachmentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("VISUAL CONTEXT")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textSecondary)

                Spacer()

                if !pendingAttachments.isEmpty {
                    Text("\(pendingAttachments.count)")
                        .font(.techLabelSmall)
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 4)
                        .background(Color.surfacePrimary.opacity(0.6))
                        .cornerRadius(CornerRadius.sm)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    RecordingVisualActionButton(
                        icon: "camera.fill",
                        title: "Camera",
                        tint: .memoAccent,
                        hint: "Capture a photo right now and save it with this recording.",
                        action: onTakePhoto
                    )

                    RecordingVisualActionButton(
                        icon: "photo.on.rectangle",
                        title: "Photos",
                        tint: .active,
                        hint: "Pick screenshots or photos from your library and add them to this recording.",
                        action: onChooseFromPhotos
                    )

                    ForEach(recentAssets, id: \.localIdentifier) { asset in
                        RecentAssetThumbnailButton(
                            asset: asset,
                            thumbnailManager: thumbnailManager,
                            action: { onAddRecentAsset(asset) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }

            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.xs) {
                        ForEach(pendingAttachments) { attachment in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: attachment.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))

                                Button {
                                    onRemoveAttachment(attachment)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                                }
                                .buttonStyle(.plain)
                                .padding(4)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } else if photoAuthorizationStatus == .denied || photoAuthorizationStatus == .restricted {
                Text("Allow Photos access to show recent screenshots here.")
                    .font(.techLabelSmall)
                    .foregroundColor(.textTertiary)
            }

            if let attachmentError {
                Text(attachmentError)
                    .font(.techLabelSmall)
                    .foregroundColor(.recording)
            }
        }
        .padding(Spacing.sm)
        .background(Color.surfacePrimary.opacity(0.5))
        .cornerRadius(CornerRadius.md)
    }
}

private struct RecordingVisualActionButton: View {
    let icon: String
    let title: String
    let tint: Color
    let hint: String
    let action: () -> Void

    @State private var showingHint = false
    @State private var hintDismissTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .fill(tint.opacity(0.14))
                        .frame(width: 60, height: 60)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(tint)
                }

                Text(title.uppercased())
                    .font(.techLabelSmall)
                    .tracking(0.8)
                    .foregroundColor(.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0.45) {
            showHint()
        }
        .overlay(alignment: .top) {
            if showingHint {
                Text(hint)
                    .font(.techLabelSmall)
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.surfacePrimary.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Color.borderPrimary.opacity(0.6), lineWidth: 0.5)
                    )
                    .cornerRadius(CornerRadius.sm)
                    .frame(width: 150)
                    .multilineTextAlignment(.leading)
                    .offset(y: -72)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .onDisappear {
            hintDismissTask?.cancel()
        }
    }

    private func showHint() {
        hintDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            showingHint = true
        }

        hintDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingHint = false
                }
            }
        }
    }
}

private struct RecentAssetThumbnailButton: View {
    let asset: PHAsset
    let thumbnailManager: PHCachingImageManager
    let action: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .fill(Color.surfacePrimary.opacity(0.8))
                    .frame(width: 60, height: 60)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .task(id: asset.localIdentifier) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            thumbnailManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 120, height: 120),
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                self.image = result
                continuation.resume()
            }
        }
    }
}

// MARK: - UIDevice Model Identifier

extension UIDevice {
    /// Hardware identifier, e.g. "iPhone17,1"
    static var modelIdentifier: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}

#Preview {
    RecordingView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
