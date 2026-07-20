//
//  AudioFileWriter.swift
//  TalkieAgent
//
//  PCM audio file writing with instant teardown and segment rotation.
//  Records as Linear PCM (WAV) for fast stop - no encoder flush needed.
//  Segments are compressed to 16kHz int16 mono in the background.
//  Conforms to AudioWriterProtocol for unified audio capture.
//

import AVFoundation
import TalkieKit

private let log = Log(.audio)

/// Handles writing audio buffers to a file (PCM or AAC)
/// Conforms to AudioWriterProtocol for use with unified audio capture system
final class AudioFileWriter: AudioWriterProtocol {

    // MARK: - Segment compression

    private static let compressQueue = DispatchQueue(label: "to.talkie.app.audio.compress", qos: .utility)
    private static let compressSampleRate: Double = 16000
    private static let compressBitDepth: Int = 16

    // MARK: - Configuration

    /// Segment duration in seconds. 0 = no segmentation.
    var segmentDuration: TimeInterval = 0

    /// Whether finalize() appends the trailing-silence pad. Whisper needs it
    /// to avoid cutting off the last words; Parakeet trims trailing silence
    /// and appends its own chirp tail in the engine, so callers can skip the
    /// pad (and the wasted write/convert bytes) when Parakeet is selected.
    var trailingSilenceEnabled = true

    /// Callback fired when a segment is completed and compressed (on background queue)
    var onSegmentCompleted: ((AudioWriterSegment) -> Void)?

    // MARK: - State

    private var audioFile: AVAudioFile?
    private var fileURL: URL?
    private var bufferCount: Int = 0
    private var _isOpen: Bool = false
    private var currentConfig: AudioWriterConfig?
    private let checkpointLock = NSLock()
    private var checkpointRequested = false

    /// Track write failures - surface immediately for reliability
    private var hasReportedWriteError: Bool = false

    /// Callback for write errors (e.g., disk full, file handle invalid)
    /// IMPORTANT: Errors are surfaced immediately on first failure to prevent silent data loss.
    var onWriteError: ((String) -> Void)?

    /// Total frames written (across all segments)
    private(set) var framesWritten: AVAudioFramePosition = 0

    /// File format being used
    private(set) var fileFormat: AVAudioFormat?

    // MARK: - Segment tracking

    private var baseURL: URL?
    private var segmentIndex = 0
    private var segmentFramesWritten: AVAudioFramePosition = 0
    private var completedSegments: [AudioWriterSegment] = []
    private var sourceFormat: AVAudioFormat?
    private var emittedSegmentIndices: Set<Int> = []

    // MARK: - AudioWriterProtocol Properties

    var isOpen: Bool { _isOpen }

    var currentURL: URL? { fileURL }

    var currentSegmentIndex: Int { segmentIndex }

    // MARK: - Public API

    /// Create a new PCM audio file (legacy API - uses default PCM config)
    /// - Parameters:
    ///   - url: Where to write the file
    ///   - format: Audio format (sample rate, channels)
    /// - Returns: true if file was created successfully
    func createFile(at url: URL, format: AVAudioFormat) -> Bool {
        createFile(at: url, format: format, config: .pcm)
    }

    /// Create a new audio file with specified configuration
    /// - Parameters:
    ///   - url: Where to write the file
    ///   - format: Audio format (sample rate, channels)
    ///   - config: Writer configuration (PCM or AAC)
    /// - Returns: true if file was created successfully
    func createFile(at url: URL, format: AVAudioFormat, config: AudioWriterConfig) -> Bool {
        baseURL = url
        sourceFormat = format
        segmentIndex = 0
        segmentFramesWritten = 0
        completedSegments.removeAll()
        emittedSegmentIndices.removeAll()
        checkpointLock.withLock {
            checkpointRequested = false
        }
        return openSegmentFile(at: url, format: format, config: config)
    }

    /// Write an audio buffer to the file
    /// - Parameter buffer: PCM buffer to write
    /// - Returns: true if write succeeded
    @discardableResult
    func write(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let audioFile = audioFile, _isOpen else {
            log.warning("Cannot write - file not open")
            return false
        }

        // Reduce channels if needed (AAC/PCM max stereo)
        let bufferToWrite: AVAudioPCMBuffer
        if buffer.format.channelCount > 2 {
            if let reduced = reduceToStereo(buffer) {
                bufferToWrite = reduced
            } else {
                bufferToWrite = buffer
            }
        } else {
            bufferToWrite = buffer
        }

        do {
            try audioFile.write(from: bufferToWrite)
            bufferCount += 1
            let frames = AVAudioFramePosition(bufferToWrite.frameLength)
            framesWritten += frames
            segmentFramesWritten += frames

            // Rotate segment if needed
            if consumeCheckpointRequest() {
                rotateSegment()
            } else if segmentDuration > 0, segmentDurationSeconds >= segmentDuration {
                rotateSegment()
            }

            return true
        } catch {
            log.error("Failed to write buffer", detail: "Buffer \(bufferCount)", error: error)

            // Surface error IMMEDIATELY on first failure to prevent silent data loss.
            // Don't wait for multiple failures - one write failure is a critical issue.
            if !hasReportedWriteError {
                hasReportedWriteError = true
                onWriteError?("Audio write failed: \(error.localizedDescription)")
            }
            return false
        }
    }

    /// Close the file - instant for PCM (no encoder flush needed)
    /// - Returns: File info if successful (legacy tuple format)
    func finalizeLegacy() -> (url: URL, size: Int, buffers: Int)? {
        guard let result = finalize() else { return nil }
        return (result.url, result.fileSize, result.bufferCount)
    }

    /// Close the file and return detailed result (AudioWriterProtocol conformance)
    /// - Returns: AudioWriterResult with file info, or nil if not open
    func finalize() -> AudioWriterResult? {
        guard _isOpen else { return nil }

        // Add trailing silence to prevent transcription cutoff
        writeTrailingSilence()

        let savedFrames = framesWritten
        let savedFormat = fileFormat
        let savedBufferCount = bufferCount

        // For AAC, we need a small delay for encoder flush
        if currentConfig?.format == .aac {
            Thread.sleep(forTimeInterval: 0.1)
        }

        // Close current segment file
        audioFile = nil
        _isOpen = false

        // Add the final segment (uncompressed)
        if let url = fileURL {
            let size = fileSize(at: url)
            if size > 0 {
                completedSegments.append(AudioWriterSegment(
                    url: url,
                    fileSize: size,
                    duration: segmentDurationSeconds,
                    index: segmentIndex
                ))
            }
        }

        // Compress ALL segments synchronously (runs once at stop — fast enough for ≤10min segments)
        var compressedSegments: [AudioWriterSegment] = []
        for segment in completedSegments.sorted(by: { $0.index < $1.index }) {
            if let compressed = compressSegment(sourceURL: segment.url, index: segment.index, duration: segment.duration) {
                compressedSegments.append(compressed)
                emitCompletedSegmentIfNeeded(compressed)
            } else {
                compressedSegments.append(segment)
                emitCompletedSegmentIfNeeded(segment)
            }
        }

        let allSegments = compressedSegments
        let primaryURL: URL
        let totalSize: Int

        if allSegments.isEmpty {
            // No segments (error case or very short recording)
            primaryURL = fileURL ?? baseURL ?? URL(fileURLWithPath: "/dev/null")
            totalSize = fileSize(at: primaryURL)
        } else {
            primaryURL = allSegments[0].url
            totalSize = allSegments.reduce(0) { $0 + $1.fileSize }
        }

        // Force filesystem flush
        for segment in allSegments {
            let fd = open(segment.url.path, O_RDONLY)
            if fd >= 0 {
                fcntl(fd, F_FULLFSYNC)
                close(fd)
            }
        }

        let sampleRate = savedFormat?.sampleRate ?? 44100

        if allSegments.count > 1 {
            log.info("Finalized audio: \(allSegments.count) segments", detail: "\(savedBufferCount) buffers, \(totalSize) bytes")
        } else {
            log.info("Finalized audio file", detail: "\(savedBufferCount) buffers, \(totalSize) bytes")
        }

        let result = AudioWriterResult(
            url: primaryURL,
            fileSize: totalSize,
            bufferCount: savedBufferCount,
            framesWritten: Int64(savedFrames),
            duration: Double(savedFrames) / sampleRate,
            segments: allSegments
        )

        // Clean up state
        fileURL = nil
        baseURL = nil
        fileFormat = nil
        sourceFormat = nil
        currentConfig = nil
        bufferCount = 0
        framesWritten = 0
        segmentFramesWritten = 0
        segmentIndex = 0
        completedSegments.removeAll()
        emittedSegmentIndices.removeAll()
        checkpointLock.withLock {
            checkpointRequested = false
        }

        return result
    }

    /// Cancel writing and delete all files
    func cancel() {
        guard _isOpen else { return }

        let url = fileURL

        audioFile = nil
        _isOpen = false

        // Delete current segment
        if let url = url {
            try? FileManager.default.removeItem(at: url)
            log.debug("Cancelled and deleted partial file", detail: url.lastPathComponent)
        }

        // Delete completed segments
        for segment in completedSegments {
            try? FileManager.default.removeItem(at: segment.url)
        }

        // Clean up state
        fileURL = nil
        baseURL = nil
        fileFormat = nil
        sourceFormat = nil
        currentConfig = nil
        bufferCount = 0
        framesWritten = 0
        segmentFramesWritten = 0
        segmentIndex = 0
        completedSegments.removeAll()
        emittedSegmentIndices.removeAll()
        checkpointLock.withLock {
            checkpointRequested = false
        }
        hasReportedWriteError = false
    }

    func requestCheckpoint() {
        checkpointLock.withLock {
            checkpointRequested = true
        }
    }

    /// Duration of audio written (in seconds)
    var duration: TimeInterval {
        guard let format = fileFormat else { return 0 }
        return TimeInterval(framesWritten) / format.sampleRate
    }

    // MARK: - Segment Rotation

    private var segmentDurationSeconds: TimeInterval {
        guard let format = fileFormat else { return 0 }
        return TimeInterval(segmentFramesWritten) / format.sampleRate
    }

    private func rotateSegment() {
        guard let sourceFormat, let config = currentConfig, let base = baseURL else { return }

        let rotatedURL = fileURL!
        let rotatedIndex = segmentIndex
        let rotatedDuration = segmentDurationSeconds

        // Close current file — compression deferred to finalize() to avoid blocking audio thread
        audioFile = nil

        let size = fileSize(at: rotatedURL)
        completedSegments.append(AudioWriterSegment(
            url: rotatedURL,
            fileSize: size,
            duration: rotatedDuration,
            index: rotatedIndex
        ))
        emitCompletedSegmentIfNeeded(completedSegments[completedSegments.count - 1])

        log.info("Segment \(rotatedIndex) rotated", detail: "\(String(format: "%.0f", rotatedDuration))s \(size / 1024)KB — compression deferred")

        // Start new segment
        segmentIndex += 1
        segmentFramesWritten = 0
        let nextURL = segmentURL(base: base, index: segmentIndex)
        _ = openSegmentFile(at: nextURL, format: sourceFormat, config: config)
    }

    private func segmentURL(base: URL, index: Int) -> URL {
        guard index > 0 else { return base }
        let name = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        return base.deletingLastPathComponent()
            .appendingPathComponent("\(name)-\(index).\(ext)")
    }

    private func consumeCheckpointRequest() -> Bool {
        checkpointLock.withLock {
            let requested = checkpointRequested
            checkpointRequested = false
            return requested
        }
    }

    private func emitCompletedSegmentIfNeeded(_ segment: AudioWriterSegment) {
        guard !emittedSegmentIndices.contains(segment.index) else { return }
        emittedSegmentIndices.insert(segment.index)
        onSegmentCompleted?(segment)
    }

    // MARK: - Compression (16kHz int16 mono)

    private func compressSegment(sourceURL: URL, index: Int, duration: TimeInterval) -> AudioWriterSegment? {
        let compressedURL = sourceURL.deletingPathExtension()
            .appendingPathExtension("compressed.wav")

        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let srcFormat = sourceFile.processingFormat  // always float32
            let totalFrames = AVAudioFrameCount(sourceFile.length)

            guard totalFrames > 0 else {
                log.warning("Compress: source file empty for segment \(index)")
                return fallbackSegment(url: sourceURL, index: index, duration: duration)
            }

            let originalSize = fileSize(at: sourceURL)

            // Read entire source into memory (fine for ≤10min segments)
            guard let srcBuffer = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: totalFrames) else {
                return fallbackSegment(url: sourceURL, index: index, duration: duration)
            }
            try sourceFile.read(into: srcBuffer)

            // Downmix to mono at source sample rate
            let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: srcFormat.sampleRate,
                channels: 1,
                interleaved: false
            )!

            let monoBuffer: AVAudioPCMBuffer
            if srcFormat.channelCount == 1 {
                monoBuffer = srcBuffer
            } else {
                guard let mb = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: srcBuffer.frameLength) else {
                    return fallbackSegment(url: sourceURL, index: index, duration: duration)
                }
                mb.frameLength = srcBuffer.frameLength
                if let src = srcBuffer.floatChannelData, let dst = mb.floatChannelData {
                    let frameCount = Int(srcBuffer.frameLength)
                    let channelCount = Int(srcFormat.channelCount)
                    memcpy(dst[0], src[0], frameCount * MemoryLayout<Float>.size)
                    for ch in 1..<channelCount {
                        for i in 0..<frameCount {
                            dst[0][i] += src[ch][i]
                        }
                    }
                    let scale = 1.0 / Float(channelCount)
                    for i in 0..<frameCount {
                        dst[0][i] *= scale
                    }
                }
                monoBuffer = mb
            }

            // Resample mono → 16kHz
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.compressSampleRate,
                channels: 1,
                interleaved: false
            )!

            guard let converter = AVAudioConverter(from: monoBuffer.format, to: targetFormat) else {
                log.warning("Compress: cannot create converter for segment \(index)")
                return fallbackSegment(url: sourceURL, index: index, duration: duration)
            }

            let ratio = Self.compressSampleRate / monoBuffer.format.sampleRate
            let outputFrames = AVAudioFrameCount(ceil(Double(monoBuffer.frameLength) * ratio)) + 64
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrames) else {
                return fallbackSegment(url: sourceURL, index: index, duration: duration)
            }

            // Single-shot conversion with the full buffer
            var inputConsumed = false
            let status = try converter.convert(to: outputBuffer, error: nil) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return monoBuffer
            }

            guard status != .error, outputBuffer.frameLength > 0 else {
                log.warning("Compress: converter returned no data for segment \(index)")
                return fallbackSegment(url: sourceURL, index: index, duration: duration)
            }

            // Write compressed output as int16
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.compressSampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: Self.compressBitDepth,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            let outputFile = try AVAudioFile(forWriting: compressedURL, settings: outputSettings)
            try outputFile.write(from: outputBuffer)

            // Replace original with compressed
            try FileManager.default.removeItem(at: sourceURL)
            try FileManager.default.moveItem(at: compressedURL, to: sourceURL)

            let compressedSize = fileSize(at: sourceURL)
            let ratio_str = originalSize > 0 ? String(format: "%.0fx", Double(originalSize) / Double(max(compressedSize, 1))) : "?"
            log.info("Compressed segment \(index)", detail: "\(originalSize / 1024)KB → \(compressedSize / 1024)KB (\(ratio_str), \(String(format: "%.0f", duration))s)")

            return AudioWriterSegment(
                url: sourceURL,
                fileSize: compressedSize,
                duration: duration,
                index: index
            )
        } catch {
            log.error("Compress failed for segment \(index)", error: error)
            try? FileManager.default.removeItem(at: compressedURL)
            return fallbackSegment(url: sourceURL, index: index, duration: duration)
        }
    }

    private func fallbackSegment(url: URL, index: Int, duration: TimeInterval) -> AudioWriterSegment {
        AudioWriterSegment(
            url: url,
            fileSize: fileSize(at: url),
            duration: duration,
            index: index
        )
    }

    // MARK: - Private Helpers

    private func openSegmentFile(at url: URL, format: AVAudioFormat, config: AudioWriterConfig) -> Bool {
        let outputChannels = min(format.channelCount, AVAudioChannelCount(config.maxChannels))

        let settings: [String: Any]
        switch config.format {
        case .linearPCM:
            settings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: outputChannels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
        case .aac:
            settings = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: outputChannels,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        }

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: settings)
            fileURL = url
            fileFormat = format
            currentConfig = config
            hasReportedWriteError = false
            _isOpen = true

            let formatName = config.format == .linearPCM ? "PCM" : "AAC"
            if segmentIndex > 0 {
                log.info("Opened segment \(segmentIndex)", detail: "\(formatName) \(format.sampleRate)Hz, \(outputChannels)ch")
            } else {
                log.info("Created \(formatName) file", detail: "\(format.sampleRate)Hz, \(outputChannels)ch")
            }
            return true
        } catch {
            log.error("Failed to create audio file", error: error)
            return false
        }
    }

    /// Duration of trailing silence to add (in seconds)
    private static let trailingSilenceDuration: Double = 1.5

    /// Write trailing silence to prevent transcription cutoff
    private func writeTrailingSilence() {
        guard trailingSilenceEnabled,
              let audioFile = audioFile,
              let format = fileFormat,
              bufferCount > 0 else { return }

        let silenceFrames = AVAudioFrameCount(format.sampleRate * Self.trailingSilenceDuration)

        guard let silenceBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: silenceFrames
        ) else {
            log.warning("Could not create silence buffer - transcription may cut off")
            return
        }

        silenceBuffer.frameLength = silenceFrames

        if let floatData = silenceBuffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                memset(floatData[channel], 0, Int(silenceFrames) * MemoryLayout<Float>.size)
            }
        } else if let int16Data = silenceBuffer.int16ChannelData {
            for channel in 0..<Int(format.channelCount) {
                memset(int16Data[channel], 0, Int(silenceFrames) * MemoryLayout<Int16>.size)
            }
        }

        do {
            try audioFile.write(from: silenceBuffer)
            let frames = AVAudioFramePosition(silenceFrames)
            framesWritten += frames
            segmentFramesWritten += frames
        } catch {
            log.warning("Could not write trailing silence - transcription may cut off", detail: error.localizedDescription)
        }
    }

    /// Reduce multi-channel buffer to stereo
    private func reduceToStereo(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        guard format.channelCount > 2 else { return buffer }

        guard let stereoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 2,
            interleaved: false
        ) else { return nil }

        guard let stereoBuffer = AVAudioPCMBuffer(
            pcmFormat: stereoFormat,
            frameCapacity: buffer.frameLength
        ) else { return nil }

        stereoBuffer.frameLength = buffer.frameLength

        if let srcData = buffer.floatChannelData,
           let dstData = stereoBuffer.floatChannelData {
            let frameCount = Int(buffer.frameLength) * MemoryLayout<Float>.size
            memcpy(dstData[0], srcData[0], frameCount)
            memcpy(dstData[1], srcData[1], frameCount)
        }

        return stereoBuffer
    }

    private func fileSize(at url: URL) -> Int {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int {
            return size
        }
        return 0
    }
}
