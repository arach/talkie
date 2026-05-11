import Foundation
import XCTest
@testable import TalkieKit

final class TalkieRuleManifestTests: XCTestCase {
    func testLoadsRouteRuleManifestWithSelectorsAndVars() throws {
        let fileURL = try makeManifestFile(
            """
            id: codex-selection-summary
            kind: route
            name: Codex Selection Summary
            enabled: true
            priority: 200
            when:
              event: selection.summarize
              apps: [Codex]
              sources: [selection]
              minConfidence: 0.8
            match:
              type: regex
              pattern: "^summarize (.+)$"
            produce:
              runWorkflow: summarize-selection
              vars:
                profile: codex-readout
                topic: "$1"
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let manifest = try TalkieRuleManifest.load(from: fileURL)
        try manifest.validate(expectedID: "codex-selection-summary")

        XCTAssertEqual(manifest.kind, .route)
        XCTAssertEqual(manifest.when.apps, ["Codex"])
        XCTAssertEqual(manifest.when.minConfidence, 0.8)
        XCTAssertEqual(manifest.produce.runWorkflow, "summarize-selection")
        XCTAssertEqual(manifest.produce.vars["profile"], "codex-readout")
    }

    func testRejectsInvalidRegexRuleManifest() throws {
        let fileURL = try makeManifestFile(
            """
            id: broken-rule
            kind: route
            match:
              type: regex
              pattern: "*("
            produce:
              runWorkflow: summarize-selection
            """
        )
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let manifest = try TalkieRuleManifest.load(from: fileURL)

        XCTAssertThrowsError(try manifest.validate(expectedID: "broken-rule")) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Invalid regex pattern `*(`."
            )
        }
    }

    private func makeManifestFile(_ source: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appending(path: "rule.yaml")
        try source.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
