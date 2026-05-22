//
//  EphemeralTranscriber.swift
//  Talkie
//
//  Ephemeral voice capture for voice guidance in Interstitial
//  Captures audio → transcribes via TalkieEngine → returns text (no persistence)
//
//  Instrumented with os_signpost for Instruments profiling
//

import AVFoundation
import AppKit
import os
import os.signpost
import Observation
import TalkieKit
import CoreAudio
import AudioToolbox

private let logger = Logger(subsystem: "to.talkie.app.mac", category: "EphemeralTranscriber")

// MARK: - Performance Instrumentation

/// Signpost log for ephemeral transcription performance profiling in Instruments
private let ephemeralPerformanceLog = OSLog(subsystem: "to.talkie.app.performance", category: "Ephemeral")

/// Signposter for ephemeral transcription intervals
private let ephemeralSignposter = OSSignposter(subsystem: "to.talkie.app.performance", category: "Ephemeral")

/// Ephemeral transcription service for voice guidance
/// Captures audio, transcribes via TalkieEngine, returns text without any persistence
public enum EphemeralCapturePurpose: String {
    case unspecified
    case composeDictation
    case composeCommand
    case draftsDictation
    case draftsCommand
    case interstitialDictation
    case interstitialCommand
    case terminalDictation
    case skillsChatDictation

    var displayName: String {
        switch self {
        case .unspecified:
            return "Another voice action"
        case .composeDictation:
            return "Compose dictation"
        case .composeCommand:
            return "Compose command"
        case .draftsDictation:
            return "Drafts dictation"
        case .draftsCommand:
            return "Drafts command"
        case .interstitialDictation:
            return "Interstitial dictation"
        case .interstitialCommand:
            return "Interstitial command"
        case .terminalDictation:
            return "Terminal dictation"
        case .skillsChatDictation:
            return "Skills chat dictation"
        }
    }
}

@MainActor
@Observable
public final class EphemeralTranscriber {
    public static let shared = EphemeralTranscriber()

    // MARK: - Published State

    public private(set) var isRecording: Bool = false
    public private(set) var isTranscribing: Bool = false
    public private(set) var audioLevel: Float = 0
    public private(set) var error: String?
    public private(set) var activePurpose: EphemeralCapturePurpose?

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var fileCreated = false

    // MARK: - Instrumentation State

    /// Signpost state for the overall capture → transcribe flow
    private var captureSignpostState: OSSignpostIntervalState?
    private var captureSignpostID: OSSignpostID?

    /// Timing for performance monitoring
    private var captureStartTime: CFAbsoluteTime = 0
    private var recordingDuration: TimeInterval = 0

    private init() {}

    // MARK: - Public API

    /// Start capturing audio from the microphone
    public func startCapture(purpose: EphemeralCapturePurpose = .unspecified) throws {
        if let busyDescription = activeCaptureDescription {
            logger.warning("Capture rejected: \(busyDescription)")
            throw EphemeralTranscriberError.captureBusy(busyDescription)
        }

        error = nil
        activePurpose = purpose

        // Begin signpost interval for full capture flow
        captureSignpostID = ephemeralSignposter.makeSignpostID()
        captureSignpostState = ephemeralSignposter.beginInterval("EphemeralCapture", id: captureSignpostID!)
        captureStartTime = CFAbsoluteTimeGetCurrent()

        // Emit event for capture start
        os_signpost(.event, log: ephemeralPerformanceLog, name: "Ephemeral",
                    "capture_start")

        // Create audio engine
        let engine = AVAudioEngine()
        self.audioEngine = engine

        // Configure input device (use selected device from AudioDeviceManager)
        configureInputDevice(engine: engine)

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
            logger.info("Ephemeral capture started for \(purpose.displayName)")
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            self.audioFile = nil
            self.activePurpose = nil
            cleanup()
            endCaptureSignpost(success: false, error: "capture_start_failed")
            throw EphemeralTranscriberError.captureStartFailed(error.localizedDescription)
        }
    }

    /// Stop capturing and transcribe the audio
    /// Returns the transcribed text
    public func stopAndTranscribe() async throws -> String {
        guard isRecording else {
            throw EphemeralTranscriberError.notRecording
        }

        // Calculate recording duration
        recordingDuration = CFAbsoluteTimeGetCurrent() - captureStartTime

        // Emit event for recording stop
        os_signpost(.event, log: ephemeralPerformanceLog, name: "Ephemeral",
                    "recording_stop")

        // Stop capture
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        isTranscribing = true
        audioLevel = 0

        // Close audio file
        audioFile = nil

        guard let fileURL = tempFileURL else {
            endCaptureSignpost(success: false, error: "no_audio_file")
            throw EphemeralTranscriberError.noAudioFile
        }

        // Validate file
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size > 1000 else {
            cleanup()
            endCaptureSignpost(success: false, error: "audio_too_small")
            throw EphemeralTranscriberError.audioFileTooSmall
        }

        logger.info("Captured audio: \(size) bytes")

        // Begin transcription phase signpost
        let transcribeSignpostID = ephemeralSignposter.makeSignpostID()
        let transcribeState = ephemeralSignposter.beginInterval("EphemeralTranscribe", id: transcribeSignpostID)
        let transcribeStart = CFAbsoluteTimeGetCurrent()

        // Transcribe
        defer {
            isTranscribing = false
            cleanup()
            activePurpose = nil
        }

        do {
            // Use EngineClient to transcribe (it handles connection internally)
            let transcript = try await EngineClient.shared.transcribe(
                audioPath: fileURL.path,
                modelId: TalkieDefaults.ephemeralModelId,  // Fast model for voice instructions
                priority: .high,          // Real-time voice instructions - highest priority
                postProcess: .inverseTextNormalization
            )

            // End transcription signpost
            let transcribeDuration = CFAbsoluteTimeGetCurrent() - transcribeStart
            ephemeralSignposter.endInterval("EphemeralTranscribe", transcribeState,
                                            "words=\(transcript.split(separator: " ").count) duration=\(String(format: "%.0f", transcribeDuration * 1000))ms")

            // End overall capture signpost
            endCaptureSignpost(success: true, wordCount: transcript.split(separator: " ").count)

            // Report to performance monitor
            await MainActor.run {
                PerformanceMonitor.shared.addOperation(
                    category: .inference,
                    name: "Ephemeral Transcription",
                    duration: transcribeDuration
                )
            }

            logger.info("Transcribed: \(transcript.prefix(50))...")
            return transcript
        } catch {
            // End signposts with error
            ephemeralSignposter.endInterval("EphemeralTranscribe", transcribeState, "error")
            endCaptureSignpost(success: false, error: error.localizedDescription)

            logger.error("Transcription failed: \(error.localizedDescription)")
            throw EphemeralTranscriberError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// End the overall capture signpost with result
    private func endCaptureSignpost(success: Bool, wordCount: Int = 0, error: String? = nil) {
        guard let state = captureSignpostState else { return }

        let totalDuration = CFAbsoluteTimeGetCurrent() - captureStartTime
        let recDuration = self.recordingDuration
        if success {
            ephemeralSignposter.endInterval("EphemeralCapture", state,
                                            "success recording=\(String(format: "%.1f", recDuration))s total=\(String(format: "%.0f", totalDuration * 1000))ms words=\(wordCount)")
        } else {
            ephemeralSignposter.endInterval("EphemeralCapture", state,
                                            "failed: \(error ?? "unknown")")
        }
        captureSignpostState = nil
        captureSignpostID = nil
    }

    /// Stop capturing and transcribe, returning both text and audio URL for persistent storage.
    /// Unlike stopAndTranscribe(), this does NOT delete the temp audio file — the caller owns cleanup.
    public func stopAndTranscribePersistent() async throws -> (text: String, audioURL: URL) {
        guard isRecording else {
            throw EphemeralTranscriberError.notRecording
        }

        // Calculate recording duration
        recordingDuration = CFAbsoluteTimeGetCurrent() - captureStartTime

        // Emit event for recording stop
        os_signpost(.event, log: ephemeralPerformanceLog, name: "Ephemeral",
                    "recording_stop_persistent")

        // Stop capture
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        isTranscribing = true
        audioLevel = 0

        // Close audio file
        audioFile = nil

        guard let fileURL = tempFileURL else {
            endCaptureSignpost(success: false, error: "no_audio_file")
            throw EphemeralTranscriberError.noAudioFile
        }

        // Validate file
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size > 1000 else {
            cleanup()
            endCaptureSignpost(success: false, error: "audio_too_small")
            throw EphemeralTranscriberError.audioFileTooSmall
        }

        logger.info("Captured audio (persistent): \(size) bytes")

        // Begin transcription phase signpost
        let transcribeSignpostID = ephemeralSignposter.makeSignpostID()
        let transcribeState = ephemeralSignposter.beginInterval("EphemeralTranscribe", id: transcribeSignpostID)
        let transcribeStart = CFAbsoluteTimeGetCurrent()

        // Transcribe (no cleanup — caller owns the file)
        defer {
            isTranscribing = false
            // Deliberately NOT calling cleanup() — caller will handle the temp file
            tempFileURL = nil
            fileCreated = false
            activePurpose = nil
        }

        do {
            let transcript = try await EngineClient.shared.transcribe(
                audioPath: fileURL.path,
                modelId: TalkieDefaults.ephemeralModelId,
                priority: .high,
                postProcess: .inverseTextNormalization
            )

            let transcribeDuration = CFAbsoluteTimeGetCurrent() - transcribeStart
            ephemeralSignposter.endInterval("EphemeralTranscribe", transcribeState,
                                            "words=\(transcript.split(separator: " ").count) duration=\(String(format: "%.0f", transcribeDuration * 1000))ms")
            endCaptureSignpost(success: true, wordCount: transcript.split(separator: " ").count)

            await MainActor.run {
                PerformanceMonitor.shared.addOperation(
                    category: .inference,
                    name: "Ephemeral Transcription (Persistent)",
                    duration: transcribeDuration
                )
            }

            logger.info("Transcribed (persistent): \(transcript.prefix(50))...")
            return (text: transcript, audioURL: fileURL)
        } catch {
            ephemeralSignposter.endInterval("EphemeralTranscribe", transcribeState, "error")
            endCaptureSignpost(success: false, error: error.localizedDescription)
            // Clean up on failure since caller won't get the URL
            try? FileManager.default.removeItem(at: fileURL)
            logger.error("Transcription failed (persistent): \(error.localizedDescription)")
            throw EphemeralTranscriberError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Cancel any ongoing capture without transcribing
    public func cancel() {
        guard isRecording else {
            if isTranscribing, let activeCaptureDescription {
                logger.warning("Cancel ignored while transcribing: \(activeCaptureDescription)")
            }
            return
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        audioLevel = 0

        // End signpost as cancelled
        endCaptureSignpost(success: false, error: "cancelled")

        audioFile = nil
        cleanup()
        activePurpose = nil
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

    private var activeCaptureDescription: String? {
        guard isRecording || isTranscribing else { return nil }

        let purposeDescription = activePurpose?.displayName ?? "Another voice action"
        if isRecording {
            return "\(purposeDescription) is already recording"
        }
        if isTranscribing {
            return "\(purposeDescription) is still transcribing"
        }
        return "\(purposeDescription) is still active"
    }

    /// Configure the audio engine to use the user's selected input device
    private func configureInputDevice(engine: AVAudioEngine) {
        let audioManager = AudioDeviceManager.shared
        audioManager.ensureInitialized()

        // Use the user's selected device from settings
        let selectedID = audioManager.selectedDeviceID
        guard selectedID != 0 else {
            logger.debug("Using system default audio input")
            return
        }

        // Get the audio unit from the input node
        guard let audioUnit = engine.inputNode.audioUnit else {
            logger.warning("Could not get audio unit from input node")
            return
        }

        // Set the input device to match user's selection
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
            logger.info("Using selected mic: \(deviceName)")
        } else {
            logger.error("Failed to set audio input device: \(status)")
        }
    }
}

// MARK: - Errors

public enum EphemeralTranscriberError: LocalizedError {
    case captureStartFailed(String)
    case captureBusy(String)
    case notRecording
    case noAudioFile
    case audioFileTooSmall
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .captureStartFailed(let reason):
            return "Failed to start capture: \(reason)"
        case .captureBusy(let reason):
            return "\(reason). Finish it before starting another voice action."
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
