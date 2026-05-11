//
//  AnthropicProvider.swift
//  Talkie
//
//  Anthropic Claude API provider
//

import Foundation

class AnthropicProvider: LLMProvider {
    let id = "anthropic"
    let name = "Anthropic"

    var models: [LLMModel] {
        get async throws {
            let configuredModels = LLMConfig.shared.models(for: id).map { $0.llmModel(for: id) }
            if !configuredModels.isEmpty {
                return configuredModels
            }

            return [
                LLMModel(
                    id: "claude-sonnet-4-6",
                    name: "claude-sonnet-4-6",
                    displayName: "Claude Sonnet 4.6",
                    size: "Cloud",
                    type: .cloud,
                    provider: "anthropic",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "claude-opus-4-6",
                    name: "claude-opus-4-6",
                    displayName: "Claude Opus 4.6",
                    size: "Cloud",
                    type: .cloud,
                    provider: "anthropic",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "claude-haiku-4-5-20251001",
                    name: "claude-haiku-4-5-20251001",
                    displayName: "Claude Haiku 4.5",
                    size: "Cloud",
                    type: .cloud,
                    provider: "anthropic",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "claude-sonnet-4-5-20250929",
                    name: "claude-sonnet-4-5-20250929",
                    displayName: "Claude Sonnet 4.5",
                    size: "Cloud",
                    type: .cloud,
                    provider: "anthropic",
                    downloadURL: nil,
                    isInstalled: true
                )
            ]
        }
    }
    
    var isAvailable: Bool {
        get async {
            !sharedAPIKey.isEmpty
        }
    }

    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        let apiKey = sharedAPIKey
        guard !apiKey.isEmpty else {
            throw LLMError.configurationError("Anthropic API key not configured")
        }
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Anthropic uses "system" as top-level field, not in messages array
        var body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": options.temperature,
            "max_tokens": options.maxTokens,
            "top_p": options.topP
        ]
        if let systemPrompt = options.systemPrompt {
            body["system"] = systemPrompt
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.generationFailed("Anthropic API request failed")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw LLMError.generationFailed("Failed to parse Anthropic response")
        }
        
        return text
    }
    
    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        let apiKey = sharedAPIKey
        guard !apiKey.isEmpty else {
            throw LLMError.configurationError("Anthropic API key not configured")
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.anthropic.com/v1/messages")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    
                    // Anthropic uses "system" as top-level field
                    var body: [String: Any] = [
                        "model": model,
                        "messages": [["role": "user", "content": prompt]],
                        "temperature": options.temperature,
                        "max_tokens": options.maxTokens,
                        "stream": true
                    ]
                    if let systemPrompt = options.systemPrompt {
                        body["system"] = systemPrompt
                    }
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            if let data = jsonString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
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
