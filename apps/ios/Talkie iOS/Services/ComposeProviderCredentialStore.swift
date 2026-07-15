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

    private let readData: (String) -> Data?
    private let writeData: (Data, String) -> OSStatus
    private let removeData: (String) -> OSStatus
    private let lastProviderAccount = "last-provider"

    init(service: String = "to.talkie.compose-provider") {
        self.readData = { account in
            Self.readKeychainData(service: service, account: account)
        }
        self.writeData = { data, account in
            Self.writeKeychainData(data, service: service, account: account)
        }
        self.removeData = { account in
            Self.removeKeychainData(service: service, account: account)
        }
    }

    init(
        readData: @escaping (String) -> Data?,
        writeData: @escaping (Data, String) -> OSStatus,
        removeData: @escaping (String) -> OSStatus
    ) {
        self.readData = readData
        self.writeData = writeData
        self.removeData = removeData
    }

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
        if let providerId = normalized(providerId) {
            guard let provider = load(account: account(for: providerId)) else {
                return nil
            }
            return provider.borrowedProvider(modelId: normalized(modelId))
        }

        return load(account: lastProviderAccount)?.borrowedProvider(modelId: normalized(modelId))
    }

    func deleteAll() {
        // Cover every catalog provider — a hardcoded openai/groq pair used to
        // leave Anthropic/OpenRouter keys behind in the Keychain on "clear".
        let accounts = [lastProviderAccount] + AIProviderCatalog.ids.map { account(for: $0) }
        for account in accounts {
            let status = removeData(account)
            if status != errSecSuccess && status != errSecItemNotFound {
                AppLogger.ai.warning("AI credential delete failed", detail: "account=\(account) status=\(status)")
            }
        }
        AppLogger.ai.info("AI credentials cleared")
    }

    func delete(providerId: String) {
        guard let providerId = normalized(providerId) else { return }
        delete(account: account(for: providerId))

        if load(account: lastProviderAccount)?.providerId == providerId {
            delete(account: lastProviderAccount)
        }
    }

    private func save(_ provider: CachedComposeProvider, account: String) -> Bool {
        guard let data = try? JSONEncoder().encode(provider) else {
            AppLogger.ai.error("AI credential encode failed", detail: "provider=\(provider.providerId)")
            return false
        }

        let status = writeData(data, account)
        if status == errSecSuccess {
            AppLogger.ai.info("AI credentials updated", detail: "provider=\(provider.providerId) model=\(provider.modelId) account=\(account)")
            return true
        }

        AppLogger.ai.error("AI credential save failed", detail: "provider=\(provider.providerId) account=\(account) status=\(status)")
        return false
    }

    private func load(account: String) -> CachedComposeProvider? {
        guard let data = readData(account) else { return nil }
        return try? JSONDecoder().decode(CachedComposeProvider.self, from: data)
    }

    private func delete(account: String) {
        let status = removeData(account)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.ai.warning("AI credential delete failed", detail: "account=\(account) status=\(status)")
        }
    }

    private static func readKeychainData(service: String, account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else {
            return nil
        }
        return item as? Data
    }

    private static func writeKeychainData(_ data: Data, service: String, account: String) -> OSStatus {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return updateStatus }
        guard updateStatus == errSecItemNotFound else { return updateStatus }

        var attributes = query
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func removeKeychainData(service: String, account: String) -> OSStatus {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        return SecItemDelete(query as CFDictionary)
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
