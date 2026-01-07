//
//  LLMProvider.swift
//  Talkie
//
//  Protocol-based LLM provider architecture supporting multiple backends
//

import Foundation
import os
import Observation

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LLM")
// MARK: - LLM Configuration (loaded from LLMConfig.json)

struct LLMConfig: Codable {
    let providers: [String: ProviderConfig]
    let preferredProviderOrder: [String]

    struct ProviderConfig: Codable {
        let id: String
        let name: String
        let defaultModel: String
        let models: [ModelConfig]
    }

    struct ModelConfig: Codable {
        let id: String
        let displayName: String
        let description: String?
    }

    /// Shared config instance loaded from bundle (lazy - only when LLM features are used)
    static let shared: LLMConfig = {
        // Try with subdirectory first (Resources/Resources/LLMConfig.json)
        if let url = Bundle.main.url(forResource: "LLMConfig", withExtension: "json", subdirectory: "Resources"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            return config
        }

        // Fallback to root Resources directory
        if let url = Bundle.main.url(forResource: "LLMConfig", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let config = try? JSONDecoder().decode(LLMConfig.self, from: data) {
            return config
        }

        logger.warning("⚠️ Failed to load LLMConfig.json from bundle, using empty config")
        return LLMConfig(providers: [:], preferredProviderOrder: [])
    }()

    /// Get config for a specific provider
    func config(for providerId: String) -> ProviderConfig? {
        providers[providerId]
    }

    /// Get default model ID for a provider
    func defaultModel(for providerId: String) -> String? {
        providers[providerId]?.defaultModel
    }
}

// MARK: - Core Protocol

protocol LLMProvider {
    /// Unique identifier for this provider
    var id: String { get }

    /// Display name
    var name: String { get }

    /// Available models for this provider
    var models: [LLMModel] { get async throws }

    /// Whether this provider is currently available/configured
    var isAvailable: Bool { get async }

    /// Generate text from prompt (non-streaming)
    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String

    /// Generate text with streaming (token by token)
    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Protocol Extension for Config-Based Defaults

extension LLMProvider {
    /// Default model ID from config file
    var defaultModelId: String {
        LLMConfig.shared.defaultModel(for: id) ?? ""
    }

    /// Provider display name from config (falls back to protocol property)
    var configName: String {
        LLMConfig.shared.config(for: id)?.name ?? name
    }
}

// MARK: - Model Definition

struct LLMModel: Identifiable, Codable {
    let id: String
    let name: String
    let displayName: String
    let size: String // "3B", "7B", "13B"
    let type: ModelType
    let provider: String
    let downloadURL: URL?
    let isInstalled: Bool

    var sizeInGB: Double? {
        guard let numeric = size.dropLast().compactMap({ $0.wholeNumberValue }).first else {
            return nil
        }
        // Rough estimate: 4-bit quantized models are ~0.5GB per billion params
        return Double(numeric) * 0.5
    }
}

enum ModelType: String, Codable {
    case local
    case cloud
}

// MARK: - Generation Options

struct GenerationOptions {
    var temperature: Double = 0.7
    var topP: Double = 0.9
    var maxTokens: Int = 512
    var stopSequences: [String] = []
    var systemPrompt: String?

    static let `default` = GenerationOptions()
}

// MARK: - Provider Registry

@Observable
@MainActor
class LLMProviderRegistry {
    static let shared = LLMProviderRegistry()

    private(set) var providers: [LLMProvider] = []
    private(set) var allModels: [LLMModel] = []
    var selectedProviderId: String?
    var selectedModelId: String?

    private init() {
        // Register providers synchronously so they're available immediately
        registerProvidersSync()

        // Refresh models asynchronously
        Task {
            await refreshModels()
        }
    }

    private func registerProvidersSync() {
        // Cloud providers
        providers.append(OpenAIProvider())
        providers.append(AnthropicProvider())
        providers.append(GeminiProvider())
        providers.append(GroqProvider())

        // Local providers
        #if arch(arm64)
        providers.append(MLXProvider())
        #endif
    }

    private func registerProviders() async {
        if providers.isEmpty {
            registerProvidersSync()
        }
        await refreshModels()
    }

    func refreshModels() async {
        var models: [LLMModel] = []

        for provider in providers {
            do {
                let providerModels = try await provider.models
                models.append(contentsOf: providerModels)
            } catch {
                logger.debug("⚠️ Failed to get models from \(provider.name): \(error)")
            }
        }

        allModels = models
    }

    func provider(for id: String) -> LLMProvider? {
        providers.first { $0.id == id }
    }

    func model(for id: String) -> LLMModel? {
        allModels.first { $0.id == id }
    }

    var selectedProvider: LLMProvider? {
        guard let id = selectedProviderId else { return nil }
        return provider(for: id)
    }

    var selectedModel: LLMModel? {
        guard let id = selectedModelId else { return nil }
        return model(for: id)
    }

    // MARK: - Default Model Resolution

    /// Get the first available provider with its default model
    /// Returns (provider, modelId) tuple or nil if no providers available
    func firstAvailableProvider() async -> (provider: LLMProvider, modelId: String)? {
        let preferredOrder = LLMConfig.shared.preferredProviderOrder

        for providerId in preferredOrder {
            if let provider = provider(for: providerId),
               await provider.isAvailable {
                return (provider, provider.defaultModelId)
            }
        }
        return nil
    }

    /// Get the selected provider/model or fall back to first available
    func resolveProviderAndModel() async -> (provider: LLMProvider, modelId: String)? {
        // First try user's selection
        if let provider = selectedProvider,
           let model = selectedModel {
            return (provider, model.id)
        }

        // Fall back to first available
        return await firstAvailableProvider()
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case providerNotAvailable(String)
    case modelNotFound(String)
    case generationFailed(String)
    case configurationError(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .providerNotAvailable(let name):
            return "Provider '\(name)' is not available"
        case .configurationError(let message):
            return message
        case .modelNotFound(let id):
            return "Model '\(id)' not found"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        case .notConfigured:
            return "Provider is not configured"
        }
    }
}
