//
//  TalkieAIProviderCredentialSetupInvite.swift
//  Talkie iOS
//
//  One-time local Wi-Fi transaction invite for importing phone-owned AI credentials.
//

import Foundation
import Network

struct TalkieAIProviderCredentialSetupInvite: Codable, Equatable {
    let endpointURL: URL
    let sessionId: String
    let serverPublicKey: String
    let providerId: String?
    let modelId: String?
    let expiresAt: Date?

    private enum CodingKeys: String, CodingKey {
        case payloadProtocol = "protocol"
        case endpointURL = "url"
        case sessionId
        case serverPublicKey
        case providerId
        case modelId
        case expiresAt
    }

    init(
        endpointURL: URL,
        sessionId: String,
        serverPublicKey: String,
        providerId: String? = nil,
        modelId: String? = nil,
        expiresAt: Date? = nil
    ) {
        self.endpointURL = endpointURL
        self.sessionId = sessionId
        self.serverPublicKey = serverPublicKey
        self.providerId = providerId
        self.modelId = modelId
        self.expiresAt = expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let payloadProtocol = try container.decode(String.self, forKey: .payloadProtocol)
        guard payloadProtocol == Self.payloadProtocol else {
            throw DecodingError.dataCorruptedError(
                forKey: .payloadProtocol,
                in: container,
                debugDescription: "Unsupported AI setup QR protocol."
            )
        }

        let endpointURL = try container.decode(URL.self, forKey: .endpointURL)
        let sessionId = try container.decode(String.self, forKey: .sessionId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let serverPublicKey = try container.decode(String.self, forKey: .serverPublicKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard endpointURL.scheme == "http",
              !sessionId.isEmpty,
              Data(base64Encoded: serverPublicKey) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .endpointURL,
                in: container,
                debugDescription: "AI setup QR transaction invite is invalid."
            )
        }

        guard let host = endpointURL.host, Self.isLocalNetworkHost(host) else {
            throw DecodingError.dataCorruptedError(
                forKey: .endpointURL,
                in: container,
                debugDescription: "AI setup QR endpoint must be on the local network."
            )
        }

        self.endpointURL = endpointURL
        self.sessionId = sessionId
        self.serverPublicKey = serverPublicKey
        self.providerId = try container.decodeIfPresent(String.self, forKey: .providerId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        self.modelId = try container.decodeIfPresent(String.self, forKey: .modelId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        self.expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.payloadProtocol, forKey: .payloadProtocol)
        try container.encode(endpointURL, forKey: .endpointURL)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(serverPublicKey, forKey: .serverPublicKey)
        try container.encodeIfPresent(providerId, forKey: .providerId)
        try container.encodeIfPresent(modelId, forKey: .modelId)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }

    static let payloadProtocol = "talkie-ai-setup-v1"

    private static func isLocalNetworkHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !trimmed.isEmpty else { return false }

        let lowercased = trimmed.lowercased()
        if lowercased.hasSuffix(".local") || lowercased.hasSuffix(".local.") {
            return true
        }

        if let ipv4 = IPv4Address(trimmed) {
            return isLocalIPv4(ipv4)
        }

        // Strip a possible zone identifier (e.g. fe80::1%en0) before parsing IPv6.
        let ipv6Candidate: String
        if let percentIndex = trimmed.firstIndex(of: "%") {
            ipv6Candidate = String(trimmed[..<percentIndex])
        } else {
            ipv6Candidate = trimmed
        }
        if let ipv6 = IPv6Address(ipv6Candidate) {
            return isLocalIPv6(ipv6)
        }

        return false
    }

    private static func isLocalIPv4(_ address: IPv4Address) -> Bool {
        let bytes = address.rawValue
        guard bytes.count == 4 else { return false }
        let b0 = bytes[0]
        let b1 = bytes[1]

        // 10.0.0.0/8
        if b0 == 10 { return true }
        // 172.16.0.0/12
        if b0 == 172, (16...31).contains(b1) { return true }
        // 192.168.0.0/16
        if b0 == 192, b1 == 168 { return true }
        // 169.254.0.0/16 (link-local)
        if b0 == 169, b1 == 254 { return true }
        // 127.0.0.0/8 (loopback)
        if b0 == 127 { return true }

        return false
    }

    private static func isLocalIPv6(_ address: IPv6Address) -> Bool {
        if address == IPv6Address.loopback { return true }
        let bytes = address.rawValue
        guard bytes.count == 16 else { return false }

        // fe80::/10 — first 10 bits are 1111 1110 10
        if bytes[0] == 0xfe, (bytes[1] & 0xC0) == 0x80 { return true }
        // fc00::/7 — first 7 bits are 1111 110
        if (bytes[0] & 0xFE) == 0xFC { return true }

        return false
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
