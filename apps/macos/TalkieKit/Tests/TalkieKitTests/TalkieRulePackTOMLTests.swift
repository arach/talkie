import XCTest
@testable import TalkieKit

final class TalkieRulePackTOMLTests: XCTestCase {
    func testRoundTripsStarterPackThroughTOML() throws {
        let pack = TalkieRulePack.starterPack()

        let source = TalkieRulePackTOML.encode(pack)
        let decoded = try TalkieRulePackTOML.decode(source)

        XCTAssertEqual(decoded, pack)
    }

    func testParsesCommentsAndStructuredTransforms() throws {
        let source = """
        version = 1
        id = "terminal-rules"
        name = "Terminal Rules"
        description = "Examples" # inline comment

        [[rules]]
        id = "bun-run-script"
        kind = "rewrite"
        scope = ["natural", "terminal"]
        priority = 100
        match = "bun run {script...}"
        emit = "bun run {{script}}"

        [rules.transforms]
        script = [{ op = "lowercase" }, { op = "split", mode = "words" }, { op = "join", separator = ":" }]

        [[tests]]
        rule = "bun-run-script"
        scope = "terminal"
        input = "Bun run Native App Build"
        output = "bun run native:app:build"
        """

        let pack = try TalkieRulePackTOML.decode(source)

        XCTAssertEqual(pack.id, "terminal-rules")
        XCTAssertEqual(pack.rules.first?.transforms["script"]?.count, 3)
        XCTAssertEqual(pack.tests.first?.output, "bun run native:app:build")
    }

    func testThrowsHelpfulLineErrorsForInvalidRuleScope() {
        let source = """
        version = 1
        id = "terminal-rules"
        name = "Terminal Rules"

        [[rules]]
        id = "bun-run-script"
        kind = "rewrite"
        scope = ["terminally"]
        match = "bun run {script...}"
        emit = "bun run {{script}}"
        """

        XCTAssertThrowsError(try TalkieRulePackTOML.decode(source)) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "Line 8: Unknown rule scope `terminally`."
            )
        }
    }
}
