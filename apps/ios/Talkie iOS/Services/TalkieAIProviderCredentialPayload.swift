//
//  TalkieAIProviderCredentialPayload.swift
//  Talkie iOS
//
//  QR payload for importing iPhone-owned AI provider credentials.
//

import Foundation

struct TalkieAIProviderCredentialPayload: Codable, Equatable {
    let providerId: String
    let providerName: String
    let modelId: String
    let apiKey: String
    let assistantPrompt: String

    private enum CodingKeys: String, CodingKey {
        case payloadProtocol = "protocol"
        case providerId
        case providerName
        case modelId
        case apiKey
        case assistantPrompt
    }

    init(
        providerId: String,
        providerName: String,
        modelId: String,
        apiKey: String,
        assistantPrompt: String
    ) {
        self.providerId = providerId
        self.providerName = providerName
        self.modelId = modelId
        self.apiKey = apiKey
        self.assistantPrompt = assistantPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payloadProtocol = try container.decode(String.self, forKey: .payloadProtocol)
        guard payloadProtocol == Self.payloadProtocol else {
            throw DecodingError.dataCorruptedError(
                forKey: .payloadProtocol,
                in: container,
                debugDescription: "Unsupported AI credential QR protocol."
            )
        }

        let providerId = try container.decode(String.self, forKey: .providerId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let apiKey = try container.decode(String.self, forKey: .apiKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard Self.supportedProviderIds.contains(providerId),
              Self.isValidAPIKey(apiKey, providerId: providerId) else {
            throw DecodingError.dataCorruptedError(
                forKey: .providerId,
                in: container,
                debugDescription: "AI credential QR provider or API key is invalid."
            )
        }

        self.providerId = providerId
        self.providerName = try container.decodeIfPresent(String.self, forKey: .providerName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? Self.displayName(for: providerId)
        self.modelId = try container.decodeIfPresent(String.self, forKey: .modelId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? Self.defaultModel(for: providerId)
        self.apiKey = apiKey
        self.assistantPrompt = try container.decodeIfPresent(String.self, forKey: .assistantPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            ?? Self.defaultAssistantPrompt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.payloadProtocol, forKey: .payloadProtocol)
        try container.encode(providerId, forKey: .providerId)
        try container.encode(providerName, forKey: .providerName)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(assistantPrompt, forKey: .assistantPrompt)
    }

    static func from(url: URL) -> TalkieAIProviderCredentialPayload? {
        guard url.scheme == "talkie" else { return nil }
        guard url.host == "ai" || url.host == "credentials" else { return nil }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard path == "import" || path == "provider" || path == "credentials" else { return nil }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = (components.queryItems ?? []).reduce(into: [String: String]()) { values, item in
            guard values[item.name] == nil, let value = item.value else { return }
            values[item.name] = value
        }

        let providerId = (items["provider"] ?? items["providerId"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let apiKey = (items["key"] ?? items["apiKey"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard supportedProviderIds.contains(providerId),
              isValidAPIKey(apiKey, providerId: providerId) else { return nil }

        return TalkieAIProviderCredentialPayload(
            providerId: providerId,
            providerName: items["providerName"]?.nilIfEmpty ?? displayName(for: providerId),
            modelId: items["model"]?.nilIfEmpty ?? items["modelId"]?.nilIfEmpty ?? defaultModel(for: providerId),
            apiKey: apiKey,
            assistantPrompt: items["assistantPrompt"]?.nilIfEmpty ?? defaultAssistantPrompt
        )
    }

    static let payloadProtocol = "talkie-ai-credentials-v1"

    static let defaultAssistantPrompt = """
    You are Talkie's Apple Watch voice assistant. Answer directly, briefly, and naturally.
    """

    // Provider metadata is owned by AIProviderCatalog (single source of truth);
    // these thin shims keep existing call sites stable.
    static var supportedProviderIds: Set<String> { AIProviderCatalog.ids }
    static let defaultOpenAIModel = AIProviderCatalog.openai.defaultModel
    static let legacyDefaultOpenAIModels: Set<String> = [
        "gpt-5.2-chat-latest",
        "gpt-5.4-mini",
    ]

    static func displayName(for providerId: String) -> String {
        AIProviderCatalog.displayName(for: providerId)
    }

    static func defaultModel(for providerId: String) -> String {
        AIProviderCatalog.defaultModel(for: providerId)
    }

    static func isLegacyDefaultModel(_ modelId: String, for providerId: String) -> Bool {
        switch providerId {
        case "openai":
            return legacyDefaultOpenAIModels.contains(modelId)
        default:
            return false
        }
    }

    static func normalizedDefaultModel(_ modelId: String?, for providerId: String) -> String? {
        let trimmed = modelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if isLegacyDefaultModel(trimmed, for: providerId) {
            return defaultModel(for: providerId)
        }
        return trimmed
    }

    private static func isValidAPIKey(_ apiKey: String, providerId: String) -> Bool {
        AIProviderCatalog.isValidKeyFormat(apiKey, providerId: providerId)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
