//
//  SSHTerminalSavedHostStore.swift
//  Talkie iOS
//
//  Stores saved SSH hosts in user defaults.
//

import Foundation

struct SSHTerminalSavedHostStore {
    static let defaultsKey = "sshTerminal.savedHosts"

    private let encoder = JSONEncoder()
    private let configurationStore = TalkieAppConfigurationStore.shared

    func load() -> [SSHTerminalSavedHost] {
        let savedHosts = configurationStore.configuration.ssh.savedHosts

        let normalizedHosts = savedHosts.map { host in
            var normalizedHost = host
            if normalizedHost.startupProfileRawValue == nil {
                let inferredProfile = SSHTerminalStartupProfile.inferredProfile(
                    from: normalizedHost.startupCommandOverride ?? ""
                )
                normalizedHost.startupProfile = inferredProfile
            }
            normalizedHost.startupCommandOverride = SSHTerminalStartupProfile.normalizedStartupCommandOverride(
                host.startupCommandOverride,
                for: normalizedHost.startupProfile
            )
            if normalizedHost.shouldUseNativeLauncher(for: normalizedHost.startupProfile) {
                normalizedHost.startupProfile = .standardShell
            }
            return normalizedHost
        }

        return normalizedHosts.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    @discardableResult
    func save(
        host: String,
        port: Int,
        username: String,
        startupProfile: SSHTerminalStartupProfile,
        startupCommandOverride: String? = nil,
        deviceIdentifier: String? = nil,
        deviceLabel: String? = nil,
        alternateHosts: [String] = []
    ) -> [SSHTerminalSavedHost] {
        var savedHosts = load()
        let normalizedHost = normalize(host)
        let normalizedUsername = normalize(username)
        let normalizedStartupCommandOverride = SSHTerminalStartupProfile.normalizedStartupCommandOverride(
            startupCommandOverride,
            for: startupProfile
        )
        let normalizedDeviceIdentifier = normalizeOptional(deviceIdentifier)
        let normalizedDeviceLabel = trimOptional(deviceLabel)
        let normalizedAlternateHosts = normalizedHostAliases(
            primaryHost: host,
            existingHosts: [],
            newHosts: alternateHosts
        )
        let incomingDeviceIdentifier = SSHTerminalSavedHost.resolvedDeviceIdentifier(
            host: host,
            port: port,
            username: username,
            deviceIdentifier: normalizedDeviceIdentifier,
            deviceLabel: normalizedDeviceLabel
        )

        if let index = savedHosts.firstIndex(where: { savedHost in
            let isSameEndpoint = normalize(savedHost.host) == normalizedHost &&
                normalize(savedHost.username) == normalizedUsername &&
                savedHost.port == port
            let isSameLogicalDevice = savedHost.resolvedDeviceIdentifier == incomingDeviceIdentifier &&
                normalize(savedHost.username) == normalizedUsername &&
                savedHost.port == port
            return isSameEndpoint || isSameLogicalDevice
        }) {
            let existingPrimaryHost = savedHosts[index].host
            let existingAlternateHosts = savedHosts[index].alternateHosts ?? []
            savedHosts[index].host = host.trimmingCharacters(in: .whitespacesAndNewlines)
            savedHosts[index].username = username.trimmingCharacters(in: .whitespacesAndNewlines)
            savedHosts[index].alternateHosts = normalizedHostAliases(
                primaryHost: host,
                existingHosts: [existingPrimaryHost] + existingAlternateHosts,
                newHosts: normalizedAlternateHosts
            )
            savedHosts[index].startupProfile = startupProfile
            savedHosts[index].startupCommandOverride = normalizedStartupCommandOverride
            if let normalizedDeviceIdentifier {
                savedHosts[index].deviceIdentifier = normalizedDeviceIdentifier
            }
            if let normalizedDeviceLabel {
                savedHosts[index].deviceLabel = normalizedDeviceLabel
            }
            savedHosts[index].lastUsedAt = .now
        } else {
            var savedHost = SSHTerminalSavedHost(
                host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                port: port,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                deviceIdentifier: normalizedDeviceIdentifier,
                deviceLabel: normalizedDeviceLabel,
                alternateHosts: normalizedAlternateHosts,
                lastUsedAt: .now
            )
            savedHost.startupProfile = startupProfile
            savedHost.startupCommandOverride = normalizedStartupCommandOverride
            savedHosts.append(savedHost)
        }

        return persist(savedHosts)
    }

    @discardableResult
    func addRouteAlias(_ aliasHost: String, to savedHost: SSHTerminalSavedHost) -> [SSHTerminalSavedHost] {
        var savedHosts = load()
        guard let index = savedHosts.firstIndex(where: { $0.id == savedHost.id }) else {
            return savedHosts
        }

        let aliases = normalizedHostAliases(
            primaryHost: savedHosts[index].host,
            existingHosts: savedHosts[index].alternateHosts ?? [],
            newHosts: [aliasHost]
        )
        savedHosts[index].alternateHosts = aliases
        savedHosts[index].lastUsedAt = .now

        return persist(savedHosts)
    }

    @discardableResult
    func delete(_ savedHost: SSHTerminalSavedHost) -> [SSHTerminalSavedHost] {
        let savedHosts = load().filter { $0.id != savedHost.id }
        return persist(savedHosts)
    }

    private func persist(_ savedHosts: [SSHTerminalSavedHost]) -> [SSHTerminalSavedHost] {
        let trimmedHosts = Array(savedHosts.sorted { $0.lastUsedAt > $1.lastUsedAt }.prefix(12))

        configurationStore.update { configuration in
            configuration.ssh.savedHosts = trimmedHosts
        }

        if let data = try? encoder.encode(trimmedHosts) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }

        return trimmedHosts
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeOptional(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue.lowercased()
    }

    private func trimOptional(_ value: String?) -> String? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private func normalizedHostAliases(
        primaryHost: String,
        existingHosts: [String],
        newHosts: [String]
    ) -> [String] {
        let normalizedPrimaryHost = normalize(primaryHost)
        var seen: Set<String> = [normalizedPrimaryHost]
        var aliases: [String] = []

        for host in existingHosts + newHosts {
            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedHost = normalize(trimmedHost)
            guard !normalizedHost.isEmpty,
                  !seen.contains(normalizedHost),
                  normalizedHost != "localhost",
                  normalizedHost != "127.0.0.1",
                  normalizedHost != "::1" else {
                continue
            }

            seen.insert(normalizedHost)
            aliases.append(trimmedHost)
        }

        return aliases
    }
}
