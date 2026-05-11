import XCTest
@testable import TalkieKit

final class TalkieSelectionRuleResolverTests: XCTestCase {
    func testBuiltInCodexLongReadoutSummaryRuleResolvesSummaryPlan() throws {
        let resolver = TalkieSelectionRuleResolver()
        let context = TalkieSelectionRuleResolver.Context(
            text: String(repeating: "Long Codex output. ", count: 80),
            appName: "Codex"
        )

        let plan = try resolver.resolve(context: context)

        XCTAssertEqual(plan?.ruleID, "codex-long-readout-summary")
        XCTAssertEqual(plan?.workflowID, "summarize-selection")
        XCTAssertEqual(plan?.mode, .summary)
        XCTAssertEqual(plan?.profile, "codex-readout-summary")
        XCTAssertEqual(plan?.shouldPersist, false)
        XCTAssertNotNil(plan?.prompt)
        XCTAssertTrue(plan?.prompt?.contains("Selected text:") == true)
        XCTAssertTrue(plan?.systemPrompt?.contains("blockers") == true)
    }

    func testBuiltInCodexLongReadoutMemoryRulePersistsDurableReadouts() throws {
        let resolver = TalkieSelectionRuleResolver()
        let context = TalkieSelectionRuleResolver.Context(
            text: """
            This is a long Codex readout about a change we just made and why it matters.
            \(String(repeating: "Implementation detail and supporting context. ", count: 20))

            **Findings**
            - The migration path is safe.
            - The API surface stayed stable.

            **Next Steps**
            - Land the schema update.
            - Verify the new resolver in production.

            \(String(repeating: "Additional surrounding detail for the spoken readout. ", count: 20))
            """,
            appName: "Codex"
        )

        let plan = try resolver.resolve(context: context)

        XCTAssertEqual(plan?.ruleID, "codex-long-readout-memory")
        XCTAssertEqual(plan?.workflowID, "summarize-selection")
        XCTAssertEqual(plan?.mode, .summary)
        XCTAssertEqual(plan?.profile, "codex-readout-memory")
        XCTAssertEqual(plan?.shouldPersist, true)
        XCTAssertNotNil(plan?.prompt)
        XCTAssertTrue(plan?.systemPrompt?.contains("storing as memory") == true)
    }

    func testBuiltInCodexRuleDoesNotMatchShortSelection() throws {
        let resolver = TalkieSelectionRuleResolver()
        let context = TalkieSelectionRuleResolver.Context(
            text: "Short answer.",
            appName: "Codex"
        )

        let plan = try resolver.resolve(context: context)

        XCTAssertNil(plan)
    }

    func testBuiltInCodexRuleDoesNotMatchOtherApps() throws {
        let resolver = TalkieSelectionRuleResolver()
        let context = TalkieSelectionRuleResolver.Context(
            text: String(repeating: "Long browser output. ", count: 80),
            appName: "Safari"
        )

        let plan = try resolver.resolve(context: context)

        XCTAssertNil(plan)
    }
}
