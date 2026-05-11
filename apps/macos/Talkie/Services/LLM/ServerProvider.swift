//
//  ServerProvider.swift
//  Talkie
//
//  Routes LLM inference through TalkieServer's Gateway module.
//  This centralizes API key management and handles model-specific quirks in one place.
//
//  TalkieServer must be running: bun run src/server.ts --local
//

import Foundation
import TalkieKit

private let log = Log(.system)

class ServerProvider: LLMProvider {
    let id = "server"
    let name = "TalkieServer"

    private let serverURL: URL
    private let timeout: TimeInterval

    init(port: Int = 8765, timeout: TimeInterval = 60.0) {
        self.serverURL = URL(string: "http://localhost:\(port)")!
        self.timeout = timeout
    }

    // MARK: - Response Types

    private struct InferenceResponse: Codable {
        let provider: String
        let model: String
        let content: String
        let usage: Usage?
        let finishReason: String?

        struct Usage: Codable {
            let inputTokens: Int?
            let outputTokens: Int?
        }
    }

    private struct ProvidersResponse: Codable {
        let providers: [ProviderInfo]

        struct ProviderInfo: Codable {
            let id: String
            let name: String
            let available: Bool
        }
    }

    private struct ModelsResponse: Codable {
        let provider: String
        let models: [String]
    }

    private struct ErrorResponse: Codable {
        let error: String
    }

    // MARK: - LLMProvider Protocol

    var models: [LLMModel] {
        get async throws {
            // Fetch models from all available providers via server
            var allModels: [LLMModel] = []

            // Get list of providers first
            let providersURL = serverURL.appendingPathComponent("inference/providers")
            var request = URLRequest(url: providersURL)
            request.timeoutInterval = 10

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    log.warning("Failed to fetch providers from server")
                    return []
                }

                let providersResp = try JSONDecoder().decode(ProvidersResponse.self, from: data)

                // Fetch models for each available provider
                for provider in providersResp.providers where provider.available {
                    let models = try await fetchModels(for: provider.id)
                    allModels.append(contentsOf: models)
                }
            } catch {
                log.error("Failed to fetch models from server: \(error.localizedDescription)")
            }

            return allModels
        }
    }

    private func fetchModels(for providerId: String) async throws -> [LLMModel] {
        var components = URLComponents(url: serverURL.appendingPathComponent("inference/models"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "provider", value: providerId)]

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return []
        }

        let modelsResp = try JSONDecoder().decode(ModelsResponse.self, from: data)

        return modelsResp.models.map { modelId in
            LLMModel(
                id: modelId,
                name: modelId,
                displayName: formatDisplayName(modelId, provider: providerId),
                size: "Cloud",
                type: .cloud,
                provider: "server:\(providerId)",  // Mark as routed through server
                downloadURL: nil,
                isInstalled: true
            )
        }
    }

    private func formatDisplayName(_ modelId: String, provider: String) -> String {
        // Add provider prefix for clarity
        let providerPrefix = provider.capitalized
        return "\(providerPrefix): \(modelId)"
    }

    var isAvailable: Bool {
        get async {
            // Skip health check if TalkieServer isn't enabled — avoids noisy connection errors
            guard await SettingsManager.shared.talkieServerEnabled else { return false }

            let healthURL = serverURL.appendingPathComponent("health")
            var request = URLRequest(url: healthURL)
            request.timeoutInterval = 2

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    return (200...299).contains(httpResponse.statusCode)
                }
            } catch {
                log.debug("Server not available: \(error.localizedDescription)")
            }
            return false
        }
    }

    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        // Parse provider from model ID if present (e.g., "server:openai" -> "openai")
        let (actualProvider, actualModel) = parseModelId(model)

        log.info("Server inference: provider=\(actualProvider), model=\(actualModel)")

        let url = serverURL.appendingPathComponent("inference")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        // Build messages array
        var messages: [[String: String]] = []
        if let systemPrompt = options.systemPrompt {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "provider": actualProvider,
            "model": actualModel,
            "messages": messages,
            "temperature": options.temperature,
            "maxTokens": options.maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.generationFailed("Server request failed: no HTTP response")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            var errorMessage = "Server error (HTTP \(httpResponse.statusCode))"

            if let errorResp = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                errorMessage = "Server: \(errorResp.error)"
            }

            log.error("Server inference failed: \(errorMessage)")
            throw LLMError.generationFailed(errorMessage)
        }

        let inferenceResp = try JSONDecoder().decode(InferenceResponse.self, from: data)
        log.info("Server inference complete: provider=\(inferenceResp.provider), model=\(inferenceResp.model)")

        return inferenceResp.content
    }

    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Server doesn't support streaming yet - fall back to non-streaming
        log.info("Server streaming not implemented, using non-streaming")

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let result = try await self.generate(prompt: prompt, model: model, options: options)
                    continuation.yield(result)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Parse model ID that might include provider prefix (e.g., "server:openai:gpt-4o" -> ("openai", "gpt-4o"))
    private func parseModelId(_ modelId: String) -> (provider: String, model: String) {
        // Check if model has provider prefix from our listing (e.g., "server:openai")
        if modelId.hasPrefix("server:") {
            let withoutServer = String(modelId.dropFirst("server:".count))
            if let colonIndex = withoutServer.firstIndex(of: ":") {
                let provider = String(withoutServer[..<colonIndex])
                let model = String(withoutServer[withoutServer.index(after: colonIndex)...])
                return (provider, model)
            }
        }

        // Default: try to infer provider from model name
        if modelId.hasPrefix("gpt-") || modelId.hasPrefix("o1") || modelId.hasPrefix("o3") {
            return ("openai", modelId)
        } else if modelId.hasPrefix("claude-") {
            return ("anthropic", modelId)
        } else if modelId.hasPrefix("gemini-") {
            return ("google", modelId)
        } else if modelId.hasPrefix("llama-") || modelId.hasPrefix("mixtral-") {
            return ("groq", modelId)
        }

        // Fallback to openai
        return ("openai", modelId)
    }
}
