//
//  InterstitialLLMClient.swift
//  TalkieKit
//
//  Internal LLM client for the interstitial polish feature.
//  Supports Anthropic and OpenAI APIs directly.
//

import Foundation

final class InterstitialLLMClient: @unchecked Sendable {
    static let shared = InterstitialLLMClient()

    private init() {}

    func complete(
        text: String,
        instruction: String,
        provider: TalkieInterstitial.LLMProvider,
        model: String,
        apiKey: String?
    ) async throws -> String {
        // Get API key from parameter or keychain
        guard let key = apiKey ?? getAPIKey(for: provider) else {
            throw LLMError.noAPIKey
        }

        let prompt = """
            Apply this instruction to the text below. Return only the modified text, nothing else.

            Instruction: \(instruction)

            Text:
            \(text)
            """

        switch provider {
        case .anthropic:
            return try await callAnthropic(prompt: prompt, model: model, apiKey: key)
        case .openai:
            return try await callOpenAI(prompt: prompt, model: model, apiKey: key)
        }
    }

    // MARK: - Anthropic

    private func callAnthropic(prompt: String, model: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw LLMError.apiError(httpResponse.statusCode, errorBody)
            }
            throw LLMError.apiError(httpResponse.statusCode, "Unknown error")
        }

        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        guard let content = decoded.content.first?.text else {
            throw LLMError.emptyResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct AnthropicResponse: Codable {
        let content: [Content]
        struct Content: Codable {
            let text: String
        }
    }

    // MARK: - OpenAI

    private func callOpenAI(prompt: String, model: String, apiKey: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw LLMError.apiError(httpResponse.statusCode, errorBody)
            }
            throw LLMError.apiError(httpResponse.statusCode, "Unknown error")
        }

        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LLMError.emptyResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct OpenAIResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable {
            let message: Message
        }
        struct Message: Codable {
            let content: String
        }
    }

    // MARK: - API Keys

    private func getAPIKey(for provider: TalkieInterstitial.LLMProvider) -> String? {
        // Read from Talkie's encrypted API key store
        switch provider {
        case .anthropic:
            return InterstitialAPIKeyStore.get("anthropic")
        case .openai:
            return InterstitialAPIKeyStore.get("openai")
        }
    }

    // MARK: - Errors

    enum LLMError: LocalizedError {
        case noAPIKey
        case invalidResponse
        case emptyResponse
        case apiError(Int, String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No API key configured"
            case .invalidResponse:
                return "Invalid response from API"
            case .emptyResponse:
                return "Empty response from API"
            case .apiError(let code, let message):
                return "API error (\(code)): \(message)"
            }
        }
    }
}

// MARK: - API Key Store (reads Talkie's encrypted key store)

import CryptoKit
import IOKit

enum InterstitialAPIKeyStore {
    private static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Talkie/.apikeys")
    }()

    private static var cache: [String: String]?

    static func get(_ provider: String) -> String? {
        // Load cache if needed
        if cache == nil {
            cache = loadKeys()
        }
        return cache?[provider]
    }

    private static func loadKeys() -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        do {
            let encryptedData = try Data(contentsOf: fileURL)
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: deriveKey())

            if let decoded = try? JSONDecoder().decode([String: String].self, from: decryptedData) {
                return decoded
            }
        } catch {
            // Failed to decrypt - keys may not be set up yet
        }

        return [:]
    }

    private static func deriveKey() -> SymmetricKey {
        // Must match Talkie's APIKeyStore.deriveKey()
        var seed = "jdi.talkie.apikeys"

        if let uuid = getHardwareUUID() {
            seed += ".\(uuid)"
        }

        let hash = SHA256.hash(data: Data(seed.utf8))
        return SymmetricKey(data: hash)
    }

    private static func getHardwareUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        guard let uuid = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }

        return uuid
    }
}
