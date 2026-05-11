//
//  RecordingView.swift
//  TalkieWatch
//
//  Recording UI matching iOS app design
//

import SwiftUI

/// UI phases for the recording view
private enum RecordingPhase: Equatable {
    case idle
    case recording
    case sending
    case sent
    case failed(String)
}

struct RecordingView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @StateObject private var recorder = AudioRecorder()
    @State private var recPulse = false
    @State private var showPostRecording = false  // Track post-recording state locally

    /// Current UI phase
    private var phase: RecordingPhase {
        if recorder.isRecording {
            return .recording
        } else if showPostRecording {
            switch sessionManager.lastSentStatus {
            case .sending:
                return .sending
            case .sent:
                return .sent
            case .failed(let error):
                return .failed(error)
            case .idle:
                return .sending  // Brief moment before status updates
            }
        } else {
            return .idle
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            switch phase {
            case .idle:
                // Ready state - show connection status + record button
                idleView

            case .recording:
                // Recording state - show REC, particles, duration, stop button
                recordingView

            case .sending:
                // Sending state - spinner + message, no button
                sendingView

            case .sent:
                // Sent confirmation - checkmark, then fade back
                sentView

            case .failed(let error):
                // Error state - show error + retry button
                failedView(error: error)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            #if DEBUG
            debugVersionInfo
            #endif
        }
        .onChange(of: sessionManager.lastSentStatus) {
            let newStatus = sessionManager.lastSentStatus
            if case .sent = newStatus {
                // After "Sent" shows, reset to idle after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showPostRecording = false
                    }
                }
            } else if case .idle = newStatus {
                // Status reset, clear post-recording flag
                showPostRecording = false
            }
        }
    }

    // MARK: - Phase Views

    private var idleView: some View {
        VStack(spacing: 12) {
            Spacer()

            // Connection status
            if sessionManager.isReachable {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            } else {
                Label("Will queue", systemImage: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }

            Spacer()

            // Record button
            recordButton
        }
    }

    private var recordingView: some View {
        VStack(spacing: 8) {
            // REC indicator with pulse
            recIndicator

            // Particles animation
            ParticlesView(level: recorder.currentLevel)
                .frame(height: 40)

            // Duration
            Text(formatDuration(recorder.recordingDuration))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))

            Spacer(minLength: 4)

            // Stop button
            stopButton
        }
    }

    private var sendingView: some View {
        VStack(spacing: 16) {
            Spacer()

            BrailleSpinner(size: 18, color: .blue)

            Text("Sending to iPhone...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.9))

            Spacer()
        }
    }

    private var sentView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text("Sent!")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.green)

            Spacer()
        }
    }

    private func failedView(error: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.red)

            Text(error)
                .font(.system(size: 11))
                .foregroundColor(.red.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Spacer()

            // Retry/dismiss button
            Button(action: {
                withAnimation {
                    showPostRecording = false
                    sessionManager.lastSentStatus = .idle
                }
            }) {
                Text("Dismiss")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.3))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
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

    // MARK: - Record Button (idle state)

    private var recordButton: some View {
        Button(action: startRecording) {
            ZStack {
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
        .buttonStyle(.plain)
    }

    // MARK: - Stop Button (recording state)

    private var stopButton: some View {
        Button(action: stopRecording) {
            ZStack {
                // Glow
                Circle()
                    .fill(Color.red)
                    .frame(width: 60, height: 60)
                    .blur(radius: 15)
                    .opacity(0.5)

                // Ring
                Circle()
                    .strokeBorder(Color.red, lineWidth: 3)
                    .frame(width: 54, height: 54)

                // Stop square
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.red)
                    .frame(width: 18, height: 18)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func startRecording() {
        recorder.startRecording()
    }

    private func stopRecording() {
        // Stop recording and transition to sending state
        if let audioURL = recorder.stopRecording() {
            withAnimation(.easeInOut(duration: 0.2)) {
                showPostRecording = true
            }
            sessionManager.sendAudio(fileURL: audioURL)
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    #if DEBUG
    private var debugVersionInfo: some View {
        Text(buildTimestamp)
            .font(.system(size: 8, design: .monospaced))
            .foregroundColor(.white.opacity(0.3))
            .padding(.bottom, 2)
    }

    private var buildTimestamp: String {
        // Get build date from executable modification time
        guard let executablePath = Bundle.main.executablePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath),
              let modDate = attributes[.modificationDate] as? Date else {
            return "Build: ?"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "M/d h:mm a"
        return "Built: \(formatter.string(from: modDate))"
    }
    #endif
}

// MARK: - Braille Spinner (matches TalkieMobileKit)

/// Minimal braille spinner for loading states
private struct BrailleSpinner: View {
    var size: CGFloat = 14
    var speed: Double = 0.08
    var color: Color = .secondary

    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    var body: some View {
        TimelineView(.periodic(from: .now, by: speed)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let frame = Int(elapsed / speed) % Self.frames.count
            Text(Self.frames[frame])
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .accessibilityLabel("Loading")
        }
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
