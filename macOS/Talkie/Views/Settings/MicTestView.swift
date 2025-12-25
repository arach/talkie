//
//  MicTestView.swift
//  Talkie
//
//  A fun, low-stakes mic test for validating audio input
//

import SwiftUI
import AVFoundation
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "MicTest")

// MARK: - Mic Test View

struct MicTestView: View {
    @State private var state: MicTestState = .idle
    @State private var audioLevel: Float = 0
    @State private var recordedURL: URL?
    @State private var recordingDuration: TimeInterval = 0
    @State private var playbackProgress: Double = 0

    @StateObject private var recorder = MicTestRecorder()

    private let maxDuration: TimeInterval = 5.0

    private let prompts = [
        "Say hi! 👋",
        "Tell us something fun",
        "Test, test, 1-2-3",
        "What's on your mind?",
        "Speak your truth ✨"
    ]

    @State private var currentPrompt: String = ""

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("MIC TEST")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundColor(Theme.current.foregroundSecondary)

                Spacer()

                if state == .hasRecording {
                    Button(action: reset) {
                        Text("Reset")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.current.foregroundSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Main content area
            VStack(spacing: 16) {
                switch state {
                case .idle:
                    idleView
                case .recording:
                    recordingView
                case .hasRecording:
                    playbackView
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Theme.current.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
        }
        .onAppear {
            currentPrompt = prompts.randomElement() ?? prompts[0]
        }
        .onChange(of: recorder.audioLevel) { _, level in
            audioLevel = level
        }
        .onChange(of: recorder.recordedURL) { _, url in
            if let url = url {
                recordedURL = url
                state = .hasRecording
            }
        }
        .onChange(of: recorder.isRecording) { _, isRecording in
            if isRecording {
                state = .recording
            }
        }
        .onChange(of: recorder.duration) { _, duration in
            recordingDuration = duration
            if duration >= maxDuration {
                stopRecording()
            }
        }
        .onChange(of: recorder.playbackProgress) { _, progress in
            playbackProgress = progress
        }
        .onChange(of: recorder.isPlaying) { _, isPlaying in
            if !isPlaying && state == .hasRecording {
                playbackProgress = 0
            }
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.circle")
                .font(.system(size: 36))
                .foregroundColor(Theme.current.foregroundSecondary)

            Text(currentPrompt)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.current.foreground)

            Button(action: startRecording) {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Record")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.red))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 12) {
            // Animated waveform
            HStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: 4, height: barHeight(for: i))
                        .animation(.easeInOut(duration: 0.1), value: audioLevel)
                }
            }
            .frame(height: 40)

            // Timer
            Text(formatTime(recordingDuration))
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundColor(.red)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: geo.size.width * (recordingDuration / maxDuration), height: 4)
                }
            }
            .frame(height: 4)

            Button(action: stopRecording) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10))
                    Text("Stop")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.red))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Playback View

    private var playbackView: some View {
        VStack(spacing: 12) {
            // Success state
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)

                Text("Sounds good!")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.current.foreground)
            }

            // Duration
            Text(formatTime(recordingDuration))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.current.foregroundSecondary)

            // Playback progress
            if recorder.isPlaying {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(width: geo.size.width * playbackProgress, height: 4)
                    }
                }
                .frame(height: 4)
            }

            // Play button
            Button(action: togglePlayback) {
                HStack(spacing: 6) {
                    Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                    Text(recorder.isPlaying ? "Pause" : "Play Back")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.green))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var borderColor: Color {
        switch state {
        case .idle: return Theme.current.divider
        case .recording: return .red.opacity(0.5)
        case .hasRecording: return .green.opacity(0.3)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 36
        let variation = sin(Double(index) * 0.8 + Double(recordingDuration) * 3) * 0.3 + 0.7
        let levelFactor = CGFloat(audioLevel) * variation
        return baseHeight + (maxHeight - baseHeight) * levelFactor
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        let ms = Int((seconds - Double(s)) * 10)
        return String(format: "%d.%d", s, ms)
    }

    // MARK: - Actions

    private func startRecording() {
        recorder.startRecording()
    }

    private func stopRecording() {
        recorder.stopRecording()
    }

    private func togglePlayback() {
        if recorder.isPlaying {
            recorder.pausePlayback()
        } else if let url = recordedURL {
            recorder.playRecording(url: url)
        }
    }

    private func reset() {
        recorder.stopPlayback()
        recordedURL = nil
        recordingDuration = 0
        playbackProgress = 0
        state = .idle
        currentPrompt = prompts.randomElement() ?? prompts[0]
    }
}

// MARK: - State

private enum MicTestState {
    case idle
    case recording
    case hasRecording
}

// MARK: - Recorder

@MainActor
private class MicTestRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var audioLevel: Float = 0
    @Published var duration: TimeInterval = 0
    @Published var playbackProgress: Double = 0
    @Published var recordedURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var levelTimer: Timer?
    private var playbackTimer: Timer?

    private var tempURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mic_test.m4a")
    }

    func startRecording() {
        // Clean up any previous recording
        try? FileManager.default.removeItem(at: tempURL)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: tempURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            duration = 0

            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateLevel()
                }
            }

            logger.info("Mic test recording started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioRecorder?.stop()
        isRecording = false
        audioLevel = 0

        if FileManager.default.fileExists(atPath: tempURL.path) {
            recordedURL = tempURL
            logger.info("Mic test recording saved: \(self.duration)s")
        }
    }

    func playRecording(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true

            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updatePlaybackProgress()
                }
            }

            logger.info("Mic test playback started")
        } catch {
            logger.error("Failed to play recording: \(error.localizedDescription)")
        }
    }

    func pausePlayback() {
        audioPlayer?.pause()
        isPlaying = false
        playbackTimer?.invalidate()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackProgress = 0
        playbackTimer?.invalidate()
    }

    private func updateLevel() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }
        recorder.updateMeters()
        duration = recorder.currentTime

        // Convert dB to 0-1 range
        let db = recorder.averagePower(forChannel: 0)
        let normalized = max(0, (db + 60) / 60) // -60dB to 0dB -> 0 to 1
        audioLevel = pow(normalized, 0.5) // Square root for better visual response
    }

    private func updatePlaybackProgress() {
        guard let player = audioPlayer else { return }
        if player.duration > 0 {
            playbackProgress = player.currentTime / player.duration
        }
    }
}

extension MicTestRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            playbackProgress = 0
            playbackTimer?.invalidate()
        }
    }
}

// MARK: - Preview

#Preview {
    MicTestView()
        .frame(width: 300)
        .padding()
}
