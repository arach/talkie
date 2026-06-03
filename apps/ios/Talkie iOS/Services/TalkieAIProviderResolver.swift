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

        if let savedKeyProvider = keychainBackedProvider(
            providerId: providerId.isEmpty ? "openai" : providerId,
            modelId: modelId.isEmpty ? nil : modelId
        ) {
            return savedKeyProvider
        }

        return legacyOpenAITTSProvider(modelId: modelId.isEmpty ? nil : modelId)
    }

    func provider(providerId requestedProviderId: String, modelId requestedModelId: String? = nil) -> ComposeBorrowedProvider? {
        let providerId = requestedProviderId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !providerId.isEmpty else { return nil }

        let modelId = requestedModelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cachedProvider = ComposeProviderCredentialStore.shared.load(
            providerId: providerId,
            modelId: modelId?.isEmpty == true ? nil : modelId
        ) {
            return cachedProvider
        }

        if let savedKeyProvider = keychainBackedProvider(
            providerId: providerId,
            modelId: modelId?.isEmpty == true ? nil : modelId
        ) {
            return savedKeyProvider
        }

        guard providerId == "openai" else { return nil }
        return legacyOpenAITTSProvider(modelId: modelId?.isEmpty == true ? nil : modelId)
    }

    private func keychainBackedProvider(providerId: String, modelId: String?) -> ComposeBorrowedProvider? {
        let providerId = providerId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard AIProviderCatalog.ids.contains(providerId),
              let apiKey = AICredentialStore.shared.key(for: providerId) else {
            return nil
        }

        return ComposeBorrowedProvider(
            providerId: providerId,
            providerName: TalkieAIProviderCredentialPayload.displayName(for: providerId),
            modelId: modelId ?? TalkieAIProviderCredentialPayload.defaultModel(for: providerId),
            apiKey: apiKey,
            assistantPrompt: TalkieAIProviderCredentialPayload.defaultAssistantPrompt,
            fallbackReason: "Using the API key saved in AI Keys on this iPhone."
        )
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
