//
//  TTSService.swift
//  Talkie iOS
//
//  Configured TTS routing for iOS — direct provider calls plus bridge-backed speech generation.
//

import Foundation
import TalkieMobileKit

private let log = Log(.system)

enum TTSService {

    enum CloudTTSError: LocalizedError {
        case missingAPIKey
        case requestFailed(String)
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "No API key configured"
            case .requestFailed(let msg): return msg
            case .invalidResponse: return "Invalid response from TTS API"
            }
        }
    }

    @MainActor
    static func canSynthesizeConfiguredAudio(
        settings: TalkieAppSettings? = nil,
        bridgeStatus: BridgeManager.ConnectionStatus? = nil
    ) -> Bool {
        let settings = settings ?? .shared
        let bridgeStatus = bridgeStatus ?? BridgeManager.shared.status
        if settings.ttsProvider == "local" {
            return bridgeStatus == .connected
        }

        let hasDirectProvider = settings.ttsMode == "direct" && !settings.ttsApiKey.isEmpty
        return hasDirectProvider || bridgeStatus == .connected
    }

    @MainActor
    static func synthesizeConfigured(
        text: String,
        settings: TalkieAppSettings = .shared
    ) async throws -> Data {
        let isDirect = settings.ttsMode == "direct" && !settings.ttsApiKey.isEmpty
        let isLocal = settings.ttsProvider == "local"

        if isLocal {
            guard BridgeManager.shared.status == .connected else {
                throw CloudTTSError.requestFailed("Reconnect to your Mac to generate speech.")
            }

            let voice = settings.ttsVoice.isEmpty ? "af_heart" : settings.ttsVoice
            let response = try await BridgeManager.shared.client.requestTTS(
                text: text,
                voice: voice,
                provider: "local"
            )
            return try bridgeAudio(from: response, failureMessage: "Local speech returned no audio.")
        }

        if isDirect {
            return try await synthesizeDirect(text: text, settings: settings)
        }

        guard BridgeManager.shared.status == .connected else {
            throw CloudTTSError.requestFailed("Reconnect to your Mac to generate speech.")
        }

        let response = try await BridgeManager.shared.client.requestTTS(text: text)
        return try bridgeAudio(from: response, failureMessage: "Speech generation returned no audio.")
    }

    // MARK: - OpenAI TTS

    static func synthesizeOpenAI(text: String, voice: String, apiKey: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw CloudTTSError.missingAPIKey }

        let url = URL(string: "https://api.openai.com/v1/audio/speech")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": "tts-1",
            "input": String(text.prefix(4096)),
            "voice": voice,
            "response_format": "mp3"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTTSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.error("OpenAI TTS failed (\(httpResponse.statusCode)): \(errorBody)")
            throw CloudTTSError.requestFailed("OpenAI TTS failed: HTTP \(httpResponse.statusCode)")
        }

        log.info("OpenAI TTS: \(data.count) bytes, voice: \(voice)")
        return data
    }

    // MARK: - ElevenLabs TTS

    static func synthesizeElevenLabs(text: String, voiceId: String, apiKey: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw CloudTTSError.missingAPIKey }

        let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "text": String(text.prefix(5000)),
            "model_id": "eleven_monolingual_v1",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CloudTTSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.error("ElevenLabs TTS failed (\(httpResponse.statusCode)): \(errorBody)")
            throw CloudTTSError.requestFailed("ElevenLabs TTS failed: HTTP \(httpResponse.statusCode)")
        }

        log.info("ElevenLabs TTS: \(data.count) bytes, voice: \(voiceId)")
        return data
    }

    @MainActor
    private static func synthesizeDirect(text: String, settings: TalkieAppSettings) async throws -> Data {
        switch settings.ttsProvider {
        case "elevenlabs":
            return try await synthesizeElevenLabs(
                text: text,
                voiceId: settings.ttsVoice,
                apiKey: settings.ttsApiKey
            )
        default:
            return try await synthesizeOpenAI(
                text: text,
                voice: settings.ttsVoice.isEmpty ? "echo" : settings.ttsVoice,
                apiKey: settings.ttsApiKey
            )
        }
    }

    private static func bridgeAudio(from response: TTSResponse, failureMessage: String) throws -> Data {
        guard response.ok, let base64 = response.audioBase64,
              let data = Data(base64Encoded: base64) else {
            log.warning("\(failureMessage)")
            throw CloudTTSError.requestFailed(failureMessage)
        }

        return data
    }
}
