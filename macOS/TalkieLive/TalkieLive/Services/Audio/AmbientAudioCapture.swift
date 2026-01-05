//
//  AmbientAudioCapture.swift
//  TalkieLive
//
//  Continuous audio capture with rolling buffer for ambient mode.
//  Captures audio in chunks and periodically sends for transcription.
//

import AVFoundation
import Foundation
import TalkieKit

private let log = Log(.audio)

// MARK: - Audio Chunk

/// A chunk of audio with timestamp
struct AudioChunk {
    let id: UUID
    let data: Data
    let duration: TimeInterval
    let timestamp: Date
    let fileURL: URL

    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }
}

// MARK: - Ambient Audio Capture

/// Continuous audio capture for ambient mode
/// Maintains a rolling buffer of audio chunks for background transcription
@MainActor
final class AmbientAudioCapture: ObservableObject {
    static let shared = AmbientAudioCapture()

    // MARK: - Configuration

    /// Duration of each audio chunk in seconds
    private let chunkDuration: TimeInterval = 10

    /// How often to finalize a chunk and start a new one
    private var chunkTimer: Timer?

    // MARK: - State

    @Published private(set) var isCapturing = false
    @Published private(set) var audioLevel: Float = 0

    /// Rolling buffer of audio chunks
    private(set) var chunks: [AudioChunk] = []

    /// Current chunk being recorded
    private var currentChunkURL: URL?
    private var currentChunkStartTime: Date?
    private var audioFile: AVAudioFile?
    private var bufferCount = 0

    // MARK: - Audio Engine

    private let engine = AVAudioEngine()

    /// Callback when a new chunk is ready for transcription (batch mode)
    var onChunkReady: ((AudioChunk) -> Void)?

    /// Callback for raw PCM data at 16kHz (streaming mode)
    /// Data is Float32 mono samples, ~100ms chunks
    var onPCMDataReady: ((Data) -> Void)?

    // MARK: - Resampling

    /// Audio converter for resampling to 16kHz
    private var audioConverter: AVAudioConverter?

    /// Target format for streaming: 16kHz mono Float32
    private lazy var targetFormat: AVAudioFormat = {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    }()

    /// Buffer for accumulating PCM data before sending
    private var pcmBuffer: [Float] = []

    /// Minimum samples to accumulate before sending (~100ms at 16kHz = 1600 samples)
    private let minPCMSamples = 1600

    // MARK: - Init

    private init() {
        // Monitor audio engine configuration changes
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isCapturing else { return }
                log.warning("Ambient audio engine config changed")

                // Try to recover
                if !self.engine.isRunning {
                    do {
                        try self.engine.start()
                        log.info("Ambient engine restarted")
                    } catch {
                        log.error("Failed to restart ambient engine", error: error)
                    }
                }
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Start/Stop

    /// Start continuous audio capture
    func start() {
        guard !isCapturing else {
            log.debug("Ambient capture already running")
            return
        }

        log.info("Starting ambient audio capture")

        // Set input device
        setInputDevice()

        let inputNode = engine.inputNode

        // Start first chunk
        startNewChunk()

        // Set up audio converter for 16kHz resampling (streaming mode)
        setupAudioConverter(sourceFormat: inputNode.outputFormat(forBus: 0))

        // Install tap for continuous capture
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Create audio file lazily on first buffer
            if self.audioFile == nil && self.currentChunkURL != nil {
                self.createAudioFile(matching: buffer)
            }

            // Write to current chunk file (batch mode)
            if let audioFile = self.audioFile {
                do {
                    try audioFile.write(from: buffer)
                    self.bufferCount += 1
                } catch {
                    log.error("Failed to write ambient buffer", error: error)
                }
            }

            // Resample and send PCM data (streaming mode)
            if self.onPCMDataReady != nil {
                self.processBufferForStreaming(buffer)
            }

            // Calculate audio level
            let level = self.calculateRMSLevel(buffer: buffer)
            Task { @MainActor in
                self.audioLevel = level
            }
        }

        do {
            try engine.start()
            isCapturing = true

            // Start chunk timer
            startChunkTimer()

            log.info("Ambient capture started")
        } catch {
            log.error("Failed to start ambient engine", error: error)
            inputNode.removeTap(onBus: 0)
            cleanupCurrentChunk()
        }
    }

    /// Stop continuous audio capture
    func stop() {
        guard isCapturing else { return }

        log.info("Stopping ambient audio capture")

        // Stop chunk timer
        chunkTimer?.invalidate()
        chunkTimer = nil

        // Finalize current chunk
        finalizeCurrentChunk()

        // Flush any remaining PCM data
        flushPCMBuffer()

        // Stop engine
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isCapturing = false
        audioLevel = 0

        // Clean up converter
        audioConverter = nil

        log.info("Ambient capture stopped", detail: "\(chunks.count) chunks in buffer")
    }

    // MARK: - Chunk Management

    /// Start a new audio chunk
    private func startNewChunk() {
        // Finalize previous chunk if any
        if audioFile != nil {
            finalizeCurrentChunk()
        }

        // Create new temp file (CAF format for PCM audio)
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir
            .appendingPathComponent("ambient_\(UUID().uuidString)")
            .appendingPathExtension("caf")

        currentChunkURL = fileURL
        currentChunkStartTime = Date()
        bufferCount = 0

        log.debug("Started new ambient chunk", detail: fileURL.lastPathComponent)
    }

    /// Finalize current chunk and add to buffer
    private func finalizeCurrentChunk() {
        guard let fileURL = currentChunkURL,
              let startTime = currentChunkStartTime else { return }

        // Calculate duration first
        let duration = Date().timeIntervalSince(startTime)

        // Need at least 1 second of audio for meaningful transcription
        guard duration >= 1.0, bufferCount >= 10 else {
            log.debug("Discarding short ambient chunk", detail: "\(String(format: "%.1f", duration))s, \(bufferCount) buffers")
            audioFile = nil
            try? FileManager.default.removeItem(at: fileURL)
            currentChunkURL = nil
            currentChunkStartTime = nil
            bufferCount = 0
            return
        }

        // Close audio file - PCM doesn't need encoder flush like AAC
        audioFile = nil

        // Small delay for file system sync (PCM doesn't need AAC encoder flush)
        Thread.sleep(forTimeInterval: 0.05)

        // Verify file exists and has content
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int,
              size > 1000 else {  // Minimal size check for PCM
            log.warning("Ambient chunk file missing or empty", detail: "path=\(fileURL.lastPathComponent)")
            try? FileManager.default.removeItem(at: fileURL)
            currentChunkURL = nil
            currentChunkStartTime = nil
            bufferCount = 0
            return
        }

        // Read file data
        guard let data = try? Data(contentsOf: fileURL) else {
            log.warning("Failed to read ambient chunk data")
            try? FileManager.default.removeItem(at: fileURL)
            currentChunkURL = nil
            currentChunkStartTime = nil
            return
        }

        // Create chunk
        let chunk = AudioChunk(
            id: UUID(),
            data: data,
            duration: duration,
            timestamp: startTime,
            fileURL: fileURL
        )

        // Add to buffer
        chunks.append(chunk)
        log.debug("Finalized ambient chunk", detail: "\(String(format: "%.1f", duration))s, \(size) bytes")

        // Prune old chunks
        pruneOldChunks()

        // Notify listener
        onChunkReady?(chunk)

        currentChunkURL = nil
        currentChunkStartTime = nil
        bufferCount = 0
    }

    /// Clean up current chunk without saving
    private func cleanupCurrentChunk() {
        audioFile = nil
        if let url = currentChunkURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentChunkURL = nil
        currentChunkStartTime = nil
        bufferCount = 0
    }

    /// Remove chunks older than buffer duration
    private func pruneOldChunks() {
        let maxAge = AmbientSettings.shared.bufferDuration

        let before = chunks.count
        chunks.removeAll { chunk in
            if chunk.age > maxAge {
                // Clean up file
                try? FileManager.default.removeItem(at: chunk.fileURL)
                return true
            }
            return false
        }

        let removed = before - chunks.count
        if removed > 0 {
            log.debug("Pruned \(removed) old ambient chunks")
        }
    }

    /// Clear all chunks
    func clearBuffer() {
        for chunk in chunks {
            try? FileManager.default.removeItem(at: chunk.fileURL)
        }
        chunks.removeAll()
        log.info("Cleared ambient buffer")
    }

    // MARK: - Chunk Timer

    private func startChunkTimer() {
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isCapturing else { return }
                self.startNewChunk()
            }
        }
    }

    // MARK: - Audio File Creation

    /// Create audio file lazily when first buffer arrives
    /// Uses CAF with Linear PCM (not AAC) to avoid encoder flush issues during chunk rotation
    private func createAudioFile(matching buffer: AVAudioPCMBuffer) {
        guard let fileURL = currentChunkURL else { return }

        let format = buffer.format

        // Use Linear PCM in CAF container - no encoder means no flush issues
        // Files are larger but transcription engine handles conversion anyway
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
            log.debug("Created ambient audio file", detail: "\(format.sampleRate)Hz PCM")
        } catch {
            log.error("Failed to create ambient audio file", error: error)
        }
    }

    // MARK: - Helpers

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

    private func setInputDevice() {
        let savedID = UInt32(UserDefaults.standard.integer(forKey: "selectedMicrophoneID"))
        guard savedID != 0 else {
            log.debug("Using system default mic for ambient")
            return
        }

        guard isAudioDeviceAvailable(savedID) else {
            log.warning("Selected mic unavailable for ambient", detail: "deviceID=\(savedID)")
            return
        }

        let inputNode = engine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            log.warning("No audio unit for ambient input node")
            return
        }

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
            log.debug("Set ambient input device", detail: "deviceID=\(savedID)")
        } else {
            log.warning("Failed to set ambient input device", detail: "status=\(status)")
        }
    }

    private func isAudioDeviceAvailable(_ deviceID: AudioDeviceID) -> Bool {
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

        guard status == noErr, deviceIDs.contains(deviceID) else { return false }

        // Check for input streams
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

        return status == noErr && inputStreamSize > 0
    }

    // MARK: - Buffer Query

    /// Get total buffered duration
    var totalBufferedDuration: TimeInterval {
        chunks.reduce(0) { $0 + $1.duration }
    }

    /// Get chunks within a time range
    func chunks(since date: Date) -> [AudioChunk] {
        chunks.filter { $0.timestamp >= date }
    }

    /// Get chunks from the last N seconds
    func chunks(lastSeconds: TimeInterval) -> [AudioChunk] {
        let cutoff = Date().addingTimeInterval(-lastSeconds)
        return chunks(since: cutoff)
    }

    // MARK: - PCM Streaming Support

    /// Set up audio converter for resampling to 16kHz
    private func setupAudioConverter(sourceFormat: AVAudioFormat) {
        // Only set up if we have a streaming callback
        guard onPCMDataReady != nil else { return }

        // Create converter from source format to 16kHz mono
        audioConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        pcmBuffer.removeAll()

        if audioConverter != nil {
            log.debug("Audio converter ready", detail: "\(sourceFormat.sampleRate)Hz → 16kHz")
        } else {
            log.warning("Failed to create audio converter")
        }
    }

    /// Process audio buffer for streaming (resample to 16kHz and send)
    private func processBufferForStreaming(_ buffer: AVAudioPCMBuffer) {
        guard let converter = audioConverter else { return }

        // Calculate output frame count based on sample rate ratio
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return
        }

        // Convert
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        guard status != .error, error == nil else {
            log.warning("Audio conversion failed", detail: error?.localizedDescription ?? "unknown")
            return
        }

        // Extract samples from output buffer
        guard let channelData = outputBuffer.floatChannelData?[0] else { return }
        let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))

        // Accumulate samples
        pcmBuffer.append(contentsOf: samples)

        // Send when we have enough samples (~100ms worth)
        while pcmBuffer.count >= minPCMSamples {
            let chunk = Array(pcmBuffer.prefix(minPCMSamples))
            pcmBuffer.removeFirst(minPCMSamples)

            // Convert to Data
            let data = chunk.withUnsafeBufferPointer { ptr in
                Data(buffer: ptr)
            }

            // Send to callback
            onPCMDataReady?(data)
        }
    }

    /// Flush any remaining PCM buffer
    private func flushPCMBuffer() {
        guard !pcmBuffer.isEmpty, let callback = onPCMDataReady else { return }

        let data = pcmBuffer.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }

        callback(data)
        pcmBuffer.removeAll()
    }
}
