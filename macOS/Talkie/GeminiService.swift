//
//  GeminiService.swift
//  talkie
//
//  Service for interacting with Google Gemini AI API
//

import Foundation

class GeminiService {
    static let shared = GeminiService()

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    private init() {}

    private var apiKey: String {
        let manager = SettingsManager.shared
        manager.loadSettings() // Ensure initialized
        return manager.geminiApiKey
    }

    // MARK: - Generate Content
    func generateContent(
        prompt: String,
        model: AIModel = .geminiFlash
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw GeminiError.missingAPIKey
        }

        let url = URL(string: "\(baseURL)/\(model.rawValue):generateContent?key=\(apiKey)")!
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
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 2048
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("❌ Gemini API error: \(errorBody)")
            }
            throw GeminiError.apiError(statusCode: httpResponse.statusCode)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let firstCandidate = geminiResponse.candidates.first,
              let text = firstCandidate.content.parts.first?.text else {
            throw GeminiError.noContent
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Execute Workflow
    func executeWorkflow(
        config: WorkflowConfig,
        transcript: String
    ) async throws -> WorkflowResult {
        let prompt = config.prompt(with: transcript)

        print("🤖 Executing \(config.actionType.rawValue) with \(config.model.displayName)")

        let output = try await generateContent(prompt: prompt, model: config.model)

        return WorkflowResult(
            actionType: config.actionType,
            output: output,
            model: config.model
        )
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
