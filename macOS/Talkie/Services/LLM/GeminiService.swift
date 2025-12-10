//
//  GeminiService.swift
//  talkie
//
//  Service for interacting with Google Gemini AI API
//

import Foundation
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "LLM")
// LLMProvider protocol and types imported from iOS/talkie/Services/LLMProvider.swift
// (automatically included via file system synchronized groups)

class GeminiProvider: LLMProvider {
    let id = "gemini"
    let name = "Google Gemini"

    static let shared = GeminiProvider()

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init() {}

    private var apiKey: String {
        let manager = SettingsManager.shared
        manager.loadSettings() // Ensure initialized
        return manager.geminiApiKey
    }

    var isAvailable: Bool {
        get async {
            return !apiKey.isEmpty
        }
    }

    var models: [LLMModel] {
        get async throws {
            return [
                LLMModel(
                    id: "gemini-1.5-flash-latest",
                    name: "gemini-1.5-flash-latest",
                    displayName: "Gemini 1.5 Flash",
                    size: "Cloud",
                    type: .cloud,
                    provider: "gemini",
                    downloadURL: nil,
                    isInstalled: true
                ),
                LLMModel(
                    id: "gemini-1.5-pro-latest",
                    name: "gemini-1.5-pro-latest",
                    displayName: "Gemini 1.5 Pro",
                    size: "Cloud",
                    type: .cloud,
                    provider: "gemini",
                    downloadURL: nil,
                    isInstalled: true
                )
            ]
        }
    }

    func generate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> String {
        return try await generateContent(prompt: prompt, modelId: model, options: options)
    }

    func streamGenerate(
        prompt: String,
        model: String,
        options: GenerationOptions
    ) async throws -> AsyncThrowingStream<String, Error> {
        // TODO: Implement streaming for Gemini
        throw LLMError.generationFailed("Streaming not yet implemented for Gemini")
    }

    // MARK: - Generate Content
    private func generateContent(
        prompt: String,
        modelId: String,
        options: GenerationOptions
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.notConfigured
        }

        let url = URL(string: "\(baseURL)/\(modelId):generateContent?key=\(apiKey)")!
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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorBody = String(data: data, encoding: .utf8) {
                logger.debug("❌ Gemini API error: \(errorBody)")
            }
            throw LLMError.generationFailed("API error: \(httpResponse.statusCode)")
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let firstCandidate = geminiResponse.candidates.first,
              let text = firstCandidate.content.parts.first?.text else {
            throw LLMError.generationFailed("No content in response")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Response Models
struct GeminiResponse: Codable {
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

// MARK: - Errors
enum GeminiError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case apiError(statusCode: Int)
    case noContent

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API key not configured. Please add your API key in Settings."
        case .invalidResponse:
            return "Invalid response from Gemini API."
        case .apiError(let statusCode):
            return "Gemini API returned error with status code: \(statusCode)"
        case .noContent:
            return "No content received from Gemini API."
        }
    }
}
