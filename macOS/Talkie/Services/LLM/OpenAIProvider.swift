//
//  OpenAIProvider.swift
//  Talkie
//
//  OpenAI API provider - fetches available models dynamically from API
//

import Foundation
import TalkieKit

private let log = Log(.system)

class OpenAIProvider: LLMProvider {
    let id = "openai"
    let name = "OpenAI"

    // Persistence keys
    private let modelsKey = "OpenAI_CachedModels"
    private let lastFetchKey = "OpenAI_LastFetchTime"

    // Cache timeout: 6 months
    private let cacheTimeout: TimeInterval = 180 * 24 * 3600

    var models: [LLMModel] {
        get async throws {
            // Return persisted models if still valid
            if let cached = loadPersistedModels(),
               let fetchTime = UserDefaults.standard.object(forKey: lastFetchKey) as? Date,
               Date().timeIntervalSince(fetchTime) < cacheTimeout {
                return cached
            }

            // Try to fetch from API
            do {
                let fetched = try await fetchModelsFromAPI()
                persistModels(fetched)
                return fetched
            } catch {
                log.warning("Failed to fetch models from API: \(error.localizedDescription)")
                // Return persisted models if available
                if let cached = loadPersistedModels() {
                    return cached
                }
                throw error
            }
        }
    }

    /// Force refresh models from API (call when user adds/updates API key)
    func refreshModels() async throws -> [LLMModel] {
        let fetched = try await fetchModelsFromAPI()
        persistModels(fetched)
        log.info("Force refreshed \(fetched.count) models from OpenAI API")
        return fetched
    }

    private func loadPersistedModels() -> [LLMModel]? {
        guard let data = UserDefaults.standard.data(forKey: modelsKey),
              let models = try? JSONDecoder().decode([LLMModel].self, from: data) else {
            return nil
        }
        return models
    }

    private func persistModels(_ models: [LLMModel]) {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: modelsKey)
            UserDefaults.standard.set(Date(), forKey: lastFetchKey)
            log.info("Persisted \(models.count) models to UserDefaults")
        }
    }

    /// Fetch models dynamically from OpenAI API
    private func fetchModelsFromAPI() async throws -> [LLMModel] {
        guard let apiKey = SettingsManager.shared.openaiApiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.configurationError("OpenAI API key not configured")
        }

        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Invalid response from OpenAI")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to extract error message from response
            let errorMessage = extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            log.error("OpenAI API error: \(errorMessage)")
            throw LLMError.generationFailed("OpenAI: \(errorMessage)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsData = json["data"] as? [[String: Any]] else {
            throw LLMError.generationFailed("Invalid models response")
        }

        // Filter for chat-capable models with created timestamp for sorting
        var chatModels: [(model: LLMModel, created: Int)] = []

        for modelData in modelsData {
            guard let modelId = modelData["id"] as? String else { continue }

            // Only include models that support chat completions
            let excludePrefixes = ["text-embedding", "whisper", "tts", "dall-e", "davinci", "babbage", "curie", "ada", "text-moderation", "omni-moderation"]
            if excludePrefixes.contains(where: { modelId.hasPrefix($0) }) {
                continue
            }

            // Focus on GPT and o-series models
            let validPrefixes = ["gpt-", "o1", "o3", "o4", "chatgpt"]
            guard validPrefixes.contains(where: { modelId.hasPrefix($0) }) else {
                continue
            }

            let created = modelData["created"] as? Int ?? 0

            let model = LLMModel(
                id: modelId,
                name: modelId,
                displayName: formatDisplayName(modelId),
                size: "Cloud",
                type: .cloud,
                provider: "openai",
                downloadURL: nil,
                isInstalled: true
            )
            chatModels.append((model, created))
        }

        // Sort by created date (newest first)
        let sorted = chatModels
            .sorted { $0.created > $1.created }
            .map { $0.model }

        log.info("Fetched \(sorted.count) chat models from OpenAI API")
        return sorted
    }

    /// Format model ID into readable display name
    private func formatDisplayName(_ modelId: String) -> String {
        var name = modelId

        // Handle gpt- prefix
        if modelId.hasPrefix("gpt-") {
            name = "GPT-" + modelId.dropFirst(4)
        }

        // Handle chatgpt prefix
        if modelId.hasPrefix("chatgpt") {
            name = "ChatGPT" + modelId.dropFirst(7)
        }

        // Capitalize o-series
        if modelId.hasPrefix("o1") || modelId.hasPrefix("o3") || modelId.hasPrefix("o4") {
            name = modelId
        }

        return name
    }

    var isAvailable: Bool {
        get async {
            guard let key = SettingsManager.shared.openaiApiKey else { return false }
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Test the API key by making a simple models request
    func testConnection() async -> (success: Bool, message: String) {
        guard let apiKey = SettingsManager.shared.openaiApiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (false, "No API key configured")
        }

        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return (false, "Invalid response")
            }

            if (200...299).contains(httpResponse.statusCode) {
                return (true, "Connected successfully")
            } else {
                let errorMessage = extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
                return (false, errorMessage)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// Extract error message from OpenAI API error response
    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }

        if let message = error["message"] as? String {
            return message
        }

        if let type = error["type"] as? String {
            return type
        }

        return nil
    }
    
    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        log.info("🔵 OpenAI generate called with model: \(model)")

        guard let apiKey = SettingsManager.shared.openaiApiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            log.error("❌ OpenAI API key not configured")
            throw LLMError.configurationError("OpenAI API key not configured")
        }

        let maskedKey = String(apiKey.prefix(8)) + "..." + String(apiKey.suffix(4))
        log.info("🔑 Using API key: \(maskedKey)")

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build messages array with optional system prompt
        var messages: [[String: String]] = []
        if let systemPrompt = options.systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        // GPT-5.x and o-series have different parameter requirements
        let isNewModel = model.hasPrefix("gpt-5") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4")

        var body: [String: Any] = [
            "model": model,
            "messages": messages
        ]

        // GPT-5.x doesn't support temperature/top_p, older models do
        if !isNewModel {
            body["temperature"] = options.temperature
            body["top_p"] = options.topP
            body["max_tokens"] = options.maxTokens
        } else {
            body["max_completion_tokens"] = options.maxTokens
        }

        log.info("📤 Request body: model=\(model), messages=\(messages.count), temp=\(options.temperature)")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            log.error("❌ Invalid response type from OpenAI")
            throw LLMError.generationFailed("Invalid response from OpenAI")
        }

        log.info("📥 Response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "unable to decode"
            log.error("❌ OpenAI error response: \(responseBody)")
            let errorMessage = extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw LLMError.generationFailed("OpenAI: \(errorMessage)")
        }

        log.info("✅ OpenAI request successful")

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
        guard let apiKey = SettingsManager.shared.openaiApiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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
                    
                    // Build messages array with optional system prompt
                    var messages: [[String: String]] = []
                    if let systemPrompt = options.systemPrompt {
                        messages.append(["role": "system", "content": systemPrompt])
                    }
                    messages.append(["role": "user", "content": prompt])

                    // GPT-5.x and o-series have different parameter requirements
                    let isNewModel = model.hasPrefix("gpt-5") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4")

                    var body: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "stream": true
                    ]

                    if !isNewModel {
                        body["temperature"] = options.temperature
                        body["max_tokens"] = options.maxTokens
                    } else {
                        body["max_completion_tokens"] = options.maxTokens
                    }
                    
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
