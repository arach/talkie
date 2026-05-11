import Foundation
import XCTest
@testable import TalkieKit

final class TalkieContextDiscoveryTests: XCTestCase {
    func testDiscoversConventionalItemsAcrossAllKinds() throws {
        let rootURL = try makeRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        try createFile(at: rootURL.appending(path: "rules/normalize-company/rule.yaml"), contents: "id: normalize-company\n")
        try createFile(at: rootURL.appending(path: "tools/jira-ticket/tool.yaml"), contents: "id: jira-ticket\n")
        try createFile(at: rootURL.appending(path: "workflows/slack-summary/workflow.json"), contents: "{}\n")
        try createFile(at: rootURL.appending(path: "automations/morning-inbox/automation.yaml"), contents: "id: morning-inbox\n")

        let snapshot = TalkieContextDiscovery().discover(
            in: [.init(kind: .global, url: rootURL)]
        )

        XCTAssertEqual(snapshot.items.count, 4)
        XCTAssertTrue(snapshot.problems.isEmpty)
        XCTAssertEqual(snapshot.item(id: "normalize-company", kind: .rule)?.entryURL.lastPathComponent, "rule.yaml")
        XCTAssertEqual(snapshot.item(id: "jira-ticket", kind: .tool)?.entryURL.lastPathComponent, "tool.yaml")
        XCTAssertEqual(snapshot.item(id: "slack-summary", kind: .workflow)?.entryURL.lastPathComponent, "workflow.json")
        XCTAssertEqual(snapshot.item(id: "morning-inbox", kind: .automation)?.entryURL.lastPathComponent, "automation.yaml")
    }

    func testWorkspaceRootsShadowLowerPriorityRoots() throws {
        let globalRootURL = try makeRoot()
        let workspaceRootURL = try makeRoot()
        defer {
            try? FileManager.default.removeItem(at: globalRootURL)
            try? FileManager.default.removeItem(at: workspaceRootURL)
        }

        try createFile(at: globalRootURL.appending(path: "rules/summarize-for-slack/rule.yaml"), contents: "id: summarize-for-slack\n")
        try createFile(at: workspaceRootURL.appending(path: "rules/summarize-for-slack/rule.yaml"), contents: "id: summarize-for-slack\n")

        let snapshot = TalkieContextDiscovery().discover(
            in: [
                .init(kind: .global, url: globalRootURL),
                .init(kind: .workspace, url: workspaceRootURL),
            ]
        )

        XCTAssertEqual(snapshot.item(id: "summarize-for-slack", kind: .rule)?.root.kind, .workspace)
        XCTAssertEqual(snapshot.problems.count, 1)

        guard case let .duplicateItem(shadowedByRoot) = snapshot.problems[0].reason else {
            return XCTFail("Expected duplicate item warning.")
        }

        XCTAssertEqual(shadowedByRoot, workspaceRootURL.standardizedFileURL)
    }

    func testReportsMissingEntryFiles() throws {
        let rootURL = try makeRoot()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let toolDirectoryURL = rootURL.appending(path: "tools/broken-tool", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: toolDirectoryURL, withIntermediateDirectories: true)

        let snapshot = TalkieContextDiscovery().discover(
            in: [.init(kind: .global, url: rootURL)]
        )

        XCTAssertEqual(snapshot.items.count, 0)
        XCTAssertEqual(snapshot.problems.count, 1)
        XCTAssertEqual(snapshot.problems[0].severity, .error)

        guard case let .missingEntry(expected) = snapshot.problems[0].reason else {
            return XCTFail("Expected missing entry error.")
        }

        XCTAssertEqual(expected, "tool.yaml")
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
