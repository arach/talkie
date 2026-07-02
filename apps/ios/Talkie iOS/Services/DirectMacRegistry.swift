//
//  DirectMacRegistry.swift
//  Talkie iOS
//
//  First-party Mac registry driven by direct Talkie knowledge:
//  Bridge pairing state and saved SSH terminal hosts.
//

import Foundation
import Observation

@MainActor
@Observable
final class DirectMacRegistry {
    struct MacEntry: Identifiable, Equatable {
        enum DeviceKind: Equatable {
            case laptop
            case mini
            case desktop
        }

        let id: String
        let name: String
        let bridgeHost: String?
        let bridgePaired: Bool
        let bridgeConnected: Bool
        let lastBridgeContactAt: Date?
        let sshHosts: [SSHTerminalSavedHost]
        let lastTerminalUseAt: Date?
        let terminalConnected: Bool
        let activeTerminalProfile: SSHTerminalStartupProfile?

        var hasTerminalAccess: Bool {
            !sshHosts.isEmpty
        }

        var terminalSavedCount: Int {
            sshHosts.count
        }

        var primaryTerminalHost: SSHTerminalSavedHost? {
            sshHosts.first
        }

        var lastDirectActivityAt: Date? {
            [lastBridgeContactAt, lastTerminalUseAt]
                .compactMap { $0 }
                .max()
        }

        var deviceKind: DeviceKind {
            let normalized = [
                name,
                bridgeHost,
                primaryTerminalHost?.previewTitle,
                primaryTerminalHost?.host,
            ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")

            if normalized.contains("mini") {
                return .mini
            }
            if normalized.contains("studio") || normalized.contains("desktop") {
                return .desktop
            }
            if normalized.contains("book") || normalized.contains("air") || normalized.contains("laptop") {
                return .laptop
            }

            return .desktop
        }

        var lastSeenText: String {
            if bridgeConnected || terminalConnected {
                return "Connected"
            }

            guard let lastDirectActivityAt else {
                return "Not yet"
            }

            return Self.relativeString(from: lastDirectActivityAt)
        }

        var bridgeStatusText: String {
            if bridgeConnected {
                return "Connected now"
            }
            if bridgePaired {
                return "Paired on this iPhone"
            }
            return "Not connected"
        }

        var terminalStatusText: String {
            if terminalConnected {
                if let activeTerminalProfile {
                    return "\(activeTerminalProfile.shortTitle) live now"
                }
                return "Connected now"
            }

            if let primaryTerminalHost {
                if terminalSavedCount == 1 {
                    return primaryTerminalHost.startupProfile.shortTitle
                }
                return "\(terminalSavedCount) destinations"
            }

            return "Not set up"
        }

        var detailText: String {
            if let bridgeHost {
                return bridgeHost
            }
            if let primaryHost = primaryTerminalHost {
                return primaryHost.title
            }
            return "Ready to connect"
        }

        var technicalConnectionText: String? {
            if let primaryHost = primaryTerminalHost {
                let trimmedHost = primaryHost.host.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedHost.isEmpty else { return nil }
                return trimmedHost
            }

            if let bridgeHost {
                let trimmedHost = bridgeHost.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmedHost.isEmpty ? nil : trimmedHost
            }

            return nil
        }

        var capabilitySummary: String {
            var parts: [String] = []
            if bridgePaired {
                parts.append("Direct pairing")
            }
            if hasTerminalAccess {
                let count = sshHosts.count
                parts.append(count == 1 ? "1 terminal" : "\(count) terminals")
            }
            return parts.joined(separator: " · ")
        }

        private static func relativeString(from date: Date) -> String {
            let interval = Date().timeIntervalSince(date)
            if interval < 60 {
                return "just now"
            } else if interval < 3600 {
                return "\(Int(interval / 60)) min ago"
            } else if interval < 86_400 {
                return "\(Int(interval / 3600)) hr ago"
            } else if interval < 604_800 {
                return "\(Int(interval / 86_400)) days ago"
            } else if interval < 2_592_000 {
                return "\(Int(interval / 604_800)) weeks ago"
            } else {
                return "\(Int(interval / 2_592_000)) months ago"
            }
        }
    }

    static let shared = DirectMacRegistry()

    private(set) var macs: [MacEntry] = []

    private let bridgeManager: BridgeManager
    private let sshManager: SSHTerminalConnectionManager

    init() {
        self.bridgeManager = .shared
        self.sshManager = .shared
    }

    func refresh() {
        sshManager.reload()
        let activeConnections = sshManager.activeConnections

        var entriesByKey: [String: MacEntry] = [:]

        for device in sshManager.devices {
            guard let primaryHost = device.primarySavedHost else { continue }
            let keys = candidateKeys(
                name: device.title,
                host: primaryHost.host,
                identifier: primaryHost.deviceIdentifier
            )

            let baseEntry = MacEntry(
                id: keys.first ?? UUID().uuidString,
                name: device.title,
                bridgeHost: nil,
                bridgePaired: false,
                bridgeConnected: false,
                lastBridgeContactAt: nil,
                sshHosts: device.savedHosts,
                lastTerminalUseAt: device.lastUsedAt,
                terminalConnected: activeConnections.contains { $0.deviceID == device.id },
                activeTerminalProfile: activeConnections.first(where: { $0.deviceID == device.id })?.startupProfile
            )

            merge(baseEntry, into: &entriesByKey, matching: keys)
        }

        for pairedMac in bridgeManager.pairedMacs {
            let name = pairedMac.pairedMacName.isEmpty ? pairedMac.hostname : pairedMac.pairedMacName
            let keys = candidateKeys(
                name: name,
                host: pairedMac.hostname,
                identifier: pairedMac.hostname
            )

            let bridgeEntry = MacEntry(
                id: keys.first ?? pairedMac.id,
                name: name,
                bridgeHost: pairedMac.hostname,
                bridgePaired: true,
                bridgeConnected: bridgeManager.activePairedMacID == pairedMac.id && bridgeManager.status == .connected,
                lastBridgeContactAt: pairedMac.lastSuccessfulContactAt > 0
                    ? Date(timeIntervalSince1970: pairedMac.lastSuccessfulContactAt)
                    : nil,
                sshHosts: [],
                lastTerminalUseAt: nil,
                terminalConnected: false,
                activeTerminalProfile: nil
            )

            merge(bridgeEntry, into: &entriesByKey, matching: keys)
        }

        macs = entriesByKey.values.sorted { left, right in
            let leftDate = left.lastDirectActivityAt ?? .distantPast
            let rightDate = right.lastDirectActivityAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate > rightDate
            }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    private func merge(
        _ candidate: MacEntry,
        into entriesByKey: inout [String: MacEntry],
        matching keys: [String]
    ) {
        if let existingKey = keys.first(where: { entriesByKey[$0] != nil }),
           let existing = entriesByKey[existingKey] {
            let merged = MacEntry(
                id: existing.id,
                name: preferredName(primary: existing.name, fallback: candidate.name),
                bridgeHost: existing.bridgeHost ?? candidate.bridgeHost,
                bridgePaired: existing.bridgePaired || candidate.bridgePaired,
                bridgeConnected: existing.bridgeConnected || candidate.bridgeConnected,
                lastBridgeContactAt: maxDate(existing.lastBridgeContactAt, candidate.lastBridgeContactAt),
                sshHosts: mergeHosts(existing.sshHosts, candidate.sshHosts),
                lastTerminalUseAt: maxDate(existing.lastTerminalUseAt, candidate.lastTerminalUseAt),
                terminalConnected: existing.terminalConnected || candidate.terminalConnected,
                activeTerminalProfile: existing.activeTerminalProfile ?? candidate.activeTerminalProfile
            )
            entriesByKey[existingKey] = merged
            return
        }

        let key = keys.first ?? candidate.id
        entriesByKey[key] = candidate
    }

    private func candidateKeys(name: String, host: String?, identifier: String?) -> [String] {
        var keys: [String] = []

        let normalizedName = normalize(name)
        if !normalizedName.isEmpty {
            keys.append("name:\(normalizedName)")
        }

        if let host {
            let normalizedHost = normalize(host)
            if !normalizedHost.isEmpty {
                keys.append("host:\(normalizedHost)")
            }
        }

        if let identifier {
            let normalizedIdentifier = normalize(identifier)
            if !normalizedIdentifier.isEmpty {
                keys.append("id:\(normalizedIdentifier)")
            }
        }

        return Array(NSOrderedSet(array: keys)) as? [String] ?? keys
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func preferredName(primary: String, fallback: String) -> String {
        let primary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if primary.isEmpty {
            return fallback
        }
        if primary.count >= fallback.count {
            return primary
        }
        return fallback
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)):
            return max(left, right)
        case let (.some(left), .none):
            return left
        case let (.none, .some(right)):
            return right
        case (.none, .none):
            return nil
        }
    }

    private func mergeHosts(_ lhs: [SSHTerminalSavedHost], _ rhs: [SSHTerminalSavedHost]) -> [SSHTerminalSavedHost] {
        let combined = lhs + rhs
        var seen = Set<UUID>()
        return combined.filter { seen.insert($0.id).inserted }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }
}
