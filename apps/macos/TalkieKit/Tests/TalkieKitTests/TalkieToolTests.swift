import Foundation
import XCTest
@testable import TalkieKit

final class TalkieToolTests: XCTestCase {
    func testRoundTripsToolInputThroughJSON() throws {
        let input = TalkieTool.Input(
            event: "selection.summarize",
            text: "Summarize this output.",
            vars: ["profile": "codex-readout"],
            context: .init(
                appName: "Codex",
                bundleID: "com.openai.codex",
                source: "selection",
                workspacePath: "/Users/example/dev/talkie",
                timestamp: "2026-03-24T13:05:00Z"
            )
        )

        let data = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(TalkieTool.Input.self, from: data)

        XCTAssertEqual(decoded, input)
        XCTAssertEqual(decoded.version, TalkieTool.schemaVersion)
    }

    func testRoundTripsToolOutputEffectsThroughJSON() throws {
        let output = TalkieTool.Output(
            effects: [
                .init(
                    type: .runWorkflow,
                    workflow: "summarize-selection",
                    vars: ["profile": "codex-readout"]
                ),
                .init(
                    type: .notify,
                    title: "Summary Ready",
                    message: "Codex readout prepared."
                ),
            ]
        )

        let data = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(TalkieTool.Output.self, from: data)

        XCTAssertEqual(decoded, output)
    }
}
