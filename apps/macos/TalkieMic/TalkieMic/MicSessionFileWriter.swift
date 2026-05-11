import Foundation
import AVFoundation
import Darwin
import TalkieKit

private let log = Log(.audio)

struct MicSessionFinalizedFile {
    let filePath: String
    let duration: TimeInterval
    let fileSize: Int
}

final class MicSessionFileWriter {
    private static let trailingSilenceDuration: Double = 1.5

    private let outputURL: URL

    private var audioFile: AVAudioFile?
    private var fileFormat: AVAudioFormat?
    private(set) var framesWritten: AVAudioFramePosition = 0
    private var bufferCount = 0
    private var lastError: Error?

    var bytesWritten: Int {
        guard let fileFormat else { return 0 }
        let bytesPerFrame = Int(fileFormat.streamDescription.pointee.mBytesPerFrame)
        return Int(framesWritten) * bytesPerFrame
    }

    var currentDuration: TimeInterval {
        durationSeconds
    }

    init(outputURL: URL) {
        self.outputURL = outputURL
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        if audioFile == nil {
            guard createFile(format: buffer.format) else { return }
        }

        guard let audioFile else { return }

        let bufferToWrite = reduceToMono(buffer) ?? buffer

        do {
            try audioFile.write(from: bufferToWrite)
            framesWritten += AVAudioFramePosition(bufferToWrite.frameLength)
            bufferCount += 1
        } catch {
            lastError = error
            log.error("TalkieMic failed to write audio buffer", error: error)
        }
    }

    func finalize() throws -> MicSessionFinalizedFile {
        if let lastError {
            throw lastError
        }

        addTrailingSilence()
        audioFile = nil

        let fileSize: Int
        if let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
           let size = attrs[.size] as? Int {
            fileSize = size
        } else {
            fileSize = 0
        }

        let duration = durationSeconds

        let fd = open(outputURL.path, O_RDONLY)
        if fd >= 0 {
            fcntl(fd, F_FULLFSYNC)
            close(fd)
        }

        return MicSessionFinalizedFile(
            filePath: outputURL.path,
            duration: duration,
            fileSize: fileSize
        )
    }

    func cancel() {
        audioFile = nil
        try? FileManager.default.removeItem(at: outputURL)
    }

    private var durationSeconds: TimeInterval {
        guard let fileFormat else { return 0 }
        return TimeInterval(framesWritten) / fileFormat.sampleRate
    }

    private func createFile(format: AVAudioFormat) -> Bool {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioFile = try AVAudioFile(forWriting: outputURL, settings: settings)
            fileFormat = AVAudioFormat(settings: settings)
            return true
        } catch {
            lastError = error
            log.error("TalkieMic failed to create audio file", error: error)
            return false
        }
    }

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
        } else if let int16Data = silenceBuffer.int16ChannelData {
            for channel in 0..<Int(fileFormat.channelCount) {
                memset(int16Data[channel], 0, Int(silenceFrames) * MemoryLayout<Int16>.size)
            }
        }

        do {
            try audioFile.write(from: silenceBuffer)
            framesWritten += AVAudioFramePosition(silenceFrames)
        } catch {
            log.warning("TalkieMic failed to append trailing silence", detail: error.localizedDescription)
        }
    }

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

        // Average all channels into mono
        memcpy(destination[0], source[0], frameCount * MemoryLayout<Float>.size)
        for ch in 1..<channelCount {
            for i in 0..<frameCount {
                destination[0][i] += source[ch][i]
            }
        }
        let scale = 1.0 / Float(channelCount)
        for i in 0..<frameCount {
            destination[0][i] *= scale
        }

        return monoBuffer
    }
}
