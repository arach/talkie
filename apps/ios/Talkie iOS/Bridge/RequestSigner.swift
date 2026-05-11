//
//  RequestSigner.swift
//  Talkie iOS
//
//  HMAC-SHA256 request signing for authenticated API calls.
//  Uses HKDF-derived auth key separate from encryption key.
//

import Foundation
import CryptoKit

/// Signs HTTP requests with HMAC-SHA256 for authentication
struct RequestSigner {
    let deviceId: String
    let authKey: SymmetricKey

    /// Sign a request by adding auth headers
    /// - Parameters:
    ///   - request: The URLRequest to sign (modified in place)
    ///   - serverTime: Current server time (for clock sync)
    func sign(_ request: inout URLRequest, serverTime: Int) {
        let timestamp = String(serverTime)
        let nonce = generateNonce()
        let method = request.httpMethod ?? "GET"

        // Build path with query string
        let pathWithQuery: String
        if let url = request.url {
            var path = url.path
            if path.isEmpty { path = "/" }
            if let query = url.query, !query.isEmpty {
                path += "?\(query)"
            }
            pathWithQuery = path
        } else {
            pathWithQuery = "/"
        }

        // Hash the body (empty body = hash of zero bytes)
        let bodyData = request.httpBody ?? Data()
        let bodyHash = SHA256.hash(data: bodyData)
            .map { String(format: "%02x", $0) }
            .joined()

        // Build message to sign: method\npath\ntimestamp\nnonce\nbodyHash
        let message = "\(method)\n\(pathWithQuery)\n\(timestamp)\n\(nonce)\n\(bodyHash)"

        // Compute HMAC signature
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: authKey
        ).map { String(format: "%02x", $0) }.joined()

        // Add auth headers
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-ID")
        request.setValue(timestamp, forHTTPHeaderField: "X-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-Nonce")
        request.setValue(signature, forHTTPHeaderField: "X-Signature")
    }

    /// Generate a unique nonce for replay protection
    /// Format: timestamp_randomHex (e.g., "1704456789_a1b2c3d4")
    private func generateNonce() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomBytes = (0..<8).map { _ in UInt8.random(in: 0...255) }
        let randomHex = randomBytes.map { String(format: "%02x", $0) }.joined()
        return "\(timestamp)_\(randomHex)"
    }
}

// MARK: - HKDF Key Derivation

extension SharedSecret {
    /// Derive the HMAC auth key using HKDF
    /// Must use identical parameters to bridge server
    func deriveAuthKey() -> SymmetricKey {
        hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(count: 32),  // 32 zero bytes
            sharedInfo: "talkie-bridge-auth".data(using: .utf8)!,
            outputByteCount: 32
        )
    }

    /// Derive the AES-GCM encryption key using HKDF
    /// Must use identical parameters to bridge server
    func deriveEncryptionKey() -> SymmetricKey {
        hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(count: 32),  // 32 zero bytes
            sharedInfo: "talkie-bridge-encrypt".data(using: .utf8)!,
            outputByteCount: 32
        )
    }
}
