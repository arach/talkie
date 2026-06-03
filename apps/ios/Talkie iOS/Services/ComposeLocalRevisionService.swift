//
//  ComposeLocalRevisionService.swift
//  Talkie iOS
//
//  Direct cloud revision for iPhone Compose using phone-owned provider keys.
//  Prompt-building lives here; the per-provider HTTP + request/response shapes
//  live in the shared DirectAIClient (catalog-driven, all providers).
//

import Foundation

actor ComposeLocalRevisionService {
    static let shared = ComposeLocalRevisionService()

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

        guard AIProviderCatalog.provider(provider.providerId) != nil else {
            throw ComposeLocalRevisionError.unsupportedProvider(provider.providerName)
        }

        let userPrompt = buildComposePrompt(
            text: trimmedText,
            instruction: trimmedInstruction,
            fullDocument: fullDocument ?? text,
            editingScope: editingScope,
            revisionHistory: revisionHistory
        )

        let revisedText = try await DirectAIClient.shared.complete(
            provider: provider,
            systemPrompt: provider.assistantPrompt,
            userPrompt: userPrompt
        )

        return ComposeLocalRevisionResult(
            revisedText: revisedText,
            providerName: provider.providerName,
            modelId: provider.modelId,
            fallbackReason: provider.fallbackReason
        )
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

    var errorDescription: String? {
        switch self {
        case .missingText:
            return "Compose needs text before it can revise anything."
        case .missingInstruction:
            return "Compose needs an instruction."
        case .unsupportedProvider(let providerName):
            return "\(providerName) is not supported for direct iPhone Compose."
        }
    }
}
