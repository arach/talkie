//
//  SSHKnownHostStore.swift
//  Talkie iOS
//
//  Minimal trust-on-first-use storage for remote SSH host keys.
//

import CryptoKit
import Foundation
@preconcurrency import NIOSSH

enum SSHKnownHostStore {
    enum ValidationResult: Equatable, Sendable {
        case trusted(fingerprint: String)
        case trustedOnFirstUse(fingerprint: String)
        case mismatch(expected: String, actual: String)
    }

    static let defaultsKey = "sshTerminal.knownHosts"

    static func validate(hostKey: NIOSSHPublicKey, host: String, port: Int) -> ValidationResult {
        let knownHostKey = key(for: host, port: port)
        let openSSH = String(openSSHPublicKey: hostKey)
        let actualFingerprint = fingerprint(forOpenSSHPublicKey: openSSH)
        var knownHosts = TalkieAppConfigurationStore.shared.configuration.ssh.knownHosts

        if let trustedKey = knownHosts[knownHostKey] {
            let expectedFingerprint = fingerprint(forOpenSSHPublicKey: trustedKey)
            if trustedKey == openSSH {
                return .trusted(fingerprint: actualFingerprint)
            }

            return .mismatch(expected: expectedFingerprint, actual: actualFingerprint)
        }

        knownHosts[knownHostKey] = openSSH
        TalkieAppConfigurationStore.shared.update { configuration in
            configuration.ssh.knownHosts = knownHosts
        }
        UserDefaults.standard.set(knownHosts, forKey: defaultsKey)
        return .trustedOnFirstUse(fingerprint: actualFingerprint)
    }

    private static func key(for host: String, port: Int) -> String {
        "\(host.lowercased()):\(port)"
    }

    private static func fingerprint(forOpenSSHPublicKey publicKey: String) -> String {
        let components = publicKey.split(separator: " ")
        guard components.count >= 2,
              let data = Data(base64Encoded: String(components[1])) else {
            return "SHA256:unavailable"
        }

        let digest = SHA256.hash(data: data)
        return "SHA256:\(Data(digest).base64EncodedString())"
    }
}
