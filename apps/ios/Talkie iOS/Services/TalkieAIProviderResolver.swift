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

        return legacyOpenAITTSProvider(modelId: modelId.isEmpty ? nil : modelId)
    }

    func provider(providerId requestedProviderId: String, modelId requestedModelId: String? = nil) -> ComposeBorrowedProvider? {
        let providerId = requestedProviderId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerId.isEmpty else { return nil }

        let modelId = requestedModelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cachedProvider = ComposeProviderCredentialStore.shared.load(
            providerId: providerId,
            modelId: modelId?.isEmpty == true ? nil : modelId
        ) {
            return cachedProvider
        }

        guard providerId == "openai" else { return nil }
        return legacyOpenAITTSProvider(modelId: modelId?.isEmpty == true ? nil : modelId)
    }

    private func legacyOpenAITTSProvider(modelId: String?) -> ComposeBorrowedProvider? {
        let settings = TalkieAppSettings.shared
        let ttsApiKey = settings.ttsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.ttsProvider == "openai", !ttsApiKey.isEmpty else { return nil }

        return ComposeBorrowedProvider(
            providerId: "openai",
            providerName: "OpenAI",
            modelId: modelId ?? TalkieAIProviderCredentialPayload.defaultModel(for: "openai"),
            apiKey: ttsApiKey,
            assistantPrompt: TalkieAIProviderCredentialPayload.defaultAssistantPrompt,
            fallbackReason: "Using the iPhone OpenAI speech key for AI commands."
        )
    }
}
