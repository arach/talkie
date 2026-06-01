//
//  LLMProvider.swift
//  Talkie
//
//  Protocol-based LLM provider architecture supporting multiple backends
//

import Foundation
import Observation
import TalkieKit

private let log = Log(.system)

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
    /// API key mirrored into shared settings for provider access outside the main-actor settings manager.
    var sharedAPIKey: String {
        let settingsKey: String
        switch id {
        case "openai":
            settingsKey = AgentSettingsKey.openaiApiKey
        case "anthropic":
            settingsKey = AgentSettingsKey.anthropicApiKey
        case "gemini":
            settingsKey = AgentSettingsKey.geminiApiKey
        case "groq":
            settingsKey = AgentSettingsKey.groqApiKey
        default:
            return ""
        }

        return TalkieSharedSettings
            .string(forKey: settingsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Default model ID from config file
    var defaultModelId: String {
        if id == "apple-local" {
            return "apple-on-device"
        }
        return LLMConfig.shared.defaultModel(for: id) ?? ""
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

@MainActor
enum LLMAgentModelPreferences {
    static let didChangeNotification = Notification.Name("LLMAgentModelPreferences.didChange")

    private static let enabledModelKeysKey = "LLMRegistry.enabledMarkupAgentModelKeys"
    private static let curatableProviderIds = Set(["gemini", "anthropic", "openai", "groq"])

    static func isCuratableProvider(_ providerId: String) -> Bool {
        curatableProviderIds.contains(providerId)
    }

    static func modelKey(for model: LLMModel) -> String {
        "\(model.provider)::\(model.id)"
    }

    static var hasStoredConfiguration: Bool {
        UserDefaults.standard.object(forKey: enabledModelKeysKey) != nil
    }

    static func enabledModelKeys(availableModels: [LLMModel]) -> Set<String> {
        if let stored = storedEnabledModelKeys() {
            return stored
        }
        return defaultEnabledModelKeys(availableModels: availableModels)
    }

    static func isEnabled(_ model: LLMModel, availableModels: [LLMModel]) -> Bool {
        enabledModelKeys(availableModels: availableModels).contains(modelKey(for: model))
    }

    static func setModel(_ model: LLMModel, enabled: Bool, availableModels: [LLMModel]) {
        var keys = enabledModelKeys(availableModels: availableModels)
        let key = modelKey(for: model)
        if enabled {
            keys.insert(key)
        } else {
            keys.remove(key)
        }
        UserDefaults.standard.set(Array(keys).sorted(), forKey: enabledModelKeysKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func resetToRecommended() {
        UserDefaults.standard.removeObject(forKey: enabledModelKeysKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func curatedModels(for providerId: String, from allModels: [LLMModel]) -> [LLMModel] {
        guard isCuratableProvider(providerId) else { return [] }
        let enabled = enabledModelKeys(availableModels: allModels)
        return sorted(
            allModels.filter { $0.provider == providerId && enabled.contains(modelKey(for: $0)) }
        )
    }

    static func curatedModels(from allModels: [LLMModel]) -> [LLMModel] {
        let enabled = enabledModelKeys(availableModels: allModels)
        return sorted(
            allModels.filter { isCuratableProvider($0.provider) && enabled.contains(modelKey(for: $0)) }
        )
    }

    static func sorted(_ models: [LLMModel]) -> [LLMModel] {
        models.sorted {
            if $0.provider != $1.provider {
                let preferred = LLMConfig.shared.preferredProviderOrder
                let lhs = preferred.firstIndex(of: $0.provider) ?? Int.max
                let rhs = preferred.firstIndex(of: $1.provider) ?? Int.max
                if lhs != rhs { return lhs < rhs }
                return $0.provider.localizedStandardCompare($1.provider) == .orderedAscending
            }
            return $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }

    private static func storedEnabledModelKeys() -> Set<String>? {
        guard UserDefaults.standard.object(forKey: enabledModelKeysKey) != nil else {
            return nil
        }
        return Set(UserDefaults.standard.stringArray(forKey: enabledModelKeysKey) ?? [])
    }

    private static func defaultEnabledModelKeys(availableModels: [LLMModel]) -> Set<String> {
        var keys = Set<String>()
        for providerId in orderedCuratableProviderIds() {
            let providerModels = availableModels.filter { $0.provider == providerId }
            guard !providerModels.isEmpty else { continue }

            let recommendedIds = LLMConfig.shared.recommendedModelIDs(for: providerId)
            let recommendedModels = providerModels.filter { recommendedIds.contains($0.id) }
            if recommendedModels.isEmpty {
                if let defaultModel = providerModels.first(where: { $0.id == LLMConfig.shared.defaultModel(for: providerId) })
                    ?? providerModels.first {
                    keys.insert(modelKey(for: defaultModel))
                }
            } else {
                keys.formUnion(recommendedModels.map { modelKey(for: $0) })
            }
        }
        return keys
    }

    private static func orderedCuratableProviderIds() -> [String] {
        var ids: [String] = []
        var seen = Set<String>()
        for providerId in LLMConfig.shared.preferredProviderOrder + Array(curatableProviderIds).sorted() {
            guard curatableProviderIds.contains(providerId), seen.insert(providerId).inserted else { continue }
            ids.append(providerId)
        }
        return ids
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
    var jsonMode: Bool = false

    static let `default` = GenerationOptions()
}

// MARK: - Provider Registry

@Observable
@MainActor
class LLMProviderRegistry {
    static let shared = LLMProviderRegistry()

    private(set) var providers: [LLMProvider] = []
    private(set) var allModels: [LLMModel] = []

    // Persisted across launches via UserDefaults so the user's last pick
    // sticks instead of falling back to first-available (Apple Local).
    private static let providerKey = "LLMRegistry.selectedProviderId"
    private static let modelKey = "LLMRegistry.selectedModelId"

    var selectedProviderId: String? {
        didSet { persistSelection() }
    }
    var selectedModelId: String? {
        didSet { persistSelection() }
    }

    private func persistSelection() {
        let defaults = UserDefaults.standard
        if let id = selectedProviderId {
            defaults.set(id, forKey: Self.providerKey)
        } else {
            defaults.removeObject(forKey: Self.providerKey)
        }
        if let id = selectedModelId {
            defaults.set(id, forKey: Self.modelKey)
        } else {
            defaults.removeObject(forKey: Self.modelKey)
        }
    }

    /// Get recommended models for a specific provider
    func recommendedModels(for providerId: String) -> [LLMModel] {
        let providerModels = allModels
            .filter { $0.provider == providerId }
            .sorted { $0.displayName < $1.displayName }

        let recommendedIDs = LLMConfig.shared.recommendedModelIDs(for: providerId)
        guard !recommendedIDs.isEmpty else {
            return providerModels
        }

        let recommendedModels = providerModels.filter { recommendedIDs.contains($0.id) }
        return recommendedModels.isEmpty ? providerModels : recommendedModels
    }

    private init() {
        // Restore the last picked provider/model before any UI binds.
        let defaults = UserDefaults.standard
        selectedProviderId = defaults.string(forKey: Self.providerKey)
        selectedModelId = defaults.string(forKey: Self.modelKey)

        // Register providers synchronously so they're available immediately
        registerProvidersSync()

        Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: LLMConfig.didRefreshNotification) {
                guard let self else { return }
                await self.refreshModels()
            }
        }

        // Refresh models asynchronously
        Task {
            await refreshModels()
        }
    }

    private func registerProvidersSync() {
        // On-device (free, private, zero-latency)
        providers.append(AppleLocalProvider())

        // Cloud providers
        providers.append(OpenAIProvider())
        providers.append(AnthropicProvider())
        providers.append(GeminiProvider())
        providers.append(GroqProvider())
        providers.append(ServerProvider())

    }

    private func registerProviders() async {
        if providers.isEmpty {
            registerProvidersSync()
        }
        await refreshModels()
    }

    func refreshModels(force: Bool = false) async {
        await LLMConfig.shared.refresh(force: force)

        var models: [LLMModel] = []

        for provider in providers {
            do {
                let providerModels = try await provider.models
                models.append(contentsOf: providerModels)
            } catch {
                log.debug("Failed to get models from \(provider.name): \(error.localizedDescription)")
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
        let preferredOrder = orderedProviderIds()

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
           await provider.isAvailable {
            if let model = selectedModel {
                return (provider, model.id)
            }
            let fallbackModelId = provider.defaultModelId
            if !fallbackModelId.isEmpty {
                return (provider, fallbackModelId)
            }
        }

        // Fall back to first available
        return await firstAvailableProvider()
    }

    private func orderedProviderIds() -> [String] {
        var ids: [String] = []
        var seen = Set<String>()

        for providerId in LLMConfig.shared.preferredProviderOrder + providers.map(\.id) {
            guard seen.insert(providerId).inserted else { continue }
            ids.append(providerId)
        }

        return ids
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
