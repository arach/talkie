//
//  RecordingSheetNext.swift
//  Talkie iOS
//
//  Phase 3 — Next-style recording modal, now wired end-to-end.
//  Two detents (280 / 560), real AudioRecorderManager driving
//  ParticlesWaveformView, on Save persists a VoiceMemo via CoreData.
//

import CoreData
import PhotosUI
import SwiftUI
import TalkieMobileKit
import UIKit

/// Tracks the active state of the next-style recording sheet — the
/// chrome's mic-FAB sets this true; the sheet observes and presents.
@MainActor
final class RecordingSheetController: ObservableObject {
    static let shared = RecordingSheetController()
    @Published var isPresented: Bool = false
    private init() {}
}

struct RecordingSheetNext: View {
    @ObservedObject private var theme = ThemeManager.shared
    @ObservedObject private var controller = RecordingSheetController.shared
    @StateObject private var recorder = AudioRecorderManager()

    @State private var detent: PresentationDetent = .height(280)
    @State private var phase: Phase = .starting
    @State private var title: String = ""
    @State private var startedAt: Date = Date()
    @State private var savedURL: URL?
    @State private var savedDuration: TimeInterval = 0
    @State private var savedLevels: [Float] = []
    @State private var selectedAttachmentItems: [PhotosPickerItem] = []
    @State private var showingAttachmentPhotoPicker = false
    @State private var pendingAttachments: [RecordingSheetPendingAttachment] = []
    @State private var pendingSidecarRequests: [RecordingSidecarRequest] = []
    @State private var attachmentError: String?

    private let memoAttachmentStore = MemoAttachmentStore.shared

    private enum Phase { case starting, recording, stopped, saving, saved }

    private var queuedContextCount: Int {
        pendingAttachments.count + pendingSidecarRequests.count
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(theme.colors.textTertiary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 12)

            switch phase {
            case .starting:  startingBody
            case .recording: recordingBody
            case .stopped:   stoppedBody
            case .saving:    savingBody
            case .saved:     savedBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .presentationDetents([.height(280), .height(560)], selection: $detent)
        .presentationDragIndicator(.hidden)
        .presentationBackground(.regularMaterial)
        .photosPicker(
            isPresented: $showingAttachmentPhotoPicker,
            selection: $selectedAttachmentItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onAppear {
            startedAt = Date()
            recorder.startRecording()
            phase = .recording
        }
        .onDisappear {
            if recorder.isRecording {
                recorder.stopRecording()
                recorder.finalizeRecording()
            }
        }
        .onChange(of: selectedAttachmentItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await importSelectedAttachmentItems(newItems)
            }
        }
    }

    // MARK: - Starting

    private var startingBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Text("· ARMING")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.top, 30)
    }

    // MARK: - Recording

    private var recordingBody: some View {
        VStack(spacing: 14) {
            // Real particle waveform driven by AudioRecorderManager.
            // Falls back to a flat field if mic permission isn't
            // granted yet — particles fade in once levels arrive.
            ParticlesWaveformView(
                levels: recorder.audioLevels,
                height: 56,
                color: theme.currentTheme.chrome.accent
            )
            .frame(height: 56)
            .padding(.horizontal, -20)

            HStack(spacing: 10) {
                RecordingPulse(color: theme.currentTheme.chrome.accent, size: 8)
                Text(timeString(recorder.recordingDuration))
                    .talkieType(.instrumentReadout)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            Text("· REC · HQ · 44.1k · MEMO")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)

            compactContextQueue

            Spacer()

            HStack(spacing: 18) {
                circleButton(
                    systemImage: "xmark",
                    label: "Cancel",
                    isPrimary: false,
                    action: cancelRecording
                )
                circleButton(
                    systemImage: "stop.fill",
                    label: "Stop",
                    isPrimary: true,
                    action: stopRecording
                )
                circleButton(
                    systemImage: "checkmark",
                    label: "Save",
                    isPrimary: false,
                    action: { stopRecording() }
                )
            }
            .padding(.bottom, 22)
        }
        .padding(.top, 4)
    }

    // MARK: - Stopped (save metadata)

    private var stoppedBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("· READY TO SAVE")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Spacer()
                Text(timeString(savedDuration))
                    .talkieType(.instrumentReadoutSmall)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            TextField("Title (optional)", text: $title)
                .talkieType(.headlineSecondary)
                .foregroundStyle(theme.colors.textPrimary)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                              lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                )

            metadataRow(label: "Started", value: startedAt.formatted(date: .omitted, time: .shortened))
            metadataRow(label: "Length",  value: timeString(savedDuration))
            metadataRow(label: "Quality", value: "HQ · 44.1k")
            metadataRow(label: "Samples", value: "\(savedLevels.count) levels")

            contextDetailsPanel

            Spacer()

            HStack(spacing: 10) {
                Button(action: discardRecording) {
                    Text("Discard")
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                                   lineWidth: theme.currentTheme.chrome.hairlineWidth)
                        )
                }
                .buttonStyle(.plain)

                Button(action: persistMemo) {
                    Text("Save memo")
                        .talkieType(.preview)
                        .foregroundStyle(theme.colors.cardBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(theme.currentTheme.chrome.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 22)
        }
        .padding(.top, 4)
        .onAppear { detent = .height(560) }
    }

    // MARK: - Saving / Saved

    private var savingBody: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(0.9)
            Text("· SAVING")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(.top, 40)
    }

    private var savedBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Text("Memo saved")
                .talkieType(.listTitle)
                .foregroundStyle(theme.colors.textPrimary)
        }
        .padding(.top, 40)
    }

    // MARK: - Context queue

    private var compactContextQueue: some View {
        HStack(spacing: 8) {
            contextPill(systemImage: "photo.on.rectangle", label: "Photos", action: showPhotosPicker)

            ForEach(RecordingSidecarKind.allCases, id: \.self) { kind in
                contextPill(systemImage: kind.iconName, label: kind.displayName) {
                    queueSidecarRequest(kind)
                }
            }

            Spacer(minLength: 0)

            if queuedContextCount > 0 {
                Text("\(queuedContextCount)")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent.opacity(0.14)))
            }
        }
    }

    private var contextDetailsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("· CONTEXT")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                Spacer()
                if queuedContextCount > 0 {
                    Text("\(queuedContextCount) QUEUED")
                        .talkieType(.channelLabelTiny)
                        .foregroundStyle(theme.currentTheme.chrome.accent)
                }
            }

            compactContextQueue

            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            pendingAttachmentTile(attachment)
                        }
                    }
                }
            }

            if !pendingSidecarRequests.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingSidecarRequests) { request in
                            pendingSidecarTile(request)
                        }
                    }
                }
            }

            if let attachmentError {
                Text(attachmentError)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.colors.cardBackground.opacity(0.68))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    private func contextPill(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(label.uppercased())
                    .talkieType(.channelLabelTiny)
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(theme.colors.cardBackground.opacity(0.7))
                    .overlay(
                        Capsule()
                            .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                          lineWidth: theme.currentTheme.chrome.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func pendingAttachmentTile(_ attachment: RecordingSheetPendingAttachment) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: attachment.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )

            Button(action: { removePendingAttachment(attachment) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.cardBackground)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    private func pendingSidecarTile(_ request: RecordingSidecarRequest) -> some View {
        HStack(spacing: 8) {
            Image(systemName: request.kind.iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.currentTheme.chrome.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(request.kind.displayName)
                    .talkieType(.fieldLabel)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Queued at \(timeString(request.queuedAtOffset))")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Button(action: { removeSidecarRequest(request) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.colors.textTertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(theme.colors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(theme.currentTheme.chrome.edgeFaint,
                                      lineWidth: theme.currentTheme.chrome.hairlineWidth)
                )
        )
    }

    // MARK: - Actions

    private func cancelRecording() {
        recorder.stopRecording()
        recorder.finalizeRecording()
        // Delete the temp file
        if let url = recorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        controller.isPresented = false
    }

    private func stopRecording() {
        // Snapshot duration + levels BEFORE finalizing — the recorder
        // resets isRecording and may clear state on finalize.
        savedDuration = recorder.recordingDuration
        savedLevels = recorder.audioLevels
        recorder.stopRecording()
        recorder.finalizeRecording()
        savedURL = recorder.currentRecordingURL
        phase = .stopped
        detent = .height(560)
    }

    private func discardRecording() {
        if let url = savedURL {
            try? FileManager.default.removeItem(at: url)
        }
        controller.isPresented = false
    }

    private func persistMemo() {
        guard let url = savedURL else {
            controller.isPresented = false
            return
        }
        phase = .saving

        let context = PersistenceController.shared.container.viewContext
        let memo = VoiceMemo(context: context)
        memo.id = UUID()
        memo.title = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? defaultTitle
            : title
        memo.createdAt = startedAt
        memo.lastModified = Date()
        memo.duration = savedDuration
        memo.fileURL = url.lastPathComponent
        memo.isTranscribing = false
        memo.sortOrder = Int32(Date().timeIntervalSince1970 * -1)
        memo.originDeviceId = PersistenceController.deviceId
        memo.autoProcessed = false
        memo.timezone = TimeZone.current.identifier
        memo.deviceModel = UIDevice.modelIdentifier

        if !savedLevels.isEmpty {
            memo.averageAmplitude = savedLevels.reduce(0, +) / Float(savedLevels.count)
            memo.peakAmplitude = savedLevels.max() ?? 0
            if let waveformData = try? JSONEncoder().encode(savedLevels) {
                memo.waveformData = waveformData
            }
        }

        if let audioData = try? Data(contentsOf: url) {
            memo.audioData = audioData
        }

        do {
            try context.save()
            if let memoID = memo.id {
                persistQueuedContext(for: memoID, memoTitle: memo.title ?? defaultTitle)
            }
            phase = .saved
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                controller.isPresented = false
            }
        } catch {
            // Best-effort: dismiss; the recording file stays on disk.
            controller.isPresented = false
        }
    }

    private func persistQueuedContext(for memoID: UUID, memoTitle: String) {
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
            memoTitle: memoTitle
        )
    }

    private func importSelectedAttachmentItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    continue
                }
                await MainActor.run {
                    addPendingAttachment(image: image, data: data, preferredName: nil)
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

    private func addPendingAttachment(image: UIImage, data: Data, preferredName: String?) {
        let name = preferredName ?? "Image_\(Int(Date().timeIntervalSince1970))"
        pendingAttachments.insert(
            RecordingSheetPendingAttachment(
                image: image,
                data: data,
                preferredName: name
            ),
            at: 0
        )
        attachmentError = nil
        detent = .height(560)
    }

    private func removePendingAttachment(_ attachment: RecordingSheetPendingAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }

    private func queueSidecarRequest(_ kind: RecordingSidecarKind) {
        pendingSidecarRequests.append(
            RecordingSidecarRequest(
                kind: kind,
                queuedAtOffset: recorder.recordingDuration
            )
        )
        detent = .height(560)
    }

    private func removeSidecarRequest(_ request: RecordingSidecarRequest) {
        pendingSidecarRequests.removeAll { $0.id == request.id }
    }

    private func showPhotosPicker() {
        showingAttachmentPhotoPicker = true
    }

    // MARK: - Helpers

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        let m = total / 60
        let s = total % 60
        let ms = Int((t - TimeInterval(total)) * 10)
        return String(format: "%01d:%02d.%d", m, s, ms)
    }

    private var defaultTitle: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d · h:mm a"
        return "Memo \(df.string(from: startedAt))"
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .talkieType(.channelLabelSmall)
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.uppercase)
            Spacer()
            Text(value)
                .talkieType(.preview)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    @ViewBuilder
    private func circleButton(systemImage: String, label: String, isPrimary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isPrimary ? theme.currentTheme.chrome.accent : theme.colors.cardBackground)
                        .overlay(Circle().strokeBorder(
                            isPrimary ? Color.clear : theme.currentTheme.chrome.edgeFaint,
                            lineWidth: theme.currentTheme.chrome.hairlineWidth
                        ))
                    Image(systemName: systemImage)
                        .font(.system(size: isPrimary ? 20 : 15, weight: .medium))
                        .foregroundStyle(isPrimary ? theme.colors.cardBackground : theme.colors.textSecondary)
                }
                .frame(width: isPrimary ? 60 : 44, height: isPrimary ? 60 : 44)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)

                Text(label)
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.colors.textTertiary)
                    .textCase(.uppercase)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecordingSheetPendingAttachment: Identifiable {
    let id = UUID()
    let image: UIImage
    let data: Data
    let preferredName: String
}
