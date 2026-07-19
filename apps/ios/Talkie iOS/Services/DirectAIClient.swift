//
//  DirectAIClient.swift
//  Talkie iOS
//
//  One shared HTTP layer for direct (phone-owned-key) AI completions. Compose
//  revisions and Ask-AI commands both build their own (system, user) prompts
//  and hand them here; this file owns the per-provider request/response shapes
//  so OpenAI / Groq / OpenRouter (OpenAI-compatible) and Anthropic (Messages
//  API) all run through a single, catalog-driven path.
//

import Foundation

actor DirectAIClient {
    static let shared = DirectAIClient()
    private init() {}

    private let defaultMaxTokens = 2048
    private let defaultTemperature = 0.3
    private let timeout: TimeInterval = 60

    /// Run a single completion against the provider's direct API.
    /// - Parameters:
    ///   - provider: resolved credentials (providerId, modelId, apiKey).
    ///   - systemPrompt: the assistant/system instruction.
    ///   - userPrompt: the user turn.
    /// - Returns: the model's text reply, trimmed.
    func complete(
        provider: ComposeBorrowedProvider,
        systemPrompt: String,
        userPrompt: String
    ) async throws -> String {
        try await complete(
            provider: provider,
            messages: [
                InferenceMessage(role: .system, content: systemPrompt),
                InferenceMessage(role: .user, content: userPrompt),
            ]
        )
    }

    /// Run a structured multi-turn conversation. Ask AI uses this overload so
    /// providers receive actual user/assistant roles instead of a transcript
    /// flattened into a synthetic "captured text" prompt.
    func complete(
        provider: ComposeBorrowedProvider,
        messages: [InferenceMessage]
    ) async throws -> String {
        guard let entry = AIProviderCatalog.provider(provider.providerId) else {
            throw DirectAIError.unsupportedProvider(provider.providerName)
        }

        switch entry.apiStyle {
        case .openAICompatible:
            return try await completeOpenAICompatible(
                entry: entry,
                provider: provider,
                messages: messages
            )
        case .anthropic:
            return try await completeAnthropic(
                entry: entry,
                provider: provider,
                messages: messages
            )
        }
    }

    // MARK: - OpenAI-compatible (OpenAI · Groq · OpenRouter)

    private func completeOpenAICompatible(
        entry: AIProviderCatalog.Provider,
        provider: ComposeBorrowedProvider,
        messages: [InferenceMessage]
    ) async throws -> String {
        // OpenAI's reasoning models (o1/o3/o4/gpt-5) take a `developer` role and
        // reject `temperature` / `max_tokens` (they want `max_completion_tokens`).
        // Only OpenAI's own API enforces this; Groq/OpenRouter take the classic
        // params, so scope the special-casing to the OpenAI provider.
        let isOpenAIReasoning = entry.id == "openai" && Self.isReasoningModel(provider.modelId)

        let chatMessages = messages.compactMap { message -> ChatMessage? in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }

            let role = if isOpenAIReasoning && message.role == .system {
                "developer"
            } else {
                message.role.rawValue
            }
            return ChatMessage(role: role, content: content)
        }

        let body = OpenAIChatRequest(
            model: provider.modelId,
            messages: chatMessages,
            temperature: isOpenAIReasoning ? nil : defaultTemperature,
            maxTokens: isOpenAIReasoning ? nil : defaultMaxTokens,
            maxCompletionTokens: isOpenAIReasoning ? defaultMaxTokens : nil,
            stream: false
        )

        var headers = entry.extraHeaders
        headers["Authorization"] = "Bearer \(provider.apiKey)"

        let response: OpenAIChatResponse = try await send(url: entry.chatURL, headers: headers, body: body)
        guard let content = response.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty
        else {
            throw DirectAIError.emptyResponse(provider.providerName)
        }
        return content
    }

    // MARK: - Anthropic (Messages API)

    private func completeAnthropic(
        entry: AIProviderCatalog.Provider,
        provider: ComposeBorrowedProvider,
        messages: [InferenceMessage]
    ) async throws -> String {
        let systemPrompt = messages
            .filter { $0.role == .system }
            .map(\.content)
            .joined(separator: "\n\n")
        let conversation = messages.compactMap { message -> AnthropicMessage? in
            guard message.role != .system else { return nil }
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return AnthropicMessage(role: message.role.rawValue, content: content)
        }

        let body = AnthropicMessagesRequest(
            model: provider.modelId,
            maxTokens: defaultMaxTokens,
            system: systemPrompt,
            messages: conversation
        )

        var headers = entry.extraHeaders
        headers["x-api-key"] = provider.apiKey
        headers["anthropic-version"] = AIProviderCatalog.anthropicVersion

        let response: AnthropicMessagesResponse = try await send(url: entry.chatURL, headers: headers, body: body)
        let content = response.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw DirectAIError.emptyResponse(provider.providerName)
        }
        return content
    }

    // MARK: - HTTP

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        url: URL,
        headers: [String: String],
        body: RequestBody
    ) async throws -> ResponseBody {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DirectAIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DirectAIError.apiError(statusCode: http.statusCode, message: Self.parseErrorMessage(from: data))
        }
        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw DirectAIError.invalidResponse
        }
    }

    static func isReasoningModel(_ model: String) -> Bool {
        model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4") || model.hasPrefix("gpt-5")
    }

    static func parseErrorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           let message = envelope.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }
        if let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            return string
        }
        return "Unknown API error"
    }
}

// MARK: - Errors

enum DirectAIError: LocalizedError {
    case unsupportedProvider(String)
    case invalidResponse
    case emptyResponse(String)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider(let name): return "\(name) is not supported for direct iPhone use."
        case .invalidResponse: return "Received an invalid response."
        case .emptyResponse(let name): return "\(name) returned no text."
        case .apiError(let statusCode, let message): return "API error (\(statusCode)): \(message)"
        }
    }
}

// MARK: - Wire shapes

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let maxTokens: Int?
    let maxCompletionTokens: Int?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

private struct AnthropicMessage: Encodable {
    let role: String
    let content: String
}

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [AnthropicMessage]

    enum CodingKeys: String, CodingKey {
        case model, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicMessagesResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }
    let content: [Block]
}

private struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable { let message: String? }
    let error: Payload?
}
