//
//  CorpusTest.swift
//  TalkieAgent
//
//  Real-audio regression tests using the existing recording corpus.
//  Pulls recordings from the live database (memos + dictations),
//  re-transcribes the audio through the real Engine, and compares
//  against the stored transcription.
//
//  This catches regressions in: audio decoding, segmentation,
//  compression, Engine transcription, and word-level accuracy.
//  DEBUG only.
//

#if DEBUG

import AVFoundation
import GRDB
import TalkieKit

private let log = Log(.audio)

@MainActor
final class CorpusTest {

    // MARK: - Types

    struct TestResult {
        let id: String
        let label: String           // e.g. "dictation-4.5s" or "memo-198s"
        let type: String            // "dictation" or "memo"
        let audioDuration: Double
        let originalWordCount: Int
        let retranscribedWordCount: Int
        let similarity: Double      // word overlap score
        let passed: Bool
        let sameModel: Bool         // true = re-transcribed with same model as original
        let durationMs: Int         // wall clock time for this test
        let detail: String
    }

    struct CorpusSample {
        let id: String
        let type: String
        let text: String
        let duration: Double
        let audioFilename: String
        let transcriptionModel: String?  // Original model used (e.g. "parakeet:v3")
    }

    // MARK: - Sampling

    /// Walk audio files on disk, look up their recordings in the DB.
    /// This is the reliable path — starts from what actually exists.
    static func sampleCorpus(
        shortCount: Int = 5,
        mediumCount: Int = 5,
        longCount: Int = 3,
        memoCount: Int = 3
    ) -> [CorpusSample] {
        let db = UnifiedDatabase.shared
        let fm = FileManager.default
        let audioDir = AudioStorage.audioDirectory

        // Walk all audio files on disk
        guard let files = try? fm.contentsOfDirectory(at: audioDir, includingPropertiesForKeys: nil) else {
            log.error("[CorpusTest] Cannot read audio directory")
            return []
        }

        let audioFilenames = Set(files.map(\.lastPathComponent))
        log.info("[CorpusTest] Found \(audioFilenames.count) audio files on disk")

        // Look up all matching recordings in one query
        let allMatches: [CorpusSample]
        do {
            allMatches = try db.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT id, type, text, duration, audioFilename, transcriptionModel
                    FROM recordings
                    WHERE transcriptionStatus = 'success'
                    AND audioFilename IS NOT NULL AND audioFilename != ''
                    AND length(text) > 10 AND duration >= 2
                    """)
                    .compactMap { row -> CorpusSample? in
                        // ID can be stored as text (older dictations) or blob (UUID, memos)
                        let id: String
                        if let textId = row["id"] as? String {
                            id = textId
                        } else if let blobId = row["id"] as? Data, blobId.count == 16 {
                            let uuid = blobId.withUnsafeBytes { NSUUID(uuidBytes: $0.baseAddress!.assumingMemoryBound(to: UInt8.self)) }
                            id = uuid.uuidString
                        } else {
                            return nil
                        }

                        guard let text = row["text"] as? String,
                              let duration = row["duration"] as? Double,
                              let audioFilename = row["audioFilename"] as? String,
                              audioFilenames.contains(audioFilename) else {
                            return nil
                        }
                        let type = (row["type"] as? String) ?? "dictation"
                        let model = row["transcriptionModel"] as? String
                        return CorpusSample(id: id, type: type, text: text, duration: duration, audioFilename: audioFilename, transcriptionModel: model)
                    }
            }
        } catch {
            log.error("[CorpusTest] Failed to query corpus: \(error.localizedDescription)")
            return []
        }

        // Get the current model so we can prefer same-model recordings (deterministic results)
        let currentModel = LiveSettings.shared.selectedModelId
        log.info("[CorpusTest] Current model: '\(currentModel)'")
        let sameModel = allMatches.filter { $0.transcriptionModel == currentModel }
        let crossModel = allMatches.filter { $0.transcriptionModel != currentModel }

        log.info("[CorpusTest] \(allMatches.count) recordings on disk (\(sameModel.count) same model [\(currentModel)], \(crossModel.count) cross-model)")

        // Bucket and sample — prefer same-model recordings for deterministic comparison,
        // fall back to cross-model if not enough same-model available.
        func bucket(_ samples: [CorpusSample]) -> [String: [CorpusSample]] {
            var b: [String: [CorpusSample]] = ["short": [], "medium": [], "long": [], "memo": []]
            for s in samples {
                if s.type == "memo" {
                    b["memo"]!.append(s)
                } else if s.duration < 5 {
                    b["short"]!.append(s)
                } else if s.duration < 30 {
                    b["medium"]!.append(s)
                } else {
                    b["long"]!.append(s)
                }
            }
            return b
        }

        let sameBuckets = bucket(sameModel)
        let crossBuckets = bucket(crossModel)

        // Merge: same-model first, then cross-model to fill gaps
        var buckets: [String: [CorpusSample]] = [:]
        for key in ["short", "medium", "long", "memo"] {
            buckets[key] = sameBuckets[key]! + crossBuckets[key]!
        }

        // Shuffle and take requested counts
        var samples: [CorpusSample] = []
        samples += buckets["short"]!.shuffled().prefix(shortCount)
        samples += buckets["medium"]!.shuffled().prefix(mediumCount)
        samples += buckets["long"]!.shuffled().prefix(longCount)
        samples += buckets["memo"]!.shuffled().prefix(memoCount)

        let dictCount = samples.filter { $0.type != "memo" }.count
        let memoActual = samples.filter { $0.type == "memo" }.count
        log.info("[CorpusTest] Sampled \(samples.count) recordings (\(dictCount) dictations, \(memoActual) memos) from \(buckets.values.map(\.count)) available [short/medium/long/memo]")
        return samples
    }

    // MARK: - Runner

    static func runAll(
        transcription: TranscriptionService,
        samples: [CorpusSample]? = nil,
        segmentDuration: TimeInterval? = nil
    ) async -> [TestResult] {
        let corpus = samples ?? sampleCorpus()
        guard !corpus.isEmpty else {
            log.warning("[CorpusTest] No samples found — is the database populated?")
            return []
        }

        log.info("[CorpusTest] Starting \(corpus.count) tests")
        var results: [TestResult] = []

        for sample in corpus {
            let result = await runOne(sample: sample, transcription: transcription, segmentDuration: segmentDuration)
            results.append(result)
            let status = result.passed ? "PASS" : "FAIL"
            log.info("[CorpusTest] [\(status)] \(result.label): sim=\(String(format: "%.0f%%", result.similarity * 100)) \(result.detail)")
        }

        let passed = results.filter(\.passed).count
        let avgSimilarity = results.isEmpty ? 0 : results.map(\.similarity).reduce(0, +) / Double(results.count)
        log.info("[CorpusTest] Done: \(passed)/\(results.count) passed, avg similarity \(String(format: "%.0f%%", avgSimilarity * 100))")
        return results
    }

    static func runOne(
        sample: CorpusSample,
        transcription: TranscriptionService,
        segmentDuration: TimeInterval?
    ) async -> TestResult {
        let start = Date()
        let currentModel = LiveSettings.shared.selectedModelId
        let isSameModel = sample.transcriptionModel == currentModel
        let modelTag = isSameModel ? "=" : "≠"
        let label = "\(sample.type)-\(String(format: "%.0fs", sample.duration))"
        let audioURL = AudioStorage.url(for: sample.audioFilename)

        // Verify audio file
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            return TestResult(
                id: sample.id, label: label, type: sample.type,
                audioDuration: sample.duration, originalWordCount: 0,
                retranscribedWordCount: 0, similarity: 0, passed: false,
                sameModel: isSameModel,
                durationMs: elapsed(since: start), detail: "audio file missing"
            )
        }

        // If segmentDuration is set, run through simulateCapture for segmented path.
        // Otherwise, transcribe the audio file directly (single-segment path).
        let retranscribedText: String
        do {
            if let segDuration = segmentDuration {
                retranscribedText = try await transcribeSegmented(
                    audioURL: audioURL, segmentDuration: segDuration, transcription: transcription
                )
            } else {
                let request = TranscriptionRequest(audioPath: audioURL.path, isLive: true)
                let result = try await transcription.transcribe(request)
                retranscribedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return TestResult(
                id: sample.id, label: label, type: sample.type,
                audioDuration: sample.duration, originalWordCount: wordCount(sample.text),
                retranscribedWordCount: 0, similarity: 0, passed: false,
                sameModel: isSameModel,
                durationMs: elapsed(since: start), detail: "transcription failed: \(error.localizedDescription)"
            )
        }

        let originalWords = wordCount(sample.text)
        let retranscribedWords = wordCount(retranscribedText)
        let sim = wordSimilarity(expected: sample.text, actual: retranscribedText)

        // Same model: expect high similarity but not 100% — beam search has some non-determinism
        // and dictionary post-processing may have evolved since original transcription.
        // Cross-model: lower bar since models normalize differently.
        let threshold: Double
        if isSameModel {
            threshold = sample.duration < 5 ? 0.80 : 0.90
        } else {
            threshold = sample.duration < 5 ? 0.65 : 0.75
        }
        let passed = sim >= threshold

        return TestResult(
            id: sample.id, label: label, type: sample.type,
            audioDuration: sample.duration,
            originalWordCount: originalWords,
            retranscribedWordCount: retranscribedWords,
            similarity: sim,
            passed: passed,
            sameModel: isSameModel,
            durationMs: elapsed(since: start),
            detail: "\(modelTag) \(originalWords)→\(retranscribedWords) words, \(String(format: "%.1fs", sample.duration)) audio"
        )
    }

    // MARK: - Segmented Transcription

    /// Feed audio through the capture pipeline with segmentation, transcribe each segment, merge.
    private static func transcribeSegmented(
        audioURL: URL,
        segmentDuration: TimeInterval,
        transcription: TranscriptionService
    ) async throws -> String {
        // Use AudioFileWriter to segment the audio (same code path as real recording)
        let writer = AudioFileWriter()
        writer.segmentDuration = segmentDuration

        let sourceFile = try AVAudioFile(forReading: audioURL)
        let format = sourceFile.processingFormat
        let chunkSize: AVAudioFrameCount = 4096

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorpusTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputURL = tempDir.appendingPathComponent("capture.wav")
        guard writer.createFile(at: outputURL, format: format) else {
            throw NSError(domain: "CorpusTest", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create output file"
            ])
        }

        // Feed audio through writer (triggers segment rotation)
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
            throw NSError(domain: "CorpusTest", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create read buffer"
            ])
        }

        while sourceFile.framePosition < sourceFile.length {
            try sourceFile.read(into: readBuffer)
            if readBuffer.frameLength == 0 { break }
            writer.write(readBuffer)
        }

        guard let result = writer.finalize() else {
            throw NSError(domain: "CorpusTest", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Finalize returned nil"
            ])
        }

        // Transcribe each segment
        let segmentPaths = result.segments.isEmpty ? [result.url.path] : result.segments.map(\.url.path)
        var allText = ""

        for segPath in segmentPaths {
            let request = TranscriptionRequest(audioPath: segPath, isLive: true)
            let segResult = try await transcription.transcribe(request)
            let segText = segResult.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !segText.isEmpty {
                if !allText.isEmpty { allText += " " }
                allText += segText
            }
        }

        return allText
    }

    // MARK: - Helpers

    private static func wordSimilarity(expected: String, actual: String) -> Double {
        let normalize: (String) -> [String] = { text in
            text.lowercased()
                .split(separator: " ")
                .map { String($0).filter(\.isLetter) }
                .filter { !$0.isEmpty }
        }
        let expectedWords = normalize(expected)
        let actualWords = normalize(actual)

        guard !expectedWords.isEmpty else { return actualWords.isEmpty ? 1.0 : 0.0 }

        let expectedSet = Set(expectedWords)
        let actualSet = Set(actualWords)
        let overlap = expectedSet.intersection(actualSet).count
        return Double(overlap) / Double(expectedSet.count)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(separator: " ").count
    }

    private static func elapsed(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}

#endif
