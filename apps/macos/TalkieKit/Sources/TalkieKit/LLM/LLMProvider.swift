//
//  LLMProvider.swift
//  TalkieKit
//
//  Protocol-based LLM provider architecture supporting multiple backends
//  Shared between Talkie and TalkieAgent for interstitial polish
//

import Foundation
import os

private let logger = Logger(subsystem: "to.talkie.app.kit", category: "LLM")

// MARK: - Core Protocol

public protocol LLMProvider: Sendable {
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
        options: LLMGenerationOptions
    ) async throws -> String

    /// Generate text with streaming (token by token)
    func streamGenerate(
        prompt: String,
        model: String,
        options: LLMGenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - Model Definition

public struct LLMModel: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let size: String
    public let type: LLMModelType
    public let provider: String
    public let downloadURL: URL?
    public let isInstalled: Bool

    public init(
        id: String,
        name: String,
        displayName: String,
        size: String,
        type: LLMModelType,
        provider: String,
        downloadURL: URL? = nil,
        isInstalled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.size = size
        self.type = type
        self.provider = provider
        self.downloadURL = downloadURL
        self.isInstalled = isInstalled
    }
}

public enum LLMModelType: String, Codable, Sendable {
    case local
    case cloud
}

// MARK: - Generation Options

public struct LLMGenerationOptions: Sendable {
    public var temperature: Double
    public var topP: Double
    public var maxTokens: Int
    public var stopSequences: [String]
    public var systemPrompt: String?

    public init(
        temperature: Double = 0.7,
        topP: Double = 0.9,
        maxTokens: Int = 512,
        stopSequences: [String] = [],
        systemPrompt: String? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.stopSequences = stopSequences
        self.systemPrompt = systemPrompt
    }

    public static let `default` = LLMGenerationOptions()
}

// MARK: - Errors

public enum LLMError: LocalizedError, Sendable {
    case providerNotAvailable(String)
    case modelNotFound(String)
    case generationFailed(String)
    case configurationError(String)
    case notConfigured

    public var errorDescription: String? {
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

// MARK: - API Key Store

/// Reads API keys from shared settings or Keychain
/// For TalkieAgent, we use shared UserDefaults since Keychain sharing requires App Groups
public final class LLMAPIKeyStore: @unchecked Sendable {
    public static let shared = LLMAPIKeyStore()

    private init() {}

    public func get(_ provider: LLMAPIKeyProvider) -> String? {
        // Read from shared UserDefaults
        // Talkie writes these keys when user configures them in settings
        let value = TalkieSharedSettings.string(forKey: provider.settingsKey)
        guard let key = value, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return key
    }
}

public enum LLMAPIKeyProvider: Sendable {
    case openai
    case anthropic
    case gemini
    case groq

    var settingsKey: String {
        switch self {
        case .openai: return AgentSettingsKey.openaiApiKey
        case .anthropic: return AgentSettingsKey.anthropicApiKey
        case .gemini: return AgentSettingsKey.geminiApiKey
        case .groq: return AgentSettingsKey.groqApiKey
        }
    }
}

// MARK: - Provider Registry

@MainActor
@Observable
public final class LLMProviderRegistry {
    public static let shared = LLMProviderRegistry()

    public private(set) var providers: [any LLMProvider] = []
    public private(set) var allModels: [LLMModel] = []
    public var selectedProviderId: String?
    public var selectedModelId: String?

    /// Curated list of recommended models to show in pickers
    public static let recommendedModels: Set<String> = [
        // OpenAI - GPT-5 (tight selection)
        "gpt-5.2-chat-latest",  // Flagship conversational
        "gpt-5.2-pro",          // Higher quality, slower
        "gpt-5-nano",           // Fastest/cheapest
        // OpenAI - Reasoning
        "o4-mini",              // Fast reasoning
        // Anthropic
        "claude-sonnet-4-20250514",
        "claude-3-5-sonnet-20241022",
        "claude-3-haiku-20240307",
        // Google
        "gemini-2.0-flash",
        "gemini-2.0-flash-lite",
        "gemini-1.5-flash",
        // Groq
        "llama-3.3-70b-versatile",
        "llama-3.1-8b-instant",
    ]

    /// Preferred order for auto-selection
    private let preferredProviderOrder = ["groq", "openai", "anthropic", "gemini"]

    private init() {
        registerProvidersSync()

        Task {
            await refreshModels()
        }
    }

    private func registerProvidersSync() {
        providers.append(LLMOpenAIProvider())
        providers.append(LLMAnthropicProvider())
        providers.append(LLMGeminiProvider())
        providers.append(LLMGroqProvider())

    }

    public func refreshModels() async {
        var models: [LLMModel] = []

        for provider in providers {
            do {
                let providerModels = try await provider.models
                models.append(contentsOf: providerModels)
            } catch {
                logger.debug("Failed to get models from \(provider.name): \(error)")
            }
        }

        allModels = models
    }

    public func provider(for id: String) -> (any LLMProvider)? {
        providers.first { $0.id == id }
    }

    public func model(for id: String) -> LLMModel? {
        allModels.first { $0.id == id }
    }

    public var selectedProvider: (any LLMProvider)? {
        guard let id = selectedProviderId else { return nil }
        return provider(for: id)
    }

    public var selectedModel: LLMModel? {
        guard let id = selectedModelId else { return nil }
        return model(for: id)
    }

    /// Get recommended models for a specific provider
    public func recommendedModels(for providerId: String) -> [LLMModel] {
        allModels
            .filter { $0.provider == providerId }
            .filter { Self.recommendedModels.contains($0.id) }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Get the first available provider with its default model
    public func firstAvailableProvider() async -> (provider: any LLMProvider, modelId: String)? {
        for providerId in preferredProviderOrder {
            if let provider = provider(for: providerId),
               await provider.isAvailable {
                let defaultModel = defaultModelId(for: providerId)
                return (provider, defaultModel)
            }
        }
        return nil
    }

    /// Get the selected provider/model or fall back to first available
    public func resolveProviderAndModel() async -> (provider: any LLMProvider, modelId: String)? {
        if let provider = selectedProvider,
           let model = selectedModel {
            return (provider, model.id)
        }
        return await firstAvailableProvider()
    }

    /// Default model ID for a provider
    public func defaultModelId(for providerId: String) -> String {
        switch providerId {
        case "openai": return "gpt-4o-mini"
        case "anthropic": return "claude-3-5-sonnet-20241022"
        case "gemini": return "gemini-1.5-flash-latest"
        case "groq": return "llama-3.3-70b-versatile"
        default: return ""
        }
    }
}
