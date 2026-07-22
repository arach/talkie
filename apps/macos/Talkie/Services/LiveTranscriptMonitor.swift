//
//  LiveTranscriptMonitor.swift
//  Talkie
//
//  Streaming partial-transcript preview for the memo recording surface.
//  Runs a parallel AVAudioEngine input tap alongside the memo recorder
//  and feeds buffers to Apple Speech for low-latency partial results.
//
//  PREVIEW ONLY. The saved transcript still comes from the canonical
//  post-stop EngineClient pass, where Parakeet remains the high-quality
//  full-file engine. This live path never loads Parakeet models.
//

import AVFoundation
import Foundation
import Observation
import Speech
import TalkieKit

private let logger = Log(.transcription)

@MainActor
@Observable
final class LiveTranscriptMonitor {
    static let shared = LiveTranscriptMonitor()

    /// Latest Apple Speech partial transcript. Survives `stop()` so the
    /// recording surface can hold the final preview while the wave settles.
    private(set) var transcript: String = ""

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var isActive = false
    /// Invalidates an in-flight authorization request when `stop()` lands.
    @ObservationIgnored private var startToken = 0

    private init() {}

    /// Begin streaming Apple Speech partials off the already-live mic.
    /// The first user-initiated recording may request Speech Recognition
    /// permission. Unavailable/error paths quietly leave the preview empty.
    func start() async {
        guard !isActive else { return }
        isActive = true
        startToken += 1
        let token = startToken
        transcript = ""

        guard await ensureAuthorization(), token == startToken else {
            isActive = false
            return
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.isAvailable else {
            logger.debug("Live transcript preview skipped: Apple Speech unavailable")
            isActive = false
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = false
        request.taskHint = .dictation

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            logger.debug("Live transcript preview skipped: no microphone input format")
            isActive = false
            return
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
            request.append(buffer)
        }

        self.engine = engine
        self.recognizer = recognizer
        self.request = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                if let result {
                    self.transcript = InverseTextNormalizer.normalize(
                        result.bestTranscription.formattedString
                    )
                }
                if let error {
                    logger.debug("Live transcript preview stopped updating: \(error.localizedDescription)")
                }
            }
        }

        do {
            engine.prepare()
            try engine.start()
            logger.info("Live transcript preview started with Apple Speech")
        } catch {
            input.removeTap(onBus: 0)
            recognitionTask?.cancel()
            recognitionTask = nil
            self.request = nil
            self.recognizer = nil
            self.engine = nil
            isActive = false
            logger.debug("Live transcript preview engine failed: \(error.localizedDescription)")
        }
    }

    /// Tear down the tap and recognition task. Idempotent. Never touches
    /// the recorder's audio path or the canonical post-stop transcription.
    func stop(clearingTranscript: Bool = false) async {
        startToken += 1
        guard isActive else {
            if clearingTranscript { transcript = "" }
            return
        }
        isActive = false

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil

        request?.endAudio()
        request = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognizer = nil

        if clearingTranscript {
            transcript = ""
        }
    }

    private func ensureAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        case .denied, .restricted:
            logger.debug("Live transcript preview skipped: Speech Recognition not authorized")
            return false
        @unknown default:
            return false
        }
    }
}
