//
//  TTSCapability.swift
//  TalkieEnginePod
//
//  TTS capability using FluidAudio's Kokoro model.
//  Runs in a separate process for memory isolation.
//

import Foundation
import FluidAudioTTS

/// Text-to-Speech capability for the execution pod
final class TTSCapability: PodCapability {
    static let name = "tts"
    static let description = "Text-to-Speech synthesis using Kokoro"
    static let supportedActions = ["synthesize", "preload", "voices"]

    private var ttsManager: TtSManager?
    private var requestsHandled = 0

    // Output directory for synthesized audio
    private var outputDirectory: URL {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let ttsDir = supportDir.appendingPathComponent("Talkie/TTS")
        try? FileManager.default.createDirectory(at: ttsDir, withIntermediateDirectories: true)
        return ttsDir
    }

    init() {}

    // MARK: - PodCapability

    var isLoaded: Bool {
        ttsManager != nil
    }

    var memoryUsageMB: Int {
        // Estimate based on model size
        // Kokoro model is ~800MB when loaded
        isLoaded ? 800 : 0
    }

    func load(config: PodConfig) async throws {
        guard !isLoaded else { return }

        let manager = TtSManager()
        try await manager.initialize()
        ttsManager = manager
    }

    func handle(_ request: PodRequest) async throws -> PodResponse {
        requestsHandled += 1

        switch request.action {
        case "synthesize":
            return try await handleSynthesize(request)

        case "preload":
            // Model is already loaded in load(), this is a no-op
            return PodResponse.success(id: request.id, result: ["status": "loaded"])

        case "voices":
            return handleVoices(request)

        default:
            return PodResponse.failure(
                id: request.id,
                error: "Unknown action: \(request.action). Supported: \(Self.supportedActions.joined(separator: ", "))"
            )
        }
    }

    func unload() async {
        ttsManager = nil
    }

    // MARK: - Action Handlers

    private func handleSynthesize(_ request: PodRequest) async throws -> PodResponse {
        guard let manager = ttsManager else {
            return PodResponse.failure(id: request.id, error: "TTS not loaded")
        }

        guard let text = request.payload["text"], !text.isEmpty else {
            return PodResponse.failure(id: request.id, error: "Missing 'text' in payload")
        }

        let voice = request.payload["voice"]
        let voiceParam = (voice == nil || voice == "default") ? nil : voice

        let startTime = Date()

        do {
            let audioData = try await manager.synthesize(text: text, voice: voiceParam)

            // Save to file
            let filename = "tts_\(UUID().uuidString).wav"
            let outputURL = outputDirectory.appendingPathComponent(filename)
            try audioData.write(to: outputURL)

            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let fileSizeKB = audioData.count / 1024

            return PodResponse(
                id: request.id,
                success: true,
                result: [
                    "audioPath": outputURL.path,
                    "fileSizeKB": String(fileSizeKB),
                    "textLength": String(text.count)
                ],
                durationMs: durationMs
            )

        } catch {
            return PodResponse.failure(id: request.id, error: "Synthesis failed: \(error.localizedDescription)")
        }
    }

    private func handleVoices(_ request: PodRequest) -> PodResponse {
        // For now, just Kokoro default voice
        let voices: [[String: String]] = [
            [
                "id": "kokoro:default",
                "provider": "kokoro",
                "name": "Kokoro",
                "language": "en-US"
            ]
        ]

        // Serialize voices array to JSON string for the result
        if let data = try? JSONEncoder().encode(voices),
           let json = String(data: data, encoding: .utf8) {
            return PodResponse.success(id: request.id, result: ["voices": json])
        }

        return PodResponse.success(id: request.id, result: ["voices": "[]"])
    }
}
