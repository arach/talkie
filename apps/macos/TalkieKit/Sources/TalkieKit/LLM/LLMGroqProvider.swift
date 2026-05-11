//
//  LLMGroqProvider.swift
//  TalkieKit
//
//  Groq fast inference API provider for LLM generation
//

import Foundation

public final class LLMGroqProvider: LLMProvider, @unchecked Sendable {
    public let id = "groq"
    public let name = "Groq"

    public init() {}

    public var models: [LLMModel] {
        get async throws {
            [
                LLMModel(
                    id: "llama-3.3-70b-versatile",
                    name: "llama-3.3-70b-versatile",
                    displayName: "Llama 3.3 70B",
                    size: "Cloud",
                    type: .cloud,
                    provider: "groq"
                ),
                LLMModel(
                    id: "llama-3.1-8b-instant",
                    name: "llama-3.1-8b-instant",
                    displayName: "Llama 3.1 8B (Instant)",
                    size: "Cloud",
                    type: .cloud,
                    provider: "groq"
                ),
                LLMModel(
                    id: "mixtral-8x7b-32768",
                    name: "mixtral-8x7b-32768",
                    displayName: "Mixtral 8x7B",
                    size: "Cloud",
                    type: .cloud,
                    provider: "groq"
                ),
                LLMModel(
                    id: "gemma2-9b-it",
                    name: "gemma2-9b-it",
                    displayName: "Gemma 2 9B",
                    size: "Cloud",
                    type: .cloud,
                    provider: "groq"
                )
            ]
        }
    }

    public var isAvailable: Bool {
        get async {
            LLMAPIKeyStore.shared.get(.groq) != nil
        }
    }

    public func generate(
        prompt: String,
        model: String,
        options: LLMGenerationOptions
    ) async throws -> String {
        guard let apiKey = LLMAPIKeyStore.shared.get(.groq) else {
            throw LLMError.configurationError("Groq API key not configured")
        }

        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build messages array (OpenAI-compatible)
        var messages: [[String: String]] = []
        if let systemPrompt = options.systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": options.temperature,
            "max_tokens": options.maxTokens,
            "top_p": options.topP
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.generationFailed("Groq API request failed")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.generationFailed("Failed to parse Groq response")
        }

        return content
    }

    public func streamGenerate(
        prompt: String,
        model: String,
        options: LLMGenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let apiKey = LLMAPIKeyStore.shared.get(.groq) else {
            throw LLMError.configurationError("Groq API key not configured")
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                    var messages: [[String: String]] = []
                    if let systemPrompt = options.systemPrompt {
                        messages.append(["role": "system", "content": systemPrompt])
                    }
                    messages.append(["role": "user", "content": prompt])

                    let body: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "temperature": options.temperature,
                        "max_tokens": options.maxTokens,
                        "stream": true
                    ]

                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, _) = try await URLSession.shared.bytes(for: request)

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: "), line != "data: [DONE]" {
                            let jsonString = String(line.dropFirst(6))
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
