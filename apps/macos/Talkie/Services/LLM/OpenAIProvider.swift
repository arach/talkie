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

    // Gateway URL for GPT-5.x models
    private let gatewayURL = "http://localhost:8765/inference"

    // Gateway auth token file path
    private var gatewayTokenPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Talkie/Bridge/.config/.local-auth-token"
    }

    // Persistence keys
    private let modelsKey = "OpenAI_CachedModels"
    private let lastFetchKey = "OpenAI_LastFetchTime"

    // Cache timeout: 6 months
    private let cacheTimeout: TimeInterval = 180 * 24 * 3600

    /// Check if model should be routed through TalkieServer gateway
    /// Currently disabled - all models use direct API calls (batteries included)
    /// Gateway routing is for developer/advanced mode only
    private func shouldUseGateway(model: String) -> Bool {
        // GPT-5.x and all blessed models go direct - no dev environment required
        // Gateway is opt-in for developers who want advanced features
        return false
    }

    /// Check if model is a reasoning model (o-series, GPT-5.x)
    /// These models don't support temperature, top_p, and use different param names
    private func isReasoningModel(_ model: String) -> Bool {
        return model.hasPrefix("o1") ||
               model.hasPrefix("o3") ||
               model.hasPrefix("o4") ||
               model.hasPrefix("gpt-5")
    }

    /// Read the gateway auth token from file
    private func readGatewayToken() -> String? {
        let path = self.gatewayTokenPath
        guard let token = try? String(contentsOfFile: path, encoding: .utf8) else {
            log.warning("Could not read gateway auth token from \(path)")
            return nil
        }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var models: [LLMModel] {
        get async throws {
            let configuredModels = LLMConfig.shared.models(for: id).map { $0.llmModel(for: id) }
            let apiKey = sharedAPIKey

            guard !apiKey.isEmpty else {
                return configuredModels
            }

            // Return persisted models if still valid
            if let cached = loadPersistedModels(),
               let fetchTime = UserDefaults.standard.object(forKey: lastFetchKey) as? Date,
               Date().timeIntervalSince(fetchTime) < cacheTimeout {
                return mergedModels(primary: cached, configured: configuredModels)
            }

            // Try to fetch from API
            do {
                let fetched = try await fetchModelsFromAPI()
                persistModels(fetched)
                return mergedModels(primary: fetched, configured: configuredModels)
            } catch {
                log.warning("Failed to fetch models from API: \(error.localizedDescription)")
                // Return persisted models if available
                if let cached = loadPersistedModels() {
                    return mergedModels(primary: cached, configured: configuredModels)
                }
                if !configuredModels.isEmpty {
                    return configuredModels
                }
                throw error
            }
        }
    }

    /// Force refresh models from API (call when user adds/updates API key)
    func refreshModels() async throws -> [LLMModel] {
        let apiKey = sharedAPIKey
        guard !apiKey.isEmpty else {
            return LLMConfig.shared.models(for: id).map { $0.llmModel(for: id) }
        }

        let fetched = try await fetchModelsFromAPI()
        persistModels(fetched)
        log.info("Force refreshed \(fetched.count) models from OpenAI API")
        return mergedModels(primary: fetched, configured: LLMConfig.shared.models(for: id).map { $0.llmModel(for: id) })
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

    private func mergedModels(primary: [LLMModel], configured: [LLMModel]) -> [LLMModel] {
        var seen = Set<String>()
        var merged: [LLMModel] = []

        for model in configured + primary {
            if seen.insert(model.id).inserted {
                merged.append(model)
            }
        }

        return merged
    }

    /// Fetch models dynamically from OpenAI API
    private func fetchModelsFromAPI() async throws -> [LLMModel] {
        let apiKey = sharedAPIKey
        guard !apiKey.isEmpty else {
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

        log.info("Fetched \(sorted.count) chat models from OpenAI API")
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
            !sharedAPIKey.isEmpty
        }
    }
    
    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        // Route GPT-5.x models through TalkieServer gateway
        if shouldUseGateway(model: model) {
            return try await generateViaGateway(prompt: prompt, model: model, options: options)
        }

        // Direct OpenAI API for other models
        let apiKey = sharedAPIKey
        guard !apiKey.isEmpty else {
            throw LLMError.configurationError("OpenAI API key not configured")
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build messages array with optional system prompt
        // Reasoning models (o-series, GPT-5.x) use "developer" role instead of "system"
        var messages: [[String: String]] = []
        if let systemPrompt = options.systemPrompt {
            let role = isReasoningModel(model) ? "developer" : "system"
            messages.append(["role": role, "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        // Build request body - reasoning models don't support temperature/top_p
        var body: [String: Any] = [
            "model": model,
            "messages": messages
        ]

        if isReasoningModel(model) {
            // Reasoning models use max_completion_tokens instead of max_tokens
            body["max_completion_tokens"] = options.maxTokens
        } else {
            // Standard models support full parameter set
            body["temperature"] = options.temperature
            body["max_tokens"] = options.maxTokens
            body["top_p"] = options.topP
        }
        if options.jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("OpenAI API request failed: no HTTP response")
        }

        // Handle error responses with detailed information
        if !(200...299).contains(httpResponse.statusCode) {
            var errorMessage = "OpenAI API error (HTTP \(httpResponse.statusCode))"

            // Try to parse OpenAI's error response
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any] {
                if let message = error["message"] as? String {
                    errorMessage = "OpenAI: \(message)"
                }
                if let type = error["type"] as? String {
                    errorMessage += " [\(type)]"
                }
                if let code = error["code"] as? String {
                    errorMessage += " (code: \(code))"
                }
            }

            log.error("OpenAI API failed: \(errorMessage)")
            throw LLMError.generationFailed(errorMessage)
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

    /// Generate via TalkieServer gateway (for GPT-5.x models)
    private func generateViaGateway(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        guard let url = URL(string: gatewayURL) else {
            throw LLMError.configurationError("Invalid gateway URL")
        }

        // Read auth token from file
        guard let authToken = readGatewayToken() else {
            throw LLMError.configurationError("Gateway auth token not found. Is TalkieServer running?")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120  // Longer timeout for reasoning models

        // Build messages array for gateway format
        var messages: [[String: String]] = []
        if let systemPrompt = options.systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        var body: [String: Any] = [
            "provider": "openai",
            "model": model,
            "messages": messages,
            "temperature": options.temperature,
            "maxTokens": options.maxTokens
        ]
        if options.jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        log.info("Gateway request: \(model)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Invalid gateway response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            log.error("Gateway error (\(httpResponse.statusCode)): \(errorText)")
            if httpResponse.statusCode == 401 {
                throw LLMError.configurationError("Gateway authentication failed. Restart TalkieServer.")
            }
            throw LLMError.generationFailed("Gateway request failed: \(httpResponse.statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? String else {
            throw LLMError.generationFailed("Failed to parse gateway response")
        }

        log.info("Gateway response received for \(model)")
        return content
    }
    
    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        // GPT-5.x models: gateway doesn't support streaming, fall back to non-streaming
        if shouldUseGateway(model: model) {
            return AsyncThrowingStream { continuation in
                Task {
                    do {
                        let result = try await self.generateViaGateway(prompt: prompt, model: model, options: options)
                        continuation.yield(result)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }

        // Direct OpenAI API with streaming for other models
        let apiKey = sharedAPIKey
        guard !apiKey.isEmpty else {
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
                    // Reasoning models (o-series, GPT-5.x) use "developer" role instead of "system"
                    let isReasoning = model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4") || model.hasPrefix("gpt-5")
                    var messages: [[String: String]] = []
                    if let systemPrompt = options.systemPrompt {
                        let role = isReasoning ? "developer" : "system"
                        messages.append(["role": role, "content": systemPrompt])
                    }
                    messages.append(["role": "user", "content": prompt])

                    // Build request body - reasoning models don't support temperature/top_p
                    var body: [String: Any] = [
                        "model": model,
                        "messages": messages,
                        "stream": true
                    ]

                    if isReasoning {
                        body["max_completion_tokens"] = options.maxTokens
                    } else {
                        body["temperature"] = options.temperature
                        body["max_tokens"] = options.maxTokens
                    }
                    if options.jsonMode {
                        body["response_format"] = ["type": "json_object"]
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
                    log.error("OpenAI streaming failed: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
