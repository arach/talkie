//
//  OpenAIProvider.swift
//  Talkie
//
//  OpenAI API provider - fetches available models dynamically from API
//

import Foundation
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "OpenAI")

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
                logger.warning("Failed to fetch models from API: \(error.localizedDescription)")
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
        logger.info("Force refreshed \(fetched.count) models from OpenAI API")
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
            logger.info("Persisted \(models.count) models to UserDefaults")
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
        request.timeoutInterval = 10  // 10 second timeout for model list fetch

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.generationFailed("Failed to fetch models from OpenAI")
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

            // Skip dated snapshot versions (e.g., gpt-4-0613, gpt-4o-2024-05-13)
            // These clutter the list - prefer canonical names or "-latest" versions
            if isDateSnapshotModel(modelId) {
                continue
            }

            // Skip preview/deprecated variants
            let skipSuffixes = ["-preview", "-instruct", "-vision-preview"]
            if skipSuffixes.contains(where: { modelId.hasSuffix($0) }) {
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

        logger.info("Fetched \(sorted.count) chat models from OpenAI API")
        return sorted
    }

    /// Check if model ID contains a date snapshot (YYYY-MM-DD or YYYYMMDD or -MMDD)
    private func isDateSnapshotModel(_ modelId: String) -> Bool {
        // Match patterns like: -2024-05-13, -0613, -1106, -20240409
        let datePatterns = [
            #"-\d{4}-\d{2}-\d{2}"#,  // -YYYY-MM-DD
            #"-\d{8}"#,              // -YYYYMMDD
            #"-\d{4}$"#,             // -MMDD at end (e.g., -0613)
        ]

        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: modelId, range: NSRange(modelId.startIndex..., in: modelId)) != nil {
                return true
            }
        }
        return false
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
    
    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        guard let apiKey = SettingsManager.shared.openaiApiKey,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.configurationError("OpenAI API key not configured")
        }
        
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
                    logger.error("OpenAI streaming failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
