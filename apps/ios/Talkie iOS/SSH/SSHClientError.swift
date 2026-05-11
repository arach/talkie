//
//  SSHClientError.swift
//  Talkie iOS
//
//  Errors surfaced by the iOS SSH terminal client.
//

import Foundation

enum SSHClientError: LocalizedError {
    case authenticationRequired
    case invalidPort
    case invalidKeyQRCode
    case securePairingUnavailable
    case passwordAuthenticationUnavailable
    case privateKeyAuthenticationUnavailable
    case supportedAuthenticationMethodsUnavailable
    case unsupportedPrivateKeyType(String)
    case invalidChannelType
    case hostKeyMismatch(expected: String, actual: String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "Enter a password or private key."
        case .invalidPort:
            "Enter a valid SSH port."
        case .invalidKeyQRCode:
            "That QR code doesn't contain a Talkie SSH key payload."
        case .securePairingUnavailable:
            "This secure pairing code couldn't be decrypted. Make sure this iPhone is signed into the same iCloud account as your Mac."
        case .passwordAuthenticationUnavailable:
            "The server did not offer password authentication."
        case .privateKeyAuthenticationUnavailable:
            "The server did not offer private-key authentication."
        case .supportedAuthenticationMethodsUnavailable:
            "The server did not offer a supported authentication method."
        case .unsupportedPrivateKeyType(let message):
            message
        case .invalidChannelType:
            "The SSH server returned an unexpected channel type."
        case .hostKeyMismatch(let expected, let actual):
            "Host key mismatch. Expected \(expected), got \(actual)."
        case .disconnected:
            "The SSH session is disconnected."
        }
    }
}
