//
//  TalkieRuntimeIdentity.swift
//  TalkieKit
//
//  Machine-readable runtime identity for debugging local installs.
//

import Foundation

public enum TalkieRuntimeComponent: String, Codable, Sendable {
    case mac
    case agent
    case engine
    case sync

    public var displayName: String {
        switch self {
        case .mac: return "Talkie"
        case .agent: return TalkieHelper.agent.displayName
        case .engine: return TalkieHelper.engine.displayName
        case .sync: return TalkieHelper.sync.displayName
        }
    }

    public var helper: TalkieHelper? {
        switch self {
        case .mac: return nil
        case .agent: return .agent
        case .engine: return .engine
        case .sync: return .sync
        }
    }

    public func expectedBundleId(for env: TalkieEnvironment) -> String {
        helper?.bundleId(for: env) ?? env.talkieBundleId
    }
}

public struct TalkieRuntimeIdentity: Codable, Sendable {
    public let schemaVersion: Int
    public let component: TalkieRuntimeComponent
    public let displayName: String
    public let environment: String
    public let bundleId: String
    public let expectedBundleId: String
    public let version: String
    public let build: String
    public let processId: Int32
    public let startedAt: Date
    public let updatedAt: Date
    public let bundlePath: String?
    public let executablePath: String?
    public let appSupportDirectory: String
    public let userInstalledApplicationsDirectory: String
    public let launchdLabel: String?
    public let xpcServiceName: String?
}

public enum TalkieRuntimeIdentityStore {
    public static func identityDirectory(
        environment: TalkieEnvironment = .current
    ) -> URL {
        environment.appSupportDirectory
            .appendingPathComponent("Identity", isDirectory: true)
    }

    public static func identityURL(
        for component: TalkieRuntimeComponent,
        environment: TalkieEnvironment = .current
    ) -> URL {
        identityDirectory(environment: environment)
            .appendingPathComponent("\(component.rawValue).json")
    }

    public static func writeCurrentProcess(
        component: TalkieRuntimeComponent,
        environment: TalkieEnvironment = .current,
        processId: pid_t = ProcessInfo.processInfo.processIdentifier,
        bundle: Bundle = .main
    ) throws {
        let helper = component.helper
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let bundleId = bundle.bundleIdentifier ?? "unknown"
        let startedAt = talkieProcessStartTime(pid: processId) ?? Date()

        let identity = TalkieRuntimeIdentity(
            schemaVersion: 1,
            component: component,
            displayName: component.displayName,
            environment: environment.rawValue,
            bundleId: bundleId,
            expectedBundleId: component.expectedBundleId(for: environment),
            version: version,
            build: build,
            processId: processId,
            startedAt: startedAt,
            updatedAt: Date(),
            bundlePath: bundle.bundleURL.path,
            executablePath: bundle.executableURL?.path,
            appSupportDirectory: environment.appSupportDirectory.path,
            userInstalledApplicationsDirectory: environment.userInstalledApplicationsDirectory.path,
            launchdLabel: helper?.launchdLabel(for: environment),
            xpcServiceName: helper?.xpcServiceName(for: environment)
        )

        let url = identityURL(for: component, environment: environment)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(identity).write(to: url, options: .atomic)
    }
}
