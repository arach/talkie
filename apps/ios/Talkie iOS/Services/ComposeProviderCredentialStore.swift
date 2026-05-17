//
//  ComposeProviderCredentialStore.swift
//  Talkie iOS
//
//  Keeps AI provider credentials available for phone-owned flows.
//

import Foundation
import Security

struct ComposeProviderCredentialStore {
    static let shared = ComposeProviderCredentialStore()

    private let service = "to.talkie.compose-provider"
    private let lastProviderAccount = "last-provider"

    @discardableResult
    func save(_ provider: ComposeBorrowedProvider) -> Bool {
        let cachedProvider = CachedComposeProvider(provider: provider, updatedAt: Date())
        let providerSaved = save(cachedProvider, account: account(for: provider.providerId))
        let lastProviderSaved = save(cachedProvider, account: lastProviderAccount)
        return providerSaved && lastProviderSaved
    }

    @discardableResult
    func save(_ payload: TalkieAIProviderCredentialPayload) -> Bool {
        let provider = ComposeBorrowedProvider(
            providerId: payload.providerId,
            providerName: payload.providerName,
            modelId: payload.modelId,
            apiKey: payload.apiKey,
            assistantPrompt: payload.assistantPrompt,
            fallbackReason: nil
        )
        return save(provider)
    }

    func load(providerId: String? = nil, modelId: String? = nil) -> ComposeBorrowedProvider? {
        if let providerId = normalized(providerId),
           let provider = load(account: account(for: providerId)) {
            return provider.borrowedProvider(modelId: normalized(modelId))
        }

        return load(account: lastProviderAccount)?.borrowedProvider(modelId: normalized(modelId))
    }

    func deleteAll() {
        for account in [lastProviderAccount, account(for: "openai"), account(for: "groq")] {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                AppLogger.ai.warning("AI credential delete failed", detail: "account=\(account) status=\(status)")
            }
        }
        AppLogger.ai.info("AI credentials cleared")
    }

    private func save(_ provider: CachedComposeProvider, account: String) -> Bool {
        guard let data = try? JSONEncoder().encode(provider) else {
            AppLogger.ai.error("AI credential encode failed", detail: "provider=\(provider.providerId)")
            return false
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            AppLogger.ai.info("AI credentials updated", detail: "provider=\(provider.providerId) model=\(provider.modelId) account=\(account)")
            return true
        }

        var attributes = query
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemDelete(query as CFDictionary)
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus == errSecSuccess {
            AppLogger.ai.info("AI credentials saved", detail: "provider=\(provider.providerId) model=\(provider.modelId) account=\(account)")
            return true
        } else {
            AppLogger.ai.error("AI credential save failed", detail: "provider=\(provider.providerId) account=\(account) status=\(addStatus)")
            return false
        }
    }

    private func load(account: String) -> CachedComposeProvider? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(CachedComposeProvider.self, from: data)
    }

    private func account(for providerId: String) -> String {
        "provider-\(providerId)"
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CachedComposeProvider: Codable {
    let providerId: String
    let providerName: String
    let modelId: String
    let apiKey: String
    let assistantPrompt: String
    let fallbackReason: String?
    let updatedAt: Date

    init(provider: ComposeBorrowedProvider, updatedAt: Date) {
        self.providerId = provider.providerId
        self.providerName = provider.providerName
        self.modelId = provider.modelId
        self.apiKey = provider.apiKey
        self.assistantPrompt = provider.assistantPrompt
        self.fallbackReason = provider.fallbackReason
        self.updatedAt = updatedAt
    }

    func borrowedProvider(modelId requestedModelId: String?) -> ComposeBorrowedProvider {
        ComposeBorrowedProvider(
            providerId: providerId,
            providerName: providerName,
            modelId: requestedModelId ?? modelId,
            apiKey: apiKey,
            assistantPrompt: assistantPrompt,
            fallbackReason: fallbackReason
        )
    }
}
