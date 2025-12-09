//
//  AudioCapture.swift
//  TalkieLive
//
//  Real microphone capture using AVAudioEngine
//

import AVFoundation
import Combine
import CoreAudio
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "AudioCapture")

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
    private var fileCreated = false

    func startCapture(onChunk: @escaping (Data) -> Void) {
        guard !isCapturing else {
            logger.warning("Already capturing")
            return
        }

        self.onChunk = onChunk
        self.fileCreated = false

        // Set the selected input device before accessing inputNode
        setInputDevice()

        let inputNode = engine.inputNode

        // Prepare temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        self.tempFileURL = fileURL

        // Install tap with nil format - we'll create the file lazily based on actual buffer format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Create file lazily on first buffer - ensures format matches exactly
            if !self.fileCreated {
                self.createAudioFile(matching: buffer)
            }

            guard let audioFile = self.audioFile else { return }

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

    private func createAudioFile(matching buffer: AVAudioPCMBuffer) {
        guard let fileURL = tempFileURL else { return }

        let format = buffer.format
        logger.info("Actual buffer format: \(format.sampleRate)Hz, \(format.channelCount)ch, \(format.commonFormat.rawValue)")

        // Create file with AAC encoding matching the actual buffer format
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            fileCreated = true
            logger.info("Created audio file: \(format.sampleRate)Hz, \(format.channelCount)ch")
        } catch {
            logger.error("Failed to create audio file: \(error.localizedDescription)")
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

                if audioData.count > 1000 {
                    onChunk?(audioData)
                } else {
                    logger.warning("Audio file too small (\(audioData.count) bytes), likely empty recording")
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: fileURL)
            } catch {
                logger.error("Failed to read audio file: \(error.localizedDescription)")
            }
        } else {
            logger.warning("No temp file URL - file may not have been created")
        }

        tempFileURL = nil
        onChunk = nil
        fileCreated = false
        logger.info("Microphone capture stopped")
    }

    /// Set the input device on the audio engine's input node
    private func setInputDevice() {
        // Read directly from UserDefaults to avoid MainActor isolation
        let selectedID = UInt32(UserDefaults.standard.integer(forKey: "selectedMicrophoneID"))
        guard selectedID != 0 else {
            logger.info("Using system default microphone")
            return
        }

        // Get the audio unit from the engine's input node
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit

        guard let audioUnit = audioUnit else {
            logger.warning("Could not get audio unit from input node")
            return
        }

        // Set the input device
        var deviceID = selectedID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            logger.info("Set input device to: \(selectedID)")
        } else {
            logger.warning("Failed to set input device: \(status)")
        }
    }
}
