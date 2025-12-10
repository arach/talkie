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
            return [
                LLMModel(
                    id: "claude-3-5-sonnet-20241022",
                    name: "claude-3-5-sonnet-20241022",
                    displayName: "Claude 3.5 Sonnet (Latest)",
                    size: "Cloud",
                    type: .cloud,
                    provider: "anthropic",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "claude-3-5-haiku-20241022",
                    name: "claude-3-5-haiku-20241022",
                    displayName: "Claude 3.5 Haiku",
                    size: "Cloud",
                    type: .cloud,
                    provider: "anthropic",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "claude-3-opus-20240229",
                    name: "claude-3-opus-20240229",
                    displayName: "Claude 3 Opus",
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
            guard let key = SettingsManager.shared.anthropicApiKey else { return false }
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        guard let apiKey = SettingsManager.shared.anthropicApiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
        guard let apiKey = SettingsManager.shared.anthropicApiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
