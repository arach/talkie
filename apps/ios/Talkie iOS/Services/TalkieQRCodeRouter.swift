//
//  TalkieQRCodeRouter.swift
//  Talkie iOS
//
//  Identifies Talkie QR payload families so scanner surfaces can route
//  users to the right flow instead of failing with the wrong expectation.
//

import Foundation

enum TalkieQRCodeRoute {
    case bridge(QRCodeData)
    case sshPayload(rawCode: String, payload: SSHPrivateKeyQRCodePayload)
    case aiProviderCredential(TalkieAIProviderCredentialPayload)
    case aiProviderCredentialSetup(TalkieAIProviderCredentialSetupInvite)
    case talkieURL(URL)
}

enum TalkieQRCodeRouter {
    static func route(scannedCode: String) async throws -> TalkieQRCodeRoute {
        let trimmedCode = scannedCode.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmedCode), url.scheme == "talkie" {
            if let payload = TalkieAIProviderCredentialPayload.from(url: url) {
                return .aiProviderCredential(payload)
            }
            return .talkieURL(url)
        }

        if let data = trimmedCode.data(using: .utf8),
           let payload = try? JSONDecoder().decode(TalkieAIProviderCredentialPayload.self, from: data) {
            return .aiProviderCredential(payload)
        }

        if let data = trimmedCode.data(using: .utf8),
           let invite = try? JSONDecoder().decode(TalkieAIProviderCredentialSetupInvite.self, from: data) {
            return .aiProviderCredentialSetup(invite)
        }

        if let data = trimmedCode.data(using: .utf8),
           let qrData = try? JSONDecoder().decode(QRCodeData.self, from: data),
           qrData.protocol == "talkie-bridge-v1" {
            return .bridge(qrData)
        }

        if let payload = try? await SSHPrivateKeyQRCodePayload.decode(from: trimmedCode) {
            return .sshPayload(rawCode: trimmedCode, payload: payload)
        }

        throw TalkieQRCodeRouterError.unrecognizedCode
    }

    static func makeSSHImportURL(from rawPayload: String) -> URL? {
        var components = URLComponents()
        components.scheme = "talkie"
        components.host = "ssh"
        components.path = "/import-key"
        components.queryItems = [
            URLQueryItem(name: "payload", value: rawPayload)
        ]
        return components.url
    }
}

enum TalkieQRCodeRouterError: LocalizedError {
    case unrecognizedCode

    var errorDescription: String? {
        switch self {
        case .unrecognizedCode:
            return "This QR code isn't recognized by Talkie."
        }
    }
}
