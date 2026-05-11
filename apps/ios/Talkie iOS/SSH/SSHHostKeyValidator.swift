//
//  SSHHostKeyValidator.swift
//  Talkie iOS
//
//  Validates SSH server host keys using trust-on-first-use semantics.
//

import NIOCore
@preconcurrency import NIOSSH

final class SSHHostKeyValidator: NIOSSHClientServerAuthenticationDelegate, @unchecked Sendable {
    private let host: String
    private let port: Int
    private let onValidation: @Sendable (SSHKnownHostStore.ValidationResult) -> Void

    init(
        host: String,
        port: Int,
        onValidation: @escaping @Sendable (SSHKnownHostStore.ValidationResult) -> Void
    ) {
        self.host = host
        self.port = port
        self.onValidation = onValidation
    }

    func validateHostKey(
        hostKey: NIOSSHPublicKey,
        validationCompletePromise: EventLoopPromise<Void>
    ) {
        let result = SSHKnownHostStore.validate(hostKey: hostKey, host: host, port: port)
        onValidation(result)

        switch result {
        case .trusted, .trustedOnFirstUse:
            validationCompletePromise.succeed(())
        case .mismatch(let expected, let actual):
            validationCompletePromise.fail(
                SSHClientError.hostKeyMismatch(expected: expected, actual: actual)
            )
        }
    }
}
