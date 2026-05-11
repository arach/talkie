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
    @State private var isSending = false  // Track sending state
    @State private var showSuccessOverlay = false
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0
    @State private var lastSentDuration: TimeInterval = 0

    var body: some View {
        ZStack {
            if recorder.isRecording {
                // Recording state - clean layout
                recordingStateView
            } else if isSending {
                // Sending state - status style
                sendingStateView
            }

            // Success overlay
            if showSuccessOverlay {
                successOverlay
            }
        }
        .opacity(showSuccessOverlay ? 0.3 : 1)
        .onAppear {
            startRecording()
        }
        .onChange(of: sessionManager.lastSentStatus) { _, newStatus in
            if case .sent = newStatus {
                triggerSuccessAnimation()
            }
        }
    }

    // MARK: - Recording State View

    private var recordingStateView: some View {
        ZStack {
            // Center: Particles + Stop button
            VStack(spacing: 8) {
                ParticlesView(level: recorder.currentLevel)
                    .frame(height: 50)

                stopButton
            }

            // Top-right: REC indicator
            VStack {
                HStack {
                    Spacer()
                    recIndicator
                }
                Spacer()
            }
            .padding(.top, 4)
            .padding(.trailing, 4)

            // Bottom-right: Timer (tactical HUD style)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(formatDuration(recorder.recordingDuration))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }
            }
            .padding(.bottom, 4)
            .padding(.trailing, 8)
        }
    }

    // MARK: - Sending State View (Status style)

    private var sendingStateView: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("STATUS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.3))
                Spacer()
            }

            // Status rows
            sendingStatusRow(
                label: "iPhone",
                value: sessionManager.isReachable ? "connected" : "waiting",
                isGood: sessionManager.isReachable
            )

            sendingStatusRow(
                label: "Recording",
                value: "complete",
                isGood: true
            )

            sendingStatusRow(
                label: "Transfer",
                value: "sending...",
                isGood: nil,  // nil = in progress
                showSpinner: true
            )

            Spacer()

            // Preset badge at bottom
            presetBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sendingStatusRow(label: String, value: String, isGood: Bool?, showSpinner: Bool = false) -> some View {
        HStack(spacing: 6) {
            if showSpinner {
                // Braille spinner (matches TalkieKit)
                BrailleSpinner(color: .blue)
            } else {
                Circle()
                    .fill(isGood == true ? Color.green : (isGood == false ? Color.orange : Color.blue))
                    .frame(width: 4, height: 4)
            }

            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            Spacer()

            Text(value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(isGood == true ? .green : (isGood == false ? .orange : .blue))
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

    // MARK: - REC Indicator (subtle, top-right)

    private var recIndicator: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.red)
                .frame(width: 5, height: 5)
                .scaleEffect(recPulse ? 1.2 : 0.8)
                .animation(
                    .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true),
                    value: recPulse
                )

            Text("REC")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.red.opacity(0.8))
                .tracking(0.5)
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
            // Transition to sending state
            withAnimation(.easeInOut(duration: 0.2)) {
                isSending = true
            }

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
        isSending = false  // Clear sending state
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

// MARK: - Braille Spinner (matches TalkieKit)

/// Minimal braille spinner for loading states - same as TalkieMobileKit version
struct BrailleSpinner: View {
    var size: CGFloat = 14
    var speed: Double = 0.08
    var color: Color = .blue

    @State private var frame = 0

    // Classic braille spinner sequence
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    var body: some View {
        Text(frames[frame])
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .onAppear {
                startAnimation()
            }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: speed, repeats: true) { _ in
            frame = (frame + 1) % frames.count
        }
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
