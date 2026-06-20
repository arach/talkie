//
//  AudioCapture.swift
//  TalkieAgent
//
//  Legacy microphone capture using AVAudioEngine with AAC encoding.
//  NOTE: AudioLevelMonitor has been extracted to Core/AudioLevelMonitor.swift
//
//  This file is used for ephemeral XPC capture sessions.
//  Main capture path now uses AudioCaptureService with PCM.
//

import AVFoundation
import AppKit
import Combine
import CoreAudio
import TalkieKit

private let log = Log(.audio)

// NOTE: AudioLevelMonitor is now in Core/AudioLevelMonitor.swift

final class MicrophoneCapture: AgentAudioCapture {
    /// Audio engine - created fresh for each recording to ensure clean device state
    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var onChunk: (([String]) -> Void)?  // Callback receives segment file paths
    private var isCapturing = false
    private var fileCreated = false
    private var bufferCount = 0  // Track buffer count for debugging

    /// Observer token for engine configuration changes
    private var configObserver: NSObjectProtocol?

    /// Converter for multi-channel to mono (for AAC compatibility)
    private var channelConverter: AVAudioConverter?
    private var fileFormat: AVAudioFormat?

    /// Pre-allocated buffers for conversion (avoid allocation on audio thread)
    private var monoConversionBuffer: AVAudioPCMBuffer?
    private var inputCopyBuffer: AVAudioPCMBuffer?
    private var lastInputFormat: AVAudioFormat?

    /// Callback for capture failure - called on main thread
    var onCaptureError: ((String) -> Void)?
    var onSegmentCompleted: ((AudioWriterSegment) -> Void)?
    var currentSegmentIndex: Int { 0 }

    init() {
        // Engine is created per-recording in startCapture()
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func startCapture(onChunk: @escaping ([String]) -> Void) {
        guard !isCapturing else {
            log.warning("Already capturing")
            return
        }

        self.onChunk = onChunk
        self.fileCreated = false
        self.bufferCount = 0

        // Create fresh audio engine for this recording
        // This ensures clean device routing after Bluetooth/AirPods changes
        let newEngine = AVAudioEngine()
        self.engine = newEngine

        // Set up configuration change observer for this engine
        // NOTE: Config changes are common during device enumeration changes.
        // Don't fail immediately - the tap usually continues working even if engine reports not running.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, self.isCapturing else { return }

            // Log but don't fail - the tap usually keeps working
            if self.bufferCount == 0 {
                log.debug("Audio engine config changed at start", detail: "Expected during initialization")
            } else {
                log.debug("Audio engine config changed mid-recording", detail: "Buffers: \(self.bufferCount) - continuing")
            }
            // Don't check isRunning or report errors - let the tap continue
            // If the tap actually fails, we'll know because stopCapture will have no data
        }

        // Set input device FIRST - so format queries see the correct device
        setInputDevice()

        // CRITICAL: Prepare engine after setting device
        // This forces the audio graph to reinitialize with the correct device format.
        // Without this, switching from AirPods (24kHz/1ch) to USB mic (48kHz/2ch)
        // causes -10868 errors because the graph is stuck in the old format.
        newEngine.prepare()

        // Log the actual device being used for diagnostics
        logCurrentInputDevice()

        // Reset silence tracking for new recording
        Task { @MainActor in
            AudioLevelMonitor.shared.resetSilenceTracking()
            AudioLevelMonitor.shared.refreshMicName()
        }

        let inputNode = newEngine.inputNode

        // Prepare temp file URL
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        self.tempFileURL = fileURL

        // Log hardware format for diagnostics
        let hwFormat = inputNode.inputFormat(forBus: 0)
        log.debug("Hardware format", detail: "\(hwFormat.sampleRate)Hz, \(hwFormat.channelCount)ch")

        // Install tap with nil format - let AVAudioEngine auto-negotiate
        // This is the v1.9.0 philosophy: trust the engine
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Create file lazily on first buffer - ensures format matches exactly
            if !self.fileCreated {
                self.createAudioFile(matching: buffer)
            }

            guard let audioFile = self.audioFile else { return }

            // Write the buffer - convert channels if needed for AAC compatibility (max 2ch)
            var bufferToWrite = buffer
            if buffer.format.channelCount > 2,
               let reduced = self.reduceChannels(buffer) {
                bufferToWrite = reduced
            }

            do {
                try audioFile.write(from: bufferToWrite)
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
            try newEngine.start()
            isCapturing = true
            log.info("Microphone capture started")
        } catch {
            log.error("Failed to start audio engine", error: error)
            inputNode.removeTap(onBus: 0)
            tempFileURL = nil
            fileCreated = false
            channelConverter = nil
            fileFormat = nil
            monoConversionBuffer = nil
            inputCopyBuffer = nil
            lastInputFormat = nil

            // Clean up engine on failure
            if let observer = configObserver {
                NotificationCenter.default.removeObserver(observer)
                configObserver = nil
            }
            engine = nil

            // Notify about the failure
            let errorMsg = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.onCaptureError?(errorMsg)
            }
        }
    }

    func requestCheckpoint() {
        // Legacy AAC capture does not support mid-recording segment checkpoints.
    }

    private func createAudioFile(matching buffer: AVAudioPCMBuffer) {
        guard let fileURL = tempFileURL else { return }

        let format = buffer.format
        log.debug("Actual buffer format", detail: "\(format.sampleRate)Hz, \(format.channelCount)ch, \(format.commonFormat.rawValue)")

        // Use the same channel count as the input - AAC supports 1-2 channels fine
        // Stereo preserves spatial audio and works well with transcription engines
        let outputChannels: AVAudioChannelCount = min(format.channelCount, 2)  // Cap at stereo for AAC compatibility

        self.fileFormat = format

        // Create file with AAC encoding matching input format
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: outputChannels,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)
            fileCreated = true
            log.info("Created audio file", detail: "\(format.sampleRate)Hz, \(outputChannels)ch")
        } catch {
            log.error("Failed to create audio file", error: error)
        }
    }

    /// Reduce channels to stereo (2ch) for AAC compatibility
    /// Only called when buffer has more than 2 channels (e.g., 4ch from Voice Processing)
    private func reduceChannels(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        guard format.channelCount > 2 else { return buffer }

        // Create stereo format
        guard let stereoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 2,
            interleaved: false
        ) else { return nil }

        guard let stereoBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: buffer.frameLength) else {
            return nil
        }
        stereoBuffer.frameLength = buffer.frameLength

        // Copy first two channels
        if let srcData = buffer.floatChannelData, let dstData = stereoBuffer.floatChannelData {
            let frameCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
            memcpy(dstData[0], srcData[0], frameCount)
            memcpy(dstData[1], srcData[1], frameCount)
        }

        return stereoBuffer
    }

    /// Convert multi-channel buffer to mono for file writing
    /// Uses pre-allocated buffers to avoid allocation on audio thread
    private func convertToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter = channelConverter,
              let targetFormat = fileFormat else {
            return buffer  // No conversion needed
        }

        // Ensure we have pre-allocated buffers of sufficient size
        // Only reallocate if format changed or capacity is insufficient
        if inputCopyBuffer == nil ||
           lastInputFormat != buffer.format ||
           inputCopyBuffer!.frameCapacity < buffer.frameLength {

            inputCopyBuffer = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: max(buffer.frameLength, 8192))
            lastInputFormat = buffer.format
        }

        if monoConversionBuffer == nil ||
           monoConversionBuffer!.frameCapacity < buffer.frameLength {
            monoConversionBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(buffer.frameLength, 8192))
        }

        guard let inputCopy = inputCopyBuffer,
              let outputBuffer = monoConversionBuffer else {
            return nil
        }

        // Copy input data
        inputCopy.frameLength = buffer.frameLength
        if let srcData = buffer.floatChannelData, let dstData = inputCopy.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                memcpy(dstData[channel], srcData[channel], Int(buffer.frameLength) * MemoryLayout<Float>.size)
            }
        }

        // Reset output buffer
        outputBuffer.frameLength = 0

        var error: NSError?
        var inputConsumed = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return inputCopy
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if status == .error {
            log.warning("Channel conversion failed", detail: error?.localizedDescription ?? "unknown")
            return nil
        }

        return outputBuffer
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

    @discardableResult
    func stopCapture() -> Bool {
        // Always reset isCapturing to prevent stuck state, even if we return early
        let wasCapturing = isCapturing
        isCapturing = false

        guard wasCapturing, let engine = engine else { return false }

        // Stop the engine first to prevent new buffers from being written
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Remove configuration observer
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }

        // Append silence padding after stopping to ensure trailing speech is captured
        // This gives the transcription engine time to process the final words
        appendSilencePadding()

        // LEGACY: AAC encoder flush delay
        // AAC encoding has a lookahead buffer that requires time to flush.
        // This blocking sleep is needed for AAC but not ideal.
        // Note: Main capture path now uses AudioCaptureService with PCM (no flush needed).
        // This code path is only used for ephemeral XPC capture sessions.
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
                    onChunk?([fileURL.path])  // Pass path, not data - engine reads directly
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
        channelConverter = nil
        fileFormat = nil
        monoConversionBuffer = nil
        inputCopyBuffer = nil
        lastInputFormat = nil
        log.info("Microphone capture stopped", detail: "\(capturedBuffers) buffers captured")

        // Log warning if suspiciously few buffers (likely a problem)
        if capturedBuffers < 10 {
            log.warning("Very short recording", detail: "Only \(capturedBuffers) audio buffers captured")
        }

        // Deallocate engine to ensure fresh state for next recording
        // This is critical for handling device changes (AirPods connect/disconnect)
        self.engine = nil
        return true
    }

    @discardableResult
    func reboot() async -> AudioRebootResult {
        log.info("Rebooting audio system (MicrophoneCapture)")
        // Stop any active capture
        stopCapture()
        // Small delay to let audio system settle
        try? await Task.sleep(for: .milliseconds(100))
        // Engine is recreated on next startCapture call
        return .success
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

    /// Set the input device on the audio engine's input node using resolved device
    private func setInputDevice() {
        guard let engine = engine else {
            log.warning("Cannot set input device - no audio engine")
            return
        }

        // Read settings directly to avoid MainActor isolation
        let store = TalkieSharedSettings
        let modeRaw = store.string(forKey: AgentSettingsKey.selectedMicrophoneMode) ?? MicrophoneSelectionMode.systemDefault.rawValue
        let mode = MicrophoneSelectionMode(rawValue: modeRaw) ?? .systemDefault
        let requestedUID = store.string(forKey: AgentSettingsKey.selectedMicrophoneUID)
        let requestedName = store.string(forKey: AgentSettingsKey.selectedMicrophoneName)

        // For system default mode, just use the default device
        if mode == .systemDefault {
            log.info("Using system default microphone")
            logRecordingStart(deviceID: 0, reason: .systemDefault, requestedUID: nil, requestedName: nil)
            return
        }

        // For fixed UID mode, try to find the device
        guard let uid = requestedUID else {
            log.warning("Fixed UID mode but no UID saved, using default")
            logRecordingStart(deviceID: 0, reason: .fallback, requestedUID: nil, requestedName: requestedName)
            return
        }

        // Find device by UID
        guard let deviceID = findDeviceByUID(uid) else {
            log.warning("Selected microphone no longer available", detail: "uid=\(uid), name=\(requestedName ?? "Unknown"), falling back to default")
            logRecordingStart(deviceID: 0, reason: .fallback, requestedUID: uid, requestedName: requestedName)
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
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            log.info("Set input device", detail: "uid=\(uid), deviceID=\(deviceID)")
            logRecordingStart(deviceID: deviceID, reason: .fixedDevice, requestedUID: uid, requestedName: requestedName)
        } else {
            log.warning("Failed to set input device", detail: "status=\(status)")
            logRecordingStart(deviceID: 0, reason: .fallback, requestedUID: uid, requestedName: requestedName)
        }
    }

    /// Log recording start for diagnostics
    private func logRecordingStart(
        deviceID: AudioDeviceID,
        reason: DeviceResolution.SelectionReason,
        requestedUID: String?,
        requestedName: String?
    ) {
        // Get actual device info
        let (actualUID, actualName) = getDeviceInfo(deviceID)

        AudioInputLogger.shared.logRecordingStart(
            deviceUID: actualUID ?? "system_default",
            deviceName: actualName ?? "System Default",
            selectionReason: reason.rawValue,
            requestedUID: requestedUID,
            requestedName: requestedName
        )
    }

    /// Find a device by its persistent UID
    private func findDeviceByUID(_ uid: String) -> AudioDeviceID? {
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

        guard status == noErr else { return nil }

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

        guard status == noErr else { return nil }

        // Find device with matching UID
        for deviceID in deviceIDs {
            if let deviceUID = getDeviceUID(deviceID), deviceUID == uid {
                // Also verify it has input capability
                if isAudioDeviceAvailable(deviceID) {
                    return deviceID
                }
            }
        }

        return nil
    }

    /// Get device UID from device ID
    private func getDeviceUID(_ deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)

        guard status == noErr, let cfUID = uid?.takeRetainedValue() else { return nil }

        return cfUID as String
    }

    /// Get device name and UID for logging
    private func getDeviceInfo(_ deviceID: AudioDeviceID) -> (uid: String?, name: String?) {
        guard deviceID != 0 else { return (nil, nil) }

        let uid = getDeviceUID(deviceID)

        var namePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &namePropertyAddress, 0, nil, &dataSize, &name)
        let deviceName = status == noErr ? (name?.takeRetainedValue() as String?) : nil

        return (uid, deviceName)
    }

    /// Log diagnostic info about the current input device for debugging
    private func logCurrentInputDevice() {
        guard let engine = engine else { return }

        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else { return }

        // Get current device ID
        var deviceID: AudioDeviceID = 0
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            &propertySize
        )

        guard status == noErr else {
            log.debug("Could not get current device ID", detail: "status=\(status)")
            return
        }

        // Get device name
        var namePropertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var nameSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &namePropertyAddress, 0, nil, &nameSize)

        var name: CFString = "" as CFString
        AudioObjectGetPropertyData(deviceID, &namePropertyAddress, 0, nil, &nameSize, &name)

        // Get sample rate
        let format = inputNode.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        log.info("Recording device", detail: "\(name as String), \(Int(sampleRate))Hz, deviceID=\(deviceID)")

        // Warn about low sample rates (AirPods HFP mode)
        if sampleRate < 44100 {
            log.warning("Low sample rate detected", detail: "\(Int(sampleRate))Hz - device may be in HFP/call mode")
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
