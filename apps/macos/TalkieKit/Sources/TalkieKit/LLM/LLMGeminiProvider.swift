//
//  LLMGeminiProvider.swift
//  TalkieKit
//
//  Google Gemini API provider for LLM generation
//

import Foundation
import os

private let logger = Logger(subsystem: "jdi.talkiekit", category: "Gemini")

public final class LLMGeminiProvider: LLMProvider, @unchecked Sendable {
    public let id = "gemini"
    public let name = "Google Gemini"

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    public init() {}

    public var models: [LLMModel] {
        get async throws {
            [
                LLMModel(
                    id: "gemini-2.0-flash",
                    name: "gemini-2.0-flash",
                    displayName: "Gemini 2.0 Flash",
                    size: "Cloud",
                    type: .cloud,
                    provider: "gemini"
                ),
                LLMModel(
                    id: "gemini-2.0-flash-lite",
                    name: "gemini-2.0-flash-lite",
                    displayName: "Gemini 2.0 Flash Lite",
                    size: "Cloud",
                    type: .cloud,
                    provider: "gemini"
                ),
                LLMModel(
                    id: "gemini-1.5-flash-latest",
                    name: "gemini-1.5-flash-latest",
                    displayName: "Gemini 1.5 Flash",
                    size: "Cloud",
                    type: .cloud,
                    provider: "gemini"
                ),
                LLMModel(
                    id: "gemini-1.5-pro-latest",
                    name: "gemini-1.5-pro-latest",
                    displayName: "Gemini 1.5 Pro",
                    size: "Cloud",
                    type: .cloud,
                    provider: "gemini"
                )
            ]
        }
    }

    public var isAvailable: Bool {
        get async {
            LLMAPIKeyStore.shared.get(.gemini) != nil
        }
    }

    public func generate(
        prompt: String,
        model: String,
        options: LLMGenerationOptions
    ) async throws -> String {
        guard let apiKey = LLMAPIKeyStore.shared.get(.gemini) else {
            throw LLMError.notConfigured
        }

        let url = URL(string: "\(baseURL)/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": options.temperature,
                "topK": 40,
                "topP": options.topP,
                "maxOutputTokens": options.maxTokens
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let errorBody = String(data: data, encoding: .utf8) {
                logger.debug("Gemini API error: \(errorBody)")
            }
            throw LLMError.generationFailed("Gemini API error")
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let firstCandidate = geminiResponse.candidates.first,
              let text = firstCandidate.content.parts.first?.text else {
            throw LLMError.generationFailed("No content in response")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func streamGenerate(
        prompt: String,
        model: String,
        options: LLMGenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Gemini streaming not implemented - fall back to non-streaming
        AsyncThrowingStream { continuation in
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
}

// MARK: - Response Models

private struct GeminiResponse: Codable {
    let candidates: [Candidate]

    struct Candidate: Codable {
        let content: Content

        struct Content: Codable {
            let parts: [Part]

            struct Part: Codable {
                let text: String?
            }
        }
    }
}
