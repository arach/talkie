//
//  RecordingView.swift
//  TalkieWatch
//
//  Recording UI matching iOS app design
//

import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @StateObject private var recorder = AudioRecorder()
    @State private var recPulse = false

    var body: some View {
        VStack(spacing: 8) {
            // Status indicator
            statusView

            if recorder.isRecording {
                // REC indicator with pulse
                recIndicator

                // Particles animation
                ParticlesView(level: recorder.currentLevel)
                    .frame(height: 40)

                // Duration
                Text(formatDuration(recorder.recordingDuration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer(minLength: 4)

            // Main record button
            recordButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        if !recorder.isRecording {
            switch sessionManager.lastSentStatus {
            case .idle:
                if sessionManager.isReachable {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                } else {
                    Label("Will queue", systemImage: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }

            case .sending:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Sending...")
                        .font(.system(size: 11))
                }
                .foregroundColor(.blue)

            case .sent:
                Label("Sent!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)

            case .failed(let error):
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Record Button (matches iOS style)

    private var recordButton: some View {
        Button(action: toggleRecording) {
            ZStack {
                if recorder.isRecording {
                    // Recording state: glow + ring + stop square
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
                } else {
                    // Idle state: mic icon in circle
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 60, height: 60)

                    Circle()
                        .strokeBorder(Color.red.opacity(0.6), lineWidth: 2)
                        .frame(width: 54, height: 54)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.red)
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
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Particles Animation (simplified for watchOS)

struct ParticlesView: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.033)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerY = size.height / 2
                let levelCG = CGFloat(level)

                // Fewer particles for watch performance
                let baseCount = 15
                let bonusCount = Int(levelCG * 25)
                let particleCount = baseCount + bonusCount

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618033988749

                    // Particle position
                    let speed = 0.3 + (seed.truncatingRemainder(dividingBy: 1.0)) * 0.5
                    let xProgress = (time * speed + seed).truncatingRemainder(dividingBy: 1.0)
                    let x = CGFloat(xProgress) * size.width

                    // Y oscillation based on level
                    let baseY = sin(time * 2.5 + seed * 8) * Double(levelCG) * Double(centerY) * 0.7
                    let y = centerY + CGFloat(baseY)

                    // Size pulses with level
                    let baseSize: CGFloat = 2.0
                    let levelBonus = levelCG * 3
                    let particleSize = baseSize + levelBonus * CGFloat(0.5 + sin(seed * 4) * 0.5)

                    // Opacity
                    let opacity = 0.4 + Double(levelCG) * 0.5 * (0.5 + sin(seed * 3) * 0.5)

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )
                    context.fill(Circle().path(in: rect), with: .color(Color.red.opacity(opacity)))
                }
            }
        }
    }
}

#Preview {
    RecordingView()
        .environmentObject(WatchSessionManager.shared)
}
