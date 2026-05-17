//
//  ComposeLocalRevisionService.swift
//  Talkie iOS
//
//  Direct cloud revision for iPhone Compose using borrowed paired-Mac credentials.
//

import Foundation

actor ComposeLocalRevisionService {
    static let shared = ComposeLocalRevisionService()

    private let openAIURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let groqURL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let temperature = 0.3
    private let maxTokens = 2048

    private init() {}

    func revise(
        text: String,
        instruction: String,
        provider: ComposeBorrowedProvider,
        fullDocument: String? = nil,
        editingScope: String = "Entire document.",
        revisionHistory: String = "No prior revisions."
    ) async throws -> ComposeLocalRevisionResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw ComposeLocalRevisionError.missingText
        }

        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            throw ComposeLocalRevisionError.missingInstruction
        }

        switch provider.providerId {
        case "openai":
            let revisedText = try await callOpenAI(
                text: trimmedText,
                instruction: trimmedInstruction,
                fullDocument: fullDocument ?? text,
                editingScope: editingScope,
                revisionHistory: revisionHistory,
                provider: provider
            )
            return ComposeLocalRevisionResult(
                revisedText: revisedText,
                providerName: provider.providerName,
                modelId: provider.modelId,
                fallbackReason: provider.fallbackReason
            )

        case "groq":
            let revisedText = try await callGroq(
                text: trimmedText,
                instruction: trimmedInstruction,
                fullDocument: fullDocument ?? text,
                editingScope: editingScope,
                revisionHistory: revisionHistory,
                provider: provider
            )
            return ComposeLocalRevisionResult(
                revisedText: revisedText,
                providerName: provider.providerName,
                modelId: provider.modelId,
                fallbackReason: provider.fallbackReason
            )

        default:
            throw ComposeLocalRevisionError.unsupportedProvider(provider.providerName)
        }
    }

    private func callOpenAI(
        text: String,
        instruction: String,
        fullDocument: String,
        editingScope: String,
        revisionHistory: String,
        provider: ComposeBorrowedProvider
    ) async throws -> String {
        let model = provider.modelId
        let isReasoningModel = isOpenAIReasoningModel(model)

        let requestBody = OpenAIChatRequest(
            model: model,
            messages: makeMessages(
                text: text,
                instruction: instruction,
                fullDocument: fullDocument,
                editingScope: editingScope,
                revisionHistory: revisionHistory,
                assistantPrompt: provider.assistantPrompt,
                usesDeveloperRole: isReasoningModel
            ),
            temperature: isReasoningModel ? nil : temperature,
            maxTokens: isReasoningModel ? nil : maxTokens,
            maxCompletionTokens: isReasoningModel ? maxTokens : nil,
            stream: false
        )

        let response: OpenAIChatResponse = try await performRequest(
            url: openAIURL,
            apiKey: provider.apiKey,
            body: requestBody
        )

        guard let content = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            throw ComposeLocalRevisionError.emptyResponse(provider.providerName)
        }

        return content
    }

    private func callGroq(
        text: String,
        instruction: String,
        fullDocument: String,
        editingScope: String,
        revisionHistory: String,
        provider: ComposeBorrowedProvider
    ) async throws -> String {
        let requestBody = GroqChatRequest(
            model: provider.modelId,
            messages: makeMessages(
                text: text,
                instruction: instruction,
                fullDocument: fullDocument,
                editingScope: editingScope,
                revisionHistory: revisionHistory,
                assistantPrompt: provider.assistantPrompt
            ),
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )

        let response: GroqChatResponse = try await performRequest(
            url: groqURL,
            apiKey: provider.apiKey,
            body: requestBody
        )

        guard let content = response.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty
        else {
            throw ComposeLocalRevisionError.emptyResponse(provider.providerName)
        }

        return content
    }

    private func makeMessages(
        text: String,
        instruction: String,
        fullDocument: String,
        editingScope: String,
        revisionHistory: String,
        assistantPrompt: String,
        usesDeveloperRole: Bool = false
    ) -> [ChatMessage] {
        [
            ChatMessage(role: usesDeveloperRole ? "developer" : "system", content: assistantPrompt),
            ChatMessage(
                role: "user",
                content: buildComposePrompt(
                    text: text,
                    instruction: instruction,
                    fullDocument: fullDocument,
                    editingScope: editingScope,
                    revisionHistory: revisionHistory
                )
            ),
        ]
    }

    private func isOpenAIReasoningModel(_ model: String) -> Bool {
        model.hasPrefix("o1")
            || model.hasPrefix("o3")
            || model.hasPrefix("o4")
            || model.hasPrefix("gpt-5")
    }

    private func buildComposePrompt(
        text: String,
        instruction: String,
        fullDocument: String,
        editingScope: String,
        revisionHistory: String
    ) -> String {
        [
            "User instruction:",
            instruction,
            "",
            "Editing scope:",
            editingScope,
            "",
            "Current target text:",
            text,
            "",
            "Current full document:",
            fullDocument,
            "",
            "Revision history (oldest to newest):",
            revisionHistory,
            "",
            "Return only the revised text for the current target text.",
        ].joined(separator: "\n")
    }

    private func performRequest<RequestBody: Encodable, ResponseBody: Decodable>(
        url: URL,
        apiKey: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ComposeLocalRevisionError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ComposeLocalRevisionError.apiError(
                statusCode: httpResponse.statusCode,
                message: parseAPIErrorMessage(from: data)
            )
        }

        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw ComposeLocalRevisionError.invalidResponse
        }
    }

    private func parseAPIErrorMessage(from data: Data) -> String {
        if let errorEnvelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data),
           let message = errorEnvelope.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            return message
        }

        if let string = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !string.isEmpty {
            return string
        }

        return "Unknown API error"
    }
}

struct ComposeLocalRevisionResult {
    let revisedText: String
    let providerName: String
    let modelId: String
    let fallbackReason: String?
}

enum ComposeLocalRevisionError: LocalizedError {
    case missingText
    case missingInstruction
    case unsupportedProvider(String)
    case invalidResponse
    case emptyResponse(String)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingText:
            return "Compose needs text before it can revise anything."
        case .missingInstruction:
            return "Compose needs an instruction."
        case .unsupportedProvider(let providerName):
            return "\(providerName) is not supported for direct iPhone Compose."
        case .invalidResponse:
            return "Compose received an invalid response."
        case .emptyResponse(let providerName):
            return "\(providerName) returned no text."
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        }
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let maxTokens: Int?
    let maxCompletionTokens: Int?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case stream
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct GroqChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct GroqChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]
}

private struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let message: String?
    }

    let error: Payload?
}
