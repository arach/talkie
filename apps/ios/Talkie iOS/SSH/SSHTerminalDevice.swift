//
//  SSHTerminalDevice.swift
//  Talkie iOS
//
//  First-class representation of a paired or remembered terminal device.
//

import Foundation

struct SSHTerminalDevice: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let savedHosts: [SSHTerminalSavedHost]
    let sessions: [SSHTerminalSessionRecord]
    let lastUsedAt: Date

    init(id: String, savedHosts: [SSHTerminalSavedHost]) {
        let sortedHosts = savedHosts.sorted { $0.lastUsedAt > $1.lastUsedAt }
        let primaryHost = sortedHosts.first ?? SSHTerminalSavedHost(host: "", port: 22, username: "")

        self.id = id
        self.title = primaryHost.resolvedDeviceTitle
        self.subtitle = primaryHost.resolvedDeviceSubtitle
        self.savedHosts = sortedHosts
        self.sessions = sortedHosts.map(SSHTerminalSessionRecord.init)
        self.lastUsedAt = sortedHosts.first?.lastUsedAt ?? .distantPast
    }

    var primarySavedHost: SSHTerminalSavedHost? {
        savedHosts.first
    }

    var primarySession: SSHTerminalSessionRecord? {
        sessions.first
    }
}
