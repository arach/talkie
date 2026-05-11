//
//  SSHTerminalConnectionManager.swift
//  Talkie iOS
//
//  Central app-level state for remembered SSH devices, sessions, and the
//  currently active terminal connection.
//

import Foundation
import Observation

@MainActor
@Observable
final class SSHTerminalConnectionManager {
    struct ActiveConnection: Equatable, Sendable {
        let deviceID: String
        let deviceTitle: String
        let sessionTitle: String
        let hostTitle: String
        let startedAt: Date
        let startupProfile: SSHTerminalStartupProfile
    }

    static let shared = SSHTerminalConnectionManager()

    private let savedHostStore: SSHTerminalSavedHostStore

    private(set) var savedHosts: [SSHTerminalSavedHost]
    private(set) var activeConnection: ActiveConnection?
    private var pendingResumeHostID: UUID?

    init(savedHostStore: SSHTerminalSavedHostStore = SSHTerminalSavedHostStore()) {
        self.savedHostStore = savedHostStore
        self.savedHosts = savedHostStore.load()
    }

    var devices: [SSHTerminalDevice] {
        Dictionary(grouping: savedHosts, by: \.resolvedDeviceIdentifier)
            .map { SSHTerminalDevice(id: $0.key, savedHosts: $0.value) }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    var recentSessions: [SSHTerminalSessionRecord] {
        devices
            .flatMap(\.sessions)
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    var featuredDevice: SSHTerminalDevice? {
        devices.first
    }

    func reload() {
        savedHosts = savedHostStore.load()
    }

    @discardableResult
    func saveHost(
        host: String,
        port: Int,
        username: String,
        startupProfile: SSHTerminalStartupProfile,
        startupCommandOverride: String? = nil,
        deviceIdentifier: String? = nil,
        deviceLabel: String? = nil,
        alternateHosts: [String] = []
    ) -> [SSHTerminalSavedHost] {
        let updatedHosts = savedHostStore.save(
            host: host,
            port: port,
            username: username,
            startupProfile: startupProfile,
            startupCommandOverride: startupCommandOverride,
            deviceIdentifier: deviceIdentifier,
            deviceLabel: deviceLabel,
            alternateHosts: alternateHosts
        )
        savedHosts = updatedHosts
        return updatedHosts
    }

    @discardableResult
    func addRouteAlias(_ aliasHost: String, to savedHost: SSHTerminalSavedHost) -> [SSHTerminalSavedHost] {
        let updatedHosts = savedHostStore.addRouteAlias(aliasHost, to: savedHost)
        savedHosts = updatedHosts
        return updatedHosts
    }

    @discardableResult
    func delete(_ savedHost: SSHTerminalSavedHost) -> [SSHTerminalSavedHost] {
        let updatedHosts = savedHostStore.delete(savedHost)
        savedHosts = updatedHosts
        if pendingResumeHostID == savedHost.id {
            pendingResumeHostID = nil
        }
        if activeConnection?.hostTitle == savedHost.title {
            activeConnection = nil
        }
        if activeConnection?.deviceID == savedHost.resolvedDeviceIdentifier,
           savedHosts.contains(where: { $0.resolvedDeviceIdentifier == savedHost.resolvedDeviceIdentifier }) == false {
            activeConnection = nil
        }
        return updatedHosts
    }

    func markConnecting(
        host: String,
        port: Int,
        username: String,
        startupProfile: SSHTerminalStartupProfile,
        startupCommandOverride: String? = nil
    ) {
        let snapshot = connectionSnapshot(
            host: host,
            port: port,
            username: username,
            startupProfile: startupProfile,
            startupCommandOverride: startupCommandOverride
        )
        activeConnection = snapshot
    }

    func clearActiveConnection() {
        activeConnection = nil
    }

    func requestResume(for savedHost: SSHTerminalSavedHost?) {
        pendingResumeHostID = savedHost?.id
    }

    func consumePendingResumeHost() -> SSHTerminalSavedHost? {
        defer { pendingResumeHostID = nil }
        guard let pendingResumeHostID else { return nil }
        return savedHosts.first(where: { $0.id == pendingResumeHostID })
    }

    private func connectionSnapshot(
        host: String,
        port: Int,
        username: String,
        startupProfile: SSHTerminalStartupProfile,
        startupCommandOverride: String?
    ) -> ActiveConnection {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let savedHost = savedHosts.first(where: {
            $0.normalizedHostCandidates.contains(normalizedHost) &&
            $0.normalizedUsername == normalizedUsername &&
            $0.port == port
        }) {
            return ActiveConnection(
                deviceID: savedHost.resolvedDeviceIdentifier,
                deviceTitle: savedHost.resolvedDeviceTitle,
                sessionTitle: startupProfile.title,
                hostTitle: savedHost.title,
                startedAt: .now,
                startupProfile: startupProfile
            )
        }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle: String
        if trimmedUsername.isEmpty {
            fallbackTitle = port == 22 ? trimmedHost : "\(trimmedHost):\(port)"
        } else {
            fallbackTitle = port == 22 ? "\(trimmedUsername)@\(trimmedHost)" : "\(trimmedUsername)@\(trimmedHost):\(port)"
        }

        let commandOverride = startupCommandOverride?.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceID = "\(normalizedUsername)@\(normalizedHost):\(port)"
        return ActiveConnection(
            deviceID: deviceID,
            deviceTitle: trimmedHost,
            sessionTitle: commandOverride?.isEmpty == false ? "Custom Shell" : startupProfile.title,
            hostTitle: fallbackTitle,
            startedAt: .now,
            startupProfile: startupProfile
        )
    }
}
