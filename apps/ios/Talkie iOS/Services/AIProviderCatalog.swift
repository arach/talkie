//
//  AIProviderCatalog.swift
//  Talkie iOS
//
//  Single source of truth for every AI provider Talkie can talk to directly
//  from the phone. The AI Keys UI, the credential resolver, the key validator,
//  and the direct execution client (DirectAIClient) all read from here, so a
//  provider is defined in exactly ONE place — no more "the UI offers four but
//  only two actually run" drift.
//

import Foundation

enum AIProviderCatalog {
    /// How a provider's chat endpoint is shaped.
    enum APIStyle: Equatable {
        /// OpenAI chat-completions shape, `Authorization: Bearer <key>`.
        /// OpenAI, Groq, and OpenRouter all speak this.
        case openAICompatible
        /// Anthropic Messages API: `POST /v1/messages`, `x-api-key` +
        /// `anthropic-version`, top-level `system`, `content[0].text` response.
        case anthropic
    }

    struct Provider: Identifiable, Equatable {
        let id: String                  // "openai"
        let displayName: String         // "OpenAI"
        let blurb: String               // catalog subtitle
        let keyPlaceholder: String      // "sk-…"
        let keyPrefixes: [String]       // accepted API-key prefixes
        let apiStyle: APIStyle
        let chatURL: URL                // completions / messages endpoint
        let validationURL: URL          // GET models endpoint (validate-on-save)
        let defaultModel: String        // one default model per provider
        /// Extra request headers (e.g. OpenRouter attribution). Empty for most.
        let extraHeaders: [String: String]
    }

    /// Anthropic API version pinned for the Messages + Models endpoints.
    static let anthropicVersion = "2023-06-01"

    static let openai = Provider(
        id: "openai",
        displayName: "OpenAI",
        blurb: "GPT-5 family, o-series, embeddings",
        keyPlaceholder: "sk-…",
        keyPrefixes: ["sk-"],
        apiStyle: .openAICompatible,
        chatURL: URL(string: "https://api.openai.com/v1/chat/completions")!,
        validationURL: URL(string: "https://api.openai.com/v1/models")!,
        defaultModel: "gpt-5.5",
        extraHeaders: [:]
    )

    static let groq = Provider(
        id: "groq",
        displayName: "Groq",
        blurb: "Llama, Mixtral, Whisper — fast",
        keyPlaceholder: "gsk_…",
        keyPrefixes: ["gsk_"],
        apiStyle: .openAICompatible,
        chatURL: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
        validationURL: URL(string: "https://api.groq.com/openai/v1/models")!,
        defaultModel: "llama-3.3-70b-versatile",
        extraHeaders: [:]
    )

    static let anthropic = Provider(
        id: "anthropic",
        displayName: "Anthropic",
        blurb: "Claude 4 — Opus, Sonnet, Haiku",
        keyPlaceholder: "sk-ant-…",
        keyPrefixes: ["sk-ant-"],
        apiStyle: .anthropic,
        chatURL: URL(string: "https://api.anthropic.com/v1/messages")!,
        validationURL: URL(string: "https://api.anthropic.com/v1/models")!,
        defaultModel: "claude-sonnet-4-6",
        extraHeaders: [:]
    )

    static let openrouter = Provider(
        id: "openrouter",
        displayName: "OpenRouter",
        blurb: "One key, many providers",
        keyPlaceholder: "sk-or-…",
        keyPrefixes: ["sk-or-"],
        apiStyle: .openAICompatible,
        chatURL: URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
        validationURL: URL(string: "https://openrouter.ai/api/v1/models")!,
        defaultModel: "openai/gpt-5.5",
        extraHeaders: [
            "HTTP-Referer": "https://talkie.to",
            "X-Title": "Talkie",
        ]
    )

    /// Display order = setup priority.
    static let all: [Provider] = [openai, anthropic, groq, openrouter]

    static var ids: Set<String> { Set(all.map(\.id)) }

    static func provider(_ id: String) -> Provider? {
        let key = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.first { $0.id == key }
    }

    static func displayName(for id: String) -> String {
        provider(id)?.displayName ?? "OpenAI"
    }

    static func defaultModel(for id: String) -> String {
        provider(id)?.defaultModel ?? openai.defaultModel
    }

    /// Cheap local sanity check on a key's shape (length + prefix). The real
    /// check is a live request in TalkieAIProviderCredentialValidator.
    static func isValidKeyFormat(_ apiKey: String, providerId: String) -> Bool {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 20, !key.contains("*"), !key.contains("•") else { return false }
        guard let provider = provider(providerId) else { return false }
        return provider.keyPrefixes.contains { key.hasPrefix($0) }
    }
}
