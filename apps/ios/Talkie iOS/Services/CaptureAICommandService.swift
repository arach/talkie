//
//  CaptureAICommandService.swift
//  Talkie iOS
//
//  Runs one-shot AI commands over captured context using borrowed paired-Mac
//  provider credentials.
//

import Foundation

actor CaptureAICommandService {
    static let shared = CaptureAICommandService()

    private let openAIURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let groqURL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private let temperature = 0.3
    private let maxTokens = 2048

    private init() {}

    func run(
        context: String,
        instruction: String,
        title: String? = nil,
        sourceDescription: String? = nil,
        provider: ComposeBorrowedProvider
    ) async throws -> CaptureAICommandResult {
        let trimmedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContext.isEmpty else {
            throw CaptureAICommandError.missingContext
        }

        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            throw CaptureAICommandError.missingInstruction
        }

        switch provider.providerId {
        case "openai":
            let responseText = try await callOpenAI(
                context: trimmedContext,
                instruction: trimmedInstruction,
                title: title,
                sourceDescription: sourceDescription,
                provider: provider
            )
            return CaptureAICommandResult(
                responseText: responseText,
                providerName: provider.providerName,
                modelId: provider.modelId,
                fallbackReason: provider.fallbackReason
            )

        case "groq":
            let responseText = try await callGroq(
                context: trimmedContext,
                instruction: trimmedInstruction,
                title: title,
                sourceDescription: sourceDescription,
                provider: provider
            )
            return CaptureAICommandResult(
                responseText: responseText,
                providerName: provider.providerName,
                modelId: provider.modelId,
                fallbackReason: provider.fallbackReason
            )

        default:
            throw CaptureAICommandError.unsupportedProvider(provider.providerName)
        }
    }

    private func callOpenAI(
        context: String,
        instruction: String,
        title: String?,
        sourceDescription: String?,
        provider: ComposeBorrowedProvider
    ) async throws -> String {
        let model = provider.modelId
        let usesDeveloperRole = isOpenAIReasoningModel(model)

        let requestBody = OpenAIRequest(
            model: model,
            messages: [
                OpenAIMessage(
                    role: usesDeveloperRole ? "developer" : "system",
                    content: captureAssistantPrompt
                ),
                OpenAIMessage(
                    role: "user",
                    content: buildPrompt(
                        context: context,
                        instruction: instruction,
                        title: title,
                        sourceDescription: sourceDescription
                    )
                ),
            ],
            temperature: usesDeveloperRole ? nil : temperature,
            maxTokens: usesDeveloperRole ? nil : maxTokens,
            maxCompletionTokens: usesDeveloperRole ? maxTokens : nil,
            stream: false
        )

        let response: OpenAIResponse = try await performRequest(
            url: openAIURL,
            apiKey: provider.apiKey,
            body: requestBody
        )

        guard let content = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw CaptureAICommandError.emptyResponse(provider.providerName)
        }

        return content
    }

    private func callGroq(
        context: String,
        instruction: String,
        title: String?,
        sourceDescription: String?,
        provider: ComposeBorrowedProvider
    ) async throws -> String {
        let requestBody = GroqRequest(
            model: provider.modelId,
            messages: [
                GroqMessage(role: "system", content: captureAssistantPrompt),
                GroqMessage(
                    role: "user",
                    content: buildPrompt(
                        context: context,
                        instruction: instruction,
                        title: title,
                        sourceDescription: sourceDescription
                    )
                ),
            ],
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )

        let response: GroqResponse = try await performRequest(
            url: groqURL,
            apiKey: provider.apiKey,
            body: requestBody
        )

        guard let content = response.choices.first?.message?.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw CaptureAICommandError.emptyResponse(provider.providerName)
        }

        return content
    }

    private var captureAssistantPrompt: String {
        """
        You help the user run quick AI commands against captured text from their device.
        Use the captured text as the primary context.
        Answer directly in concise, speech-friendly prose unless the user explicitly asks for another format.
        If the capture does not contain enough information, say so briefly and answer with the best grounded help you can.
        Return only the answer.
        """
    }

    private func buildPrompt(
        context: String,
        instruction: String,
        title: String?,
        sourceDescription: String?
    ) -> String {
        var lines: [String] = []
        lines.append("Source:")
        lines.append(sourceDescription ?? "Captured text")

        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("Title:")
            lines.append(title)
        }

        lines.append("")
        lines.append("Captured text:")
        lines.append(context)
        lines.append("")
        lines.append("User instruction:")
        lines.append(instruction)
        lines.append("")
        lines.append("Return only the answer.")

        return lines.joined(separator: "\n")
    }

    private func isOpenAIReasoningModel(_ model: String) -> Bool {
        model.hasPrefix("o1")
            || model.hasPrefix("o3")
            || model.hasPrefix("o4")
            || model.hasPrefix("gpt-5")
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
            throw CaptureAICommandError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CaptureAICommandError.apiError(
                statusCode: httpResponse.statusCode,
                message: parseAPIErrorMessage(from: data)
            )
        }

        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw CaptureAICommandError.invalidResponse
        }
    }

    private func parseAPIErrorMessage(from data: Data) -> String {
        if let envelope = try? JSONDecoder().decode(CaptureAICommandAPIErrorEnvelope.self, from: data),
           let message = envelope.error?.message?.trimmingCharacters(in: .whitespacesAndNewlines),
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

struct CaptureAICommandResult {
    let responseText: String
    let providerName: String
    let modelId: String
    let fallbackReason: String?
}

enum CaptureAICommandError: LocalizedError {
    case missingContext
    case missingInstruction
    case unsupportedProvider(String)
    case invalidResponse
    case emptyResponse(String)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingContext:
            return "AI Commands needs captured text before it can answer anything."
        case .missingInstruction:
            return "AI Commands needs a command."
        case .unsupportedProvider(let providerName):
            return "\(providerName) is not supported for direct iPhone AI Commands."
        case .invalidResponse:
            return "AI Commands received an invalid response."
        case .emptyResponse(let providerName):
            return "\(providerName) returned no text."
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        }
    }
}

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [OpenAIMessage]
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

private struct OpenAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct GroqMessage: Codable {
    let role: String
    let content: String
}

private struct GroqRequest: Encodable {
    let model: String
    let messages: [GroqMessage]
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

private struct GroqResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]
}

private struct CaptureAICommandAPIErrorEnvelope: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}
