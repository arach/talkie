//
//  SSHTerminalSessionRecord.swift
//  Talkie iOS
//
//  App-level metadata for a launchable SSH terminal session.
//

import Foundation

struct SSHTerminalSessionRecord: Identifiable, Equatable, Sendable {
    let id: String
    let deviceID: String
    let savedHostID: UUID
    let title: String
    let subtitle: String
    let startupProfile: SSHTerminalStartupProfile
    let startupCommandOverride: String?
    let savedHost: SSHTerminalSavedHost
    let lastUsedAt: Date

    init(savedHost: SSHTerminalSavedHost) {
        self.id = "\(savedHost.id.uuidString.lowercased())::\(savedHost.startupProfile.rawValue)"
        self.deviceID = savedHost.resolvedDeviceIdentifier
        self.savedHostID = savedHost.id
        self.title = savedHost.startupProfile.title
        self.subtitle = savedHost.title
        self.startupProfile = savedHost.startupProfile
        self.startupCommandOverride = savedHost.startupCommandOverride
        self.savedHost = savedHost
        self.lastUsedAt = savedHost.lastUsedAt
    }

    var isPersistent: Bool {
        startupProfile == .talkieSession
    }
}
