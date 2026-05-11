//
//  MinimalDictationOverlay.swift
//  Talkie iOS
//
//  Ultra-minimal recording indicator for keyboard dictation.
//  Just shows essential status - nothing more.
//

import SwiftUI
import TalkieMobileKit

struct MinimalDictationOverlay: View {
    @ObservedObject private var headlessService = HeadlessDictationService.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var currentState: DictationSharedState.Phase = .idle
    @State private var recordingStartTime: Date?
    @State private var recordingDuration: TimeInterval = 0

    private let sharedStore = DictationSharedStore.shared

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: Spacing.md) {
                Spacer()

                // Minimal status
                statusContent

                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap()
        }
        .onAppear {
            currentState = sharedStore.phase
            if currentState == .recording {
                recordingStartTime = Date()
            }
        }
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in
            currentState = sharedStore.phase
            updateRecordingDuration()
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch currentState {
        case .recording:
            // Recording: red dot + duration + stop
            VStack(spacing: Spacing.md) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text(formatDuration(recordingDuration))
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }

                Button(action: handleTap) {
                    Text("Stop")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(8)
                }
            }

        case .stopping, .transcribing:
            // Processing: spinner
            HStack(spacing: 8) {
                BrailleSpinner(size: 14, color: .white.opacity(0.6))
                Text("Processing...")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }

        case .done:
            // Done: checkmark
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.green)
                Text("Done")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }

        default:
            // Starting: spinner
            HStack(spacing: 8) {
                BrailleSpinner(size: 14, color: .white.opacity(0.6))
                Text("Starting...")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func handleTap() {
        if currentState == .recording {
            KeyboardBridge.shared.requestStopRecording()
        }
    }

    private func updateRecordingDuration() {
        if currentState == .recording {
            if recordingStartTime == nil {
                recordingStartTime = Date()
            }
            recordingDuration = Date().timeIntervalSince(recordingStartTime ?? Date())
        } else {
            recordingStartTime = nil
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Preview

#Preview {
    MinimalDictationOverlay()
}
