@preconcurrency import AVFoundation
import Foundation

struct AudioSegment: Sendable {
    let index: Int
    let url: URL
    let duration: TimeInterval
    let startedAt: Date
    let endedAt: Date
}

actor SegmentAnalyzer {
    func analyze(_ segment: AudioSegment) async {
        let size = (try? FileManager.default.attributesOfItem(atPath: segment.url.path)[.size] as? Int) ?? 0
        print(
            """

            analysis hook
              segment: \(segment.index)
              file: \(segment.url.lastPathComponent)
              duration: \(segment.duration.formatted(.number.precision(.fractionLength(1))))s
              bytes: \(size)
              next step: transcribe this file, then feed the transcript to a rolling summary/task extractor
            """
        )
    }
}

private struct PCMBufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

final class RollingRecorder: @unchecked Sendable {
    private let segmentDuration: TimeInterval
    private let overlapDuration: TimeInterval
    private let outputDirectory: URL
    private let onSegmentCompleted: @Sendable (AudioSegment) -> Void

    private let engine = AVAudioEngine()
    private let writerQueue = DispatchQueue(label: "sample.rolling-recorder.writer")

    private var currentFile: AVAudioFile?
    private var currentURL: URL?
    private var currentStartedAt = Date()
    private var currentFrames: AVAudioFramePosition = 0
    private var currentFreshFrames: AVAudioFramePosition = 0
    private var segmentIndex = 0
    private var inputFormat: AVAudioFormat?
    private var overlapBuffers: [AVAudioPCMBuffer] = []
    private var overlapFrames: AVAudioFramePosition = 0
    private var isRunning = false

    init(
        segmentDuration: TimeInterval,
        overlapDuration: TimeInterval,
        outputDirectory: URL,
        onSegmentCompleted: @escaping @Sendable (AudioSegment) -> Void
    ) {
        self.segmentDuration = segmentDuration
        self.overlapDuration = overlapDuration
        self.outputDirectory = outputDirectory
        self.onSegmentCompleted = onSegmentCompleted
    }

    func start() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        inputFormat = format

        try openNextSegment(format: format, includeOverlap: false)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let copy = buffer.deepCopy() else { return }
            let box = PCMBufferBox(buffer: copy)
            writerQueue.async {
                self.write(box.buffer)
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() -> AudioSegment? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        return writerQueue.sync {
            closeCurrentSegment()
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }

        do {
            try currentFile?.write(from: buffer)
            currentFrames += AVAudioFramePosition(buffer.frameLength)
            currentFreshFrames += AVAudioFramePosition(buffer.frameLength)
            rememberForOverlap(buffer)

            if currentDuration >= segmentDuration {
                if let completed = closeCurrentSegment() {
                    onSegmentCompleted(completed)
                }
                if let inputFormat {
                    try openNextSegment(format: inputFormat, includeOverlap: true)
                }
            }
        } catch {
            print("write failed: \(error.localizedDescription)")
        }
    }

    private var currentDuration: TimeInterval {
        guard let sampleRate = inputFormat?.sampleRate, sampleRate > 0 else { return 0 }
        return Double(currentFrames) / sampleRate
    }

    private func openNextSegment(format: AVAudioFormat, includeOverlap: Bool) throws {
        currentStartedAt = Date()
        currentFrames = 0
        currentFreshFrames = 0

        let paddedIndex = segmentIndex.formatted(.number.precision(.integerLength(3)))
        let url = outputDirectory.appending(path: "segment-\(paddedIndex).wav")
        currentURL = url
        currentFile = try AVAudioFile(forWriting: url, settings: format.settings)

        if includeOverlap {
            for buffer in overlapBuffers {
                try currentFile?.write(from: buffer)
                currentFrames += AVAudioFramePosition(buffer.frameLength)
            }
        }
    }

    private func closeCurrentSegment() -> AudioSegment? {
        guard let url = currentURL, currentFreshFrames > 0 else { return nil }

        currentFile = nil
        let sampleRate = inputFormat?.sampleRate ?? 44_100
        let segment = AudioSegment(
            index: segmentIndex,
            url: url,
            duration: Double(currentFrames) / sampleRate,
            startedAt: currentStartedAt,
            endedAt: Date()
        )

        segmentIndex += 1
        currentURL = nil
        currentFrames = 0
        currentFreshFrames = 0
        return segment
    }

    private func rememberForOverlap(_ buffer: AVAudioPCMBuffer) {
        guard let copy = buffer.deepCopy(),
              let sampleRate = inputFormat?.sampleRate,
              overlapDuration > 0 else {
            return
        }

        overlapBuffers.append(copy)
        overlapFrames += AVAudioFramePosition(copy.frameLength)

        let maxOverlapFrames = AVAudioFramePosition(overlapDuration * sampleRate)
        while overlapFrames > maxOverlapFrames, let first = overlapBuffers.first {
            overlapFrames -= AVAudioFramePosition(first.frameLength)
            overlapBuffers.removeFirst()
        }
    }
}

extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        copy.frameLength = frameLength

        let audioBuffers = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let copyAudioBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)

        for index in 0..<audioBuffers.count {
            let source = audioBuffers[index]
            let destination = copyAudioBuffers[index]
            guard let sourceData = source.mData, let destinationData = destination.mData else {
                continue
            }
            memcpy(destinationData, sourceData, Int(source.mDataByteSize))
        }

        return copy
    }
}

@main
struct RollingRecorderSample {
    static func main() async throws {
        let permissionGranted = await AVCaptureDevice.requestAccess(for: .audio)
        guard permissionGranted else {
            print("Microphone permission was denied.")
            return
        }

        let analyzer = SegmentAnalyzer()
        let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "Segments")

        let recorder = RollingRecorder(
            segmentDuration: 12,
            overlapDuration: 2,
            outputDirectory: outputDirectory
        ) { segment in
            Task {
                await analyzer.analyze(segment)
            }
        }

        print("Recording rolling chunks to \(outputDirectory.path)")
        print("Segment duration: 12s, overlap: 2s")
        print("Press Return to stop.")

        try recorder.start()
        _ = readLine()

        if let finalSegment = recorder.stop() {
            await analyzer.analyze(finalSegment)
        }

        print("\nStopped.")
    }
}
