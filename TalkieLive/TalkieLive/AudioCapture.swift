//
//  AudioCapture.swift
//  TalkieLive
//
//  Real microphone capture using AVAudioEngine
//

import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "live.talkie", category: "AudioCapture")

/// Shared audio level for UI visualization
@MainActor
final class AudioLevelMonitor: ObservableObject {
    static let shared = AudioLevelMonitor()
    @Published var level: Float = 0
    private init() {}
}

final class MicrophoneCapture: LiveAudioCapture {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var onChunk: ((Data) -> Void)?
    private var isCapturing = false

    func startCapture(onChunk: @escaping (Data) -> Void) {
        guard !isCapturing else {
            logger.warning("Already capturing")
            return
        }

        self.onChunk = onChunk

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        self.tempFileURL = fileURL

        // Set up audio file with AAC encoding (m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: recordingFormat.sampleRate,
            AVNumberOfChannelsKey: recordingFormat.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
        } catch {
            logger.error("Failed to create audio file: \(error.localizedDescription)")
            return
        }

        // Install tap to capture audio and measure levels
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, let audioFile = self.audioFile else { return }

            // Write to file
            do {
                try audioFile.write(from: buffer)
            } catch {
                logger.error("Failed to write audio buffer: \(error.localizedDescription)")
            }

            // Calculate RMS level for visualization
            let level = self.calculateRMSLevel(buffer: buffer)
            Task { @MainActor in
                AudioLevelMonitor.shared.level = level
            }
        }

        do {
            try engine.start()
            isCapturing = true
            logger.info("Microphone capture started")
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
        }
    }

    private func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        // Aggressive amplification for better visual response
        let level = min(1.0, rms * 8.0)
        return level
    }

    func stopCapture() {
        guard isCapturing else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        // Close the audio file
        audioFile = nil

        // Read the recorded audio and deliver it
        if let fileURL = tempFileURL {
            do {
                let audioData = try Data(contentsOf: fileURL)
                logger.info("Captured \(audioData.count) bytes of audio")
                onChunk?(audioData)

                // Clean up temp file
                try? FileManager.default.removeItem(at: fileURL)
            } catch {
                logger.error("Failed to read audio file: \(error.localizedDescription)")
            }
        }

        tempFileURL = nil
        onChunk = nil
        logger.info("Microphone capture stopped")
    }
}
