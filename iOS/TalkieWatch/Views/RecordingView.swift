//
//  RecordingView.swift
//  TalkieWatch
//
//  Minimal fire-and-forget recording UI
//

import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @StateObject private var recorder = AudioRecorder()

    var body: some View {
        VStack(spacing: 16) {
            // Status indicator
            statusView

            // Main record button
            recordButton

            // Duration when recording
            if recorder.isRecording {
                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        switch sessionManager.lastSentStatus {
        case .idle:
            if sessionManager.isReachable {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                Label("Will queue", systemImage: "clock.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

        case .sending:
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Sending...")
                    .font(.caption)
            }
            .foregroundColor(.blue)

        case .sent:
            Label("Sent!", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)

        case .failed(let error):
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                // Background circle
                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.red.opacity(0.2))
                    .frame(width: 80, height: 80)

                // Inner shape - circle when idle, square when recording
                if recorder.isRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 28, height: 28)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 60, height: 60)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
    }

    // MARK: - Actions

    private func toggleRecording() {
        if recorder.isRecording {
            // Stop and send
            if let audioURL = recorder.stopRecording() {
                sessionManager.sendAudio(fileURL: audioURL)
            }
        } else {
            // Start recording
            recorder.startRecording()
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

#Preview {
    RecordingView()
        .environmentObject(WatchSessionManager.shared)
}
