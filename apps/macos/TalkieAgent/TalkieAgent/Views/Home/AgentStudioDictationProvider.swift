//
//  AgentStudioDictationProvider.swift
//  TalkieAgent
//
//  Bridges the Talkie Markdown editor (in TalkieKit) to the Agent's voice
//  stack. TalkieKit declares the `MarkdownStudioDictating` seam; the Agent's
//  capture primitive (`AgentVoiceAudioMeter`) and transcription client
//  (`EngineClient`) live here, so this adapter assembles them into the
//  record → transcribe → hand-back flow the editor's Dictate actions need.
//

import Foundation
import TalkieKit

@MainActor
final class AgentStudioDictationProvider: MarkdownStudioDictating {
    private var meter: AgentVoiceAudioMeter?
    private var level: Float = 0

    var audioLevel: Float { level }

    func start() async throws {
        cancel()
        let m = AgentVoiceAudioMeter { [weak self] lvl in self?.level = lvl }
        m.start()
        meter = m
        level = 0
    }

    func stop() async throws -> (text: String, audioURL: URL) {
        guard let m = meter else { throw AgentStudioDictationError.notRecording }
        m.stop()
        meter = nil
        level = 0

        guard let url = m.recordedFileURL else {
            throw AgentStudioDictationError.noAudio
        }

        do {
            let text = try await EngineClient.shared.transcribe(
                audioPath: url.path,
                modelId: LiveSettings.shared.selectedModelId,
                priority: .userInitiated,
                postProcess: .none
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            return (text: text, audioURL: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func cancel() {
        if let m = meter {
            m.stop()
            if let url = m.recordedFileURL { try? FileManager.default.removeItem(at: url) }
        }
        meter = nil
        level = 0
    }
}

enum AgentStudioDictationError: LocalizedError {
    case notRecording
    case noAudio

    var errorDescription: String? {
        switch self {
        case .notRecording: return "Not currently recording"
        case .noAudio: return "Didn't catch any audio"
        }
    }
}
