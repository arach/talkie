//
//  EphemeralTranscriber.swift
//  Talkie
//
//  Ephemeral voice capture for voice guidance in Interstitial
//  Captures audio → transcribes via TalkieEngine → returns text (no persistence)
//

import AVFoundation
import AppKit
import os
import Observation

private let logger = Logger(subsystem: "jdi.talkie.core", category: "EphemeralTranscriber")

/// Ephemeral transcription service for voice guidance
/// Captures audio, transcribes via TalkieEngine, returns text without any persistence
@MainActor
@Observable
public final class EphemeralTranscriber {
    public static let shared = EphemeralTranscriber()

    // MARK: - Published State

    public private(set) var isRecording: Bool = false
    public private(set) var isTranscribing: Bool = false
    public private(set) var audioLevel: Float = 0
    public private(set) var error: String?

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var fileCreated = false

    private init() {}

    // MARK: - Public API

    /// Start capturing audio from the microphone
    public func startCapture() throws {
        guard !isRecording else {
            logger.warning("Already recording")
            return
        }

        error = nil

        // Create audio engine
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let inputNode = engine.inputNode

        // Prepare temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("ephemeral_\(UUID().uuidString)").appendingPathExtension("m4a")
        self.tempFileURL = fileURL
        self.fileCreated = false

        // Install tap - create file lazily based on actual buffer format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Create file lazily on first buffer
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
                self.audioLevel = level
            }
        }

        do {
            try engine.start()
            isRecording = true
            logger.info("Ephemeral capture started")
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            throw EphemeralTranscriberError.captureStartFailed(error.localizedDescription)
        }
    }

    /// Stop capturing and transcribe the audio
    /// Returns the transcribed text
    public func stopAndTranscribe() async throws -> String {
        guard isRecording else {
            throw EphemeralTranscriberError.notRecording
        }

        // Stop capture
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        audioLevel = 0

        // Close audio file
        audioFile = nil

        guard let fileURL = tempFileURL else {
            throw EphemeralTranscriberError.noAudioFile
        }

        // Validate file
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size > 1000 else {
            cleanup()
            throw EphemeralTranscriberError.audioFileTooSmall
        }

        logger.info("Captured audio: \(size) bytes")

        // Transcribe
        isTranscribing = true
        defer {
            isTranscribing = false
            cleanup()
        }

        do {
            // Use EngineClient to transcribe
            let transcript = try await EngineClient.shared.transcribe(
                audioPath: fileURL.path,
                modelId: "parakeet:v3"  // Use fast model for voice instructions
            )
            logger.info("Transcribed: \(transcript.prefix(50))...")
            return transcript
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription)")
            throw EphemeralTranscriberError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Cancel any ongoing capture without transcribing
    public func cancel() {
        if isRecording {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            isRecording = false
            audioLevel = 0
        }
        audioFile = nil
        cleanup()
        logger.info("Capture cancelled")
    }

    // MARK: - Private Helpers

    private func createAudioFile(matching buffer: AVAudioPCMBuffer) {
        guard let fileURL = tempFileURL else { return }

        let format = buffer.format
        logger.info("Buffer format: \(format.sampleRate)Hz, \(format.channelCount)ch")

        // Create file with AAC encoding
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            fileCreated = true
            logger.info("Created temp audio file")
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
        // Amplify for visual response
        return min(1.0, rms * 8.0)
    }

    private func cleanup() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            logger.debug("Cleaned up temp file")
        }
        tempFileURL = nil
        fileCreated = false
    }
}

// MARK: - Errors

public enum EphemeralTranscriberError: LocalizedError {
    case captureStartFailed(String)
    case notRecording
    case noAudioFile
    case audioFileTooSmall
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .captureStartFailed(let reason):
            return "Failed to start capture: \(reason)"
        case .notRecording:
            return "Not currently recording"
        case .noAudioFile:
            return "No audio file created"
        case .audioFileTooSmall:
            return "Recording too short"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
