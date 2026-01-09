//
//  RecordingView.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import SwiftUI
import CoreData

struct RecordingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = AudioRecorderManager()
    @State private var recordingTitle = ""
    @State private var defaultTitle = ""
    @State private var recPulse = false
    @State private var waveformStyle: WaveformStyle = .particles
    @State private var sheetDetent: PresentationDetent = .height(280)
    @State private var hasAppeared = false
    @State private var isCancelling = false

    private let compactHeight: CGFloat = 280
    private let expandedHeight: CGFloat = 600

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
        .onAppear {
            if !hasAppeared {
                hasAppeared = true
                defaultTitle = "Recording \(formatDate(Date()))"
                // Start recording immediately - no delay needed
                // (watchOS version and push-to-talk both work without delay)
                recorder.startRecording()
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

                Spacer()

                // REC indicator
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(Color.recording)
                        .frame(width: 6, height: 6)
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
            if sheetDetent == .height(expandedHeight) {
                waveformStyleSwitcher
            }

            // Live waveform
            LiveWaveformView(
                levels: recorder.audioLevels,
                height: sheetDetent == .height(expandedHeight) ? 120 : 60,
                color: .recording,
                style: waveformStyle
            )
            .padding(.horizontal, Spacing.sm)
            .background(Color.surfacePrimary.opacity(0.5))
            .cornerRadius(CornerRadius.md)
            .padding(.horizontal, Spacing.lg)

            // Duration - always below waveform
            Text(formatDuration(recorder.recordingDuration))
                .font(sheetDetent == .height(expandedHeight) ? .monoLarge : .monoMedium)
                .fontWeight(.medium)
                .foregroundColor(.textPrimary)

            Spacer(minLength: Spacing.sm)

            // Stop button centered - matches list view mic button position
            Button(action: {
                recorder.stopRecording()
            }) {
                ZStack {
                    // Subtle glow while recording
                    Circle()
                        .fill(Color.recording)
                        .frame(width: 68, height: 68)
                        .blur(radius: 20)
                        .opacity(0.5)

                    // Outer ring
                    Circle()
                        .strokeBorder(Color.recording, lineWidth: 3)
                        .frame(width: 58, height: 58)

                    // Stop icon
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.recording)
                        .frame(width: 18, height: 18)
                }
            }
            .padding(.top, Spacing.xs)
            .padding(.bottom, 8)
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

                // READY indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.success)
                        .frame(width: 6, height: 6)

                    Text("READY")
                        .font(.techLabelSmall)
                        .tracking(1)
                        .foregroundColor(.success)
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

            Spacer(minLength: Spacing.xs)

            // Action buttons - Resume left, Save center
            HStack(spacing: Spacing.lg) {
                // Resume button - subtle, secondary action
                Button(action: {
                    resumeRecording()
                }) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.recording.opacity(0.6))
                        .frame(width: 48, height: 48)
                        .background(Color.surfaceSecondary.opacity(0.6))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.recording.opacity(0.3), lineWidth: 1)
                        )
                }

                // Save button - primary action, centered
                Button(action: {
                    saveRecording()
                    dismiss()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 58, height: 58)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                            )
                            .shadow(color: Color.success.opacity(0.3), radius: 6, x: 0, y: 3)

                        Image(systemName: "checkmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                // Balance spacer for resume button
                Color.clear.frame(width: 48, height: 48)
            }
            .padding(.bottom, 7)
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

            ProgressView()
                .tint(.recording)

            Text("STARTING...")
                .font(.techLabel)
                .tracking(2)
                .foregroundColor(.textSecondary)

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
                        .foregroundColor(waveformStyle == style ? .white : .textTertiary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(waveformStyle == style ? Color.recording.opacity(0.8) : Color.clear)
                        .cornerRadius(CornerRadius.sm)
                }
            }
        }
        .padding(.bottom, Spacing.xs)
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

            // Update widget with new memo
            PersistenceController.refreshWidgetData(context: viewContext)

            let memoObjectID = newMemo.objectID

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)

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

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
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

#Preview {
    RecordingView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
