import Foundation
import XCTest
@testable import TalkieKit

final class LocalCheckoutLocatorTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    func testFindsTalkieServerByRemappingCompileTimeHomePath() throws {
        let homeURL = temporaryDirectoryURL.appendingPathComponent("art", isDirectory: true)
        let serverURL = homeURL
            .appendingPathComponent("dev", isDirectory: true)
            .appendingPathComponent("talkie", isDirectory: true)
            .appendingPathComponent("macOS", isDirectory: true)
            .appendingPathComponent("TalkieServer", isDirectory: true)

        try makeFile(
            at: serverURL
                .appendingPathComponent("src", isDirectory: true)
                .appendingPathComponent("server.ts")
        )

        let result = LocalCheckoutLocator.talkieServerSourceURL(
            compileTimeFilePath: "/Users/example/dev/talkie/apps/macos/TalkieAgent/TalkieAgent/Services/TalkieServerSupervisor.swift",
            currentDirectoryPath: temporaryDirectoryURL.path,
            homeDirectoryURL: homeURL
        )

        XCTAssertEqual(result?.standardizedFileURL.path, serverURL.standardizedFileURL.path)
    }

    func testFindsRepositoryFromCurrentDirectoryAncestors() throws {
        let repoRootURL = temporaryDirectoryURL.appendingPathComponent("talkie", isDirectory: true)
        let serverURL = repoRootURL
            .appendingPathComponent("macOS", isDirectory: true)
            .appendingPathComponent("TalkieServer", isDirectory: true)

        try makeFile(
            at: serverURL
                .appendingPathComponent("src", isDirectory: true)
                .appendingPathComponent("server.ts")
        )

        let currentDirectory = serverURL.path
        let result = LocalCheckoutLocator.talkieServerSourceURL(
            compileTimeFilePath: "/Users/example/dev/talkie/apps/macos/Talkie/Services/Bridge/BridgeManager.swift",
            currentDirectoryPath: currentDirectory,
            homeDirectoryURL: temporaryDirectoryURL.appendingPathComponent("home", isDirectory: true)
        )

        XCTAssertEqual(result?.standardizedFileURL.path, serverURL.standardizedFileURL.path)
    }

    func testPrefersExplicitTalkieServerOverride() throws {
        let explicitServerURL = temporaryDirectoryURL.appendingPathComponent("ExplicitServer", isDirectory: true)
        try makeFile(
            at: explicitServerURL
                .appendingPathComponent("src", isDirectory: true)
                .appendingPathComponent("server.ts")
        )

        let result = LocalCheckoutLocator.talkieServerSourceURL(
            compileTimeFilePath: "/Users/example/dev/talkie/apps/macos/Talkie/Services/Bridge/BridgeManager.swift",
            environment: ["TALKIE_SERVER_SOURCE_PATH": explicitServerURL.path],
            currentDirectoryPath: "/",
            homeDirectoryURL: temporaryDirectoryURL.appendingPathComponent("home", isDirectory: true)
        )

        XCTAssertEqual(result?.standardizedFileURL.path, explicitServerURL.standardizedFileURL.path)
    }

    func testFindsTalkieSpeechExecutableViaCurrentHomeRemap() throws {
        let homeURL = temporaryDirectoryURL.appendingPathComponent("art", isDirectory: true)
        let executableURL = homeURL
            .appendingPathComponent("dev", isDirectory: true)
            .appendingPathComponent("talkie", isDirectory: true)
            .appendingPathComponent("macOS", isDirectory: true)
            .appendingPathComponent("TalkieSpeech", isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("debug", isDirectory: true)
            .appendingPathComponent("TalkieSpeech")

        try makeExecutable(at: executableURL)

        let result = LocalCheckoutLocator.talkieSpeechExecutableURL(
            compileTimeFilePath: "/Users/example/dev/talkie/apps/macos/TalkieAgent/TalkieAgent/Services/TalkieSpeechSupervisor.swift",
            currentDirectoryPath: temporaryDirectoryURL.path,
            homeDirectoryURL: homeURL
        )

        XCTAssertEqual(result?.standardizedFileURL.path, executableURL.standardizedFileURL.path)
    }

    private func makeFile(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    private func makeExecutable(at url: URL) throws {
        try makeFile(at: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
