//
//  GroqProvider.swift
//  Talkie
//
//  Groq fast inference API provider
//

import Foundation

class GroqProvider: LLMProvider {
    let id = "groq"
    let name = "Groq"

    var models: [LLMModel] {
        get async throws {
            return [
                LLMModel(
                    id: "llama-3.3-70b-versatile",
                    name: "llama-3.3-70b-versatile",
                    displayName: "Llama 3.3 70B",
                    size: "Cloud",
                    type: .cloud,
                    provider: "groq",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "llama-3.1-8b-instant",
                    name: "llama-3.1-8b-instant",
                    displayName: "Llama 3.1 8B (Instant)",
                    size: "Cloud",
                    type: .cloud,
                    provider: "groq",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "mixtral-8x7b-32768",
                    name: "mixtral-8x7b-32768",
                    displayName: "Mixtral 8x7B",
                    size: "Cloud",
                    type: .cloud,
                    provider: "groq",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "gemma2-9b-it",
                    name: "gemma2-9b-it",
                    displayName: "Gemma 2 9B",
                    size: "Cloud",
                    type: .cloud,
                    provider: "groq",
                    downloadURL: nil,
                    isInstalled: true
                )
            ]
        }
    }
    
    var isAvailable: Bool {
        get async {
            guard let key = SettingsManager.shared.groqApiKey else { return false }
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        guard let apiKey = SettingsManager.shared.groqApiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.configurationError("Groq API key not configured")
        }
        
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build messages array with optional system prompt (OpenAI-compatible)
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
    
    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let apiKey = SettingsManager.shared.groqApiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
                    
                    // Build messages array with optional system prompt (OpenAI-compatible)
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
