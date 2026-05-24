//
//  SSHTerminalDictationController.swift
//  Talkie iOS
//
//  Shared inline dictation flow for in-app text surfaces.
//  Records locally, then transcribes with the normal Talkie transcription engine.
//

import AVFoundation
import Foundation

@MainActor
final class InlineDictationController: NSObject {
    private enum Constants {
        static let minimumRecordedDuration: TimeInterval = 0.2
    }

    enum State: Equatable {
        case idle
        case recording
        case transcribing
    }

    var onStateChange: ((State) -> Void)?
    var onTranscript: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    var currentState: State {
        state
    }

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var activeStartToken: UUID?
    private var activeTranscriptionToken: UUID?

    func start() async {
        guard state == .idle else { return }

        let startToken = UUID()
        activeStartToken = startToken
        state = .transcribing

        let speechAuthorized = await requestSpeechPermission()
        let microphoneAuthorized = await requestMicrophonePermission()

        guard activeStartToken == startToken else { return }

        guard speechAuthorized, microphoneAuthorized else {
            activeStartToken = nil
            state = .idle
            onError?("Allow microphone and speech access to use dictation.")
            return
        }

        do {
            try configureAudioSession()

            let outputURL = makeRecordingURL()
            let recorder = try AVAudioRecorder(url: outputURL, settings: recorderSettings)
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw NSError(domain: "SSHTerminalDictation", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not start recording."
                ])
            }

            guard activeStartToken == startToken else {
                recorder.stop()
                deactivateAudioSession()
                try? FileManager.default.removeItem(at: outputURL)
                return
            }

            activeStartToken = nil
            self.recorder = recorder
            self.recordingURL = outputURL
            state = .recording
        } catch {
            activeStartToken = nil
            cleanupRecording(discardFile: true)
            state = .idle
            onError?(error.localizedDescription)
        }
    }

    func stop(insertTranscript: Bool) {
        activeStartToken = nil

        guard let recorder, let recordingURL else {
            cancel()
            return
        }

        let recordedDuration = recorder.currentTime
        recorder.stop()
        self.recorder = nil

        deactivateAudioSession()

        guard insertTranscript else {
            cleanupRecording(discardFile: true)
            state = .idle
            return
        }

        guard recordedDuration >= Constants.minimumRecordedDuration else {
            cleanupRecording(discardFile: true)
            state = .idle
            return
        }

        state = .transcribing
        let transcriptionToken = UUID()
        activeTranscriptionToken = transcriptionToken

        TranscriptionService.shared.transcribe(audioURL: recordingURL, useCase: .keyboard) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.activeTranscriptionToken == transcriptionToken else { return }

                self.activeTranscriptionToken = nil
                defer {
                    self.cleanupRecording(discardFile: true)
                    self.state = .idle
                }

                switch result {
                case .success(let transcript):
                    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    self.onTranscript?(trimmed)
                case .failure(let error):
                    if self.shouldSuppressTranscriptionError(error) {
                        return
                    }
                    self.onError?(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        activeStartToken = nil
        activeTranscriptionToken = nil
        recorder?.stop()
        recorder = nil
        deactivateAudioSession()
        cleanupRecording(discardFile: true)
        state = .idle
    }

    private var recorderSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }

    private func makeRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "ssh-dictation-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
    }

    private func cleanupRecording(discardFile: Bool) {
        if discardFile, let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }

        self.recordingURL = nil
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true)
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            TranscriptionService.shared.requestAuthorization { authorized in
                continuation.resume(returning: authorized)
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        let permission = AVAudioApplication.shared.recordPermission
        switch permission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func shouldSuppressTranscriptionError(_ error: Error) -> Bool {
        // We deliberately do NOT suppress `.noResult` here anymore.
        // Hosts (compose, terminal, …) need to know when the engine
        // ran but returned nothing so they can surface "no speech
        // detected" instead of silently resetting. The donor's behavior
        // before this change was masking a broken transcription path —
        // see PR #27 + the engine-not-loaded session diagnosis.
        return false
    }
}
