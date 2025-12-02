//
//  OpenAIProvider.swift
//  Talkie
//
//  OpenAI API provider (GPT-4, GPT-3.5-turbo)
//

import Foundation

class OpenAIProvider: LLMProvider {
    let id = "openai"
    let name = "OpenAI"

    var models: [LLMModel] {
        get async throws {
            return [
                LLMModel(
                    id: "gpt-4o",
                    name: "gpt-4o",
                    displayName: "GPT-4o (Latest)",
                    size: "Cloud",
                    type: .cloud,
                    provider: "openai",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "gpt-4o-mini",
                    name: "gpt-4o-mini",
                    displayName: "GPT-4o Mini",
                    size: "Cloud",
                    type: .cloud,
                    provider: "openai",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "gpt-4-turbo",
                    name: "gpt-4-turbo",
                    displayName: "GPT-4 Turbo",
                    size: "Cloud",
                    type: .cloud,
                    provider: "openai",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "gpt-3.5-turbo",
                    name: "gpt-3.5-turbo",
                    displayName: "GPT-3.5 Turbo",
                    size: "Cloud",
                    type: .cloud,
                    provider: "openai",
                    downloadURL: nil,
                    isInstalled: true
                )
            ]
        }
    }
    
    var isAvailable: Bool {
        get async {
            return SettingsManager.shared.openaiApiKey != nil
        }
    }
    
    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        guard let apiKey = SettingsManager.shared.openaiApiKey else {
            throw LLMError.configurationError("OpenAI API key not configured")
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": options.temperature,
            "max_tokens": options.maxTokens,
            "top_p": options.topP
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.generationFailed("OpenAI API request failed")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.generationFailed("Failed to parse OpenAI response")
        }
        
        return content
    }
    
    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let apiKey = SettingsManager.shared.openaiApiKey else {
            throw LLMError.configurationError("OpenAI API key not configured")
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let url = URL(string: "https://api.openai.com/v1/chat/completions")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    
                    let body: [String: Any] = [
                        "model": model,
                        "messages": [["role": "user", "content": prompt]],
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
