import Foundation
import AVFoundation
import Darwin
import TalkieKit

private let log = Log(.audio)

struct MicSessionSegment {
    let filePath: String
    let duration: TimeInterval
    let fileSize: Int
    let index: Int
}

struct MicSessionFinalizedFile {
    let filePath: String
    let duration: TimeInterval
    let fileSize: Int
    let segments: [MicSessionSegment]
}

final class MicSessionFileWriter {
    private static let trailingSilenceDuration: Double = 1.5
    private static let compressQueue = DispatchQueue(label: "to.talkie.agent.mic.compress", qos: .utility)

    // Target format for completed segments (16kHz int16 mono = ~32KB/s)
    private static let compressSampleRate: Double = 16000
    private static let compressBitDepth: Int = 16

    private let baseURL: URL
    private let segmentDuration: TimeInterval

    private var audioFile: AVAudioFile?
    private var fileFormat: AVAudioFormat?
    private var sourceFormat: AVAudioFormat?
    private(set) var framesWritten: AVAudioFramePosition = 0
    private var segmentFramesWritten: AVAudioFramePosition = 0
    private var bufferCount = 0
    private var lastError: Error?

    private var completedSegments: [MicSessionSegment] = []
    private var pendingCompressions = 0
    private var currentSegmentIndex = 0
    private var currentSegmentURL: URL

    var bytesWritten: Int {
        guard let fileFormat else { return 0 }
        let bytesPerFrame = Int(fileFormat.streamDescription.pointee.mBytesPerFrame)
        return Int(framesWritten) * bytesPerFrame
    }

    var currentDuration: TimeInterval {
        durationSeconds
    }

    var segmentCount: Int {
        completedSegments.count + (audioFile != nil ? 1 : 0)
    }

    init(outputURL: URL, segmentDuration: TimeInterval = 60) {
        self.baseURL = outputURL
        self.currentSegmentURL = outputURL
        self.segmentDuration = segmentDuration
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        if sourceFormat == nil {
            sourceFormat = buffer.format
        }

        if audioFile == nil {
            guard createFile(format: buffer.format, url: currentSegmentURL) else { return }
        }

        guard audioFile != nil else { return }

        let bufferToWrite = reduceToMono(buffer) ?? buffer

        do {
            try audioFile!.write(from: bufferToWrite)
            let frames = AVAudioFramePosition(bufferToWrite.frameLength)
            framesWritten += frames
            segmentFramesWritten += frames
            bufferCount += 1

            if segmentDurationSeconds >= segmentDuration {
                rotateSegment()
            }
        } catch {
            lastError = error
            log.error("MicSessionFileWriter failed to write audio buffer", error: error)
        }
    }

    func finalize() throws -> MicSessionFinalizedFile {
        if let lastError {
            throw lastError
        }

        // Finalize current segment — compress inline since we're done recording
        addTrailingSilence()
        audioFile = nil

        if let lastSegment = closeAndCompressSync(url: currentSegmentURL, index: currentSegmentIndex) {
            completedSegments.append(lastSegment)
        }

        // Wait for any in-flight background compressions
        // (they write to completedSegments which we read below)
        Self.compressQueue.sync {}

        let allSegments = completedSegments.sorted { $0.index < $1.index }

        // fsync all segments
        for segment in allSegments {
            let fd = open(segment.filePath, O_RDONLY)
            if fd >= 0 {
                fcntl(fd, F_FULLFSYNC)
                close(fd)
            }
        }

        let totalSize = allSegments.reduce(0) { $0 + $1.fileSize }
        let totalDuration = durationSeconds
        let primaryPath = allSegments.first?.filePath ?? currentSegmentURL.path

        return MicSessionFinalizedFile(
            filePath: primaryPath,
            duration: totalDuration,
            fileSize: totalSize,
            segments: allSegments
        )
    }

    func cancel() {
        audioFile = nil

        try? FileManager.default.removeItem(at: currentSegmentURL)

        for segment in completedSegments {
            try? FileManager.default.removeItem(atPath: segment.filePath)
        }
        completedSegments.removeAll()
    }

    // MARK: - Segment rotation

    private var segmentDurationSeconds: TimeInterval {
        guard let fileFormat else { return 0 }
        return TimeInterval(segmentFramesWritten) / fileFormat.sampleRate
    }

    private var durationSeconds: TimeInterval {
        guard let fileFormat else { return 0 }
        return TimeInterval(framesWritten) / fileFormat.sampleRate
    }

    private func rotateSegment() {
        guard let sourceFormat else { return }

        let segDuration = segmentDurationSeconds
        audioFile = nil

        let rotatedURL = currentSegmentURL
        let rotatedIndex = currentSegmentIndex

        // Compress the completed segment in the background
        Self.compressQueue.async { [weak self] in
            guard let self else { return }
            if let segment = self.compressSegment(sourceURL: rotatedURL, index: rotatedIndex, duration: segDuration) {
                self.completedSegments.append(segment)
            }
        }

        log.info("MicSessionFileWriter rotated segment \(rotatedIndex): \(String(format: "%.0f", segDuration))s — compressing in background")

        // Start new segment
        currentSegmentIndex += 1
        currentSegmentURL = segmentURL(index: currentSegmentIndex)
        segmentFramesWritten = 0

        _ = createFile(format: sourceFormat, url: currentSegmentURL)
    }

    // MARK: - Compression

    private func compressSegment(sourceURL: URL, index: Int, duration: TimeInterval) -> MicSessionSegment? {
        let compressedURL = sourceURL.deletingPathExtension()
            .appendingPathExtension("compressed.wav")

        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let sourceFormat = sourceFile.processingFormat

            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.compressSampleRate,
                channels: 1,
                interleaved: false
            ) else {
                log.warning("MicSessionFileWriter compress: failed to create target format")
                return fallbackSegment(url: sourceURL, index: index, duration: duration)
            }

            guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                log.warning("MicSessionFileWriter compress: failed to create converter")
                return fallbackSegment(url: sourceURL, index: index, duration: duration)
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: Self.compressSampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: Self.compressBitDepth,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            let outputFile = try AVAudioFile(forWriting: compressedURL, settings: outputSettings)

            let bufferSize: AVAudioFrameCount = 8192
            guard let convertBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: bufferSize) else {
                return fallbackSegment(url: sourceURL, index: index, duration: duration)
            }

            var isDone = false
            while !isDone {
                let status = try converter.convert(to: convertBuffer, error: nil) { inNumPackets, outStatus in
                    guard let readBuffer = AVAudioPCMBuffer(
                        pcmFormat: sourceFormat,
                        frameCapacity: inNumPackets
                    ) else {
                        outStatus.pointee = .noDataNow
                        return nil
                    }

                    do {
                        try sourceFile.read(into: readBuffer)
                        if readBuffer.frameLength == 0 {
                            outStatus.pointee = .endOfStream
                            return nil
                        }
                        outStatus.pointee = .haveData
                        return readBuffer
                    } catch {
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                }

                if status == .endOfStream || convertBuffer.frameLength == 0 {
                    isDone = true
                } else {
                    try outputFile.write(from: convertBuffer)
                }
            }

            // Replace original with compressed
            try FileManager.default.removeItem(at: sourceURL)
            try FileManager.default.moveItem(at: compressedURL, to: sourceURL)

            let fileSize: Int
            if let attrs = try? FileManager.default.attributesOfItem(atPath: sourceURL.path),
               let size = attrs[.size] as? Int {
                fileSize = size
            } else {
                fileSize = 0
            }

            log.info("MicSessionFileWriter compressed segment \(index): \(fileSize / 1024)KB")

            return MicSessionSegment(
                filePath: sourceURL.path,
                duration: duration,
                fileSize: fileSize,
                index: index
            )
        } catch {
            log.error("MicSessionFileWriter compress failed for segment \(index)", error: error)
            try? FileManager.default.removeItem(at: compressedURL)
            return fallbackSegment(url: sourceURL, index: index, duration: duration)
        }
    }

    /// Synchronous compress for the final segment (called from finalize)
    private func closeAndCompressSync(url: URL, index: Int) -> MicSessionSegment? {
        let duration = segmentDurationSeconds
        return compressSegment(sourceURL: url, index: index, duration: duration)
    }

    private func fallbackSegment(url: URL, index: Int, duration: TimeInterval) -> MicSessionSegment {
        let fileSize: Int
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int {
            fileSize = size
        } else {
            fileSize = 0
        }

        return MicSessionSegment(
            filePath: url.path,
            duration: duration,
            fileSize: fileSize,
            index: index
        )
    }

    private func segmentURL(index: Int) -> URL {
        guard index > 0 else { return baseURL }
        let base = baseURL.deletingPathExtension().lastPathComponent
        let ext = baseURL.pathExtension
        return baseURL.deletingLastPathComponent()
            .appendingPathComponent("\(base)-\(index).\(ext)")
    }

    // MARK: - File creation (native quality)

    private func createFile(format: AVAudioFormat, url: URL) -> Bool {
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            lastError = NSError(domain: "MicSessionFileWriter", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create mono format from \(format)"
            ])
            return false
        }

        do {
            audioFile = try AVAudioFile(forWriting: url, settings: monoFormat.settings)
            fileFormat = monoFormat
            return true
        } catch {
            lastError = error
            log.error("MicSessionFileWriter failed to create audio file", error: error)
            return false
        }
    }

    // MARK: - Trailing silence

    private func addTrailingSilence() {
        guard let audioFile,
              let fileFormat,
              bufferCount > 0 else { return }

        let silenceFrames = AVAudioFrameCount(fileFormat.sampleRate * Self.trailingSilenceDuration)
        guard let silenceBuffer = AVAudioPCMBuffer(
            pcmFormat: fileFormat,
            frameCapacity: silenceFrames
        ) else {
            return
        }

        silenceBuffer.frameLength = silenceFrames

        if let floatData = silenceBuffer.floatChannelData {
            for channel in 0..<Int(fileFormat.channelCount) {
                memset(floatData[channel], 0, Int(silenceFrames) * MemoryLayout<Float>.size)
            }
        }

        do {
            try audioFile.write(from: silenceBuffer)
            let frames = AVAudioFramePosition(silenceFrames)
            framesWritten += frames
            segmentFramesWritten += frames
        } catch {
            log.warning("MicSessionFileWriter failed to append trailing silence", detail: error.localizedDescription)
        }
    }

    // MARK: - Mono downmix

    private func reduceToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let format = buffer.format
        guard format.channelCount > 1 else { return nil }

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: format.sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            return nil
        }

        guard let monoBuffer = AVAudioPCMBuffer(
            pcmFormat: monoFormat,
            frameCapacity: buffer.frameLength
        ) else {
            return nil
        }

        monoBuffer.frameLength = buffer.frameLength

        guard let source = buffer.floatChannelData,
              let destination = monoBuffer.floatChannelData else {
            return nil
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)

        memcpy(destination[0], source[0], frameCount * MemoryLayout<Float>.size)
        for ch in 1..<channelCount {
            for i in 0..<frameCount {
                destination[0][i] += source[ch][i]
            }
        }
        if channelCount > 1 {
            let scale = 1.0 / Float(channelCount)
            for i in 0..<frameCount {
                destination[0][i] *= scale
            }
        }

        return monoBuffer
    }
}
