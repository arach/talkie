//
//  VoiceCommandService.swift
//  Talkie
//
//  Voice command capture and intent recognition.
//  Captures audio → transcribes via Engine → recognizes intent → returns structured result.
//
//  Uses the same audio capture approach as EphemeralTranscriber but with intent recognition
//  post-processing in the Engine.
//

import AVFoundation
import Foundation
import Observation
import TalkieKit
import CoreAudio
import AudioToolbox

private let log = Log(.system)

// MARK: - Voice Command Service

/// Service for capturing voice commands and recognizing intents
/// Atomic flow: capture audio → transcribe → recognize intent → return IntentResult
@MainActor
@Observable
public final class VoiceCommandService {
    public static let shared = VoiceCommandService()

    // MARK: - State

    public private(set) var isRecording = false
    public private(set) var isProcessing = false
    public private(set) var audioLevel: Float = 0
    public private(set) var lastError: String?

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var fileCreated = false
    private var captureStartTime: CFAbsoluteTime = 0

    private init() {}

    // MARK: - Public API

    /// Start capturing voice command
    public func startCapture() throws {
        log.info("[VoiceCmd:Capture] startCapture() entry, isRecording=\(isRecording), hasEngine=\(audioEngine != nil)")
        guard !isRecording else {
            log.warning("[VoiceCmd:Capture] Already recording, returning")
            return
        }

        lastError = nil
        isRecording = false  // Reset state
        isProcessing = false
        captureStartTime = CFAbsoluteTimeGetCurrent()

        // Reuse existing engine or create new one (persistent engine pattern)
        let engine: AVAudioEngine
        if let existing = audioEngine {
            log.info("[VoiceCmd:Capture] Reusing existing engine")
            engine = existing
        } else {
            log.info("[VoiceCmd:Capture] Creating new engine")
            engine = AVAudioEngine()
            self.audioEngine = engine
            configureInputDevice(engine: engine)
            engine.reset()
        }

        let inputNode = engine.inputNode
        log.info("[VoiceCmd:Capture] Got inputNode, installing tap")

        // Prepare temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("voice_cmd_\(UUID().uuidString)").appendingPathExtension("wav")
        self.tempFileURL = fileURL
        self.fileCreated = false

        // Install tap
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }

            if !self.fileCreated {
                self.createAudioFile(matching: buffer)
            }

            guard let audioFile = self.audioFile else { return }

            do {
                try audioFile.write(from: buffer)
            } catch {
                log.error("Failed to write buffer: \(error.localizedDescription)")
            }

            let level = self.calculateRMSLevel(buffer: buffer)
            Task { @MainActor in
                self.audioLevel = level
            }
        }

        do {
            log.info("[VoiceCmd:Capture] Starting engine...")
            try engine.start()
            isRecording = true
            log.info("[VoiceCmd:Capture] ✓ Engine started, recording active")
        } catch {
            log.error("[VoiceCmd:Capture] ✗ Engine start FAILED: \(error.localizedDescription)")
            inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            throw VoiceCommandError.captureStartFailed(error.localizedDescription)
        }
    }

    /// Stop capturing and recognize intent
    /// Returns the IntentResult with recognized intent, confidence, and raw text
    public func stopAndRecognize() async throws -> IntentResult {
        log.info("[VoiceCmd:Recognize] stopAndRecognize() entry, isRecording=\(isRecording)")
        guard isRecording else {
            log.error("[VoiceCmd:Recognize] Not recording, throwing error")
            throw VoiceCommandError.notRecording
        }

        let recordingDuration = CFAbsoluteTimeGetCurrent() - captureStartTime
        log.info("[VoiceCmd:Recognize] Recording duration: \(String(format: "%.2f", recordingDuration))s")

        // Stop capture (keep engine alive for reuse)
        log.info("[VoiceCmd:Recognize] Removing tap and stopping engine")
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        isRecording = false
        audioLevel = 0

        // Close audio file
        audioFile = nil

        guard let fileURL = tempFileURL else {
            log.error("[VoiceCmd:Recognize] No temp file URL")
            throw VoiceCommandError.noAudioFile
        }

        // Validate file size
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size > 1000 else {
            let actualSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
            log.error("[VoiceCmd:Recognize] Audio too short: \(actualSize) bytes")
            cleanup()
            throw VoiceCommandError.audioTooShort
        }

        log.info("[VoiceCmd:Recognize] Audio file: \(size) bytes, sending to Engine")

        // Transcribe with intent recognition
        isProcessing = true
        defer {
            isProcessing = false
            cleanup()
        }

        do {
            // Call Engine with intent recognition post-processing
            log.info("[VoiceCmd:Recognize] Calling EngineClient.transcribe()")
            let jsonResult = try await EngineClient.shared.transcribe(
                audioPath: fileURL.path,
                modelId: TalkieDefaults.ephemeralModelId,
                priority: .high,
                postProcess: .intentRecognition
            )
            log.info("[VoiceCmd:Recognize] Engine returned: \(jsonResult.prefix(200))...")

            // Decode the IntentResult from JSON
            guard let result = IntentResult.decode(from: jsonResult) else {
                log.error("[VoiceCmd:Recognize] Failed to decode IntentResult")
                throw VoiceCommandError.decodeFailed
            }

            log.info("[VoiceCmd:Recognize] ✓ Decoded: intent=\(result.intent.rawValue) confidence=\(String(format: "%.2f", result.confidence))")
            return result

        } catch {
            log.error("[VoiceCmd:Recognize] Transcription failed: \(error.localizedDescription)")
            throw VoiceCommandError.recognitionFailed(error.localizedDescription)
        }
    }

    /// Cancel any ongoing capture
    public func cancel() {
        if isRecording {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            isRecording = false
            audioLevel = 0
        }
        audioFile = nil
        cleanup()
        log.info("Voice command cancelled")
    }

    // MARK: - Private Helpers

    private func createAudioFile(matching buffer: AVAudioPCMBuffer) {
        guard let fileURL = tempFileURL else { return }

        let format = buffer.format
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            fileCreated = true
        } catch {
            log.error("Failed to create audio file: \(error.localizedDescription)")
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
        return min(1.0, rms * 8.0)
    }

    private func cleanup() {
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        tempFileURL = nil
        fileCreated = false
    }

    private func configureInputDevice(engine: AVAudioEngine) {
        let audioManager = AudioDeviceManager.shared
        audioManager.ensureInitialized()

        let selectedID = audioManager.selectedDeviceID
        guard selectedID != 0 else { return }

        guard let audioUnit = engine.inputNode.audioUnit else { return }

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
            let deviceName = audioManager.inputDevices.first(where: { $0.id == selectedID })?.name ?? "Unknown"
            log.debug("Using mic: \(deviceName)")
        }
    }
}

// MARK: - Errors

public enum VoiceCommandError: LocalizedError {
    case captureStartFailed(String)
    case notRecording
    case noAudioFile
    case audioTooShort
    case decodeFailed
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .captureStartFailed(let reason): return "Failed to start capture: \(reason)"
        case .notRecording: return "Not recording"
        case .noAudioFile: return "No audio file"
        case .audioTooShort: return "Recording too short"
        case .decodeFailed: return "Failed to decode intent result"
        case .recognitionFailed(let reason): return "Recognition failed: \(reason)"
        }
    }
}
