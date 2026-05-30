//
//  SSHTerminalConfiguration.swift
//  Talkie iOS
//
//  Connection settings for an interactive SSH terminal session.
//

import Foundation

struct SSHTerminalConfiguration: Equatable, Sendable {
    var host: String
    var port: Int
    var username: String
    var password: String = ""
    var privateKeyPEM: String? = nil
    var term: String = "xterm-256color"
    var startupProfile: SSHTerminalStartupProfile = .standardShell
    var startupCommand: String? = nil
    var connectTimeoutSeconds: Int = 8
}
