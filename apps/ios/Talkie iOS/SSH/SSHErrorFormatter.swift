//
//  SSHErrorFormatter.swift
//  Talkie iOS
//
//  Converts low-level SSH and transport errors into user-facing copy.
//

import Darwin
import Foundation
import NIOCore

#if canImport(Network)
import Network
#endif

enum SSHErrorFormatter {
    static func message(for error: Error) -> String {
        if let clientError = error as? SSHClientError {
            return message(for: clientError)
        }

        if let channelError = error as? ChannelError {
            return message(for: channelError)
        }

        if let ioError = error as? IOError {
            return message(forPOSIXCode: ioError.errnoCode) ?? ioError.localizedDescription
        }

        #if canImport(Network)
        if let networkError = error as? NWError {
            return message(for: networkError)
        }
        #endif

        let nsError = error as NSError
        if let posixMessage = message(forNSError: nsError) {
            return posixMessage
        }

        let description = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty, description != "The operation couldn’t be completed." {
            return description
        }

        return "The SSH connection failed."
    }

    private static func message(for error: SSHClientError) -> String {
        switch error {
        case .invalidPort:
            "Enter a valid SSH port."
        case .authenticationRequired:
            "Enter a password or private key."
        case .invalidKeyQRCode:
            "That QR code doesn't contain a Talkie SSH key payload."
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
        case .hostKeyMismatch:
            "The server's host key does not match the one we already trust."
        case .disconnected:
            "The SSH session is disconnected."
        }
    }

    private static func message(for error: ChannelError) -> String {
        switch error {
        case .connectPending:
            "A connection attempt is already in progress."
        case .connectTimeout:
            "The SSH connection timed out."
        case .operationUnsupported:
            "This connection can't open an SSH session."
        case .ioOnClosedChannel, .alreadyClosed, .outputClosed, .inputClosed, .eof:
            "The SSH connection closed unexpectedly."
        case .inappropriateOperationForState:
            "The SSH session entered an unexpected state."
        case .writeHostUnreachable:
            "The SSH host is unreachable."
        default:
            "The SSH connection failed."
        }
    }

    #if canImport(Network)
    private static func message(for error: NWError) -> String {
        switch error {
        case .dns:
            return "The host name couldn't be resolved."
        case .tls:
            return "A secure transport error blocked the SSH connection."
        case .wifiAware:
            return "This network path doesn't support SSH right now."
        case .posix(let code):
            return message(forPOSIXCode: Int32(code.rawValue)) ?? error.localizedDescription
        @unknown default:
            return "The network connection failed."
        }
    }
    #endif

    private static func message(forNSError error: NSError) -> String? {
        if error.domain == NSPOSIXErrorDomain {
            return message(forPOSIXCode: Int32(error.code))
        }

        return nil
    }

    private static func message(forPOSIXCode code: CInt) -> String? {
        switch code {
        case ECONNABORTED:
            "The network connection was aborted."
        case ECONNREFUSED:
            "The server refused the connection. Check the host and port."
        case ETIMEDOUT:
            "The SSH connection timed out."
        case EHOSTUNREACH:
            "The host is unreachable from this device."
        case ENETUNREACH:
            "The network is unreachable from this device."
        case ECONNRESET:
            "The server reset the SSH connection."
        case ENOTCONN, EPIPE:
            "The SSH connection closed unexpectedly."
        default:
            nil
        }
    }
}
