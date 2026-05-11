//
//  LLMOpenAIProvider.swift
//  TalkieKit
//
//  OpenAI API provider for LLM generation
//

import Foundation
import os

private let logger = Logger(subsystem: "jdi.talkiekit", category: "OpenAI")

public final class LLMOpenAIProvider: LLMProvider, @unchecked Sendable {
    public let id = "openai"
    public let name = "OpenAI"

    // Cache
    private let modelsKey = "TalkieKit_OpenAI_CachedModels"
    private let lastFetchKey = "TalkieKit_OpenAI_LastFetchTime"
    private let cacheTimeout: TimeInterval = 180 * 24 * 3600 // 6 months

    public init() {}

    /// Check if model is a reasoning model (o-series, GPT-5.x)
    private func isReasoningModel(_ model: String) -> Bool {
        model.hasPrefix("o1") ||
        model.hasPrefix("o3") ||
        model.hasPrefix("o4") ||
        model.hasPrefix("gpt-5")
    }

    public var models: [LLMModel] {
        get async throws {
            // Return cached if valid
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
                if let cached = loadPersistedModels() {
                    return cached
                }
                // Return static list as fallback
                return Self.staticModels
            }
        }
    }

    private static let staticModels: [LLMModel] = [
        // GPT-5 family
        LLMModel(id: "gpt-5.2", name: "gpt-5.2", displayName: "GPT-5.2 Thinking", size: "Cloud", type: .cloud, provider: "openai"),
        LLMModel(id: "gpt-5.2-chat-latest", name: "gpt-5.2-chat-latest", displayName: "GPT-5.2 Instant", size: "Cloud", type: .cloud, provider: "openai"),
        LLMModel(id: "gpt-5.1", name: "gpt-5.1", displayName: "GPT-5.1 Thinking", size: "Cloud", type: .cloud, provider: "openai"),
        LLMModel(id: "gpt-5.1-chat-latest", name: "gpt-5.1-chat-latest", displayName: "GPT-5.1 Instant", size: "Cloud", type: .cloud, provider: "openai"),
        // GPT-4 family
        LLMModel(id: "gpt-4.1", name: "gpt-4.1", displayName: "GPT-4.1", size: "Cloud", type: .cloud, provider: "openai"),
        LLMModel(id: "gpt-4.1-mini", name: "gpt-4.1-mini", displayName: "GPT-4.1 Mini", size: "Cloud", type: .cloud, provider: "openai"),
        LLMModel(id: "gpt-4o", name: "gpt-4o", displayName: "GPT-4o", size: "Cloud", type: .cloud, provider: "openai"),
        LLMModel(id: "gpt-4o-mini", name: "gpt-4o-mini", displayName: "GPT-4o Mini", size: "Cloud", type: .cloud, provider: "openai"),
        // Reasoning models
        LLMModel(id: "o3-mini", name: "o3-mini", displayName: "o3-mini", size: "Cloud", type: .cloud, provider: "openai"),
    ]

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
        }
    }

    private func fetchModelsFromAPI() async throws -> [LLMModel] {
        guard let apiKey = LLMAPIKeyStore.shared.get(.openai) else {
            throw LLMError.configurationError("OpenAI API key not configured")
        }

        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMError.generationFailed("Failed to fetch models from OpenAI")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelsData = json["data"] as? [[String: Any]] else {
            throw LLMError.generationFailed("Invalid models response")
        }

        var chatModels: [(model: LLMModel, created: Int)] = []

        for modelData in modelsData {
            guard let modelId = modelData["id"] as? String else { continue }

            let excludePrefixes = ["text-embedding", "whisper", "tts", "dall-e", "davinci", "babbage", "curie", "ada", "text-moderation", "omni-moderation"]
            if excludePrefixes.contains(where: { modelId.hasPrefix($0) }) { continue }

            let validPrefixes = ["gpt-", "o1", "o3", "o4", "chatgpt"]
            guard validPrefixes.contains(where: { modelId.hasPrefix($0) }) else { continue }

            // Skip dated snapshots
            if isDateSnapshotModel(modelId) { continue }

            let skipSuffixes = ["-preview", "-instruct", "-vision-preview"]
            if skipSuffixes.contains(where: { modelId.hasSuffix($0) }) { continue }

            let created = modelData["created"] as? Int ?? 0

            let model = LLMModel(
                id: modelId,
                name: modelId,
                displayName: formatDisplayName(modelId),
                size: "Cloud",
                type: .cloud,
                provider: "openai"
            )
            chatModels.append((model, created))
        }

        return chatModels.sorted { $0.created > $1.created }.map { $0.model }
    }

    private func isDateSnapshotModel(_ modelId: String) -> Bool {
        let datePatterns = [#"-\d{4}-\d{2}-\d{2}"#, #"-\d{8}"#, #"-\d{4}$"#]
        for pattern in datePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: modelId, range: NSRange(modelId.startIndex..., in: modelId)) != nil {
                return true
            }
        }
        return false
    }

    private func formatDisplayName(_ modelId: String) -> String {
        var name = modelId
        if modelId.hasPrefix("gpt-") {
            name = "GPT-" + modelId.dropFirst(4)
        }
        if modelId.hasPrefix("chatgpt") {
            name = "ChatGPT" + modelId.dropFirst(7)
        }
        return name
    }

    public var isAvailable: Bool {
        get async {
            LLMAPIKeyStore.shared.get(.openai) != nil
        }
    }

    public func generate(
        prompt: String,
        model: String,
        options: LLMGenerationOptions
    ) async throws -> String {
        guard let apiKey = LLMAPIKeyStore.shared.get(.openai) else {
            throw LLMError.configurationError("OpenAI API key not configured")
        }

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build messages
        var messages: [[String: String]] = []
        if let systemPrompt = options.systemPrompt {
            let role = isReasoningModel(model) ? "developer" : "system"
            messages.append(["role": role, "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        var body: [String: Any] = [
            "model": model,
            "messages": messages
        ]

        if isReasoningModel(model) {
            body["max_completion_tokens"] = options.maxTokens
        } else {
            body["temperature"] = options.temperature
            body["max_tokens"] = options.maxTokens
            body["top_p"] = options.topP
        }

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

    public func streamGenerate(
        prompt: String,
        model: String,
        options: LLMGenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let apiKey = LLMAPIKeyStore.shared.get(.openai) else {
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

                    let isReasoning = self.isReasoningModel(model)
                    var messages: [[String: String]] = []
                    if let systemPrompt = options.systemPrompt {
                        let role = isReasoning ? "developer" : "system"
                        messages.append(["role": role, "content": systemPrompt])
                    }
                    messages.append(["role": "user", "content": prompt])

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
