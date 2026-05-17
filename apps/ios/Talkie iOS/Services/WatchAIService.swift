//
//  WatchAIService.swift
//  Talkie iOS
//
//  Runs Apple Watch "Talk to AI" requests on the phone.
//

import Foundation

@MainActor
final class WatchAIService {
    static let shared = WatchAIService()

    private init() {}

    func answer(question: String, memoId: String? = nil) async throws -> WatchAIResponse {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw WatchAIError.emptyQuestion
        }

        var configuredProviderFailure: Error?

        if let provider = TalkieAIProviderResolver.shared.configuredProvider() {
            do {
                let result = try await CaptureAICommandService.shared.run(
                    context: trimmedQuestion,
                    instruction: "Answer this Apple Watch voice request directly. Keep the answer concise and comfortable to read aloud.",
                    title: "Apple Watch AI Request",
                    sourceDescription: "Apple Watch voice request",
                    provider: provider
                )
                let speech = await AIResponseSpeechRouter.shared.speak(
                    result.responseText,
                    provider: provider,
                    memoId: memoId,
                    preview: result.responseText
                )
                return WatchAIResponse(
                    answer: result.responseText,
                    providerName: result.providerName,
                    modelId: result.modelId,
                    didSpeak: speech.didSpeak,
                    speechRoute: speech.route
                )
            } catch {
                configuredProviderFailure = error
                AppLogger.ai.warning("Watch AI cloud answer failed: \(error.localizedDescription)")
            }
        }

        do {
            let answer = try await OnDeviceAIService.shared.answerWatchQuestion(trimmedQuestion)
            let speech = await AIResponseSpeechRouter.shared.speak(
                answer,
                memoId: memoId,
                preview: answer
            )
            return WatchAIResponse(
                answer: answer,
                providerName: "Apple Intelligence",
                modelId: "on-device",
                didSpeak: speech.didSpeak,
                speechRoute: speech.route
            )
        } catch {
            if let configuredProviderFailure {
                throw WatchAIError.unavailable(
                    "AI credentials are saved, but the provider rejected the request: \(configuredProviderFailure.localizedDescription)"
                )
            }
            throw WatchAIError.unavailable("Run npx @talkie/ai qr on your Mac or enable Apple Intelligence on this iPhone.")
        }
    }
}

struct WatchAIResponse {
    let answer: String
    let providerName: String
    let modelId: String
    let didSpeak: Bool
    let speechRoute: AIResponseSpeechRoute
}

enum WatchAIError: LocalizedError {
    case emptyQuestion
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuestion:
            return "Ask AI needs something to answer."
        case .unavailable(let message):
            return message
        }
    }
}
