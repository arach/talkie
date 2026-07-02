//
//  VisualContextFrameProcessor.swift
//  TalkieKit
//
//  Optional FFmpeg processor that decomposes screen clips into a sampled frame
//  set and a unified contact-sheet canvas (TLK-026).
//

import Foundation

public enum VisualContextFrameProcessor {
    public static let processorVersion = "talkie-ffmpeg-frames-v1"
    public static let contactSheetFilename = "contact-sheet.jpg"
    public static let framesDirectoryName = "frames"
    public static let frameFilenamePrefix = "frame-"
    public static let maxFrames = 48
    public static let minFrames = 4
    public static let cellWidth = 420
    public static let contactSheetMaxWidth = 3_360
    private static let timeoutSeconds: TimeInterval = 120

    private static let log = Log(.system)

    public static var isAvailable: Bool {
        ExecutableResolver.resolve("ffmpeg") != nil
            && ExecutableResolver.resolve("ffprobe") != nil
    }

    /// Fire-and-forget background decomposition. Updates the bundle on disk when
    /// complete; does not block capture or paste delivery.
    public static func schedule(for context: RecordingVisualContext) {
        guard isAvailable else { return }
        Task.detached(priority: .utility) {
            _ = await process(context: context)
        }
    }

    @concurrent
    public static func process(context: RecordingVisualContext) async -> RecordingVisualContext {
        guard isAvailable else { return context }
        guard let ffmpeg = ExecutableResolver.resolve("ffmpeg"),
              let ffprobe = ExecutableResolver.resolve("ffprobe") else {
            return context
        }

        var updated = context
        updated.status = .processing
        let bundleURL = VisualContextStorage.bundleURL(for: context)
        let sourceURL = CaptureMediaFileResolver.visualContextSourceURL(for: context)

        guard let sourceURL,
              FileManager.default.fileExists(atPath: sourceURL.path) else {
            updated.status = .failed
            updated.errorMessage = "Source clip missing"
            return updated
        }

        do {
            let durationSeconds = try await probeDuration(
                sourceURL: sourceURL,
                ffprobe: ffprobe,
                fallbackSeconds: context.durationMs.map { Double($0) / 1000.0 }
            )
            let targetCount = targetFrameCount(durationSeconds: durationSeconds)
            let fps = max(0.02, Double(targetCount) / max(durationSeconds, 0.25))
            let layout = tileLayout(for: targetCount)

            let framesURL = bundleURL.appendingPathComponent(framesDirectoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: framesURL, withIntermediateDirectories: true)
            try removeExistingFrames(in: framesURL)

            let extractCommand = [
                ffmpeg.path,
                "-hide_banner",
                "-loglevel", "error",
                "-i", sourceURL.path,
                "-vf", "fps=\(formatFPS(fps)),scale=\(cellWidth):-1",
                framesURL.appendingPathComponent("\(frameFilenamePrefix)%04d.jpg").path,
            ].joined(separator: " ")

            _ = try await runExecutable(
                ffmpeg,
                arguments: [
                    "-hide_banner",
                    "-loglevel", "error",
                    "-i", sourceURL.path,
                    "-vf", "fps=\(formatFPS(fps)),scale=\(cellWidth):-1",
                    framesURL.appendingPathComponent("\(frameFilenamePrefix)%04d.jpg").path,
                ],
                workingDirectory: bundleURL
            )

            let frameFiles = try sortedFrameFiles(in: framesURL)
            guard !frameFiles.isEmpty else {
                throw ProcessingError.noFramesExtracted
            }

            let tileFilter = "tile=\(layout.columns)x\(layout.rows):margin=8:padding=4,scale=\(contactSheetMaxWidth):-1"
            let contactSheetURL = bundleURL.appendingPathComponent(contactSheetFilename)
            if FileManager.default.fileExists(atPath: contactSheetURL.path) {
                try FileManager.default.removeItem(at: contactSheetURL)
            }

            let tileCommand = [
                ffmpeg.path,
                "-hide_banner",
                "-loglevel", "error",
                "-pattern_type", "glob",
                "-i", framesURL.appendingPathComponent("\(frameFilenamePrefix)*.jpg").path,
                "-vf", tileFilter,
                "-frames:v", "1",
                contactSheetURL.path,
            ].joined(separator: " ")

            _ = try await runExecutable(
                ffmpeg,
                arguments: [
                    "-hide_banner",
                    "-loglevel", "error",
                    "-pattern_type", "glob",
                    "-i", framesURL.appendingPathComponent("\(frameFilenamePrefix)*.jpg").path,
                    "-vf", tileFilter,
                    "-frames:v", "1",
                    contactSheetURL.path,
                ],
                workingDirectory: bundleURL
            )

            let manifest = try VisualContextStorage.loadManifest(from: bundleURL)
            let frameEntries = frameManifestEntries(
                frameFiles: frameFiles,
                durationSeconds: durationSeconds
            )
            let processorRun = RecordingVisualContextProcessorRun(
                kind: "ffmpeg-frames",
                version: processorVersion,
                command: "\(extractCommand); \(tileCommand)",
                status: .ready
            )

            var mergedManifest = manifest
            mergedManifest.frames = frameEntries
            mergedManifest.durationSeconds = durationSeconds
            mergedManifest.processors.append(processorRun)

            updated.contactSheetFilename = contactSheetFilename
            updated.frameCount = frameEntries.count
            updated.status = .ready
            updated.processorVersion = processorVersion
            updated.errorMessage = nil

            try VisualContextStorage.writeProcessedBundle(
                context: updated,
                manifest: mergedManifest,
                bundleURL: bundleURL
            )
            log.info(
                "Visual context frames ready",
                detail: "\(frameEntries.count) frames · \(layout.columns)x\(layout.rows) canvas"
            )
            return updated
        } catch {
            updated.status = .failed
            updated.errorMessage = error.localizedDescription
            log.warning("Visual context frame processing failed: \(error.localizedDescription)")

            if var manifest = try? VisualContextStorage.loadManifest(from: bundleURL) {
                manifest.processors.append(
                    RecordingVisualContextProcessorRun(
                        kind: "ffmpeg-frames",
                        version: processorVersion,
                        status: .failed,
                        errorMessage: error.localizedDescription
                    )
                )
                try? VisualContextStorage.writeProcessedBundle(
                    context: updated,
                    manifest: manifest,
                    bundleURL: bundleURL
                )
            }

            return updated
        }
    }

    // MARK: - Sampling

    public static func sampleInterval(durationSeconds: Double) -> Double {
        switch durationSeconds {
        case ...8:
            return 1.0 / 3.0
        case ...30:
            return 1.0
        case ...120:
            return 2.0
        case ...600:
            return 5.0
        default:
            return 10.0
        }
    }

    public static func targetFrameCount(durationSeconds: Double) -> Int {
        guard durationSeconds > 0 else { return minFrames }
        let interval = sampleInterval(durationSeconds: durationSeconds)
        let estimated = Int(floor(durationSeconds / interval)) + 2
        return min(maxFrames, max(minFrames, estimated))
    }

    public static func tileLayout(for frameCount: Int) -> (columns: Int, rows: Int) {
        let count = max(1, frameCount)
        let columns = min(8, max(4, Int(ceil(sqrt(Double(count))))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        return (columns, rows)
    }

    // MARK: - Internals

    private enum ProcessingError: LocalizedError {
        case noFramesExtracted
        case invalidDuration
        case timedOut
        case nonZeroExit(Int32, String)

        var errorDescription: String? {
            switch self {
            case .noFramesExtracted:
                return "No frames were extracted from the clip."
            case .invalidDuration:
                return "Could not determine clip duration."
            case .timedOut:
                return "Frame processing timed out."
            case .nonZeroExit(let code, let stderr):
                if stderr.isEmpty {
                    return "ffmpeg exited with status \(code)."
                }
                return "ffmpeg exited with status \(code): \(stderr)"
            }
        }
    }

    private static func formatFPS(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    private static func frameManifestEntries(
        frameFiles: [URL],
        durationSeconds: Double
    ) -> [RecordingVisualContextFrame] {
        let denominator = max(1, frameFiles.count - 1)
        return frameFiles.enumerated().map { index, url in
            let timeSeconds: Double
            if durationSeconds <= 0 {
                timeSeconds = 0
            } else if index == frameFiles.count - 1 {
                timeSeconds = durationSeconds
            } else {
                timeSeconds = (Double(index) / Double(denominator)) * durationSeconds
            }
            return RecordingVisualContextFrame(
                index: index + 1,
                timeSeconds: timeSeconds,
                path: "frames/\(url.lastPathComponent)"
            )
        }
    }

    private static func sortedFrameFiles(in directory: URL) throws -> [URL] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return urls
            .filter { $0.lastPathComponent.hasPrefix(frameFilenamePrefix) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func removeExistingFrames(in directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        for url in urls where url.lastPathComponent.hasPrefix(frameFilenamePrefix) {
            try FileManager.default.removeItem(at: url)
        }
    }

    @concurrent
    private static func probeDuration(
        sourceURL: URL,
        ffprobe: URL,
        fallbackSeconds: Double?
    ) async throws -> Double {
        let result = try await runExecutable(
            ffprobe,
            arguments: [
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                sourceURL.path,
            ],
            workingDirectory: sourceURL.deletingLastPathComponent()
        )

        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(trimmed), value > 0 {
            return value
        }
        if let fallbackSeconds, fallbackSeconds > 0 {
            return fallbackSeconds
        }
        throw ProcessingError.invalidDuration
    }

    @concurrent
    private static func runExecutable(
        _ executable: URL,
        arguments: [String],
        workingDirectory: URL
    ) async throws -> (stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ExecutableResolver.enrichedEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while process.isRunning {
            if Date() >= deadline {
                process.terminate()
                throw ProcessingError.timedOut
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            throw ProcessingError.nonZeroExit(process.terminationStatus, stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return (stdout, stderr)
    }
}
