//
//  AIResponseSpeechRouter.swift
//  Talkie iOS
//
//  Speaks short AI responses on the configured device.
//

import Foundation

@MainActor
final class AIResponseSpeechRouter {
    static let shared = AIResponseSpeechRouter()

    private let audioPlayer = AudioPlayerManager()

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
                audioPlayer.setPlaybackRate(Float(settings.ttsPlaybackRate))
                audioPlayer.playAudio(data: audioData)
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
