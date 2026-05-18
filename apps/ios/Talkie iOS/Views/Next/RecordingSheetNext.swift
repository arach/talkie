//
//  RecordingSheetNext.swift
//  Talkie iOS
//
//  Phase 3 — Next-style recording modal, now wired end-to-end.
//  Two detents (280 / 560), real AudioRecorderManager driving
//  ParticlesWaveformView, on Save persists a VoiceMemo via CoreData.
//

import CoreData
import SwiftUI
import TalkieMobileKit

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

    private enum Phase { case starting, recording, stopped, saving, saved }

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
    }

    // MARK: - Starting

    private var startingBody: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(theme.currentTheme.chrome.accent)
            Text("· ARMING")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
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
                    .font(.system(size: 26, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.textPrimary)
                    .tracking(-1)
            }

            Text("· REC · HQ · 44.1k · MEMO")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(theme.colors.textTertiary)

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
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(theme.currentTheme.chrome.accent)
                Spacer()
                Text(timeString(savedDuration))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.textTertiary)
            }

            TextField("Title (optional)", text: $title)
                .font(.system(size: 17, weight: .medium))
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

            Spacer()

            HStack(spacing: 10) {
                Button(action: discardRecording) {
                    Text("Discard")
                        .font(.system(size: 13, weight: .medium))
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
                        .font(.system(size: 13, weight: .semibold))
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
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(2)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.colors.textPrimary)
        }
        .padding(.top, 40)
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
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.uppercase)
            Spacer()
            Text(value)
                .font(.system(size: 13))
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
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(theme.colors.textTertiary)
                    .textCase(.uppercase)
            }
        }
        .buttonStyle(.plain)
    }
}
