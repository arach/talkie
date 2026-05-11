import XCTest
@testable import TalkieKit

final class TalkieRuleExecutorTests: XCTestCase {
    func testRewriteAppliesMatchTransformAndEmit() {
        let pack = TalkieRulePack(
            id: "terminal-rules",
            name: "Terminal Rules",
            rules: [
                .init(
                    id: "bun-run-script",
                    scope: [.natural, .terminal],
                    priority: 100,
                    match: "bun run {script...}",
                    emit: "bun run {{script}}",
                    transforms: [
                        "script": [
                            .init(op: .lowercase),
                            .init(op: .split, mode: .words),
                            .init(op: .join, separator: ":"),
                        ]
                    ]
                )
            ]
        )

        let match = TalkieRuleExecutor.shared.rewrite(
            "Bun run Native    App Build",
            scope: .terminal,
            packs: [pack]
        )

        XCTAssertEqual(
            match,
            .init(
                output: "bun run native:app:build",
                packID: "terminal-rules",
                ruleID: "bun-run-script"
            )
        )
    }

    func testRewriteReturnsNilWhenLiteralDoesNotMatch() {
        let pack = TalkieRulePack(
            id: "terminal-rules",
            name: "Terminal Rules",
            rules: [
                .init(
                    id: "bun-run-script",
                    scope: [.terminal],
                    priority: 100,
                    match: "bun run {script...}",
                    emit: "bun run {{script}}"
                )
            ]
        )

        let match = TalkieRuleExecutor.shared.rewrite(
            "npm run build",
            scope: .terminal,
            packs: [pack]
        )

        XCTAssertNil(match)
    }
}
