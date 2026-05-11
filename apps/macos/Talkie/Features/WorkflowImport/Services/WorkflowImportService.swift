//
//  WorkflowImportService.swift
//  Talkie
//
//  Fetches and validates workflow payloads from URLs.
//  Supports encrypted payloads with passphrase decryption.
//

import Foundation
import CryptoKit
import TalkieKit

private let log = Log(.workflow)

// MARK: - Import Errors

enum WorkflowImportError: LocalizedError {
    case invalidUrl
    case networkError(Error)
    case claimExpired
    case claimNotFound
    case invalidPayload(String)
    case unsupportedVersion(Int)
    case decryptionFailed
    case invalidPassphrase

    var errorDescription: String? {
        switch self {
        case .invalidUrl:
            return "Invalid import URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .claimExpired:
            return "This link has expired or was already used"
        case .claimNotFound:
            return "Invalid link"
        case .invalidPayload(let reason):
            return "Invalid workflow: \(reason)"
        case .unsupportedVersion(let version):
            return "Unsupported workflow version: \(version)"
        case .decryptionFailed:
            return "Failed to decrypt. Check your passphrase."
        case .invalidPassphrase:
            return "Invalid passphrase"
        }
    }
}

// MARK: - Encrypted Payload

/// Response from import URL - may be encrypted or plain
struct ImportResponse: Codable {
    let encrypted: Bool
    let payload: String?              // Base64 encrypted data (if encrypted)
    let salt: String?                 // Base64 salt for key derivation
    let nonce: String?                // Base64 nonce for decryption
    let data: ImportedWorkflowPayload? // Plain payload (if not encrypted)
}

// MARK: - Import Service

actor WorkflowImportService {

    static let shared = WorkflowImportService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Import from URL

    /// Import a workflow from a URL (e.g., tawkie.dev/import/xxx)
    /// Returns a core WorkflowDefinition that can be saved via WorkflowFileRepository
    /// - Parameters:
    ///   - urlString: The import URL
    ///   - passphrase: Passphrase for decryption (required if payload is encrypted)
    func importWorkflow(from urlString: String, passphrase: String?) async throws -> WorkflowDefinition {
        log.info("Importing workflow from: \(urlString)")

        guard let url = URL(string: urlString) else {
            throw WorkflowImportError.invalidUrl
        }

        // Fetch the response (may be encrypted)
        let importResponse = try await fetchImportResponse(from: url)

        // Decrypt or use plain payload
        let payload: ImportedWorkflowPayload
        if importResponse.encrypted {
            guard let passphrase = passphrase, !passphrase.isEmpty else {
                throw WorkflowImportError.invalidPassphrase
            }
            payload = try decrypt(importResponse, passphrase: passphrase)
        } else if let plainPayload = importResponse.data {
            payload = plainPayload
        } else {
            throw WorkflowImportError.invalidPayload("No payload data")
        }

        // Validate version
        guard payload.version == 1 else {
            throw WorkflowImportError.unsupportedVersion(payload.version)
        }

        // Validate required fields
        try validatePayload(payload)

        // Convert to core WorkflowDefinition
        let result = try ImportPayloadConverter.convert(payload, sourceUrl: url)

        // Store credentials securely
        for credential in result.credentials {
            if let secret = result.secrets[credential.id] {
                try await CredentialStore.shared.store(credential, secret: secret)
            }
        }

        log.info("Successfully imported workflow: \(result.workflow.name)")
        return result.workflow
    }

    /// Import a workflow and get the legacy StoredWorkflow format (for migration compatibility)
    @available(*, deprecated, message: "Use importWorkflow(from:passphrase:) returning WorkflowDefinition instead")
    func importWorkflowLegacy(from urlString: String, passphrase: String?) async throws -> StoredWorkflow {
        log.info("Importing workflow (legacy) from: \(urlString)")

        guard let url = URL(string: urlString) else {
            throw WorkflowImportError.invalidUrl
        }

        // Fetch the response (may be encrypted)
        let importResponse = try await fetchImportResponse(from: url)

        // Decrypt or use plain payload
        let payload: ImportedWorkflowPayload
        if importResponse.encrypted {
            guard let passphrase = passphrase, !passphrase.isEmpty else {
                throw WorkflowImportError.invalidPassphrase
            }
            payload = try decrypt(importResponse, passphrase: passphrase)
        } else if let plainPayload = importResponse.data {
            payload = plainPayload
        } else {
            throw WorkflowImportError.invalidPayload("No payload data")
        }

        // Validate version
        guard payload.version == 1 else {
            throw WorkflowImportError.unsupportedVersion(payload.version)
        }

        // Validate required fields
        try validatePayload(payload)

        // Create stored workflow
        let stored = StoredWorkflow(
            id: UUID(),
            name: payload.name,
            icon: payload.icon ?? "paperplane.fill",
            description: payload.description,
            importedAt: Date(),
            sourceUrl: urlString,
            credentials: payload.credentials,
            workflow: payload.workflow
        )

        log.info("Successfully imported workflow (legacy): \(stored.name)")
        return stored
    }

    /// Check if a URL requires a passphrase (prefetch metadata)
    func requiresPassphrase(urlString: String) async throws -> Bool {
        guard let url = URL(string: urlString) else {
            throw WorkflowImportError.invalidUrl
        }

        // HEAD request or fetch and check
        let response = try await fetchImportResponse(from: url, checkOnly: true)
        return response.encrypted
    }

    // MARK: - Fetch Response

    private func fetchImportResponse(from url: URL, checkOnly: Bool = false) async throws -> ImportResponse {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if checkOnly {
            // Just check metadata, don't consume the claim
            request.setValue("true", forHTTPHeaderField: "X-Check-Only")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WorkflowImportError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkflowImportError.networkError(URLError(.badServerResponse))
        }

        // Handle error responses
        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            throw WorkflowImportError.claimNotFound
        case 410:
            throw WorkflowImportError.claimExpired
        default:
            throw WorkflowImportError.networkError(
                URLError(.badServerResponse, userInfo: [
                    NSLocalizedDescriptionKey: "Server returned \(httpResponse.statusCode)"
                ])
            )
        }

        // Decode response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode(ImportResponse.self, from: data)
        } catch {
            log.error("Failed to decode import response: \(error)")
            throw WorkflowImportError.invalidPayload(error.localizedDescription)
        }
    }

    // MARK: - Decryption

    private func decrypt(_ response: ImportResponse, passphrase: String) throws -> ImportedWorkflowPayload {
        guard let payloadBase64 = response.payload,
              let saltBase64 = response.salt,
              let nonceBase64 = response.nonce else {
            throw WorkflowImportError.invalidPayload("Missing encryption components")
        }

        guard let encryptedData = Data(base64Encoded: payloadBase64),
              let salt = Data(base64Encoded: saltBase64),
              let nonceData = Data(base64Encoded: nonceBase64) else {
            throw WorkflowImportError.invalidPayload("Invalid base64 encoding")
        }

        // Derive key from passphrase using PBKDF2
        let key = try deriveKey(from: passphrase, salt: salt)

        // Decrypt using AES-GCM
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: encryptedData.dropLast(16), tag: encryptedData.suffix(16))
            let decryptedData = try AES.GCM.open(sealedBox, using: key)

            // Decode payload
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ImportedWorkflowPayload.self, from: decryptedData)
        } catch {
            log.error("Decryption failed: \(error)")
            throw WorkflowImportError.decryptionFailed
        }
    }

    private func deriveKey(from passphrase: String, salt: Data) throws -> SymmetricKey {
        // Use PBKDF2-like key derivation via HKDF
        let passphraseData = Data(passphrase.utf8)
        let keyMaterial = SymmetricKey(data: passphraseData)

        // Derive a 256-bit key
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: keyMaterial,
            salt: salt,
            info: Data("tawkie-v1".utf8),
            outputByteCount: 32
        )

        return derivedKey
    }

    // MARK: - Validation

    private func validatePayload(_ payload: ImportedWorkflowPayload) throws {
        // Must have at least notify credentials for "send to agent" workflow
        if payload.workflow.type == .sendToAgent {
            guard payload.credentials.notify != nil else {
                throw WorkflowImportError.invalidPayload("Missing notification credentials")
            }
        }

        // Must have storage for upload workflows
        if payload.workflow.type == .sendToAgent || payload.workflow.type == .uploadOnly {
            guard payload.credentials.storage != nil else {
                throw WorkflowImportError.invalidPayload("Missing storage credentials")
            }
        }
    }
}

// MARK: - URL Scheme Handling

extension WorkflowImportService {

    /// Check if a URL is an import URL we handle
    static func isImportUrl(_ url: URL) -> Bool {
        // Handle talkie:// scheme
        if url.scheme == "talkie" {
            return url.host == "import" || url.host == "tawkie"
        }

        // Handle https:// from known domains
        if url.scheme == "https" {
            let knownDomains = ["tawkie.dev", "talkie.to"]
            if let host = url.host, knownDomains.contains(host) {
                return url.pathComponents.contains("claim")
            }
        }

        return false
    }

    /// Extract the claim URL from various formats
    static func normalizeImportUrl(_ url: URL) -> URL? {
        // talkie://import?url=https://tawkie.dev/claim/xxx
        if url.scheme == "talkie", url.host == "import" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let urlParam = components.queryItems?.first(where: { $0.name == "url" })?.value,
               let claimUrl = URL(string: urlParam) {
                return claimUrl
            }
        }

        // talkie://tawkie/connect?token=xxx → https://tawkie.dev/claim/xxx
        if url.scheme == "talkie", url.host == "tawkie" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
                return URL(string: "https://tawkie.dev/claim/\(token)")
            }
        }

        // Already a valid https:// claim URL
        if url.scheme == "https" {
            return url
        }

        return nil
    }
}
