//
//  AICredentialStore.swift
//  Talkie iOS
//
//  Keychain-backed storage for per-provider AI API keys.
//

import Combine
import Foundation
import Security

@MainActor
final class AICredentialStore: ObservableObject {
    static let shared = AICredentialStore()

    @Published private(set) var setProviderIDs: Set<String>

    private static var knownProviderIDs: Set<String> { AIProviderCatalog.ids }

    private let account = "api-key"

    private init() {
        setProviderIDs = Self.knownProviderIDs.filter { providerID in
            Self.storedKey(for: providerID) != nil
        }
    }

    /// One-time migration: the OpenAI key used to live in plaintext app config
    /// (`TalkieAppSettings.ttsApiKey`). Lift it into the Keychain so it surfaces
    /// in AI Keys and resolves like every other provider. No-op once an OpenAI
    /// key already exists in the Keychain.
    func migrateLegacyTTSKeyIfNeeded() {
        guard key(for: "openai") == nil else { return }

        let settings = TalkieAppSettings.shared
        let legacyKey = settings.ttsApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.ttsProvider == "openai",
              AIProviderCatalog.isValidKeyFormat(legacyKey, providerId: "openai") else { return }

        do {
            try set(legacyKey, for: "openai")
            AppLogger.ai.info("Migrated legacy TTS OpenAI key into the Keychain")
        } catch {
            AppLogger.ai.warning(
                "Legacy TTS key migration failed",
                detail: error.localizedDescription
            )
        }
    }

    func key(for providerID: String) -> String? {
        let providerID = normalizedProviderID(providerID)
        guard !providerID.isEmpty else { return nil }
        return Self.storedKey(for: providerID)
    }

    func set(_ key: String, for providerID: String) throws {
        let providerID = normalizedProviderID(providerID)
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !providerID.isEmpty else {
            throw AICredentialStoreError.invalidProviderID
        }
        guard !key.isEmpty else {
            try clear(providerID)
            return
        }

        let data = Data(key.utf8)
        let query = query(for: providerID)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)

        if updateStatus == errSecSuccess {
            setProviderIDs.insert(providerID)
            return
        }

        if updateStatus != errSecItemNotFound {
            throw AICredentialStoreError.keychainFailure(updateStatus)
        }

        var attributes = query
        attributes[kSecValueData] = data
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AICredentialStoreError.keychainFailure(addStatus)
        }

        setProviderIDs.insert(providerID)
    }

    func clear(_ providerID: String) throws {
        let providerID = normalizedProviderID(providerID)
        guard !providerID.isEmpty else {
            throw AICredentialStoreError.invalidProviderID
        }

        let status = SecItemDelete(query(for: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AICredentialStoreError.keychainFailure(status)
        }

        setProviderIDs.remove(providerID)
    }

    private static func storedKey(for providerID: String) -> String? {
        let providerID = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !providerID.isEmpty else { return nil }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service(for: providerID),
            kSecAttrAccount: "api-key",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            return nil
        }

        return key
    }

    private func query(for providerID: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service(for: providerID),
            kSecAttrAccount: account
        ]
    }

    private static func service(for providerID: String) -> String {
        "to.talkie.aikey.\(providerID)"
    }

    private func normalizedProviderID(_ providerID: String) -> String {
        providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum AICredentialStoreError: LocalizedError {
    case invalidProviderID
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidProviderID:
            return "Missing AI provider."
        case .keychainFailure(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}
