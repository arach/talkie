//
//  RuntimeFeatureFlags.swift
//  TalkieKit
//
//  Shared feature flag catalog and remote fetch helper.
//

import Foundation

public struct RuntimeFeatureFlagDefinition: Identifiable, Hashable, Sendable {
    public let key: String
    public let title: String
    public let detail: String
    public let defaultValue: Bool
    public let sharedSettingsKey: String?

    public var id: String { key }

    public init(
        key: String,
        title: String,
        detail: String,
        defaultValue: Bool,
        sharedSettingsKey: String? = nil
    ) {
        self.key = key
        self.title = title
        self.detail = detail
        self.defaultValue = defaultValue
        self.sharedSettingsKey = sharedSettingsKey
    }
}

public enum RuntimeFeatureFlags {
    public static let endpoint = "https://api.usetalkie.com/api/flags"
    public static let fetchTimeout: TimeInterval = 5
    public static let cacheDuration: TimeInterval = 7 * 24 * 60 * 60

    public static let definitions: [RuntimeFeatureFlagDefinition] = [
        RuntimeFeatureFlagDefinition(
            key: "enableCapture",
            title: "Capture",
            detail: "Tray, drain-to-recording, and capture shortcuts.",
            defaultValue: true,
            sharedSettingsKey: AgentSettingsKey.featureCaptureEnabled
        ),
        RuntimeFeatureFlagDefinition(
            key: "enableScreenshots",
            title: "Screenshots",
            detail: "Screenshot capture and capture shortcuts.",
            defaultValue: true
        ),
        RuntimeFeatureFlagDefinition(
            key: "enableCameraBubble",
            title: "Camera Bubble",
            detail: "Floating camera preview and clip recording.",
            defaultValue: false
        ),
        RuntimeFeatureFlagDefinition(
            key: "enableCaptureRichUI",
            title: "Rich Capture UI",
            detail: "Enhanced screenshot overlay and preview visuals.",
            defaultValue: false
        ),
        RuntimeFeatureFlagDefinition(
            key: "enableNotchComposer",
            title: "Legacy Notch Composer",
            detail: "Talkie-owned live notch/island renderer.",
            defaultValue: false,
            sharedSettingsKey: AgentSettingsKey.featureNotchComposerEnabled
        ),
        RuntimeFeatureFlagDefinition(
            key: "enableVoiceForegrounding",
            title: "Voice Foregrounding",
            detail: "Experimental voice-over-background audio processing.",
            defaultValue: false,
            sharedSettingsKey: AgentSettingsKey.featureVoiceForegroundingEnabled
        ),
        RuntimeFeatureFlagDefinition(
            key: "showConnectionCenter",
            title: "Connection Center",
            detail: "iOS bridge and connection settings.",
            defaultValue: false
        ),
        RuntimeFeatureFlagDefinition(
            key: "showExtensionAPI",
            title: "Extension API",
            detail: "Extension API surface in Compose.",
            defaultValue: false
        ),
        RuntimeFeatureFlagDefinition(
            key: "paywallEnabled",
            title: "Paywall",
            detail: "Premium feature gating.",
            defaultValue: false
        ),
        RuntimeFeatureFlagDefinition(
            key: "showProFeatures",
            title: "Pro Features",
            detail: "Pro surfaces and affordances.",
            defaultValue: false
        ),
        RuntimeFeatureFlagDefinition(
            key: "enableCloudSync",
            title: "Cloud Sync",
            detail: "CloudKit sync surfaces.",
            defaultValue: false
        ),
        RuntimeFeatureFlagDefinition(
            key: "enableAutoUpdates",
            title: "Auto Updates",
            detail: "Automatic update checks.",
            defaultValue: true
        ),
        RuntimeFeatureFlagDefinition(
            key: "showDebugInfo",
            title: "Debug Info",
            detail: "Extra diagnostic information in Settings.",
            defaultValue: false
        ),
    ]

    public static let childFlags: [String: [String]] = [
        "enableCapture": ["enableCameraBubble", "enableScreenshots"],
        "enableScreenshots": ["enableCaptureRichUI"],
    ]

    public static var defaults: [String: Bool] {
        Dictionary(uniqueKeysWithValues: definitions.map { ($0.key, $0.defaultValue) })
    }

    public static var sharedSettingsKeys: [String: String] {
        Dictionary(
            uniqueKeysWithValues: definitions.compactMap { definition in
                guard let sharedSettingsKey = definition.sharedSettingsKey else { return nil }
                return (definition.key, sharedSettingsKey)
            }
        )
    }

    public static var topLevelKeys: [String] {
        let children = Set(childFlags.values.flatMap { $0 })
        return definitions.map(\.key).filter { !children.contains($0) }.sorted()
    }

    public static func definition(for key: String) -> RuntimeFeatureFlagDefinition? {
        definitions.first { $0.key == key }
    }

    public static func children(of key: String) -> [String] {
        childFlags[key] ?? []
    }

    public static func fetchRemoteFlags(
        version: String? = nil,
        build: String? = nil,
        platform: String = "macos"
    ) async throws -> [String: Bool] {
        guard let url = URL(string: endpoint),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw RuntimeFeatureFlagError.invalidURL
        }

        let resolvedVersion = version
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "unknown"
        let resolvedBuild = build
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "0"

        components.queryItems = [
            URLQueryItem(name: "version", value: resolvedVersion),
            URLQueryItem(name: "build", value: resolvedBuild),
            URLQueryItem(name: "platform", value: platform),
        ]

        guard let requestURL = components.url else {
            throw RuntimeFeatureFlagError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = fetchTimeout
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw RuntimeFeatureFlagError.serverError
        }

        do {
            return try JSONDecoder().decode(RuntimeFeatureFlagResponse.self, from: data).flags
        } catch {
            throw RuntimeFeatureFlagError.decodingError
        }
    }
}

public struct RuntimeFeatureFlagResponse: Decodable {
    public let flags: [String: Bool]
}

public enum RuntimeFeatureFlagError: LocalizedError {
    case invalidURL
    case serverError
    case decodingError

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid flags URL"
        case .serverError: return "Server returned an error"
        case .decodingError: return "Failed to decode flags response"
        }
    }
}
