//
//  SSHClientAuthenticationDelegate.swift
//  Talkie iOS
//
//  Client-side SSH authentication that can try a private key, password, or both.
//

import NIOCore
@preconcurrency import NIOSSH

final class SSHClientAuthenticationDelegate: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let password: String?
    private let privateKey: NIOSSHPrivateKey?

    private var didOfferPassword = false
    private var didOfferPrivateKey = false

    init(username: String, password: String?, privateKey: NIOSSHPrivateKey?) {
        self.username = username
        self.password = password
        self.privateKey = privateKey
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        if let privateKey, !didOfferPrivateKey, availableMethods.contains(.publicKey) {
            didOfferPrivateKey = true
            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: username,
                    serviceName: "",
                    offer: .privateKey(.init(privateKey: privateKey))
                )
            )
            return
        }

        if let password, !didOfferPassword, availableMethods.contains(.password) {
            didOfferPassword = true
            nextChallengePromise.succeed(
                NIOSSHUserAuthenticationOffer(
                    username: username,
                    serviceName: "",
                    offer: .password(.init(password: password))
                )
            )
            return
        }

        let canAttemptPrivateKey = privateKey != nil && availableMethods.contains(.publicKey)
        let canAttemptPassword = password != nil && availableMethods.contains(.password)

        if !canAttemptPrivateKey && !canAttemptPassword {
            if privateKey != nil && password == nil {
                nextChallengePromise.fail(SSHClientError.privateKeyAuthenticationUnavailable)
            } else if password != nil && privateKey == nil {
                nextChallengePromise.fail(SSHClientError.passwordAuthenticationUnavailable)
            } else {
                nextChallengePromise.fail(SSHClientError.supportedAuthenticationMethodsUnavailable)
            }
            return
        }

        nextChallengePromise.succeed(nil)
    }
}
