//
//  AudioRecorder.swift
//  TalkieWatch
//
//  Simple audio recording for watchOS with level metering
//

import Foundation
import AVFoundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var currentLevel: Float = 0  // 0.0 to 1.0 for visualization

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var timer: Timer?

    private let fileManager = FileManager.default

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            print("[Watch] Audio session setup failed: \(error)")
        }
    }

    func startRecording() {
        // Generate unique filename
        let filename = "talkie_\(Int(Date().timeIntervalSince1970)).m4a"
        let tempDir = fileManager.temporaryDirectory
        recordingURL = tempDir.appendingPathComponent(filename)

        guard let url = recordingURL else { return }

        // Recording settings optimized for speech
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true  // Enable metering
            audioRecorder?.record()
            isRecording = true
            recordingDuration = 0
            currentLevel = 0

            // Update duration and level timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self, let recorder = self.audioRecorder else { return }

                    self.recordingDuration = recorder.currentTime

                    // Update audio level
                    recorder.updateMeters()
                    let db = recorder.averagePower(forChannel: 0)
                    // Convert dB (-160 to 0) to 0.0-1.0 range
                    // Typical speech is around -30 to -10 dB
                    let normalizedLevel = max(0, min(1, (db + 50) / 50))
                    self.currentLevel = normalizedLevel
                }
            }

            print("[Watch] Recording started: \(url.lastPathComponent)")
        } catch {
            print("[Watch] Recording failed to start: \(error)")
        }
    }

    func stopRecording() -> URL? {
        timer?.invalidate()
        timer = nil

        audioRecorder?.stop()
        isRecording = false
        currentLevel = 0

        let url = recordingURL
        audioRecorder = nil

        if let url = url {
            print("[Watch] Recording stopped: \(url.lastPathComponent)")
        }

        return url
    }

    func cancelRecording() {
        timer?.invalidate()
        timer = nil

        audioRecorder?.stop()
        isRecording = false
        currentLevel = 0

        // Delete the file
        if let url = recordingURL {
            try? fileManager.removeItem(at: url)
        }

        audioRecorder = nil
        recordingURL = nil
        recordingDuration = 0
    }
}
