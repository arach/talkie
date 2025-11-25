//
//  LLMProvider.swift
//  Talkie
//
//  Protocol-based LLM provider architecture supporting multiple backends
//

import Foundation

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

@MainActor
class LLMProviderRegistry: ObservableObject {
    static let shared = LLMProviderRegistry()

    @Published private(set) var providers: [LLMProvider] = []
    @Published private(set) var allModels: [LLMModel] = []
    @Published var selectedProviderId: String?
    @Published var selectedModelId: String?

    private init() {
        // Register providers
        Task {
            await registerProviders()
        }
    }

    private func registerProviders() async {
        // Cloud providers
        providers.append(OpenAIProvider())
        providers.append(AnthropicProvider())
        providers.append(GeminiProvider())
        providers.append(GroqProvider())

        // Local providers
        #if arch(arm64)
        providers.append(MLXProvider())
        #endif

        await refreshModels()
    }

    func refreshModels() async {
        var models: [LLMModel] = []

        for provider in providers {
            do {
                let providerModels = try await provider.models
                models.append(contentsOf: providerModels)
            } catch {
                print("⚠️ Failed to get models from \(provider.name): \(error)")
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
