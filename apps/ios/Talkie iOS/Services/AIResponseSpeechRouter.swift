//
//  AIResponseSpeechRouter.swift
//  Talkie iOS
//
//  Speaks short AI responses on the configured device.
//

import Foundation
import AVFoundation

@MainActor
final class AIResponseSpeechRouter {
    static let shared = AIResponseSpeechRouter()

    private init() { }

    func speak(
        _ text: String,
        provider: ComposeBorrowedProvider? = nil,
        memoId: String? = nil,
        preview: String? = nil
    ) async -> AIResponseSpeechResult {
        let settings = TalkieAppSettings.shared
        let route = AIResponseSpeechRoute(rawValue: settings.aiVoiceOutputRoute) ?? .phone

        guard route != .silent else {
            return AIResponseSpeechResult(didSpeak: false, route: route)
        }

        do {
            let audioData = try await synthesizeSpeech(text, provider: provider, settings: settings)

            switch route {
            case .phone:
                let playbackRate = Float(settings.ttsPlaybackRate)

                // Walkie bookend: opening kerchunk -> speech -> tail + closing
                // kerchunk. Synthesized at runtime; failures are silent so the
                // FX never blocks speech playback.
                WalkieFX.shared.playOpeningClick()
                try? await Task.sleep(for: .milliseconds(60))

                await WalkieFX.shared.playVoiceAudio(data: audioData, playbackRate: playbackRate)

                let rawDuration = aiAudioDuration(of: audioData)
                let effectiveRate = playbackRate > 0 ? Double(playbackRate) : 1.0
                let speechDuration = rawDuration / effectiveRate
                WalkieFX.shared.playClosingSequence(after: speechDuration)

                return AIResponseSpeechResult(didSpeak: true, route: route)

            case .watch:
                let didSend = WatchSessionManager.shared.sendAIAudio(
                    memoId: memoId ?? "",
                    audioData: audioData,
                    preview: preview ?? text
                )
                return AIResponseSpeechResult(didSpeak: didSend, route: route)

            case .silent:
                return AIResponseSpeechResult(didSpeak: false, route: route)
            }
        } catch {
            AppLogger.ai.warning("AI speech skipped: \(error.localizedDescription)")
            return AIResponseSpeechResult(didSpeak: false, route: route)
        }
    }

    private func synthesizeSpeech(
        _ text: String,
        provider: ComposeBorrowedProvider?,
        settings: TalkieAppSettings
    ) async throws -> Data {
        let hasDirectTTS = settings.ttsMode == "direct"
            && settings.ttsProvider != "local"
            && !settings.ttsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasDirectTTS {
            return try await TTSService.synthesizeConfigured(text: text, settings: settings)
        }

        if let provider, provider.providerId == "openai", !provider.apiKey.isEmpty {
            return try await TTSService.synthesizeOpenAI(
                text: text,
                voice: settings.ttsVoice.isEmpty ? "echo" : settings.ttsVoice,
                apiKey: provider.apiKey
            )
        }

        return try await TTSService.synthesizeConfigured(text: text, settings: settings)
    }

    /// Best-effort duration probe for the TTS audio payload. Returns 0 if the
    /// data cannot be parsed; callers should treat that as a no-op for any
    /// time-based scheduling.
    private func aiAudioDuration(of data: Data) -> TimeInterval {
        if let probe = try? AVAudioPlayer(data: data) {
            let duration = probe.duration
            return duration.isFinite ? duration : 0
        }
        return 0
    }
}

enum AIResponseSpeechRoute: String {
    case phone
    case watch
    case silent

    var displayName: String {
        switch self {
        case .phone:
            return "iPhone"
        case .watch:
            return "Watch"
        case .silent:
            return "Silent"
        }
    }
}

struct AIResponseSpeechResult {
    let didSpeak: Bool
    let route: AIResponseSpeechRoute
}
