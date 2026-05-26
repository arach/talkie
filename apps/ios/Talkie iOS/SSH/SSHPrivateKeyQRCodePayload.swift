//
//  SSHPrivateKeyQRCodePayload.swift
//  Talkie iOS
//
//  QR payload format for importing SSH private keys into the iOS terminal.
//

import Foundation

struct SSHPrivateKeyQRCodePayload: Codable, Equatable {
    static let protocolVersionV1 = "talkie-ssh-key-v1"
    static let protocolVersionV2 = "talkie-ssh-key-v2"

    struct Connection: Codable, Equatable {
        let host: String
        let port: Int
        let username: String
        let startupProfileRawValue: String?
        let launcherModeRawValue: String?
        let startupCommand: String?
        let autoConnect: Bool?
        let alternateHosts: [String]?

        var normalizedHost: String {
            host.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var normalizedUsername: String {
            username.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var normalizedStartupCommand: String? {
            let command = startupCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return command.isEmpty ? nil : command
        }

        var normalizedAlternateHosts: [String] {
            var seen: Set<String> = [normalizedHost.lowercased()]
            var hosts: [String] = []

            for alternateHost in alternateHosts ?? [] {
                let host = alternateHost.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = host.lowercased()
                guard !host.isEmpty,
                      !seen.contains(normalized),
                      normalized != "localhost",
                      normalized != "127.0.0.1",
                      normalized != "::1" else {
                    continue
                }

                seen.insert(normalized)
                hosts.append(host)
            }

            return hosts
        }

        var resolvedStartupCommand: String? {
            if let normalizedStartupCommand {
                return normalizedStartupCommand
            }

            switch launcherModeRawValue?.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "pairedHome":
                return SSHTerminalStartupProfile.pairedHomeLauncherCommand()
            case "native", "nativeShell", "nativeSession":
                return SSHTerminalStartupProfile.nativeLauncherCommand()
            default:
                return nil
            }
        }

        var startupProfile: SSHTerminalStartupProfile {
            guard let startupProfileRawValue else {
                return .standardShell
            }

            return SSHTerminalStartupProfile(rawValue: startupProfileRawValue) ?? .standardShell
        }

        var shouldAutoConnect: Bool {
            autoConnect ?? false
        }
    }

    let `protocol`: String
    let label: String?
    let privateKey: String
    let connection: Connection?

    init(label: String? = nil, privateKey: String, connection: Connection? = nil) {
        self.protocol = Self.protocolVersionV2
        self.label = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.privateKey = privateKey
        self.connection = connection
    }

    var normalizedPrivateKey: String {
        privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode(from scannedCode: String) async throws -> SSHPrivateKeyQRCodePayload {
        let normalizedCode = scannedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else {
            throw SSHClientError.invalidKeyQRCode
        }

        if let deepLinkPayload = deepLinkPayload(from: normalizedCode) {
            return try await decode(from: deepLinkPayload)
        }

        if let data = normalizedCode.data(using: .utf8) {
            if let payload = try? JSONDecoder().decode(Self.self, from: data) {
                return try validated(payload)
            }
        }

        guard normalizedCode.localizedCaseInsensitiveContains("BEGIN"),
              normalizedCode.localizedCaseInsensitiveContains("PRIVATE KEY") else {
            throw SSHClientError.invalidKeyQRCode
        }

        return Self(privateKey: normalizedCode)
    }

    private static func deepLinkPayload(from code: String) -> String? {
        guard
            let url = URL(string: code),
            url.scheme == "talkie",
            url.host == "ssh"
        else {
            return nil
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard components?.path == "/import-key" else {
            return nil
        }

        return components?.queryItems?.first(where: { $0.name == "payload" })?.value
    }

    private static func validated(_ payload: SSHPrivateKeyQRCodePayload) throws -> SSHPrivateKeyQRCodePayload {
        guard payload.protocol == Self.protocolVersionV1 || payload.protocol == Self.protocolVersionV2 else {
            throw SSHClientError.invalidKeyQRCode
        }

        guard !payload.normalizedPrivateKey.isEmpty else {
            throw SSHClientError.invalidKeyQRCode
        }

        return payload
    }
}
