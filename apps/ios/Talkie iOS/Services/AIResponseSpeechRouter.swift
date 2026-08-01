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

        AppLogger.ai.info(
            "AI speech start route=\(route.rawValue) provider=\(settings.ttsProvider) "
                + "mode=\(settings.ttsMode) chars=\(text.count)"
        )

        guard route != .silent else {
            AppLogger.ai.info("AI speech skipped route=silent")
            return AIResponseSpeechResult(didSpeak: false, route: route)
        }

        // Interrupt anything still being read aloud. Without this a new
        // response would overlap the tail of the previous one.
        WalkieFX.shared.stopVoicePlayback()

        do {
            let audioData = try await synthesizeSpeech(text, provider: provider, settings: settings)
            AppLogger.ai.info("AI speech synthesized bytes=\(audioData.count) route=\(route.rawValue)")

            switch route {
            case .phone:
                let playbackRate = Float(settings.ttsPlaybackRate)

                let session = AVAudioSession.sharedInstance()
                let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
                AppLogger.ai.info(
                    "AI speech phone playback rate=\(playbackRate) category=\(session.category.rawValue) "
                        + "outputs=\(outputs.isEmpty ? "none" : outputs)"
                )

                // Walkie bookend: opening kerchunk -> speech -> tail + closing
                // kerchunk. Synthesized at runtime; failures are silent so the
                // FX never blocks speech playback.
                WalkieFX.shared.playOpeningClick()
                try? await Task.sleep(for: .milliseconds(60))

                let speechDuration = await WalkieFX.shared.playVoiceAudio(
                    data: audioData,
                    playbackRate: playbackRate,
                    transcript: text,
                    title: preview
                )

                AppLogger.ai.info("AI speech phone scheduled duration=\(speechDuration)")

                return AIResponseSpeechResult(
                    didSpeak: true,
                    route: route,
                    speechDuration: speechDuration
                )

            case .watch:
                let didSend = WatchSessionManager.shared.sendAIAudio(
                    memoId: memoId ?? "",
                    audioData: audioData,
                    preview: preview ?? text
                )
                return AIResponseSpeechResult(
                    didSpeak: didSend,
                    route: route,
                    failure: didSend ? nil : "The Watch did not accept the audio."
                )

            case .silent:
                return AIResponseSpeechResult(didSpeak: false, route: route)
            }
        } catch {
            AppLogger.ai.warning("AI speech skipped: \(error.localizedDescription)")
            // Reported, not thrown: callers narrate the result of work that
            // already succeeded, so a speech failure must stay separable from
            // the success of that work.
            return AIResponseSpeechResult(
                didSpeak: false,
                route: route,
                failure: error.localizedDescription
            )
        }
    }

    private func synthesizeSpeech(
        _ text: String,
        provider: ComposeBorrowedProvider?,
        settings: TalkieAppSettings
    ) async throws -> Data {
        let hasDirectTTS = settings.ttsMode == "direct"
            && settings.ttsProvider != "local"
            && (
                !settings.ttsApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || TalkieAIProviderResolver.shared.provider(providerId: settings.ttsProvider) != nil
            )

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

enum AIResponseSpeechRoute: String, Equatable, Sendable {
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
    /// Why narration did not happen, when it was attempted and failed.
    /// `nil` for both success and a deliberately silent route.
    let failure: String?
    /// Best-effort length of the spoken audio, so callers can hold a
    /// "speaking" state for as long as speech is actually playing.
    let speechDuration: TimeInterval

    init(
        didSpeak: Bool,
        route: AIResponseSpeechRoute,
        failure: String? = nil,
        speechDuration: TimeInterval = 0
    ) {
        self.didSpeak = didSpeak
        self.route = route
        self.failure = failure
        self.speechDuration = speechDuration
    }
}
