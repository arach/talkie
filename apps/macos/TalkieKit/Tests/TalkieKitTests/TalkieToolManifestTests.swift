import Foundation
import XCTest
@testable import TalkieKit

final class TalkieToolManifestTests: XCTestCase {
    func testLoadsToolManifest() throws {
        let fileURL = try makeManifestFile(
            """
            id: jira-ticket
            name: Jira Ticket
            enabled: true
            runtime: node
            entry: run.ts
            input: talkie/v1
            timeoutMs: 15000
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let manifest = try TalkieToolManifest.load(from: fileURL)
        try manifest.validate(expectedID: "jira-ticket")

        XCTAssertEqual(manifest.runtime, .node)
        XCTAssertEqual(manifest.timeoutMs, 15_000)
    }

    func testRejectsUnknownRuntime() throws {
        let fileURL = try makeManifestFile(
            """
            id: jira-ticket
            name: Jira Ticket
            runtime: deno
            entry: run.ts
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        XCTAssertThrowsError(try TalkieToolManifest.load(from: fileURL)) { error in
            XCTAssertEqual(error.localizedDescription, "Unknown runtime `deno`.")
        }
    }

    private func makeManifestFile(_ source: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appending(path: "tool.yaml")
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
