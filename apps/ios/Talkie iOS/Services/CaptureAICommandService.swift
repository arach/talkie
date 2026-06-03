//
//  CaptureAICommandService.swift
//  Talkie iOS
//
//  Runs one-shot AI commands over captured context using phone-owned provider
//  keys. Prompt-building lives here; the per-provider HTTP + request/response
//  shapes live in the shared DirectAIClient (catalog-driven, all providers).
//

import Foundation

actor CaptureAICommandService {
    static let shared = CaptureAICommandService()

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

        guard AIProviderCatalog.provider(provider.providerId) != nil else {
            throw CaptureAICommandError.unsupportedProvider(provider.providerName)
        }

        let userPrompt = buildPrompt(
            context: trimmedContext,
            instruction: trimmedInstruction,
            title: title,
            sourceDescription: sourceDescription
        )

        let responseText = try await DirectAIClient.shared.complete(
            provider: provider,
            systemPrompt: captureAssistantPrompt,
            userPrompt: userPrompt
        )

        return CaptureAICommandResult(
            responseText: responseText,
            providerName: provider.providerName,
            modelId: provider.modelId,
            fallbackReason: provider.fallbackReason
        )
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

    var errorDescription: String? {
        switch self {
        case .missingContext:
            return "AI Commands needs captured text before it can answer anything."
        case .missingInstruction:
            return "AI Commands needs a command."
        case .unsupportedProvider(let providerName):
            return "\(providerName) is not supported for direct iPhone AI Commands."
        }
    }
}
