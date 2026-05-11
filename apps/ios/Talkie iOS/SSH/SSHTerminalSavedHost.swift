//
//  SSHTerminalSavedHost.swift
//  Talkie iOS
//
//  Persisted SSH host profile for quick reconnects.
//

import Foundation

struct SSHTerminalSavedHost: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var host: String
    var port: Int
    var username: String
    var deviceIdentifier: String? = nil
    var deviceLabel: String? = nil
    var alternateHosts: [String]? = nil
    var startupProfileRawValue: String? = nil
    var startupCommandOverride: String? = nil
    var lastUsedAt: Date = .now

    var startupProfile: SSHTerminalStartupProfile {
        get {
            guard let startupProfileRawValue else {
                return .standardShell
            }

            return SSHTerminalStartupProfile(rawValue: startupProfileRawValue) ?? .standardShell
        }
        set {
            startupProfileRawValue = newValue.rawValue
        }
    }

    var resolvedStartupCommand: String {
        if let override = SSHTerminalStartupProfile.normalizedStartupCommandOverride(
            startupCommandOverride,
            for: startupProfile
        ) {
            return override
        }

        return startupProfile.startupCommand
    }

    var title: String {
        if username.isEmpty {
            if port == 22 {
                return host
            }

            return "\(host):\(port)"
        }

        if port == 22 {
            return "\(username)@\(host)"
        }

        return "\(username)@\(host):\(port)"
    }

    var normalizedHost: String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var trimmedDeviceLabel: String? {
        let trimmedLabel = deviceLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedLabel.isEmpty ? nil : trimmedLabel
    }

    private var cleanedDeviceLabel: String? {
        guard let trimmedDeviceLabel else { return nil }

        let prefixes = [
            "Talkie SSH for ",
            "Talkie Shell for ",
            "Talkie Session for ",
            "Talkie Terminal for "
        ]

        for prefix in prefixes where trimmedDeviceLabel.hasPrefix(prefix) {
            let cleaned = String(trimmedDeviceLabel.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return trimmedDeviceLabel
    }

    var resolvedDeviceIdentifier: String {
        let trimmedIdentifier = deviceIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedIdentifier.isEmpty {
            return trimmedIdentifier.lowercased()
        }

        if let cleanedDeviceLabel {
            return "label:\(Self.normalizedDeviceIdentifierComponent(cleanedDeviceLabel))"
        }

        return "\(normalizedUsername)@\(normalizedHost):\(port)"
    }

    var normalizedHostCandidates: [String] {
        let candidates = [host] + (alternateHosts ?? [])
        var seen: Set<String> = []
        var normalizedCandidates: [String] = []

        for candidate in candidates {
            let normalizedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedCandidate.isEmpty, !seen.contains(normalizedCandidate) else {
                continue
            }
            seen.insert(normalizedCandidate)
            normalizedCandidates.append(normalizedCandidate)
        }

        return normalizedCandidates
    }

    var resolvedDeviceTitle: String {
        cleanedDeviceLabel ?? host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedDeviceSubtitle: String {
        if let trimmedDeviceLabel, trimmedDeviceLabel != title {
            return title
        }

        return startupProfile.title
    }

    var previewTitle: String {
        if let cleanedDeviceLabel {
            return cleanedDeviceLabel
        }

        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHost.isEmpty {
            if port == 22 {
                return trimmedHost
            }

            return "\(trimmedHost):\(port)"
        }

        return title
    }

    var previewSubtitle: String {
        if trimmedDeviceLabel != nil {
            return title
        }

        if !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        return startupProfile.title
    }

    var previewSourceLabel: String {
        if trimmedDeviceLabel != nil {
            return "paired mac"
        }

        switch startupProfile {
        case .standardShell:
            return "ssh host"
        case .talkieShell:
            return "talkie shell"
        case .talkieSession:
            return "talkie session"
        }
    }

    static func resolvedDeviceIdentifier(
        host: String,
        port: Int,
        username: String,
        deviceIdentifier: String?,
        deviceLabel: String?
    ) -> String {
        let trimmedIdentifier = deviceIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedIdentifier.isEmpty {
            return trimmedIdentifier.lowercased()
        }

        let temporaryHost = SSHTerminalSavedHost(
            host: host,
            port: port,
            username: username,
            deviceLabel: deviceLabel
        )
        return temporaryHost.resolvedDeviceIdentifier
    }

    static func normalizedDeviceIdentifierComponent(_ value: String) -> String {
        let normalized = value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        return normalized.isEmpty ? "unknown" : normalized
    }
}
