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
    @State private var appSettings = TalkieAppSettings.shared
    @StateObject private var recorder = AudioRecorderManager()
    // Live partial-transcript ticker. Rides a parallel AVAudioEngine
    // tap beside the AVAudioRecorder — preview only; the saved
    // transcript still comes from the full-file pass after save.
    @StateObject private var liveTranscript = LiveTranscriptMonitor()

    @State private var detent: PresentationDetent = .height(330)
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
    @State private var saveErrorMessage: String?

    // First-ever-save milestone. `didCelebrateFirstSave` swaps the saved
    // state for the celebratory variant; `firstSavePulse` drives the
    // one-shot ring + checkmark spring. Recomputed from the store on each
    // save, so it fires exactly once (then quiets) — never noise.
    @State private var didCelebrateFirstSave = false
    @State private var firstSavePulse = false

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
        // 330 (was 280) — the recording screen gained a reserved
        // two-line live-transcript slot beneath the waveform.
        .presentationDetents([.height(330), .height(460), .height(560)], selection: $detent)
        .presentationDragIndicator(.hidden)
        // Theme-true sheet: the app's palette is fixed-dark per theme, but
        // `.regularMaterial` follows the SYSTEM appearance — on a light-mode
        // device it rendered light while every text color stayed dark-theme,
        // washing the sheet out. Back it with the theme's own base so the
        // inner cards (cardBackground) still read as elevated above it.
        .presentationBackground(theme.colors.background)
        .photosPicker(
            isPresented: $showingAttachmentPhotoPicker,
            selection: $selectedAttachmentItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onAppear {
            startedAt = Date()
            didCelebrateFirstSave = false
            firstSavePulse = false
            recorder.startRecording()
            Haptics.confirm.fire()        // gentle "go" the frame capture engages
            Haptics.prepare(.transition)  // warm the stop thunk so it lands instantly
            phase = .recording
            // Live preview + Live Activity ride along once the tape is
            // actually rolling. startRecording() can defer ~300ms while
            // the keyboard dictation service releases the mic, so poll
            // briefly instead of assuming the session is live — starting
            // the parallel AVAudioEngine tap before the recorder owns
            // the session would race its category setup.
            Task { @MainActor in
                for _ in 0..<4 {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard controller.isPresented, phase == .recording else { return }
                    if recorder.isRecording {
                        RecordingLiveActivityController.shared.start(startedAt: startedAt)
                        liveTranscript.start()
                        return
                    }
                }
            }
        }
        .onDisappear {
            liveTranscript.stop()
            if recorder.isRecording {
                recorder.stopRecording()
                recorder.finalizeRecording()
            }
            // Catch-all (idempotent) — covers swipe-dismiss from any phase.
            RecordingLiveActivityController.shared.end()
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

    private var recordingWaveformUsesParticles: Bool {
        appSettings.recordingWaveformStyle == .particles
    }

    private var recordingWaveformColor: Color {
        recordingWaveformUsesParticles ? .recording : theme.currentTheme.chrome.accent
    }

    private var recordingBody: some View {
        VStack(spacing: 14) {
            recordingWaveform
                .frame(height: 56)
                .padding(.horizontal, -20)

            liveTranscriptPreview

            HStack(spacing: 10) {
                RecordingPulse(color: recordingWaveformColor, size: 8)
                Text(timeString(recorder.recordingDuration))
                    .talkieType(.instrumentReadout)
                    .foregroundStyle(theme.colors.textPrimary)
            }

            Text("· REC · HQ · 44.1k · MEMO")
                .talkieType(.channelLabelTiny)
                .foregroundStyle(theme.colors.textTertiary)

            compactContextQueue(centered: true)

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
                    // Save means save: stop the tape and persist in one tap
                    // (auto-title; detail view is where naming/undo lives).
                    action: {
                        stopRecording()
                        persistMemo()
                    }
                )
            }
            .padding(.bottom, 22)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var recordingWaveform: some View {
        if recordingWaveformUsesParticles {
            ParticlesWaveformView(
                levels: recorder.audioLevels,
                height: 56,
                color: .recording
            )
            .background(theme.colors.cardBackground.opacity(0.35))
        } else {
            TapeWaveformView(
                levels: recorder.audioLevels,
                height: 56,
                color: theme.currentTheme.chrome.accent
            )
        }
    }

    // Two-line live transcript ticker beneath the waveform. The slot
    // height is RESERVED whether or not words ever arrive — degraded
    // (no speech permission, recognizer down) is just quiet emptiness,
    // never an error and never a layout jump. Tail-biased so the most
    // recent words are always the visible ones.
    private var liveTranscriptPreview: some View {
        Text(liveTranscriptTail)
            .talkieType(.fieldValue)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(2)
            .truncationMode(.head)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 34, alignment: .bottom)
            .animation(
                TalkieMotion.isReduced ? nil : .easeOut(duration: 0.18),
                value: liveTranscript.transcript
            )
            .accessibilityLabel("Live transcript preview")
    }

    /// Last ~2 lines' worth of the running partial transcript, cut on
    /// a word boundary with a leading ellipsis once it overflows.
    private var liveTranscriptTail: String {
        let text = liveTranscript.transcript
        let maxTail = 96  // ≈ two lines of 12pt mono at sheet width
        guard text.count > maxTail else { return text }
        let tail = text.suffix(maxTail)
        if let space = tail.firstIndex(of: " ") {
            return "… " + tail[tail.index(after: space)...]
        }
        return "… " + tail
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

            if let saveErrorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                    Text(saveErrorMessage)
                        .talkieType(.preview)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color(red: 0.85, green: 0.46, blue: 0.34))
            }

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
        // Content-fit height: title + metadata + context pills sit snug with
        // a small button gap, not a tall empty void. Grows to 560 only when
        // attachments/sidecars are queued (see addPendingAttachment /
        // queueSidecarRequest, which bump the detent).
        .onAppear { detent = .height(460) }
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
        Group {
            if didCelebrateFirstSave {
                firstSaveCelebration
            } else {
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
        }
    }

    // The first-ever save. A single amber ring expands out of the
    // checkmark — one tape-reel pulse, not a particle burst — and the
    // label reads like a tape spine. Earned once; every later save is
    // the quiet "Memo saved" above.
    private var firstSaveCelebration: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(
                        theme.currentTheme.chrome.accent.opacity(firstSavePulse ? 0 : 0.55),
                        lineWidth: 2
                    )
                    .frame(width: firstSavePulse ? 98 : 46,
                           height: firstSavePulse ? 98 : 46)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .scaleEffect(firstSavePulse ? 1 : 0.7)
            }
            VStack(spacing: 4) {
                Text("Your first memo")
                    .talkieType(.listTitle)
                    .foregroundStyle(theme.colors.textPrimary)
                Text("Saved to tape")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
            }
        }
        .padding(.top, 36)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62)) {
                firstSavePulse = true
            }
        }
    }

    // MARK: - Context queue

    // `centered` mirrors the chip group with Spacers on both ends so it
    // sits under the centered timer/transport on the recording screen.
    // Default (false) keeps chips left + count badge pinned right, which
    // is what the labeled · CONTEXT card on the save sheet wants.
    private func compactContextQueue(centered: Bool = false) -> some View {
        HStack(spacing: 8) {
            if centered { Spacer(minLength: 0) }

            contextPill(systemImage: "photo.on.rectangle", label: "Photos", action: showPhotosPicker)

            ForEach(RecordingSidecarKind.allCases, id: \.self) { kind in
                contextPill(systemImage: kind.iconName, label: kind.displayName) {
                    queueSidecarRequest(kind)
                }
            }

            if !centered {
                Spacer(minLength: 0)
            }

            if queuedContextCount > 0 {
                Text("\(queuedContextCount)")
                    .talkieType(.channelLabelTiny)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(theme.currentTheme.chrome.accent.opacity(0.14)))
            }

            if centered { Spacer(minLength: 0) }
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

            compactContextQueue()

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
                    // Negative-inset hit zone: ~45×45 touch target
                    // around the 15pt glyph without moving or growing
                    // the visual out of the tile corner.
                    .contentShape(Rectangle().inset(by: -15))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
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
                    // Negative-inset hit zone: 44×44 touch target
                    // without growing the 22pt visual or the tile.
                    .contentShape(Rectangle().inset(by: -11))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(request.kind.displayName)")
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
        Haptics.toggle.fire()  // neutral dismiss — nothing kept
        // Preview engine down BEFORE the recorder deactivates the
        // shared session — reverse order races the teardown.
        liveTranscript.stop()
        recorder.stopRecording()
        recorder.finalizeRecording()
        // Delete the temp file
        if let url = recorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        RecordingLiveActivityController.shared.end()
        controller.isPresented = false
    }

    private func stopRecording() {
        Haptics.transition.fire()  // firm "caught it" the instant capture ends
        // Preview engine down BEFORE the recorder deactivates the
        // shared session — reverse order races the teardown.
        liveTranscript.stop()
        // Snapshot duration + levels BEFORE finalizing — the recorder
        // resets isRecording and may clear state on finalize.
        savedDuration = recorder.recordingDuration
        savedLevels = recorder.audioLevels
        recorder.stopRecording()
        recorder.finalizeRecording()
        savedURL = recorder.currentRecordingURL
        // Tape stopped: freeze the Live Activity readout. The activity
        // itself ends on save / discard / dismiss.
        RecordingLiveActivityController.shared.markStopped()
        phase = .stopped
        detent = .height(560)
    }

    private func discardRecording() {
        Haptics.toggle.fire()  // neutral dismiss — nothing kept
        if let url = savedURL {
            try? FileManager.default.removeItem(at: url)
        }
        RecordingLiveActivityController.shared.end()
        controller.isPresented = false
    }

    private func persistMemo() {
        guard let url = savedURL else {
            RecordingLiveActivityController.shared.end()
            controller.isPresented = false
            return
        }
        saveErrorMessage = nil
        phase = .saving

        let context = PersistenceController.shared.container.viewContext
        // Detect the milestone BEFORE inserting this memo — count == 0
        // means this is the first one ever. `--celebrateFirstSave` forces
        // it so the moment can be previewed on a device that already has
        // memos.
        let isFirstMemo = Self.isFirstMemoSave(in: context)
        let memo = VoiceMemo(context: context)
        memo.id = UUID()
        memo.title = title.trimmingCharacters(in: .whitespaces).isEmpty
            ? defaultTitle
            : title
        memo.createdAt = startedAt
        memo.lastModified = Date()
        memo.duration = savedDuration
        memo.fileURL = url.lastPathComponent
        // The detail screen may open before TranscriptionService has had a
        // chance to flip the flag. Start optimistic so the first frame reads
        // as "working" instead of empty.
        memo.isTranscribing = true
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
            VoiceMemoStore.publishChange(context: context)

            if let memoID = memo.id {
                persistQueuedContext(for: memoID, memoTitle: memo.title ?? defaultTitle)
            }

            // Kick off transcription on the saved memo. Matches the
            // donor RecordingView flow: ~500ms grace so Core Data
            // settles the write, then hand the memo + context to
            // TranscriptionService.shared which writes the transcript
            // back via isTranscribing toggling + transcription field.
            let memoObjectID = memo.objectID
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                if let savedMemo = context.object(with: memoObjectID) as? VoiceMemo {
                    AppLogger.transcription.info("Starting transcription for persisted memo")
                    TranscriptionService.shared.transcribeVoiceMemo(savedMemo, context: context)
                }
            }

            Haptics.success.fire()  // earned: you made something and it's safe
            RecordingLiveActivityController.shared.end()
            didCelebrateFirstSave = isFirstMemo
            if isFirstMemo {
                // Kerchunk — the sound of committing to tape. Safe here:
                // the mic is already closed, so it can't bleed in. Small
                // delay lets the recorder release the audio session first.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(140))
                    WalkieFX.shared.playOpeningClick()
                }
            }
            phase = .saved
            // Let the first-save moment breathe before the sheet dismisses.
            let savedMemoID = memo.id?.uuidString
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(isFirstMemo ? 1800 : 700))
                controller.isPresented = false
                if let savedMemoID {
                    try? await Task.sleep(for: .milliseconds(80))
                    AppShellRouter.shared.openMemoDetail(memoID: savedMemoID)
                }
            }
        } catch {
            // A failed save must never look like success: stay open, say so,
            // and let the user retry from the metadata screen. Roll back the
            // failed insert so a retry doesn't create a duplicate memo; the
            // recording file stays on disk either way.
            context.delete(memo)
            Haptics.error.fire()
            // Save failed: the recording is over either way — don't
            // leave a stale island up while the user decides on retry.
            RecordingLiveActivityController.shared.end()
            saveErrorMessage = "Couldn’t save the memo — tap Save to try again. Your audio is safe on disk."
            phase = .stopped
        }
    }

    /// True when no memo exists yet (this save is the first ever), or when
    /// the `--celebrateFirstSave` launch arg forces the milestone for preview.
    private static func isFirstMemoSave(in context: NSManagedObjectContext) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--celebrateFirstSave") {
            return true
        }
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: "VoiceMemo")
        let count = (try? context.count(for: request)) ?? 1
        return count == 0
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
            .frame(width: isPrimary ? 76 : 56, height: 82)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(label == "Stop" ? "recording.stop" : "recording.\(label.lowercased())")
    }
}

private struct RecordingSheetPendingAttachment: Identifiable {
    let id = UUID()
    let image: UIImage
    let data: Data
    let preferredName: String
}
