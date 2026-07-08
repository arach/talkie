import Foundation
import XCTest
@testable import TalkieKit

final class TalkieDevBuildManifestTests: XCTestCase {
    func testBundleIdentityReadsInfoPlistVersion() throws {
        let appURL = try makeAppBundle(
            product: "TalkieAgent",
            bundleIdentifier: "to.talkie.agent.dev",
            version: "2.5.28",
            build: "22"
        )
        defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }

        let identity = TalkieDevBuildManifestStore.bundleIdentity(for: appURL)

        XCTAssertEqual(identity?.bundleIdentifier, "to.talkie.agent.dev")
        XCTAssertEqual(identity?.version, "2.5.28")
        XCTAssertEqual(identity?.build, "22")
        XCTAssertEqual(identity?.displayVersion, "2.5.28 (22)")
    }

    func testAppManifestLivesBesideStableDevApp() throws {
        let appURL = try makeAppBundle(
            product: "TalkieAgent",
            bundleIdentifier: "to.talkie.agent.dev",
            version: "2.5.28",
            build: "22"
        )
        defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }

        let manifestURL = TalkieDevBuildManifestStore.appManifestURL(for: appURL)
        XCTAssertEqual(manifestURL.lastPathComponent, "TalkieAgent.json")
        XCTAssertEqual(manifestURL.deletingLastPathComponent().lastPathComponent, ".talkie-dev-builds")

        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let manifest = TalkieDevBuildManifest(
            product: "TalkieAgent",
            bundleIdentifier: "to.talkie.agent.dev",
            version: "2.5.28",
            build: "22",
            sourcePath: "/repo/build/TalkieAgent.app",
            installedPath: appURL.path,
            builtAt: "2026-06-29T12:00:00Z",
            installedAt: "2026-06-29T12:00:00Z",
            gitBranch: "codex/dev-selection",
            gitCommit: "abc123",
            workspaceRoot: "/repo"
        )
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL)

        let loaded = TalkieDevBuildManifestStore.readAppManifest(for: appURL)
        XCTAssertEqual(loaded, manifest)
    }

    private func makeAppBundle(
        product: String,
        bundleIdentifier: String,
        version: String,
        build: String
    ) throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkieDevBuildManifestTests-\(UUID().uuidString)", isDirectory: true)
        let contentsURL = rootURL
            .appendingPathComponent("\(product).app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)

        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))

        return rootURL.appendingPathComponent("\(product).app", isDirectory: true)
    }
}
