//
//  TalkieNetworkRouteClassifier.swift
//  TalkieKit
//
//  Shared host classification for local-network and Tailscale bridge routes.
//

import Foundation

public enum TalkieNetworkRoute: Equatable, Sendable {
    case direct
    case localNetwork
    case tailscale

    public var displayName: String {
        switch self {
        case .direct:
            return "Direct"
        case .localNetwork:
            return "Local network"
        case .tailscale:
            return "Tailscale"
        }
    }
}

public enum TalkieNetworkRouteClassifier {
    public static func route(for host: String?) -> TalkieNetworkRoute {
        guard let normalizedHost = normalizedHost(host) else {
            return .direct
        }

        if isTailscaleHost(normalizedHost) {
            return .tailscale
        }

        if isLocalNetworkHost(normalizedHost) {
            return .localNetwork
        }

        return .direct
    }

    public static func isTailscaleHost(_ host: String?) -> Bool {
        guard let normalizedHost = normalizedHost(host) else { return false }
        if normalizedHost.hasSuffix(".ts.net") { return true }
        if normalizedHost.hasPrefix("fd7a:115c:a1e0:") { return true }
        return isTailscaleIPv4Address(normalizedHost)
    }

    public static func isTailscaleIPv4Address(_ host: String?) -> Bool {
        guard let normalizedHost = normalizedHost(host),
              let octets = ipv4Octets(from: normalizedHost) else {
            return false
        }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    public static func isLocalNetworkHost(_ host: String?) -> Bool {
        guard let normalizedHost = normalizedHost(host) else { return false }
        if normalizedHost == "localhost" { return true }
        if normalizedHost.hasSuffix(".local") || normalizedHost.hasSuffix(".lan") { return true }
        if normalizedHost == "::1" || normalizedHost.hasPrefix("fe80:") { return true }
        if normalizedHost.contains(":") &&
            (normalizedHost.hasPrefix("fc") || normalizedHost.hasPrefix("fd")) {
            return true
        }
        guard let octets = ipv4Octets(from: normalizedHost) else { return false }
        return octets[0] == 10 ||
            octets[0] == 127 ||
            (octets[0] == 169 && octets[1] == 254) ||
            (octets[0] == 172 && (16...31).contains(octets[1])) ||
            (octets[0] == 192 && octets[1] == 168)
    }

    public static func localBonjourHostname(from host: String?) -> String? {
        guard let normalizedHost = normalizedHost(host),
              normalizedHost != "localhost",
              normalizedHost != "127.0.0.1",
              normalizedHost != "::1" else {
            return nil
        }

        if normalizedHost.hasSuffix(".local") || normalizedHost.hasSuffix(".lan") {
            return normalizedHost
        }

        guard !normalizedHost.contains("."),
              !normalizedHost.contains(":") else {
            return nil
        }

        return "\(normalizedHost).local"
    }

    public static func networkIdentity(from value: String?) -> String? {
        guard var normalizedValue = normalizedHost(value) else { return nil }

        if isTailscaleHost(normalizedValue) {
            normalizedValue = normalizedValue.split(separator: ".").first.map(String.init) ?? normalizedValue
        } else {
            for suffix in [".local", ".lan"] where normalizedValue.hasSuffix(suffix) {
                normalizedValue.removeLast(suffix.count)
                break
            }
        }

        let identity = normalizedValue
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
        return identity.isEmpty ? nil : identity
    }

    private static func normalizedHost(_ host: String?) -> String? {
        let rawValue = (host ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !rawValue.isEmpty else { return nil }

        if rawValue.contains("://"),
           let components = URLComponents(string: rawValue),
           let componentHost = components.host {
            return normalizedHost(componentHost)
        }

        var normalized = rawValue
        if let atIndex = normalized.lastIndex(of: "@") {
            normalized = String(normalized[normalized.index(after: atIndex)...])
        }

        if normalized.hasPrefix("["),
           let closingBracket = normalized.firstIndex(of: "]") {
            let start = normalized.index(after: normalized.startIndex)
            normalized = String(normalized[start..<closingBracket])
        } else if let colonIndex = normalized.lastIndex(of: ":") {
            let hostPart = normalized[..<colonIndex]
            let portPart = normalized[normalized.index(after: colonIndex)...]
            if !hostPart.contains(":"), !portPart.isEmpty, portPart.allSatisfy(\.isNumber) {
                normalized = String(hostPart)
            }
        }

        normalized = normalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? nil : normalized
    }

    private static func ipv4Octets(from host: String) -> [Int]? {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { part -> Int? in
            guard let value = Int(part), (0...255).contains(value) else { return nil }
            return value
        }
        return octets.count == 4 ? octets : nil
    }
}
