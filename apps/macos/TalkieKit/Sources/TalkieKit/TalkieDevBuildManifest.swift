//
//  TalkieDevBuildManifest.swift
//  TalkieKit
//
//  Persistent identity for stable local dev app installs.
//

import Foundation

public struct TalkieBundleBuildIdentity: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let version: String
    public let build: String

    public init(bundleIdentifier: String?, version: String, build: String) {
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
    }

    public var displayVersion: String {
        "\(version) (\(build))"
    }
}

public struct TalkieDevBuildManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let product: String
    public let bundleIdentifier: String
    public let version: String
    public let build: String
    public let sourcePath: String?
    public let installedPath: String?
    public let builtAt: String?
    public let installedAt: String?
    public let gitBranch: String?
    public let gitCommit: String?
    public let workspaceRoot: String?

    public init(
        schemaVersion: Int = 1,
        product: String,
        bundleIdentifier: String,
        version: String,
        build: String,
        sourcePath: String? = nil,
        installedPath: String? = nil,
        builtAt: String? = nil,
        installedAt: String? = nil,
        gitBranch: String? = nil,
        gitCommit: String? = nil,
        workspaceRoot: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.product = product
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
        self.sourcePath = sourcePath
        self.installedPath = installedPath
        self.builtAt = builtAt
        self.installedAt = installedAt
        self.gitBranch = gitBranch
        self.gitCommit = gitCommit
        self.workspaceRoot = workspaceRoot
    }

    public var displayVersion: String {
        "\(version) (\(build))"
    }
}

public struct TalkieDevRuntimeManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let environment: String
    public let appsDirectory: String
    public let updatedAt: String
    public let products: [String: TalkieDevBuildManifest]

    public init(
        schemaVersion: Int = 1,
        environment: String,
        appsDirectory: String,
        updatedAt: String,
        products: [String: TalkieDevBuildManifest]
    ) {
        self.schemaVersion = schemaVersion
        self.environment = environment
        self.appsDirectory = appsDirectory
        self.updatedAt = updatedAt
        self.products = products
    }
}

public enum TalkieDevBuildManifestStore {
    public static let manifestsDirectoryName = ".talkie-dev-builds"
    public static let runtimeManifestFileName = ".talkie-dev-runtime.json"

    public static func appManifestURL(for appURL: URL) -> URL {
        let product = appURL.deletingPathExtension().lastPathComponent
        return appURL
            .deletingLastPathComponent()
            .appendingPathComponent(manifestsDirectoryName, isDirectory: true)
            .appendingPathComponent("\(product).json")
    }

    public static func runtimeManifestURL(appsDirectory: URL) -> URL {
        appsDirectory.appendingPathComponent(runtimeManifestFileName)
    }

    public static func readAppManifest(for appURL: URL) -> TalkieDevBuildManifest? {
        readManifest(at: appManifestURL(for: appURL), as: TalkieDevBuildManifest.self)
    }

    public static func readRuntimeManifest(appsDirectory: URL) -> TalkieDevRuntimeManifest? {
        readManifest(at: runtimeManifestURL(appsDirectory: appsDirectory), as: TalkieDevRuntimeManifest.self)
    }

    public static func bundleIdentity(for appURL: URL) -> TalkieBundleBuildIdentity? {
        let infoURL = appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")

        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        let bundleIdentifier = info["CFBundleIdentifier"] as? String
        guard let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String,
              !version.isEmpty,
              !build.isEmpty else {
            return nil
        }

        return TalkieBundleBuildIdentity(
            bundleIdentifier: bundleIdentifier,
            version: version,
            build: build
        )
    }

    private static func readManifest<T: Decodable>(at url: URL, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: data)
    }
}
