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
        let providerId = settings.composeDirectProviderId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let resolvedProviderId = providerId.isEmpty ? "openai" : providerId
        let rawModelId = settings.composeDirectModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelId = TalkieAIProviderCredentialPayload.normalizedDefaultModel(
            rawModelId.isEmpty ? nil : rawModelId,
            for: resolvedProviderId
        )
        if let modelId, modelId != rawModelId {
            settings.composeDirectModelId = modelId
        }

        if let selectedProvider = exactProvider(
            providerId: resolvedProviderId,
            modelId: modelId
        ) {
            return selectedProvider
        }

        // A user may save a key without explicitly changing the Compose model
        // picker. Fall back deliberately to the last imported provider, then
        // to another locally configured catalog provider. Keep that provider's
        // own model rather than applying the missing provider's model to it.
        if let lastProvider = ComposeProviderCredentialStore.shared.load(),
           AIProviderCatalog.provider(lastProvider.providerId) != nil {
            pin(lastProvider, in: settings)
            return lastProvider
        }

        for entry in AIProviderCatalog.all where entry.id != resolvedProviderId {
            if let provider = exactProvider(providerId: entry.id, modelId: nil) {
                pin(provider, in: settings)
                return provider
            }
        }

        return nil
    }

    func provider(providerId requestedProviderId: String, modelId requestedModelId: String? = nil) -> ComposeBorrowedProvider? {
        let providerId = requestedProviderId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !providerId.isEmpty else { return nil }

        let rawModelId = requestedModelId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelId = TalkieAIProviderCredentialPayload.normalizedDefaultModel(
            rawModelId?.isEmpty == true ? nil : rawModelId,
            for: providerId
        )
        return exactProvider(providerId: providerId, modelId: modelId)
    }

    private func exactProvider(providerId: String, modelId: String?) -> ComposeBorrowedProvider? {
        // A key explicitly managed on this iPhone wins over an older provider
        // payload imported from the Mac, especially after credential recovery.
        if let savedKeyProvider = keychainBackedProvider(
            providerId: providerId,
            modelId: modelId
        ) {
            return savedKeyProvider
        }

        if let cachedProvider = ComposeProviderCredentialStore.shared.load(
            providerId: providerId,
            modelId: modelId
        ) {
            return cachedProvider
        }

        guard providerId == "openai" else { return nil }
        return legacyOpenAITTSProvider(modelId: modelId)
    }

    private func pin(_ provider: ComposeBorrowedProvider, in settings: TalkieAppSettings) {
        settings.composeDirectProviderId = provider.providerId
        settings.composeDirectModelId = provider.modelId
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
