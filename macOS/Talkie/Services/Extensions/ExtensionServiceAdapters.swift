//
//  ExtensionServiceAdapters.swift
//  Talkie
//
//  Adapters that bridge Talkie's internal services to the Extension Server protocols.
//

import Foundation
import TalkieKit

// MARK: - Transcription Adapter

/// Adapts EphemeralTranscriber to TranscriptionServiceProtocol
@MainActor
final class EphemeralTranscriberAdapter: TranscriptionServiceProtocol {
    static let shared = EphemeralTranscriberAdapter()

    private init() {}

    func startCapture() async throws {
        try EphemeralTranscriber.shared.startCapture()
    }

    func stopAndTranscribe() async throws -> String {
        try await EphemeralTranscriber.shared.stopAndTranscribe()
    }
}

// MARK: - LLM Adapter

/// Adapts LLMProviderRegistry to LLMServiceProtocol
@MainActor
final class LLMProviderAdapter: LLMServiceProtocol {
    static let shared = LLMProviderAdapter()

    private init() {}

    func complete(
        messages: [LLMMessage],
        provider: String?,
        model: String?,
        stream: Bool
    ) async throws -> LLMServiceResult {
        // Resolve provider and model
        let resolved = try await resolveProviderAndModel(provider: provider, model: model)

        // Build prompt from messages
        let prompt = buildPrompt(from: messages)
        let systemPrompt = messages.first { $0.role == "system" }?.content

        var options = GenerationOptions.default
        options.systemPrompt = systemPrompt

        // Make completion request
        let response = try await resolved.provider.generate(
            prompt: prompt,
            model: resolved.modelId,
            options: options
        )

        return LLMServiceResult(
            content: response,
            provider: resolved.provider.name,
            model: resolved.modelId
        )
    }

    func revise(
        content: String,
        instruction: String,
        constraints: LLMConstraints?,
        provider: String?,
        model: String?
    ) async throws -> LLMServiceResult {
        // Resolve provider and model
        let resolved = try await resolveProviderAndModel(provider: provider, model: model)

        // Build system prompt with constraints
        var systemPrompt = """
        You are a writing assistant. Revise the user's text according to their instruction.
        Return ONLY the revised text, no explanations or commentary.
        """

        if let constraints = constraints {
            if let maxLength = constraints.maxLength {
                systemPrompt += "\nKeep the response under \(maxLength) characters."
            }
            if let style = constraints.style {
                systemPrompt += "\nWrite in a \(style) style."
            }
            if let format = constraints.format {
                systemPrompt += "\nFormat: \(format)"
            }
        }

        // Build the prompt
        let prompt = "Text to revise:\n\(content)\n\nInstruction: \(instruction)"

        var options = GenerationOptions.default
        options.systemPrompt = systemPrompt
        if let maxTokens = constraints?.maxTokens {
            options.maxTokens = maxTokens
        }

        // Make completion request
        let response = try await resolved.provider.generate(
            prompt: prompt,
            model: resolved.modelId,
            options: options
        )

        return LLMServiceResult(
            content: response,
            provider: resolved.provider.name,
            model: resolved.modelId
        )
    }

    // MARK: - Private

    private func buildPrompt(from messages: [LLMMessage]) -> String {
        // Filter out system messages (handled separately) and build conversation
        return messages
            .filter { $0.role != "system" }
            .map { msg in
                switch msg.role {
                case "user": return "User: \(msg.content)"
                case "assistant": return "Assistant: \(msg.content)"
                default: return msg.content
                }
            }
            .joined(separator: "\n\n")
    }

    private func resolveProviderAndModel(
        provider: String?,
        model: String?
    ) async throws -> (provider: any LLMProvider, modelId: String) {
        let registry = LLMProviderRegistry.shared

        // If both provided, use them directly
        if let providerId = provider, let modelId = model {
            guard let provider = registry.provider(for: providerId) else {
                throw LLMAdapterError.providerNotFound(providerId)
            }
            return (provider, modelId)
        }

        // Otherwise use default resolution
        guard let resolved = await registry.resolveProviderAndModel() else {
            throw LLMAdapterError.noProviderConfigured
        }

        return (resolved.provider, resolved.modelId)
    }
}

enum LLMAdapterError: LocalizedError {
    case providerNotFound(String)
    case noProviderConfigured

    var errorDescription: String? {
        switch self {
        case .providerNotFound(let id):
            return "LLM provider not found: \(id)"
        case .noProviderConfigured:
            return "No LLM provider configured"
        }
    }
}
