//
//  KeychainManager.swift
//  Talkie macOS
//
//  Secure storage for API keys using macOS Keychain
//

import Foundation
import Security
import os

private let logger = Logger(subsystem: "jdi.talkie.core", category: "Keychain")
/// Manages secure storage of API keys in the macOS Keychain
final class KeychainManager {
    static let shared = KeychainManager()

    private let service = "jdi.talkie.core"

    // Keychain item keys
    enum Key: String {
        case geminiApiKey = "gemini_api_key"
        case openaiApiKey = "openai_api_key"
        case anthropicApiKey = "anthropic_api_key"
        case groqApiKey = "groq_api_key"
    }

    private init() {}

    // MARK: - Public API

    /// Save a string value to Keychain
    func save(_ value: String, for key: Key) -> Bool {
        guard !value.isEmpty else {
            // Empty value means delete
            return delete(key)
        }

        guard let data = value.data(using: .utf8) else {
            logger.debug("KeychainManager: Failed to encode value for \(key.rawValue)")
            return false
        }

        // Try to update first, if item doesn't exist, add it
        let query = baseQuery(for: key)
        let updateAttributes: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if status == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        if status != errSecSuccess {
            logger.error("Failed to save \(key.rawValue), status: \(status)")
            return false
        }

        return true
    }

    /// Retrieve a string value from Keychain
    func retrieve(for key: Key) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                logger.error("Failed to retrieve \(key.rawValue), status: \(status)")
            }
            return nil
        }

        return string
    }

    /// Delete a value from Keychain
    @discardableResult
    func delete(_ key: Key) -> Bool {
        let query = baseQuery(for: key)
        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("Failed to delete \(key.rawValue), status: \(status)")
            return false
        }

        return true
    }

    /// Check if a key exists in Keychain
    func exists(_ key: Key) -> Bool {
        let query = baseQuery(for: key)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - Migration

    /// Migrate API keys from Core Data to Keychain
    /// Returns true if migration was performed (or no migration needed)
    func migrateFromCoreData(
        geminiKey: String?,
        openaiKey: String?,
        anthropicKey: String?,
        groqKey: String?,
        clearCoreData: @escaping () -> Void
    ) -> Bool {
        var migrated = false

        // Only migrate if Keychain is empty and Core Data has values
        if !exists(.geminiApiKey), let key = geminiKey, !key.isEmpty {
            if save(key, for: .geminiApiKey) {
                logger.info("Migrated Gemini API key to Keychain")
                migrated = true
            }
        }

        if !exists(.openaiApiKey), let key = openaiKey, !key.isEmpty {
            if save(key, for: .openaiApiKey) {
                logger.info("Migrated OpenAI API key to Keychain")
                migrated = true
            }
        }

        if !exists(.anthropicApiKey), let key = anthropicKey, !key.isEmpty {
            if save(key, for: .anthropicApiKey) {
                logger.info("Migrated Anthropic API key to Keychain")
                migrated = true
            }
        }

        if !exists(.groqApiKey), let key = groqKey, !key.isEmpty {
            if save(key, for: .groqApiKey) {
                logger.info("Migrated Groq API key to Keychain")
                migrated = true
            }
        }

        // Clear Core Data after successful migration
        if migrated {
            clearCoreData()
            logger.info("Migration complete, cleared Core Data API keys")
        }

        return true
    }

    // MARK: - Private

    private func baseQuery(for key: Key) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }
}
