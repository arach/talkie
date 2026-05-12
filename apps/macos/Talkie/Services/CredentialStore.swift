//
//  CredentialStore.swift
//  Talkie
//
//  Secure storage for workflow credentials in Keychain.
//  Credentials are referenced by UUID and support scoped permissions.
//

import Foundation
import Security
import TalkieKit

private let log = Log(.workflow)

// MARK: - Credential Types

/// A securely stored credential with metadata
struct SecureCredential: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: CredentialType
    let scope: CredentialScope
    let createdAt: Date
    let importSource: URL?

    init(
        id: UUID = UUID(),
        name: String,
        type: CredentialType,
        scope: CredentialScope = CredentialScope(),
        createdAt: Date = Date(),
        importSource: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.scope = scope
        self.createdAt = createdAt
        self.importSource = importSource
    }
}

/// Type of credential with associated secret data
enum CredentialType: Codable {
    case awsSigningKey(accessKeyId: String)      // secretAccessKey stored separately
    case bearerToken                              // Token stored separately
    case apiKey                                   // Key stored separately
    case telegramBot(chatId: String)             // botToken stored separately
    case discordWebhook                           // webhookUrl stored separately
    case convexDeployKey(url: String)            // deployKey stored separately

    var displayName: String {
        switch self {
        case .awsSigningKey: return "AWS Signing Key"
        case .bearerToken: return "Bearer Token"
        case .apiKey: return "API Key"
        case .telegramBot: return "Telegram Bot"
        case .discordWebhook: return "Discord Webhook"
        case .convexDeployKey: return "Convex Deploy Key"
        }
    }

    var icon: String {
        switch self {
        case .awsSigningKey: return "cloud.fill"
        case .bearerToken: return "key.fill"
        case .apiKey: return "key.horizontal.fill"
        case .telegramBot: return "paperplane.fill"
        case .discordWebhook: return "bubble.left.fill"
        case .convexDeployKey: return "server.rack"
        }
    }

    // Custom Codable for associated values
    private enum CodingKeys: String, CodingKey {
        case type, accessKeyId, chatId, url
    }

    private enum TypeKey: String, Codable {
        case awsSigningKey, bearerToken, apiKey, telegramBot, discordWebhook, convexDeployKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeKey = try container.decode(TypeKey.self, forKey: .type)

        switch typeKey {
        case .awsSigningKey:
            let accessKeyId = try container.decode(String.self, forKey: .accessKeyId)
            self = .awsSigningKey(accessKeyId: accessKeyId)
        case .bearerToken:
            self = .bearerToken
        case .apiKey:
            self = .apiKey
        case .telegramBot:
            let chatId = try container.decode(String.self, forKey: .chatId)
            self = .telegramBot(chatId: chatId)
        case .discordWebhook:
            self = .discordWebhook
        case .convexDeployKey:
            let url = try container.decode(String.self, forKey: .url)
            self = .convexDeployKey(url: url)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .awsSigningKey(let accessKeyId):
            try container.encode(TypeKey.awsSigningKey, forKey: .type)
            try container.encode(accessKeyId, forKey: .accessKeyId)
        case .bearerToken:
            try container.encode(TypeKey.bearerToken, forKey: .type)
        case .apiKey:
            try container.encode(TypeKey.apiKey, forKey: .type)
        case .telegramBot(let chatId):
            try container.encode(TypeKey.telegramBot, forKey: .type)
            try container.encode(chatId, forKey: .chatId)
        case .discordWebhook:
            try container.encode(TypeKey.discordWebhook, forKey: .type)
        case .convexDeployKey(let url):
            try container.encode(TypeKey.convexDeployKey, forKey: .type)
            try container.encode(url, forKey: .url)
        }
    }
}

/// Restricts where a credential can be used
struct CredentialScope: Codable {
    let allowedHosts: [String]       // e.g., ["api.telegram.org", "*.convex.cloud"]
    let allowedMethods: [String]?    // e.g., ["POST"] (nil = any)
    let allowedPaths: [String]?      // e.g., ["/bot*/sendMessage"] (nil = any)

    init(
        allowedHosts: [String] = [],
        allowedMethods: [String]? = nil,
        allowedPaths: [String]? = nil
    ) {
        self.allowedHosts = allowedHosts
        self.allowedMethods = allowedMethods
        self.allowedPaths = allowedPaths
    }

    /// Check if a request is allowed by this scope
    func allows(host: String?, method: String?, path: String?) -> Bool {
        // Check host
        if !allowedHosts.isEmpty {
            guard let host = host else { return false }
            let hostMatches = allowedHosts.contains { pattern in
                matchesPattern(host, pattern: pattern)
            }
            if !hostMatches { return false }
        }

        // Check method
        if let allowedMethods = allowedMethods {
            guard let method = method else { return false }
            if !allowedMethods.contains(method.uppercased()) { return false }
        }

        // Check path
        if let allowedPaths = allowedPaths {
            guard let path = path else { return false }
            let pathMatches = allowedPaths.contains { pattern in
                matchesPattern(path, pattern: pattern)
            }
            if !pathMatches { return false }
        }

        return true
    }

    /// Simple glob-style pattern matching (* matches any sequence)
    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        if pattern == "*" { return true }

        // Handle wildcard at start (*.example.com)
        if pattern.hasPrefix("*") {
            let suffix = String(pattern.dropFirst())
            return string.hasSuffix(suffix)
        }

        // Handle wildcard in middle (e.g., /bot*/sendMessage)
        if pattern.contains("*") {
            let parts = pattern.components(separatedBy: "*")
            guard parts.count == 2 else { return string == pattern }
            return string.hasPrefix(parts[0]) && string.hasSuffix(parts[1])
        }

        // Exact match
        return string == pattern
    }

    // MARK: - Preset Scopes

    /// Scope for Telegram bot credentials
    static func telegram() -> CredentialScope {
        CredentialScope(
            allowedHosts: ["api.telegram.org"],
            allowedMethods: ["POST"],
            allowedPaths: ["/bot*/sendMessage", "/bot*/sendDocument", "/bot*/sendAudio"]
        )
    }

    /// Scope for Discord webhook credentials
    static func discord() -> CredentialScope {
        CredentialScope(
            allowedHosts: ["discord.com", "discordapp.com"],
            allowedMethods: ["POST"],
            allowedPaths: nil
        )
    }

    /// Scope for Convex deploy key
    static func convex(url: String) -> CredentialScope {
        guard let host = URL(string: url)?.host else {
            return CredentialScope(allowedHosts: ["*.convex.cloud"])
        }
        return CredentialScope(
            allowedHosts: [host],
            allowedMethods: ["POST"],
            allowedPaths: ["/api/*"]
        )
    }

    /// Scope for S3-compatible storage
    static func s3(endpoint: String?, region: String?) -> CredentialScope {
        if let endpoint = endpoint, let host = URL(string: endpoint)?.host {
            return CredentialScope(allowedHosts: [host], allowedMethods: ["PUT", "GET", "DELETE"])
        }
        if let region = region {
            return CredentialScope(
                allowedHosts: ["s3.\(region).amazonaws.com", "*.s3.\(region).amazonaws.com"],
                allowedMethods: ["PUT", "GET", "DELETE"]
            )
        }
        return CredentialScope(allowedHosts: ["*.amazonaws.com"], allowedMethods: ["PUT", "GET", "DELETE"])
    }
}

// MARK: - Credential Store

/// Manages secure storage of workflow credentials
actor CredentialStore {

    static let shared = CredentialStore()

    private let service = "to.talkie.app.credentials"
    private let metadataService = "to.talkie.app.credentials.metadata"

    private init() {}

    // MARK: - Store Credential

    /// Store a credential with its secret
    func store(_ credential: SecureCredential, secret: String) throws {
        // Store metadata
        let metadataData = try JSONEncoder().encode(credential)
        try storeData(metadataData, key: credential.id.uuidString, service: metadataService)

        // Store secret separately
        guard let secretData = secret.data(using: .utf8) else {
            throw CredentialStoreError.invalidSecret
        }
        try storeData(secretData, key: credential.id.uuidString, service: service)

        log.info("Stored credential: \(credential.name) (\(credential.id))")
    }

    /// Retrieve a credential's metadata
    func getCredential(id: UUID) -> SecureCredential? {
        guard let data = retrieveData(key: id.uuidString, service: metadataService) else {
            return nil
        }
        return try? JSONDecoder().decode(SecureCredential.self, from: data)
    }

    /// Retrieve a credential's secret
    func getSecret(id: UUID) -> String? {
        guard let data = retrieveData(key: id.uuidString, service: service) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieve a credential with validation against request scope
    func getSecret(id: UUID, for request: URLRequest) throws -> String {
        guard let credential = getCredential(id: id) else {
            throw CredentialStoreError.notFound(id)
        }

        // Validate scope
        guard credential.scope.allows(
            host: request.url?.host,
            method: request.httpMethod,
            path: request.url?.path
        ) else {
            throw CredentialStoreError.scopeViolation(
                credentialId: id,
                attemptedHost: request.url?.host ?? "unknown"
            )
        }

        guard let secret = getSecret(id: id) else {
            throw CredentialStoreError.notFound(id)
        }

        return secret
    }

    /// List all stored credentials
    func listCredentials() -> [SecureCredential] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: metadataService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }

        return items.compactMap { item -> SecureCredential? in
            guard let data = item[kSecValueData as String] as? Data else {
                return nil
            }
            return try? JSONDecoder().decode(SecureCredential.self, from: data)
        }
    }

    /// Delete a credential
    func delete(id: UUID) throws {
        // Delete secret
        try deleteItem(key: id.uuidString, service: service)
        // Delete metadata
        try deleteItem(key: id.uuidString, service: metadataService)

        log.info("Deleted credential: \(id)")
    }

    /// Check if a credential exists
    func exists(id: UUID) -> Bool {
        getCredential(id: id) != nil
    }

    // MARK: - Private Keychain Operations

    private func storeData(_ data: Data, key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            // Update existing
            let updateQuery: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, updateQuery as CFDictionary)
            if updateStatus != errSecSuccess {
                throw CredentialStoreError.saveFailed(updateStatus)
            }
        } else {
            // Add new
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw CredentialStoreError.saveFailed(addStatus)
            }
        }
    }

    private func retrieveData(key: String, service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }

        return data
    }

    private func deleteItem(key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw CredentialStoreError.deleteFailed(status)
        }
    }
}

// MARK: - Errors

enum CredentialStoreError: LocalizedError {
    case invalidSecret
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notFound(UUID)
    case scopeViolation(credentialId: UUID, attemptedHost: String)

    var errorDescription: String? {
        switch self {
        case .invalidSecret:
            return "Invalid credential secret"
        case .saveFailed(let status):
            return "Failed to save credential (error \(status))"
        case .deleteFailed(let status):
            return "Failed to delete credential (error \(status))"
        case .notFound(let id):
            return "Credential not found: \(id)"
        case .scopeViolation(let id, let host):
            return "Credential \(id) not allowed for host: \(host)"
        }
    }
}
