//
//  AudioCapture.swift
//  TalkieLive
//
//  Real microphone capture using AVAudioEngine
//

import AVFoundation
import AppKit
import Combine
import CoreAudio
import TalkieKit

private let log = Log(.audio)

/// Shared audio level for UI visualization and silent mic detection
@MainActor
final class AudioLevelMonitor: ObservableObject {
    static let shared = AudioLevelMonitor()

    @Published var level: Float = 0
    @Published var isSilent: Bool = false  // True when mic appears silent during recording
    @Published var selectedMicName: String = "System Default"

    // Silent detection settings
    private let silenceThreshold: Float = 0.02  // Level below this is considered silent
    private let silenceWindowSeconds: TimeInterval = 2.0  // How long silence before warning
    private var silentSampleCount: Int = 0
    private var totalSampleCount: Int = 0
    private let samplesPerSecond: Int = 10  // Approximate samples per second

    private var cancellables = Set<AnyCancellable>()

    private init() {
        refreshMicName()

        // Listen for device changes
        AudioDeviceManager.shared.$inputDevices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMicName()
            }
            .store(in: &cancellables)

        // Listen for settings changes (user changed mic selection)
        LiveSettings.shared.$selectedMicrophoneID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshMicName()
            }
            .store(in: &cancellables)
    }

    /// Call on each level update during recording
    func updateLevel(_ newLevel: Float, isRecording: Bool) {
        level = newLevel

        if isRecording {
            totalSampleCount += 1

            if newLevel < silenceThreshold {
                silentSampleCount += 1
            } else {
                // Reset if we get any audio
                silentSampleCount = 0
                if isSilent {
                    isSilent = false
                }
            }

            // Check if we've been silent for the window duration
            let windowSamples = Int(silenceWindowSeconds) * samplesPerSecond
            if silentSampleCount >= windowSamples && !isSilent {
                isSilent = true
                playAlertSound()
            }
        }
    }

    /// Reset silence tracking when recording starts/stops
    func resetSilenceTracking() {
        silentSampleCount = 0
        totalSampleCount = 0
        isSilent = false
    }

    /// Refresh the displayed mic name from current selection
    func refreshMicName() {
        Task { @MainActor in
            let deviceManager = AudioDeviceManager.shared
            let selectedID = deviceManager.selectedDeviceID

            if let device = deviceManager.inputDevices.first(where: { $0.id == selectedID }) {
                selectedMicName = device.name
            } else if let defaultDevice = deviceManager.inputDevices.first(where: { $0.isDefault }) {
                selectedMicName = defaultDevice.name
            } else {
                selectedMicName = "No Microphone"
            }
        }
    }

    private func playAlertSound() {
        // Play system alert sound
        NSSound.beep()
    }
}

final class MicrophoneCapture: LiveAudioCapture {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var onChunk: ((String) -> Void)?  // Callback receives file path
    private var isCapturing = false
    private var fileCreated = false
    private var bufferCount = 0  // Track buffer count for debugging

    /// Callback for capture failure - called on main thread
    var onCaptureError: ((String) -> Void)?

    init() {
        // Monitor audio engine configuration changes (can cause silent failures)
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isCapturing else { return }
            log.error("Audio engine configuration changed mid-recording", detail: "Buffers: \(self.bufferCount)")

            // Try to recover by restarting the engine
            if !self.engine.isRunning {
                log.warning("Engine stopped - attempting restart")
                do {
                    try self.engine.start()
                    log.info("Engine restarted successfully")
                } catch {
                    log.error("Failed to restart engine", error: error)
                    Task { @MainActor in
                        self.onCaptureError?("Audio engine stopped unexpectedly")
                    }
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func startCapture(onChunk: @escaping (String) -> Void) {
        guard !isCapturing else {
            log.warning("Already capturing")
            return
        }

        self.onChunk = onChunk
        self.fileCreated = false
        self.bufferCount = 0

        // Set the selected input device before accessing inputNode
        setInputDevice()

        // Reset silence tracking for new recording
        Task { @MainActor in
            AudioLevelMonitor.shared.resetSilenceTracking()
            AudioLevelMonitor.shared.refreshMicName()
        }

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
                self.bufferCount += 1
            } catch {
                log.error("Failed to write audio buffer", detail: "Buffer \(self.bufferCount)", error: error)
            }

            // Calculate RMS level for visualization and silence detection
            let level = self.calculateRMSLevel(buffer: buffer)
            Task { @MainActor in
                AudioLevelMonitor.shared.updateLevel(level, isRecording: true)
            }
        }

        do {
            try engine.start()
            isCapturing = true
            log.info("Microphone capture started")
        } catch {
            log.error("Failed to start audio engine", error: error)
            inputNode.removeTap(onBus: 0)
            tempFileURL = nil
            fileCreated = false

            // Notify about the failure
            let errorMsg = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.onCaptureError?(errorMsg)
            }
        }
    }

    private func createAudioFile(matching buffer: AVAudioPCMBuffer) {
        guard let fileURL = tempFileURL else { return }

        let format = buffer.format
        log.debug("Actual buffer format", detail: "\(format.sampleRate)Hz, \(format.channelCount)ch, \(format.commonFormat.rawValue)")

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
            log.info("Created audio file", detail: "\(format.sampleRate)Hz, \(format.channelCount)ch")
        } catch {
            log.error("Failed to create audio file", error: error)
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

        // Stop the engine first to prevent new buffers from being written
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false

        // Append silence padding after stopping to ensure trailing speech is captured
        // This gives the transcription engine time to process the final words
        appendSilencePadding()

        // Small delay to let AAC encoder flush any pending frames
        // AAC encoding has a lookahead that can cause the last few frames to be lost
        Thread.sleep(forTimeInterval: 0.1)

        // Reset audio level and silence tracking
        Task { @MainActor in
            AudioLevelMonitor.shared.level = 0
            AudioLevelMonitor.shared.resetSilenceTracking()
        }

        // Close the audio file (this flushes the encoder)
        audioFile = nil

        // Deliver the file path - caller is responsible for cleanup after transcription
        if let fileURL = tempFileURL {
            // Check file size to validate recording
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int {
                log.info("Captured audio file", detail: "\(fileURL.lastPathComponent) (\(size) bytes)")

                if size > 1000 {
                    onChunk?(fileURL.path)  // Pass path, not data - engine reads directly
                } else {
                    log.warning("Audio file too small", detail: "\(size) bytes, likely empty recording")
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } else {
                log.error("Failed to get audio file attributes")
                try? FileManager.default.removeItem(at: fileURL)
            }
        } else {
            log.warning("No temp file URL - file may not have been created")
        }

        let capturedBuffers = bufferCount
        tempFileURL = nil
        onChunk = nil
        fileCreated = false
        bufferCount = 0
        log.info("Microphone capture stopped", detail: "\(capturedBuffers) buffers captured")

        // Log warning if suspiciously few buffers (likely a problem)
        if capturedBuffers < 10 {
            log.warning("Very short recording", detail: "Only \(capturedBuffers) audio buffers captured")
        }
    }

    /// Append silence padding to the end of the recording
    /// This helps transcription engines process trailing speech that might otherwise be clipped
    private func appendSilencePadding() {
        guard let audioFile = audioFile else {
            log.debug("No audio file to pad")
            return
        }

        // Get the format from the audio file
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = format.channelCount

        // 1.5 seconds of silence to ensure trailing speech is fully captured
        // Whisper and other transcription engines need this buffer to process final words
        let silenceDurationSeconds: Double = 1.5
        let frameCount = AVAudioFrameCount(sampleRate * silenceDurationSeconds)

        // Create a silent buffer
        guard let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            log.warning("Failed to create silence buffer")
            return
        }
        silentBuffer.frameLength = frameCount

        // Fill with zeros (silence)
        if let channelData = silentBuffer.floatChannelData {
            for channel in 0..<Int(channelCount) {
                memset(channelData[channel], 0, Int(frameCount) * MemoryLayout<Float>.size)
            }
        }

        // Write silence to the file
        do {
            try audioFile.write(from: silentBuffer)
            log.debug("Added silence padding", detail: "\(Int(silenceDurationSeconds * 1000))ms")
        } catch {
            log.warning("Failed to write silence padding", error: error)
        }
    }

    /// Set the input device on the audio engine's input node
    private func setInputDevice() {
        // Read directly from UserDefaults to avoid MainActor isolation
        let savedID = UInt32(UserDefaults.standard.integer(forKey: "selectedMicrophoneID"))
        guard savedID != 0 else {
            log.info("Using system default microphone")
            return
        }

        // Validate device still exists before trying to use it
        // This prevents errors when Bluetooth headsets disconnect
        guard isAudioDeviceAvailable(savedID) else {
            log.warning("Selected microphone no longer available", detail: "deviceID=\(savedID), falling back to default")
            return
        }

        // Get the audio unit from the engine's input node
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit

        guard let audioUnit = audioUnit else {
            log.warning("Could not get audio unit from input node")
            return
        }

        // Set the input device
        var deviceID = savedID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            log.info("Set input device", detail: "deviceID=\(savedID)")
        } else {
            log.warning("Failed to set input device", detail: "status=\(status)")
        }
    }

    /// Check if an audio device ID is available AND has input capability
    private func isAudioDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
        // First check if device exists at all
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return false }
        guard deviceIDs.contains(deviceID) else { return false }

        // Now check if this device has input streams (is actually a microphone)
        var inputPropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var inputStreamSize: UInt32 = 0
        status = AudioObjectGetPropertyDataSize(
            deviceID,
            &inputPropertyAddress,
            0,
            nil,
            &inputStreamSize
        )

        // Device must have at least one input stream
        return status == noErr && inputStreamSize > 0
    }
}
