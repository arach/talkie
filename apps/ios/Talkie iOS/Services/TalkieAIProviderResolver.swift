//
//  TalkieAIProviderResolver.swift
//  Talkie iOS
//
//  Finds phone-owned AI provider credentials for local AI commands.
//

import Foundation

@MainActor
struct TalkieAIProviderResolver {
    static let shared = TalkieAIProviderResolver()

    private static let defaultOpenAIModel = "gpt-5.2-chat-latest"

    private init() { }

    func configuredProvider() -> ComposeBorrowedProvider? {
        let settings = TalkieAppSettings.shared
        let providerId = settings.composeDirectProviderId.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelId = settings.composeDirectModelId.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cachedProvider = ComposeProviderCredentialStore.shared.load(
            providerId: providerId.isEmpty ? nil : providerId,
            modelId: modelId.isEmpty ? nil : modelId
        ) {
            return cachedProvider
        }

        let ttsApiKey = settings.ttsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if settings.ttsProvider == "openai", !ttsApiKey.isEmpty {
            return ComposeBorrowedProvider(
                providerId: "openai",
                providerName: "OpenAI",
                modelId: modelId.isEmpty ? Self.defaultOpenAIModel : modelId,
                apiKey: ttsApiKey,
                assistantPrompt: TalkieAIProviderCredentialPayload.defaultAssistantPrompt,
                fallbackReason: "Using the iPhone OpenAI speech key for AI commands."
            )
        }

        return nil
    }
}
