import Foundation
import XCTest
@testable import TalkieKit

final class TalkieContextCatalogTests: XCTestCase {
    func testCatalogValidatesRuleAndToolManifests() throws {
        let rootURL = try makeRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try createFile(
            at: rootURL.appending(path: "rules/selection-summary/rule.yaml"),
            contents: """
            id: selection-summary
            kind: route
            match:
              type: exact
              text: summarize this
            produce:
              runWorkflow: summarize-selection
            """
        )
        try createFile(
            at: rootURL.appending(path: "tools/jira-ticket/tool.yaml"),
            contents: """
            id: jira-ticket
            name: Jira Ticket
            runtime: node
            entry: run.ts
            """
        )
        try createFile(at: rootURL.appending(path: "workflows/selection-summary/workflow.json"), contents: "{}")

        let snapshot = TalkieContextCatalog().load(in: [.init(kind: .global, url: rootURL)])

        XCTAssertEqual(snapshot.summary.totalItems, 3)
        XCTAssertEqual(snapshot.summary.validItems, 2)
        XCTAssertEqual(snapshot.summary.unvalidatedItems, 1)
        XCTAssertEqual(snapshot.summary.invalidItems, 0)
        XCTAssertTrue(snapshot.problems.isEmpty)
    }

    func testCatalogSurfacesInvalidManifestProblems() throws {
        let rootURL = try makeRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try createFile(
            at: rootURL.appending(path: "tools/broken-tool/tool.yaml"),
            contents: """
            id: something-else
            name: Broken Tool
            runtime: shell
            entry: run.sh
            """
        )

        let snapshot = TalkieContextCatalog().load(in: [.init(kind: .global, url: rootURL)])

        XCTAssertEqual(snapshot.summary.invalidItems, 1)
        XCTAssertEqual(snapshot.problems.count, 1)
        XCTAssertEqual(
            snapshot.problems[0].message,
            "Manifest id `something-else` does not match folder id `broken-tool`."
        )
    }

    private func makeRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        return rootURL
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }
}
