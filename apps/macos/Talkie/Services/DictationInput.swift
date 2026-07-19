//
//  DictationInput.swift
//  Talkie
//
//  Short dictation input for command and text-entry surfaces.
//  Captures audio → transcribes via TalkieEngine → returns text or a caller-owned audio file.
//
//  Instrumented with os_signpost for Instruments profiling
//

import AVFoundation
import AppKit
import os.signpost
import Observation
import TalkieKit
import CoreAudio
import AudioToolbox

private let logger = Log(.audio)

private struct PreparedDictationInputAudioEngine: @unchecked Sendable {
    let engine: AVAudioEngine
    let inputNode: AVAudioInputNode
    let deviceName: String
    let setupDurationMs: Int
}

// MARK: - Performance Instrumentation

/// Signpost log for dictation input transcription performance profiling in Instruments
private let dictationInputPerformanceLog = OSLog(subsystem: "to.talkie.app.performance", category: "DictationInput")

/// Signposter for dictation input transcription intervals
private let dictationInputSignposter = OSSignposter(subsystem: "to.talkie.app.performance", category: "DictationInput")

/// Shared owner for short dictation and command input.
/// Captures audio, transcribes via TalkieEngine, and keeps persistence decisions with callers.
public enum DictationInputPurpose: String {
    case unspecified
    case composeDictation
    case composeCommand
    case draftsDictation
    case draftsCommand
    case interstitialDictation
    case interstitialCommand
    case terminalDictation
    case skillsChatDictation
    case captureMarkupDictation
    case markdownEditorDictation

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
        case .captureMarkupDictation:
            return "Capture markup dictation"
        case .markdownEditorDictation:
            return "Markdown editor dictation"
        }
    }
}

@MainActor
@Observable
public final class DictationInput {
    public static let shared = DictationInput()

    // MARK: - Published State

    public private(set) var isRecording: Bool = false
    public private(set) var isPreparing: Bool = false
    public private(set) var isTranscribing: Bool = false
    public private(set) var audioLevel: Float = 0
    public private(set) var error: String?
    public private(set) var activePurpose: DictationInputPurpose?

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var fileCreated = false
    private var captureToken: UUID?

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
    public func startCapture(purpose: DictationInputPurpose = .unspecified) async throws {
        if let busyDescription = activeCaptureDescription {
            logger.warning("Capture rejected: \(busyDescription)")
            throw DictationInputError.captureBusy(busyDescription)
        }

        error = nil
        isPreparing = true
        activePurpose = purpose
        let token = UUID()
        captureToken = token

        // Begin signpost interval for full capture flow
        captureSignpostID = dictationInputSignposter.makeSignpostID()
        captureSignpostState = dictationInputSignposter.beginInterval("DictationInputCapture", id: captureSignpostID!)
        captureStartTime = CFAbsoluteTimeGetCurrent()

        // Emit event for capture start
        os_signpost(.event, log: dictationInputPerformanceLog, name: "DictationInput",
                    "capture_start")

        let deviceSelection = resolveInputDeviceSelection()
        logger.info(
            "Dictation input capture preparing for \(purpose.displayName)",
            detail: "device=\(deviceSelection.name)"
        )

        let prepared = await Self.prepareAudioEngine(selection: deviceSelection)

        guard captureToken == token, isPreparing else {
            prepared.engine.stop()
            endCaptureSignpost(success: false, error: "capture_start_cancelled")
            throw DictationInputError.captureStartFailed("Capture start cancelled")
        }

        let engine = prepared.engine
        let inputNode = prepared.inputNode
        self.audioEngine = engine

        // Prepare temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("dictation_input_\(UUID().uuidString)").appendingPathExtension("m4a")
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
            try await Self.startPreparedEngine(engine)
            guard captureToken == token, isPreparing else {
                inputNode.removeTap(onBus: 0)
                engine.stop()
                self.audioEngine = nil
                endCaptureSignpost(success: false, error: "capture_start_cancelled")
                throw DictationInputError.captureStartFailed("Capture start cancelled")
            }
            isPreparing = false
            isRecording = true
            logger.info(
                "Dictation input capture started for \(purpose.displayName)",
                detail: "device=\(prepared.deviceName) setupMs=\(prepared.setupDurationMs)"
            )
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioEngine = nil
            self.audioFile = nil
            self.isPreparing = false
            self.activePurpose = nil
            self.captureToken = nil
            cleanup()
            endCaptureSignpost(success: false, error: "capture_start_failed")
            throw DictationInputError.captureStartFailed(error.localizedDescription)
        }
    }

    /// Stop capturing and transcribe the audio
    /// Returns the transcribed text
    public func stopAndTranscribe() async throws -> String {
        guard isRecording else {
            if let activeCaptureDescription {
                throw DictationInputError.captureBusy(activeCaptureDescription)
            }
            throw DictationInputError.notRecording
        }

        // Calculate recording duration
        recordingDuration = CFAbsoluteTimeGetCurrent() - captureStartTime

        // Emit event for recording stop
        os_signpost(.event, log: dictationInputPerformanceLog, name: "DictationInput",
                    "recording_stop")

        // Stop capture
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        captureToken = nil
        isRecording = false
        isTranscribing = true
        audioLevel = 0

        // Close audio file
        audioFile = nil

        guard let fileURL = tempFileURL else {
            endCaptureSignpost(success: false, error: "no_audio_file")
            throw DictationInputError.noAudioFile
        }

        // Validate file
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size > 1000 else {
            cleanup()
            endCaptureSignpost(success: false, error: "audio_too_small")
            throw DictationInputError.audioFileTooSmall
        }

        logger.info("Captured audio: \(size) bytes")

        // Begin transcription phase signpost
        let transcribeSignpostID = dictationInputSignposter.makeSignpostID()
        let transcribeState = dictationInputSignposter.beginInterval("DictationInputTranscribe", id: transcribeSignpostID)
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
                modelId: TalkieDefaults.dictationInputModelId,  // Fast model for voice instructions
                priority: .high,          // Real-time voice instructions - highest priority
                postProcess: .inverseTextNormalization
            )

            // End transcription signpost
            let transcribeDuration = CFAbsoluteTimeGetCurrent() - transcribeStart
            dictationInputSignposter.endInterval("DictationInputTranscribe", transcribeState,
                                            "words=\(transcript.split(separator: " ").count) duration=\(String(format: "%.0f", transcribeDuration * 1000))ms")

            // End overall capture signpost
            endCaptureSignpost(success: true, wordCount: transcript.split(separator: " ").count)

            // Report to performance monitor
            await MainActor.run {
                PerformanceMonitor.shared.addOperation(
                    category: .inference,
                    name: "Dictation Input Transcription",
                    duration: transcribeDuration
                )
            }

            logger.info("Transcribed: \(transcript.prefix(50))...")
            return transcript
        } catch {
            // End signposts with error
            dictationInputSignposter.endInterval("DictationInputTranscribe", transcribeState, "error")
            endCaptureSignpost(success: false, error: error.localizedDescription)

            logger.error("Transcription failed: \(error.localizedDescription)")
            throw DictationInputError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// End the overall capture signpost with result
    private func endCaptureSignpost(success: Bool, wordCount: Int = 0, error: String? = nil) {
        guard let state = captureSignpostState else { return }

        let totalDuration = CFAbsoluteTimeGetCurrent() - captureStartTime
        let recDuration = self.recordingDuration
        if success {
            dictationInputSignposter.endInterval("DictationInputCapture", state,
                                            "success recording=\(String(format: "%.1f", recDuration))s total=\(String(format: "%.0f", totalDuration * 1000))ms words=\(wordCount)")
        } else {
            dictationInputSignposter.endInterval("DictationInputCapture", state,
                                            "failed: \(error ?? "unknown")")
        }
        captureSignpostState = nil
        captureSignpostID = nil
    }

    /// Stop capturing and transcribe, returning both text and audio URL for persistent storage.
    /// Unlike stopAndTranscribe(), this does NOT delete the temp audio file — the caller owns cleanup.
    public func stopAndTranscribePersistent() async throws -> (text: String, audioURL: URL) {
        guard isRecording else {
            if let activeCaptureDescription {
                throw DictationInputError.captureBusy(activeCaptureDescription)
            }
            throw DictationInputError.notRecording
        }

        // Calculate recording duration
        recordingDuration = CFAbsoluteTimeGetCurrent() - captureStartTime

        // Emit event for recording stop
        os_signpost(.event, log: dictationInputPerformanceLog, name: "DictationInput",
                    "recording_stop_persistent")

        // Stop capture
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        captureToken = nil
        isRecording = false
        isTranscribing = true
        audioLevel = 0

        // Close audio file
        audioFile = nil

        guard let fileURL = tempFileURL else {
            endCaptureSignpost(success: false, error: "no_audio_file")
            throw DictationInputError.noAudioFile
        }

        // Validate file
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size > 1000 else {
            cleanup()
            endCaptureSignpost(success: false, error: "audio_too_small")
            throw DictationInputError.audioFileTooSmall
        }

        logger.info("Captured audio (persistent): \(size) bytes")

        // Begin transcription phase signpost
        let transcribeSignpostID = dictationInputSignposter.makeSignpostID()
        let transcribeState = dictationInputSignposter.beginInterval("DictationInputTranscribe", id: transcribeSignpostID)
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
                modelId: TalkieDefaults.dictationInputModelId,
                priority: .high,
                postProcess: .inverseTextNormalization
            )

            let transcribeDuration = CFAbsoluteTimeGetCurrent() - transcribeStart
            dictationInputSignposter.endInterval("DictationInputTranscribe", transcribeState,
                                            "words=\(transcript.split(separator: " ").count) duration=\(String(format: "%.0f", transcribeDuration * 1000))ms")
            endCaptureSignpost(success: true, wordCount: transcript.split(separator: " ").count)

            await MainActor.run {
                PerformanceMonitor.shared.addOperation(
                    category: .inference,
                    name: "Dictation Input Transcription (Persistent)",
                    duration: transcribeDuration
                )
            }

            logger.info("Transcribed (persistent): \(transcript.prefix(50))...")
            return (text: transcript, audioURL: fileURL)
        } catch {
            dictationInputSignposter.endInterval("DictationInputTranscribe", transcribeState, "error")
            endCaptureSignpost(success: false, error: error.localizedDescription)
            // Clean up on failure since caller won't get the URL
            try? FileManager.default.removeItem(at: fileURL)
            logger.error("Transcription failed (persistent): \(error.localizedDescription)")
            throw DictationInputError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Cancel any ongoing capture without transcribing
    public func cancel() {
        if isPreparing {
            audioEngine?.inputNode.removeTap(onBus: 0)
            audioEngine?.stop()
            audioEngine = nil
            isPreparing = false
            audioLevel = 0
            captureToken = nil

            endCaptureSignpost(success: false, error: "cancelled")

            audioFile = nil
            cleanup()
            activePurpose = nil
            logger.info("Capture startup cancelled")
            return
        }

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
        captureToken = nil

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
        guard isPreparing || isRecording || isTranscribing else { return nil }

        let purposeDescription = activePurpose?.displayName ?? "Another voice action"
        if isPreparing {
            return "\(purposeDescription) is still starting"
        }
        if isRecording {
            return "\(purposeDescription) is already recording"
        }
        if isTranscribing {
            return "\(purposeDescription) is still transcribing"
        }
        return "\(purposeDescription) is still active"
    }

    private func resolveInputDeviceSelection() -> (id: AudioDeviceID, name: String) {
        let audioManager = AudioDeviceManager.shared
        audioManager.ensureInitialized()

        let selectedID = audioManager.selectedDeviceID
        guard selectedID != 0 else { return (0, "system default") }

        let deviceName = audioManager.inputDevices.first(where: { $0.id == selectedID })?.name ?? "Unknown"
        return (selectedID, deviceName)
    }

    /// Prepare AVAudioEngine away from the main actor. Accessing inputNode can
    /// synchronously initialize CoreAudio HAL and block for seconds.
    private nonisolated static func prepareAudioEngine(
        selection: (id: AudioDeviceID, name: String)
    ) async -> PreparedDictationInputAudioEngine {
        await Task.detached(priority: .userInitiated) {
            let setupStart = CFAbsoluteTimeGetCurrent()
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode

            if selection.id == 0 {
                logger.debug("Using system default audio input")
            } else {
                configurePreparedInputDevice(inputNode: inputNode, selection: selection)
            }

            engine.prepare()

            let setupDurationMs = Int((CFAbsoluteTimeGetCurrent() - setupStart) * 1000)
            logger.info(
                "Dictation input audio engine prepared",
                detail: "device=\(selection.name) setupMs=\(setupDurationMs)"
            )

            return PreparedDictationInputAudioEngine(
                engine: engine,
                inputNode: inputNode,
                deviceName: selection.name,
                setupDurationMs: setupDurationMs
            )
        }.value
    }

    private nonisolated static func configurePreparedInputDevice(
        inputNode: AVAudioInputNode,
        selection: (id: AudioDeviceID, name: String)
    ) {
        guard let audioUnit = inputNode.audioUnit else {
            logger.warning("Could not get audio unit from input node")
            return
        }

        var deviceID = selection.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            logger.info("Using selected mic: \(selection.name)")
        } else {
            logger.error("Failed to set audio input device: \(status)")
        }
    }

    private nonisolated static func startPreparedEngine(_ engine: AVAudioEngine) async throws {
        try await Task.detached(priority: .userInitiated) {
            try engine.start()
        }.value
    }
}

// MARK: - Markdown editor adapter

/// Bridges the Talkie Markdown editor (in TalkieKit) to the app's real
/// dictation engine. TalkieKit declares the `MarkdownStudioDictating` seam;
/// `DictationInput` lives in the app target, so this thin adapter is what
/// actually captures + transcribes voice for the editor's Dictate actions.
@MainActor
final class StudioDictationProvider: MarkdownStudioDictating {
    var audioLevel: Float { DictationInput.shared.audioLevel }

    func start() async throws {
        try await DictationInput.shared.startCapture(purpose: .markdownEditorDictation)
    }

    func stop() async throws -> (text: String, audioURL: URL) {
        try await DictationInput.shared.stopAndTranscribePersistent()
    }

    func cancel() {
        DictationInput.shared.cancel()
    }
}

// MARK: - Errors

public enum DictationInputError: LocalizedError {
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
