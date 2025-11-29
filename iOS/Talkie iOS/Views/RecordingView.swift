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
    @State private var showDeleteConfirmation = false
    @State private var recPulse = false
    @State private var waveformStyle: WaveformStyle = .particles
    @State private var sheetDetent: PresentationDetent = .height(280)
    @State private var hasAppeared = false

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

                if recorder.isRecording {
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
                // Auto-start recording immediately
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    recorder.startRecording()
                }
            }
        }
        .alert("Delete Recording?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteRecording()
                dismiss()
            }
        } message: {
            Text("This recording will be permanently deleted.")
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

            // Stop button centered - same size as list view (52pt), subtle glow while recording
            Button(action: {
                recorder.stopRecording()
            }) {
                ZStack {
                    // Subtle glow while recording
                    Circle()
                        .fill(Color.recording)
                        .frame(width: 60, height: 60)
                        .blur(radius: 20)
                        .opacity(0.5)

                    // Outer ring
                    Circle()
                        .strokeBorder(Color.recording, lineWidth: 3)
                        .frame(width: 52, height: 52)

                    // Stop icon
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.recording)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.bottom, Spacing.md)
        }
    }

    // MARK: - Stopped Content (Ready to Save)

    private var stoppedContent: some View {
        VStack(spacing: Spacing.sm) {
            // Duration display
            HStack {
                Text(formatDuration(recorder.recordingDuration))
                    .font(.monoMedium)
                    .foregroundColor(.textSecondary)

                Text("•")
                    .foregroundColor(.textTertiary)

                Text("READY")
                    .font(.techLabelSmall)
                    .tracking(1)
                    .foregroundColor(.success)
            }

            // Rename input - always visible with label
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("RECORDING NAME")
                    .font(.techLabelSmall)
                    .tracking(1)
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, Spacing.xs)

                TextField(defaultTitle, text: $recordingTitle)
                    .font(.bodySmall)
                    .foregroundColor(.textPrimary)
                    .padding(Spacing.sm)
                    .background(Color.surfacePrimary)
                    .cornerRadius(CornerRadius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .strokeBorder(Color.active.opacity(0.5), lineWidth: 1)
                    )
            }
            .padding(.horizontal, Spacing.lg)

            Spacer(minLength: Spacing.sm)

            // Action buttons
            HStack(spacing: Spacing.md) {
                // Delete button
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.recording)
                        .frame(width: 48, height: 48)
                        .background(Color.recording.opacity(0.1))
                        .cornerRadius(CornerRadius.full)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.recording.opacity(0.3), lineWidth: 1)
                        )
                }

                // Save button
                Button(action: {
                    saveRecording()
                    dismiss()
                }) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("SAVE")
                            .font(.techLabelSmall)
                            .tracking(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        LinearGradient(
                            colors: [Color.active, Color.activeGlow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(CornerRadius.full)
                    .shadow(color: Color.active.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
            .padding(.bottom, Spacing.md)
        }
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
        recorder.stopRecording()
        if let url = recorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
            AppLogger.recording.info("Cancelled recording: \(url.lastPathComponent)")
        }
        dismiss()
    }

    private func deleteRecording() {
        if let url = recorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
            AppLogger.recording.info("Deleted unsaved recording: \(url.lastPathComponent)")
        }
    }

    private func saveRecording() {
        guard let url = recorder.currentRecordingURL else { return }

        let newMemo = VoiceMemo(context: viewContext)
        newMemo.id = UUID()
        newMemo.title = recordingTitle.isEmpty ? defaultTitle : recordingTitle
        newMemo.createdAt = Date()
        newMemo.duration = recorder.recordingDuration
        newMemo.fileURL = url.lastPathComponent
        newMemo.isTranscribing = false
        newMemo.sortOrder = Int32(Date().timeIntervalSince1970 * -1)
        newMemo.originDeviceId = PersistenceController.deviceId

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
