//
//  PresetRecordingView.swift
//  TalkieWatch
//
//  Recording view with preset indicator
//

import SwiftUI
import WatchKit

struct PresetRecordingView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    let preset: WatchPreset
    @Binding var isRecording: Bool
    var onComplete: () -> Void

    @StateObject private var recorder = AudioRecorder()
    @State private var recPulse = false
    @State private var showSuccessOverlay = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var lastSentDuration: TimeInterval = 0

    var body: some View {
        ZStack {
            // Main recording UI
            VStack(spacing: 6) {
                // Preset indicator
                presetBadge

                if recorder.isRecording {
                    // REC indicator
                    recIndicator

                    // Particles
                    ParticlesView(level: recorder.currentLevel)
                        .frame(height: 36)

                    // Duration
                    Text(formatDuration(recorder.recordingDuration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer(minLength: 4)

                // Stop button
                stopButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .opacity(showSuccessOverlay ? 0.3 : 1)

            // Success overlay
            if showSuccessOverlay {
                successOverlay
            }
        }
        .onAppear {
            startRecording()
        }
        .onChange(of: sessionManager.lastSentStatus) { _, newStatus in
            if case .sent = newStatus {
                triggerSuccessAnimation()
            }
        }
    }

    // MARK: - Preset Badge

    private var presetBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: preset.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(preset.name.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1)
        }
        .foregroundColor(preset.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(preset.color.opacity(0.2))
        .cornerRadius(8)
    }

    // MARK: - REC Indicator

    private var recIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .scaleEffect(recPulse ? 1.3 : 0.7)
                .animation(
                    .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true),
                    value: recPulse
                )

            Text("REC")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
                .tracking(1)
        }
        .onAppear { recPulse = true }
        .onDisappear { recPulse = false }
    }

    // MARK: - Stop Button

    private var stopButton: some View {
        Button(action: stopAndSend) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 60, height: 60)
                    .blur(radius: 15)
                    .opacity(0.5)

                Circle()
                    .strokeBorder(Color.red, lineWidth: 3)
                    .frame(width: 54, height: 54)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red)
                    .frame(width: 18, height: 18)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        VStack(spacing: 10) {
            // Checkmark
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .scaleEffect(checkmarkScale * 1.2)
                    .opacity(checkmarkOpacity * 0.5)

                Circle()
                    .strokeBorder(Color.green, lineWidth: 3)
                    .frame(width: 48, height: 48)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)

                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.green)
                    .scaleEffect(checkmarkScale)
                    .opacity(checkmarkOpacity)
            }

            // Info
            VStack(spacing: 4) {
                Text("Sent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 4) {
                    Image(systemName: preset.icon)
                        .font(.system(size: 9))
                    Text(preset.name)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(preset.color)
            }
            .opacity(checkmarkOpacity)
        }
    }

    // MARK: - Actions

    private func startRecording() {
        recorder.startRecording()
    }

    private func stopAndSend() {
        let duration = recorder.recordingDuration
        if let audioURL = recorder.stopRecording() {
            // Send with preset info
            sessionManager.sendAudio(
                fileURL: audioURL,
                duration: duration,
                preset: preset
            )
        }
    }

    private func triggerSuccessAnimation() {
        lastSentDuration = recorder.recordingDuration
        showSuccessOverlay = true

        WKInterfaceDevice.current().play(.success)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }

        // Return to picker after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.3)) {
                checkmarkOpacity = 0
                checkmarkScale = 0.8
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showSuccessOverlay = false
                isRecording = false
                onComplete()
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    PresetRecordingView(
        preset: .go,
        isRecording: .constant(true),
        onComplete: {}
    )
    .environmentObject(WatchSessionManager.shared)
}
