//
//  AudioRecorder.swift
//  TalkieWatch
//
//  Simple audio recording for watchOS
//

import Foundation
import AVFoundation

@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

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
            audioRecorder?.record()
            isRecording = true
            recordingDuration = 0

            // Update duration timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration = self?.audioRecorder?.currentTime ?? 0
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

        // Delete the file
        if let url = recordingURL {
            try? fileManager.removeItem(at: url)
        }

        audioRecorder = nil
        recordingURL = nil
        recordingDuration = 0
    }
}
