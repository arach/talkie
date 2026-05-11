//
//  SSHPrivateKeyParser.swift
//  Talkie iOS
//
//  Parses PEM private keys into the key types supported by SwiftNIO SSH.
//

import CryptoKit
import Foundation
@preconcurrency import NIOSSH

enum SSHPrivateKeyParser {
    static func parse(_ pemRepresentation: String) throws -> NIOSSHPrivateKey {
        let normalized = pemRepresentation.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.isEmpty {
            throw SSHClientError.authenticationRequired
        }

        if normalized.localizedCaseInsensitiveContains("BEGIN OPENSSH PRIVATE KEY") {
            return try parseOpenSSHPrivateKey(normalized)
        }

        if normalized.localizedCaseInsensitiveContains("BEGIN RSA PRIVATE KEY") {
            throw SSHClientError.unsupportedPrivateKeyType("RSA private keys aren't supported by this SSH client yet.")
        }

        if let key = try? P256.Signing.PrivateKey(pemRepresentation: normalized) {
            return NIOSSHPrivateKey(p256Key: key)
        }

        if let key = try? P384.Signing.PrivateKey(pemRepresentation: normalized) {
            return NIOSSHPrivateKey(p384Key: key)
        }

        if let key = try? P521.Signing.PrivateKey(pemRepresentation: normalized) {
            return NIOSSHPrivateKey(p521Key: key)
        }

        throw SSHClientError.unsupportedPrivateKeyType(
            "Paste an unencrypted OpenSSH Ed25519 key or a PEM-formatted P256, P384, or P521 private key."
        )
    }

    private static func parseOpenSSHPrivateKey(_ pemRepresentation: String) throws -> NIOSSHPrivateKey {
        let base64Payload = pemRepresentation
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()

        guard let data = Data(base64Encoded: base64Payload) else {
            throw SSHClientError.unsupportedPrivateKeyType("The OpenSSH private key couldn't be decoded.")
        }

        var reader = OpenSSHReader(data: data)
        let magic = try reader.readCString()
        guard magic == "openssh-key-v1" else {
            throw SSHClientError.unsupportedPrivateKeyType("The OpenSSH private key header is invalid.")
        }

        let cipherName = try reader.readString()
        let kdfName = try reader.readString()
        _ = try reader.readData()
        let keyCount = try reader.readUInt32()

        guard cipherName == "none", kdfName == "none" else {
            throw SSHClientError.unsupportedPrivateKeyType("Encrypted OpenSSH private keys aren't supported yet.")
        }

        guard keyCount == 1 else {
            throw SSHClientError.unsupportedPrivateKeyType("Only single-key OpenSSH identities are supported.")
        }

        _ = try reader.readData()
        let privateSection = try reader.readData()

        return try parseOpenSSHPrivateSection(privateSection)
    }

    private static func parseOpenSSHPrivateSection(_ data: Data) throws -> NIOSSHPrivateKey {
        var reader = OpenSSHReader(data: data)
        let check1 = try reader.readUInt32()
        let check2 = try reader.readUInt32()

        guard check1 == check2 else {
            throw SSHClientError.unsupportedPrivateKeyType("The OpenSSH private key failed its integrity check.")
        }

        let keyType = try reader.readString()
        guard keyType == "ssh-ed25519" else {
            throw SSHClientError.unsupportedPrivateKeyType("Only OpenSSH Ed25519 private keys are supported right now.")
        }

        let publicKey = try reader.readData()
        let privateKeyBlob = try reader.readData()
        _ = try reader.readString()

        guard publicKey.count == 32, privateKeyBlob.count == 64 else {
            throw SSHClientError.unsupportedPrivateKeyType("The Ed25519 key payload is malformed.")
        }

        let privateSeed = privateKeyBlob.prefix(32)
        let expectedPublicKey = privateKeyBlob.suffix(32)
        let signingKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateSeed)

        guard Data(expectedPublicKey) == signingKey.publicKey.rawRepresentation,
              publicKey == signingKey.publicKey.rawRepresentation else {
            throw SSHClientError.unsupportedPrivateKeyType("The Ed25519 key data didn't match its public key.")
        }

        return NIOSSHPrivateKey(ed25519Key: signingKey)
    }
}

private struct OpenSSHReader {
    private let data: Data
    private var offset = 0

    init(data: Data) {
        self.data = data
    }

    mutating func readCString() throws -> String {
        guard let terminator = data[offset...].firstIndex(of: 0) else {
            throw SSHClientError.unsupportedPrivateKeyType("The OpenSSH key is missing its magic header terminator.")
        }

        let valueData = data[offset..<terminator]
        offset = terminator + 1

        guard let value = String(data: valueData, encoding: .utf8) else {
            throw SSHClientError.unsupportedPrivateKeyType("The OpenSSH key contains invalid UTF-8.")
        }

        return value
    }

    mutating func readString() throws -> String {
        let value = try readData()
        guard let string = String(data: value, encoding: .utf8) else {
            throw SSHClientError.unsupportedPrivateKeyType("The OpenSSH key contains invalid UTF-8.")
        }
        return string
    }

    mutating func readData() throws -> Data {
        let length = try Int(readUInt32())
        guard offset + length <= data.count else {
            throw SSHClientError.unsupportedPrivateKeyType("The OpenSSH key is truncated.")
        }

        let slice = data[offset..<(offset + length)]
        offset += length
        return Data(slice)
    }

    mutating func readUInt32() throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw SSHClientError.unsupportedPrivateKeyType("The OpenSSH key is truncated.")
        }

        let value = data[offset..<(offset + 4)].reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        offset += 4
        return value
    }
}
