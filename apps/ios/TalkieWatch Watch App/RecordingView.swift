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
                    .foregroundColor(WatchTheme.current.panelInk.opacity(0.85))
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
            // .red is universally semantic for recording — keep it across themes.
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
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.red)
                .tracking(1.5)
        }
        .onAppear { recPulse = true }
        .onDisappear { recPulse = false }
    }

    // MARK: - Status View

    @ViewBuilder
    private var statusView: some View {
        if !recorder.isRecording {
            let chrome = WatchTheme.current
            switch sessionManager.lastSentStatus {
            case .idle:
                if sessionManager.isReachable {
                    // .green is universal "good/ready" — keep semantic.
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                } else {
                    // .orange is universal "warning/queued" — keep semantic.
                    Label("Will queue", systemImage: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }

            case .sending:
                HStack(spacing: 4) {
                    BrailleSpinner(size: 12, color: chrome.accent)
                    Text("Sending...")
                        .font(.system(size: 11))
                }
                .foregroundColor(chrome.accent)

            case .sent:
                // .green is universal "success" — keep semantic.
                Label("Sent!", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)

            case .failed(let error):
                // .red is universal "error" — keep semantic.
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
            Task { @MainActor in
                if let audioURL = await recorder.stopRecording() {
                    sessionManager.sendAudio(fileURL: audioURL)
                }
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
    var color: Color = .red
    var centerQuietZone: CGFloat = 0
    var particleScale: CGFloat = 1
    var isPaused = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 0.033, paused: reduceMotion || isPaused)
        ) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let centerY = size.height / 2
                let levelCG = if reduceMotion {
                    CGFloat(0.14)
                } else if isPaused {
                    CGFloat(0.06)
                } else {
                    min(max(CGFloat(level), 0), 1)
                }

                // A stable low-energy field is always present. Voice adds
                // density and vertical expansion instead of switching the
                // animation on and off.
                let baseCount = 30
                let bonusCount = Int(levelCG * 18)
                let particleCount = baseCount + bonusCount

                for i in 0..<particleCount {
                    let seed = Double(i) * 1.618033988749
                    let depth = 0.28 + seed.truncatingRemainder(dividingBy: 0.72)

                    // Slow parallax drift keeps the field atmospheric. Nearer
                    // particles move faster and read a little brighter.
                    let speed = 0.055 + depth * 0.16
                    let xProgress = (time * speed + seed * 0.37)
                        .truncatingRemainder(dividingBy: 1.0)
                    let x = CGFloat(xProgress) * size.width

                    // Each point owns a lane. The lane drifts slowly, then
                    // opens further from center as the live level increases.
                    let lane = sin(seed * 2.71) * 0.42
                    let drift = sin(time * (0.34 + depth * 0.32) + seed * 7.3) * 0.14
                    let response = sin(time * (1.1 + depth * 0.8) + seed * 11)
                        * Double(levelCG) * 0.44
                    let y = centerY + CGFloat(lane + drift + response) * centerY

                    let voiceScale = CGFloat(0.35 + sin(seed * 4) * 0.18)
                    let particleSize = (
                        0.85 + CGFloat(depth) * 1.45 + levelCG * voiceScale
                    ) * particleScale

                    // When used behind the elapsed time, form a soft negative
                    // space rather than covering the numerals with dots.
                    let distanceFromCenter = abs(x / max(size.width, 1) - 0.5)
                    let quietFactor: CGFloat = {
                        guard centerQuietZone > 0 else { return 1 }
                        let normalized = min(
                            max((distanceFromCenter - centerQuietZone) / 0.22, 0),
                            1
                        )
                        return 0.16 + normalized * 0.84
                    }()

                    let shimmer = 0.82 + sin(time * 0.72 + seed * 5) * 0.18
                    let opacity = (
                        0.20
                        + depth * 0.40
                        + Double(levelCG) * 0.30
                    ) * Double(quietFactor) * shimmer

                    let rect = CGRect(
                        x: x - particleSize / 2,
                        y: y - particleSize / 2,
                        width: particleSize,
                        height: particleSize
                    )

                    if i.isMultiple(of: 9) {
                        let haloSize = particleSize * 2.8
                        let haloRect = CGRect(
                            x: x - haloSize / 2,
                            y: y - haloSize / 2,
                            width: haloSize,
                            height: haloSize
                        )
                        context.fill(
                            Circle().path(in: haloRect),
                            with: .color(color.opacity(opacity * 0.10))
                        )
                    }

                    context.fill(Circle().path(in: rect), with: .color(color.opacity(opacity)))
                }
            }
        }
    }
}

#Preview {
    RecordingView()
        .environmentObject(WatchSessionManager.shared)
}
