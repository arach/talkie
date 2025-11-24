//
//  AudioRecorderManager.swift
//  talkie
//
//  Created by Claude Code on 2025-11-23.
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

class AudioRecorderManager: NSObject, ObservableObject {

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var audioLevels: [Float] = []
    @Published var currentRecordingURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var levelTimer: Timer?

    override init() {
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }

    func startRecording() {
        let audioFilename = getDocumentsDirectory().appendingPathComponent("\(UUID().uuidString).m4a")

        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            currentRecordingURL = audioFilename
            isRecording = true
            recordingDuration = 0
            audioLevels = []

            // Start duration timer
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.recordingDuration = self.audioRecorder?.currentTime ?? 0
            }

            // Start level monitoring timer
            levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                self?.updateAudioLevels()
            }

        } catch {
            print("Failed to start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        timer?.invalidate()
        levelTimer?.invalidate()
        isRecording = false
    }

    private func updateAudioLevels() {
        audioRecorder?.updateMeters()

        // Get both average and peak power for better dynamic range
        let averagePower = audioRecorder?.averagePower(forChannel: 0) ?? -160
        let peakPower = audioRecorder?.peakPower(forChannel: 0) ?? -160

        // Use peak power for more dynamic visualization
        // dB range is typically -160 (silence) to 0 (max)
        // We'll focus on the -50 to 0 range for speech
        let normalizedLevel: Float
        if peakPower < -50 {
            // Very quiet - show minimal bar
            normalizedLevel = 0.05
        } else {
            // Map -50 to 0 dB to 0.1 to 1.0 range
            normalizedLevel = max(0.1, min(1.0, (peakPower + 50) / 50))
        }

        audioLevels.append(normalizedLevel)

        // Keep more samples for better detail in waveform
        // Sample every 50ms, keep 20 seconds worth (400 samples)
        if audioLevels.count > 400 {
            audioLevels.removeFirst()
        }
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func getAudioDuration(url: URL) -> TimeInterval {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
}

extension AudioRecorderManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording failed")
        }
    }
}
