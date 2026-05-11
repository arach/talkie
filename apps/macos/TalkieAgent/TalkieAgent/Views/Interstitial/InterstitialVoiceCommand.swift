//
//  InterstitialVoiceCommand.swift
//  TalkieAgent
//
//  Voice command capture for interstitial LLM instructions.
//  Records user's spoken command (e.g., "make this more professional")
//  which is then used as an LLM prompt to transform the text.
//
//  NOTE: This is separate from dictation. Dictation appends verbatim
//  transcribed text. Voice commands instruct the LLM what to do.
//

import AVFoundation
import TalkieKit

private let log = Log(.audio)

/// Voice command capture for interstitial LLM instructions.
/// Records spoken command → transcribes → uses as LLM prompt.
@MainActor
public final class InterstitialVoiceCommand {
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var isCapturing = false
    private var fileCreated = false

    /// Current audio level for UI visualization
    private(set) var audioLevel: Float = 0

    /// Whether currently recording
    var isRecording: Bool { isCapturing }

    init() {}

    /// Start capturing audio for instruction
    func startCapture() throws {
        guard !isCapturing else {
            log.warning("Already capturing")
            return
        }

        // Create temp file path (file created lazily on first buffer)
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "interstitial_command_\(UUID().uuidString).wav"
        tempFileURL = tempDir.appendingPathComponent(filename)
        fileCreated = false

        guard tempFileURL != nil else {
            throw CaptureError.fileCreationFailed
        }

        // Create fresh audio engine
        let newEngine = AVAudioEngine()
        self.engine = newEngine

        let inputNode = newEngine.inputNode

        // Install tap with nil format to use hardware format
        // File will be created lazily based on actual buffer format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Create file lazily on first buffer with matching format
            if !self.fileCreated {
                self.createAudioFile(matching: buffer)
            }

            guard let file = self.audioFile else { return }

            // Calculate audio level from first channel
            if let channelData = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<count {
                    let sample = channelData[i]
                    sum += sample * sample
                }
                let rms = sqrt(sum / Float(max(count, 1)))

                Task { @MainActor in
                    self.audioLevel = rms
                }
            }

            // Write to file
            do {
                try file.write(from: buffer)
            } catch {
                log.error("Failed to write audio buffer", error: error)
            }
        }

        // Start engine
        newEngine.prepare()
        try newEngine.start()

        isCapturing = true
        log.info("Started voice command capture")
    }

    /// Create audio file lazily with format matching the buffer
    private func createAudioFile(matching buffer: AVAudioPCMBuffer) {
        guard let fileURL = tempFileURL else { return }

        let format = buffer.format
        log.debug("Creating audio file: \(format.sampleRate)Hz, \(format.channelCount)ch")

        // Use Linear PCM (WAV) format - matches buffer format exactly
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            fileCreated = true
            log.info("Created audio file: \(format.sampleRate)Hz, \(format.channelCount)ch")
        } catch {
            log.error("Failed to create audio file", error: error)
        }
    }

    /// Stop capturing and transcribe
    func stopAndTranscribe() async throws -> String {
        guard isCapturing else {
            throw CaptureError.notRecording
        }

        // Stop capture
        stopCapture()

        guard let fileURL = tempFileURL else {
            throw CaptureError.noAudioFile
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CaptureError.noAudioFile
        }

        // Transcribe via EngineClient
        let client = EngineClient.shared
        let connected = await client.ensureConnected()

        guard connected else {
            throw CaptureError.engineNotConnected
        }

        let modelId = LiveSettings.shared.selectedModelId
        let text = try await client.transcribe(
            audioPath: fileURL.path,
            modelId: modelId,
            priority: .userInitiated,
            postProcess: .none  // No dictionary processing for commands
        )

        // Cleanup temp file
        try? FileManager.default.removeItem(at: fileURL)
        tempFileURL = nil

        return text
    }

    /// Stop capturing and transcribe, returning both text and audio URL for persistent storage.
    /// Unlike stopAndTranscribe(), this does NOT delete the temp audio file — the caller owns cleanup.
    func stopAndTranscribePersistent() async throws -> (text: String, audioURL: URL) {
        guard isCapturing else {
            throw CaptureError.notRecording
        }

        // Stop capture
        stopCapture()

        guard let fileURL = tempFileURL else {
            throw CaptureError.noAudioFile
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CaptureError.noAudioFile
        }

        // Transcribe via EngineClient
        let client = EngineClient.shared
        let connected = await client.ensureConnected()

        guard connected else {
            throw CaptureError.engineNotConnected
        }

        let modelId = LiveSettings.shared.selectedModelId
        let text = try await client.transcribe(
            audioPath: fileURL.path,
            modelId: modelId,
            priority: .userInitiated,
            postProcess: .none
        )

        // Deliberately NOT cleaning up temp file — caller owns it
        tempFileURL = nil

        return (text: text, audioURL: fileURL)
    }

    /// Cancel recording without transcribing
    func cancel() {
        stopCapture()

        // Cleanup temp file
        if let fileURL = tempFileURL {
            try? FileManager.default.removeItem(at: fileURL)
            tempFileURL = nil
        }
    }

    private func stopCapture() {
        guard isCapturing else { return }

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        audioFile = nil
        audioLevel = 0
        isCapturing = false

        log.info("Stopped voice command capture")
    }

    enum CaptureError: LocalizedError {
        case fileCreationFailed
        case invalidFormat
        case notRecording
        case noAudioFile
        case engineNotConnected

        var errorDescription: String? {
            switch self {
            case .fileCreationFailed: return "Failed to create audio file"
            case .invalidFormat: return "Invalid audio format"
            case .notRecording: return "Not currently recording"
            case .noAudioFile: return "No audio file to transcribe"
            case .engineNotConnected: return "Engine not connected"
            }
        }
    }
}
