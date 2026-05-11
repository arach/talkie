//
//  BlackChannelTest.swift
//  TalkieAgent
//
//  End-to-end segmentation test.
//  For each test case: TTS → WAV → transcribe as single file (control) →
//  then feed through black channel with segmentation → transcribe segments → compare.
//  Pass = segmented output matches unsegmented output (>85% word similarity).
//  DEBUG only.
//

#if DEBUG

import AVFoundation
import TalkieKit

private let log = Log(.audio)

@MainActor
final class BlackChannelTest {

    // MARK: - Types

    struct TestCase {
        let label: String
        let text: String
        let segmentDuration: TimeInterval
    }

    struct TestResult {
        let label: String
        let controlText: String      // single-file transcription (ground truth)
        let segmentedText: String     // segmented transcription
        let segments: Int
        let durationMs: Int
        let passed: Bool
        let similarity: Double        // control vs segmented
        let audioDuration: Double
    }

    // MARK: - Content

    private static let memoProductUpdate = """
    Okay so here is my update on the product for this week. We shipped the new segmentation pipeline which was a big milestone. \
    The basic idea is that when you record a long voice memo the system automatically breaks it into smaller chunks. \
    Each chunk is about ten minutes by default but we made it configurable for testing. \
    The reason this matters is that if you are recording for an hour or two hours you do not want a single massive file. \
    If the app crashes you lose everything. With segments you only lose the current chunk. \
    The other benefit is that we can start transcribing earlier segments while the user is still recording. \
    We have not wired that up yet but the infrastructure is there. \
    On the transcription side each segment gets sent to the engine individually and the results are merged. \
    Word level timestamps are offset by the cumulative duration of prior segments so everything lines up correctly. \
    We tested this with both synthetic speech and real recordings and it works great. \
    The similarity scores are above ninety percent across the board. \
    There is one known issue with the background compression. \
    When a segment rotates we compress it from the native sample rate down to sixteen kilohertz mono. \
    This works fine synchronously but the background path has a timing issue where the file is not fully flushed before the compressor reads it. \
    We added a sync call to fix this but it still falls back to the uncompressed version sometimes. \
    Not a blocker since the uncompressed files still work fine for transcription. \
    Next week I want to focus on two things. First getting the compression reliable. \
    Second adding the ability to start transcribing segments while still recording. \
    That would make the experience feel much faster for long recordings. \
    The user would see partial transcription appearing in real time even for a two hour recording session.
    """

    private static let memoDesignReview = """
    Let me walk through the design decisions we made this sprint. \
    The main question was how to handle session lifecycle when clients disconnect and reconnect. \
    Previously when a websocket connection dropped we would immediately cancel the recording session. \
    That was fine when recordings were short but now that we support two hour sessions it is a problem. \
    If your wifi blips for a second you lose your entire recording. \
    So we introduced the concept of orphaned sessions. \
    When a client disconnects the session keeps recording but is marked as orphaned with a timestamp. \
    If the client reconnects within fifteen minutes and calls start dictation with the same client ID \
    we reclaim the session and swap in the new callbacks. \
    The recording never stopped so no audio is lost. \
    If nobody comes back within the grace period the sweep timer cancels the session and cleans up. \
    We also made the session type a class instead of a struct so we can mutate the callbacks in place. \
    The orphan sweep runs every thirty seconds which is good enough granularity. \
    On the audio side we decided to capture at the hardware native rate and compress on segment rotation. \
    The alternative was to downsample in real time but that adds latency to the write path. \
    Since compression happens in the background on a utility queue it does not affect recording at all. \
    The compressed format is sixteen kilohertz mono which is exactly what whisper wants. \
    At that rate a ten minute segment is only about nineteen megabytes. \
    A full two hour recording would be about two hundred and twenty five megabytes across twelve segments. \
    That is very manageable. \
    We also added mono downmixing to the writer. \
    Previously we were capping at stereo but for voice recording mono is all you need. \
    This cuts file size in half compared to stereo with zero quality loss for speech.
    """

    private static let memoStreamOfThought = """
    I have been thinking a lot about what it means to build a voice first product. \
    Most apps treat voice as a secondary input. You type and occasionally you might use dictation. \
    But what if voice was the primary interface and typing was the fallback. \
    That changes everything about how you design the product. \
    For one thing latency becomes critical. When someone finishes speaking they expect the result immediately. \
    Not in two seconds not in five seconds but right now. \
    That is why we invested so much in the audio pipeline. \
    The hot path from pressing the hotkey to getting the first buffer is under fifty milliseconds. \
    We pre warm the audio engine so there is no cold start penalty. \
    The transcription engine runs locally on the device using whisper. \
    No network round trip needed for the basic case. \
    For longer recordings the segmentation helps because we can overlap transcription with recording. \
    While the user is still talking we are already transcribing the first segment. \
    Another thing about voice first is error handling. \
    When you type a wrong word you see it immediately and fix it. \
    With voice you do not know if the transcription will be correct until after you stop recording. \
    That creates anxiety. Did it get my words right. Did it understand that technical term. \
    So you need really good feedback mechanisms. \
    We show confidence scores and highlight uncertain words. \
    We have a custom dictionary for domain specific terms. \
    And we are exploring real time partial transcription so you can see the words appearing as you speak. \
    The other big challenge is context. \
    When you are typing you can see where the cursor is. You know what app you are in. \
    With voice you might be looking at your code editor but the transcription goes to a text field somewhere else. \
    That is why we capture context at the start and end of each recording. \
    We know what app was in the foreground and what text was selected and we can use that to route the output intelligently.
    """

    // MARK: - Test Suite

    static let defaultCases: [TestCase] = [
        // Quick baseline
        TestCase(label: "short-5s", text: "The quick brown fox jumps over the lazy dog.", segmentDuration: 5),

        // Product update at various segment sizes
        TestCase(label: "product-30s", text: memoProductUpdate, segmentDuration: 30),
        TestCase(label: "product-15s", text: memoProductUpdate, segmentDuration: 15),
        TestCase(label: "product-10s", text: memoProductUpdate, segmentDuration: 10),

        // Design review
        TestCase(label: "design-30s", text: memoDesignReview, segmentDuration: 30),
        TestCase(label: "design-20s", text: memoDesignReview, segmentDuration: 20),

        // Stream of thought
        TestCase(label: "thoughts-30s", text: memoStreamOfThought, segmentDuration: 30),
        TestCase(label: "thoughts-15s", text: memoStreamOfThought, segmentDuration: 15),

        // Stress: very small segments
        TestCase(label: "thoughts-5s-stress", text: memoStreamOfThought, segmentDuration: 5),
    ]

    // MARK: - Runner

    static func runAll(
        audioService: AudioCaptureService,
        transcription: TranscriptionService
    ) async -> [TestResult] {
        let cases = defaultCases
        log.info("[BlackChannelTest] Starting \(cases.count) test cases (control vs segmented)")
        var results: [TestResult] = []

        for testCase in cases {
            let result = await runOne(
                testCase: testCase,
                audioService: audioService,
                transcription: transcription
            )
            results.append(result)
            let status = result.passed ? "PASS" : "FAIL"
            log.info("[BlackChannelTest] [\(status)] \(testCase.label): sim=\(String(format: "%.0f%%", result.similarity * 100)) seg=\(result.segments) audio=\(String(format: "%.1f", result.audioDuration))s \(result.durationMs)ms")
        }

        let passed = results.filter(\.passed).count
        log.info("[BlackChannelTest] Done: \(passed)/\(results.count) passed")
        return results
    }

    static func runOne(
        testCase: TestCase,
        audioService: AudioCaptureService,
        transcription: TranscriptionService
    ) async -> TestResult {
        let start = Date()

        // Step 1: Synthesize audio
        guard let wavURL = await synthesize(text: testCase.text) else {
            return failResult(label: testCase.label, error: "TTS failed")
        }

        // Measure audio duration
        let audioDuration: Double
        if let file = try? AVAudioFile(forReading: wavURL) {
            audioDuration = Double(file.length) / file.processingFormat.sampleRate
        } else {
            audioDuration = 0
        }

        log.info("[BlackChannelTest] \(testCase.label): TTS done, \(String(format: "%.1f", audioDuration))s audio")

        // Step 2: CONTROL — transcribe the whole file as one piece
        let controlText: String
        do {
            let request = TranscriptionRequest(audioPath: wavURL.path, isLive: true)
            let result = try await transcription.transcribe(request)
            controlText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            log.error("[BlackChannelTest] Control transcription failed", error: error)
            try? FileManager.default.removeItem(at: wavURL)
            return failResult(label: testCase.label, error: "Control transcription failed")
        }

        log.info("[BlackChannelTest] \(testCase.label): control done (\(controlText.split(separator: " ").count) words)")

        // Step 3: SEGMENTED — feed through black channel with segmentation
        let segmentPaths: [String] = await withCheckedContinuation { continuation in
            audioService.simulateCapture(
                filePaths: [wavURL.path],
                segmentDuration: testCase.segmentDuration
            ) { paths in
                continuation.resume(returning: paths)
            }
        }

        log.info("[BlackChannelTest] \(testCase.label): \(segmentPaths.count) segments produced")

        // Step 4: Transcribe each segment
        var segmentedText = ""
        for segPath in segmentPaths {
            do {
                let request = TranscriptionRequest(audioPath: segPath, isLive: true)
                let result = try await transcription.transcribe(request)
                let segText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !segText.isEmpty {
                    if !segmentedText.isEmpty { segmentedText += " " }
                    segmentedText += segText
                }
            } catch {
                log.error("[BlackChannelTest] Segment transcription failed", error: error)
            }
        }

        // Step 5: Compare control vs segmented
        let similarity = wordSimilarity(expected: controlText, actual: segmentedText)
        let durationMs = Int(Date().timeIntervalSince(start) * 1000)

        // Clean up
        try? FileManager.default.removeItem(at: wavURL)
        for path in segmentPaths {
            try? FileManager.default.removeItem(atPath: path)
        }

        return TestResult(
            label: testCase.label,
            controlText: String(controlText.prefix(120)),
            segmentedText: String(segmentedText.prefix(120)),
            segments: segmentPaths.count,
            durationMs: durationMs,
            passed: similarity >= 0.85,
            similarity: similarity,
            audioDuration: audioDuration
        )
    }

    // MARK: - TTS

    private static func synthesize(text: String) async -> URL? {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let synthesizer = AVSpeechSynthesizer()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blackchannel-tts-\(UUID().uuidString).wav")

        return await withCheckedContinuation { continuation in
            var audioBuffers: [AVAudioPCMBuffer] = []
            var outputFormat: AVAudioFormat?
            var didResume = false

            func finishWriting() {
                guard !didResume else { return }
                didResume = true

                guard let format = outputFormat, !audioBuffers.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    let file = try AVAudioFile(forWriting: outputURL, settings: format.settings)
                    for buf in audioBuffers where buf.frameLength > 0 {
                        try file.write(from: buf)
                    }
                    continuation.resume(returning: outputURL)
                } catch {
                    log.error("[BlackChannelTest] Failed to write TTS WAV", error: error)
                    continuation.resume(returning: nil)
                }
            }

            synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    finishWriting()
                    return
                }
                guard pcmBuffer.frameLength > 0 else {
                    finishWriting()
                    return
                }

                if outputFormat == nil {
                    outputFormat = pcmBuffer.format
                }

                if let copy = AVAudioPCMBuffer(pcmFormat: pcmBuffer.format, frameCapacity: pcmBuffer.frameLength) {
                    copy.frameLength = pcmBuffer.frameLength
                    if let src = pcmBuffer.floatChannelData, let dst = copy.floatChannelData {
                        for ch in 0..<Int(pcmBuffer.format.channelCount) {
                            memcpy(dst[ch], src[ch], Int(pcmBuffer.frameLength) * MemoryLayout<Float>.size)
                        }
                    } else if let src = pcmBuffer.int16ChannelData, let dst = copy.int16ChannelData {
                        for ch in 0..<Int(pcmBuffer.format.channelCount) {
                            memcpy(dst[ch], src[ch], Int(pcmBuffer.frameLength) * MemoryLayout<Int16>.size)
                        }
                    }
                    audioBuffers.append(copy)
                }
            }
        }
    }

    // MARK: - Helpers

    private static func failResult(label: String, error: String) -> TestResult {
        TestResult(label: label, controlText: "", segmentedText: "(\(error))", segments: 0, durationMs: 0, passed: false, similarity: 0, audioDuration: 0)
    }

    private static func wordSimilarity(expected: String, actual: String) -> Double {
        let normalize: (String) -> [String] = { text in
            text.lowercased().split(separator: " ").map { String($0).filter(\.isLetter) }.filter { !$0.isEmpty }
        }
        let expectedWords = normalize(expected)
        let actualWords = normalize(actual)

        guard !expectedWords.isEmpty else { return actualWords.isEmpty ? 1.0 : 0.0 }

        // Use set overlap for similarity (order-independent)
        let expectedSet = Set(expectedWords)
        let actualSet = Set(actualWords)
        let overlap = expectedSet.intersection(actualSet).count
        return Double(overlap) / Double(expectedSet.count)
    }
}

#endif
