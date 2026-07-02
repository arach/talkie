//
//  LiveTranscriptMonitor.swift
//  Talkie iOS
//
//  Streaming partial-transcript preview for the recording sheet.
//  Runs a parallel AVAudioEngine input tap on the audio session the
//  recorder already activated (the DictationMicMonitor pattern) and
//  feeds buffers to an SFSpeechAudioBufferRecognitionRequest for
//  live partial results — the SpeechRecognizer live-preview approach,
//  minus its session ownership.
//
//  PREVIEW ONLY. The saved transcript still comes from the full-file
//  TranscriptionService pass after save; nothing here touches the
//  save pipeline.
//
//  Degrades silently: speech permission missing (onboarding asks —
//  this monitor never prompts), recognizer unavailable, or the
//  engine failing to start just means `transcript` stays empty.
//  No errors surface, no layout moves.
//
//  Session etiquette: AVAudioRecorder (AudioRecorderManager) owns
//  the AVAudioSession. This monitor never sets the category and
//  never deactivates the session — it only rides the input that is
//  already live. Callers must stop() the monitor BEFORE the recorder
//  tears the session down.
//

import AVFoundation
import Foundation
import Speech

@MainActor
final class LiveTranscriptMonitor: ObservableObject {
    /// Latest partial transcript — the full running text since start().
    @Published private(set) var transcript: String = ""

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

    /// Begin streaming partials off the already-active audio session.
    /// Safe to call when speech is unauthorized or no input exists —
    /// every failure path is a silent no-op.
    func start() {
        guard !isRunning else { return }
        transcript = ""

        // Never prompt from here — onboarding owns the speech
        // permission ask. Anything but .authorized → no preview.
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { return }

        guard let recognizer = SFSpeechRecognizer(locale: Locale.current),
              recognizer.isAvailable else { return }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device for latency + privacy (matches SpeechRecognizer).
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        // No punctuation — cleaner look for a two-line ticker.
        request.addsPunctuation = false
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // A 0Hz input format (no mic route yet / permission race)
        // makes installTap throw an NSException — bail quietly instead.
        guard format.sampleRate > 0 else {
            self.request = nil
            return
        }

        input.removeTap(onBus: 0)
        // Capture the request strongly: the tap runs on the audio
        // thread and appending to the request is thread-safe.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.request = nil
            AppLogger.recording.debug("Live transcript preview unavailable: \(error.localizedDescription)")
            return
        }

        isRunning = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                // Errors are non-events for a preview: keep whatever
                // text already arrived and simply stop updating.
            }
        }
    }

    /// Tear down the tap + recognition. Idempotent. Never touches the
    /// shared AVAudioSession — the recorder owns its lifecycle.
    func stop() {
        isRunning = false
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        recognizer = nil
    }
}
