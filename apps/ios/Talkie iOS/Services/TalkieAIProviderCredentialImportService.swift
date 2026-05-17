//
//  TalkieAIProviderCredentialImportService.swift
//  Talkie iOS
//
//  Completes one-time local AI credential setup transactions.
//

import CryptoKit
import Foundation

struct TalkieAIProviderCredentialImportService {
    static let shared = TalkieAIProviderCredentialImportService()

    private init() { }

    func importCredentials(
        from invite: TalkieAIProviderCredentialSetupInvite
    ) async throws -> TalkieAIProviderCredentialPayload {
        if let expiresAt = invite.expiresAt, expiresAt < Date() {
            throw TalkieAIProviderCredentialImportError.expired
        }

        guard let serverPublicKeyData = Data(base64Encoded: invite.serverPublicKey) else {
            throw TalkieAIProviderCredentialImportError.invalidInvite
        }

        let clientPrivateKey = P256.KeyAgreement.PrivateKey()
        let serverPublicKey = try P256.KeyAgreement.PublicKey(x963Representation: serverPublicKeyData)
        let claim = ClaimRequest(
            sessionId: invite.sessionId,
            clientPublicKey: clientPrivateKey.publicKey.x963Representation.base64EncodedString()
        )

        var claimURL = invite.endpointURL
        claimURL.append(path: "talkie-ai/claim")

        var request = URLRequest(url: claimURL, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(claim)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TalkieAIProviderCredentialImportError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw TalkieAIProviderCredentialImportError.serverRejected(httpResponse.statusCode)
        }

        let encryptedResponse = try JSONDecoder().decode(ClaimResponse.self, from: data)
        guard encryptedResponse.payloadProtocol == ClaimResponse.expectedProtocol,
              let combinedData = Data(base64Encoded: encryptedResponse.ciphertext) else {
            throw TalkieAIProviderCredentialImportError.invalidResponse
        }

        let sharedSecret = try clientPrivateKey.sharedSecretFromKeyAgreement(with: serverPublicKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(invite.sessionId.utf8),
            sharedInfo: Data(TalkieAIProviderCredentialSetupInvite.payloadProtocol.utf8),
            outputByteCount: 32
        )
        let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: symmetricKey)
        let payload = try JSONDecoder().decode(TalkieAIProviderCredentialPayload.self, from: decryptedData)
        try await TalkieAIProviderCredentialValidator.shared.validate(payload)
        return payload
    }

    func reportCompletion(
        invite: TalkieAIProviderCredentialSetupInvite,
        success: Bool,
        message: String? = nil
    ) async {
        do {
            var completionURL = invite.endpointURL
            completionURL.append(path: "talkie-ai/complete")

            var request = URLRequest(url: completionURL, timeoutInterval: 8)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                CompletionRequest(
                    sessionId: invite.sessionId,
                    status: success ? "ok" : "failed",
                    message: message?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                )
            )

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                AppLogger.ai.warning("AI setup completion ack rejected")
                return
            }
        } catch {
            AppLogger.ai.warning("AI setup completion ack failed: \(error.localizedDescription)")
        }
    }
}

private struct ClaimRequest: Encodable {
    let sessionId: String
    let clientPublicKey: String

    private enum CodingKeys: String, CodingKey {
        case payloadProtocol = "protocol"
        case sessionId
        case clientPublicKey
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.payloadProtocol, forKey: .payloadProtocol)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(clientPublicKey, forKey: .clientPublicKey)
    }

    static let payloadProtocol = "talkie-ai-setup-claim-v1"
}

private struct ClaimResponse: Decodable {
    let payloadProtocol: String
    let ciphertext: String

    private enum CodingKeys: String, CodingKey {
        case payloadProtocol = "protocol"
        case ciphertext
    }

    static let expectedProtocol = "talkie-ai-setup-response-v1"
}

private struct CompletionRequest: Encodable {
    let sessionId: String
    let status: String
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case payloadProtocol = "protocol"
        case sessionId
        case status
        case message
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.payloadProtocol, forKey: .payloadProtocol)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(message, forKey: .message)
    }

    static let payloadProtocol = "talkie-ai-setup-complete-v1"
}

enum TalkieAIProviderCredentialImportError: LocalizedError {
    case expired
    case invalidInvite
    case invalidResponse
    case serverRejected(Int)
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .expired:
            return "This AI setup code has expired. Generate a fresh code from your Mac."
        case .invalidInvite:
            return "This AI setup code is not valid."
        case .invalidResponse:
            return "The AI setup response could not be read."
        case .serverRejected(let statusCode):
            return "The AI setup transaction was rejected by your Mac. HTTP \(statusCode)."
        case .saveFailed:
            return "Talkie couldn't save these AI credentials. Try again."
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
