//
//  AgentHomeVoiceCapture.swift
//  TalkieAgent
//

import Foundation
import TalkieKit

private let agentHomeVoiceLog = Log(.audio)

@MainActor
final class AgentHomeVoiceCapture: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recording
        case processing
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsedMs = 0
    @Published private(set) var errorMessage: String?

    private var meter: AgentVoiceAudioMeter?
    private var startedAt: Date?
    private var elapsedTimer: Timer?
    private var transcriptionTask: Task<Void, Never>?

    var formattedElapsed: String {
        let totalTenths = max(0, elapsedMs / 100)
        let totalSeconds = totalTenths / 10
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = totalTenths % 10
        let secondsText = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(secondsText).\(tenths)"
    }

    func start() {
        guard phase == .idle else { return }

        transcriptionTask?.cancel()
        transcriptionTask = nil
        errorMessage = nil
        level = 0
        elapsedMs = 0
        startedAt = Date()
        phase = .recording

        let capture = AgentVoiceAudioMeter { [weak self] nextLevel in
            guard let self else { return }
            self.level = self.level * 0.8 + nextLevel * 0.2
        }
        capture.start()
        meter = capture

        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            }
        }

        agentHomeVoiceLog.info("Agent Home inline voice capture started")
    }

    func stopAndTranscribe(
        onTranscript: @escaping (String) -> Void,
        onFinish: @escaping () -> Void
    ) {
        guard phase == .recording else { return }

        let audioURL = stopCapture()
        guard let audioURL else {
            errorMessage = "I didn't catch enough audio."
            phase = .idle
            onFinish()
            return
        }

        phase = .processing
        transcriptionTask?.cancel()
        transcriptionTask = Task { @MainActor [weak self] in
            defer {
                try? FileManager.default.removeItem(at: audioURL)
                onFinish()
            }

            guard let self, !Task.isCancelled else { return }

            do {
                let connected = await EngineClient.shared.ensureConnected()
                guard connected else {
                    self.errorMessage = "Transcription engine isn't ready."
                    self.phase = .idle
                    return
                }

                let rawTranscript = try await EngineClient.shared.transcribe(
                    audioPath: audioURL.path,
                    modelId: LiveSettings.shared.selectedModelId,
                    priority: .userInitiated,
                    postProcess: .none
                )
                let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !Task.isCancelled else { return }

                guard !transcript.isEmpty else {
                    self.errorMessage = "I didn't catch any speech."
                    self.phase = .idle
                    return
                }

                self.errorMessage = nil
                self.phase = .idle
                onTranscript(transcript)
                agentHomeVoiceLog.info("Agent Home inline voice transcript captured", detail: transcript)
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = "Couldn't transcribe that. \(error.localizedDescription)"
                self.phase = .idle
                agentHomeVoiceLog.error(
                    "Agent Home inline voice transcription failed",
                    detail: error.localizedDescription
                )
            }
        }
    }

    func cancel() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        errorMessage = nil
        _ = stopCapture()
        phase = .idle
        level = 0
        elapsedMs = 0
        agentHomeVoiceLog.info("Agent Home inline voice capture cancelled")
    }

    private func stopCapture() -> URL? {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        startedAt = nil

        meter?.stop()
        let audioURL = meter?.recordedFileURL
        meter = nil
        level = 0
        return audioURL
    }
}
