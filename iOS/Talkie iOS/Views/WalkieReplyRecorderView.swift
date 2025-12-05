//
//  WalkieReplyRecorderView.swift
//  Talkie iOS
//
//  Quick voice reply recorder for Walkie conversations.
//  Records, transcribes, and uploads to CloudKit.
//

import SwiftUI
import AVFoundation

struct WalkieReplyRecorderView: View {
    let memoId: String
    let parentWalkieId: String?
    let onComplete: () -> Void
    let onCancel: () -> Void

    @StateObject private var recorder = AudioRecorderManager()
    @State private var state: RecorderState = .ready
    @State private var transcript: String = ""
    @State private var errorMessage: String?

    enum RecorderState {
        case ready
        case recording
        case transcribing
        case uploading
        case done
        case error
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Header
            HStack {
                Button("Cancel") {
                    cleanup()
                    onCancel()
                }
                .foregroundColor(.textSecondary)

                Spacer()

                Text("REPLY")
                    .font(.techLabel)
                    .tracking(2)
                    .foregroundColor(.textSecondary)

                Spacer()

                // Placeholder for balance
                Text("Cancel")
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)

            Spacer()

            // Main content
            VStack(spacing: Spacing.lg) {
                // Status indicator
                statusView

                // Duration (when recording)
                if state == .recording {
                    Text(formatDuration(recorder.recordingDuration))
                        .font(.monoLarge)
                        .foregroundColor(.textPrimary)
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.bodySmall)
                        .foregroundColor(.recording)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }

                // Transcript preview (when transcribing/done)
                if !transcript.isEmpty {
                    Text(transcript)
                        .font(.bodySmall)
                        .foregroundColor(.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.lg)
                }
            }

            Spacer()

            // Action buttons
            actionButtons
                .padding(.bottom, Spacing.xl)
        }
        .background(Color.surfacePrimary)
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .ready:
            VStack(spacing: Spacing.sm) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.active)
                Text("Tap to record your reply")
                    .font(.bodySmall)
                    .foregroundColor(.textSecondary)
            }

        case .recording:
            VStack(spacing: Spacing.sm) {
                // Pulsing recording indicator
                Circle()
                    .fill(Color.recording)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    )
                    .modifier(PulseModifier())

                Text("Recording...")
                    .font(.bodySmall)
                    .foregroundColor(.recording)
            }

        case .transcribing:
            VStack(spacing: Spacing.sm) {
                ProgressView()
                    .tint(.transcribing)
                    .scaleEffect(1.5)
                Text("Transcribing...")
                    .font(.bodySmall)
                    .foregroundColor(.transcribing)
            }

        case .uploading:
            VStack(spacing: Spacing.sm) {
                ProgressView()
                    .tint(.active)
                    .scaleEffect(1.5)
                Text("Sending...")
                    .font(.bodySmall)
                    .foregroundColor(.active)
            }

        case .done:
            VStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.success)
                Text("Sent!")
                    .font(.bodySmall)
                    .foregroundColor(.success)
            }

        case .error:
            VStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.recording)
                Text("Failed to send")
                    .font(.bodySmall)
                    .foregroundColor(.recording)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch state {
        case .ready:
            Button(action: startRecording) {
                Circle()
                    .fill(Color.active)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white)
                    )
            }

        case .recording:
            Button(action: stopRecording) {
                Circle()
                    .fill(Color.recording)
                    .frame(width: 72, height: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                    )
            }

        case .transcribing, .uploading:
            // No action during processing
            Circle()
                .fill(Color.surfaceSecondary)
                .frame(width: 72, height: 72)

        case .done:
            Button(action: {
                onComplete()
            }) {
                Text("Done")
                    .font(.headlineMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(Color.active)
                    .cornerRadius(CornerRadius.full)
            }

        case .error:
            HStack(spacing: Spacing.md) {
                Button(action: {
                    state = .ready
                    errorMessage = nil
                }) {
                    Text("Try Again")
                        .font(.headlineMedium)
                        .foregroundColor(.active)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .background(Color.active.opacity(0.1))
                        .cornerRadius(CornerRadius.full)
                }

                Button(action: {
                    cleanup()
                    onCancel()
                }) {
                    Text("Cancel")
                        .font(.headlineMedium)
                        .foregroundColor(.textSecondary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .background(Color.surfaceSecondary)
                        .cornerRadius(CornerRadius.full)
                }
            }
        }
    }

    // MARK: - Recording Logic

    private func startRecording() {
        state = .recording
        recorder.startRecording()
    }

    private func stopRecording() {
        recorder.finalizeRecording()
        state = .transcribing

        guard let audioURL = recorder.currentRecordingURL else {
            errorMessage = "No audio recorded"
            state = .error
            return
        }

        // Transcribe the recording
        TranscriptionService.shared.transcribe(audioURL: audioURL) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    self.transcript = text
                    self.uploadReply(audioURL: audioURL, transcript: text)

                case .failure(let error):
                    self.errorMessage = "Transcription failed: \(error.localizedDescription)"
                    self.state = .error
                }
            }
        }
    }

    private func uploadReply(audioURL: URL, transcript: String) {
        state = .uploading

        Task {
            do {
                try await WalkieService.shared.uploadReply(
                    audioURL: audioURL,
                    memoId: memoId,
                    parentWalkieId: parentWalkieId,
                    transcript: transcript
                )

                await MainActor.run {
                    state = .done
                    // Auto-dismiss after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        onComplete()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                    state = .error
                }
            }
        }
    }

    private func cleanup() {
        if recorder.isRecording {
            recorder.finalizeRecording()
        }
        // Clean up temp audio file
        if let url = recorder.currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Pulse Animation

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .opacity(isPulsing ? 0.8 : 1.0)
            .animation(
                Animation.easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

// MARK: - Preview

#Preview {
    WalkieReplyRecorderView(
        memoId: "test-memo",
        parentWalkieId: nil,
        onComplete: {},
        onCancel: {}
    )
}
