import XCTest
@testable import TalkieKit

final class LiveSidecarTests: XCTestCase {
    func testFeedbackPromptIncludesTranscriptAndContext() {
        let prompt = LiveSidecarPromptBuilder.build(
            kind: .feedback,
            transcript: "I think we should turn long brainstorming calls into structured artifacts.",
            appName: "Talkie",
            windowTitle: "Brainstorm"
        )

        XCTAssertTrue(prompt.system.contains("constructive feedback"))
        XCTAssertTrue(prompt.user.contains("App: Talkie"))
        XCTAssertTrue(prompt.user.contains("Window: Brainstorm"))
        XCTAssertTrue(prompt.user.contains("structured artifacts"))
        XCTAssertTrue(prompt.user.contains("3 to 5 short bullets"))
    }

    func testResearchPromptTellsModelNotToInventFacts() {
        let prompt = LiveSidecarPromptBuilder.build(
            kind: .research,
            transcript: "We should compare local speech models for long-form note capture."
        )

        XCTAssertTrue(prompt.system.contains("inventing facts"))
        XCTAssertTrue(prompt.user.contains("best next research directions"))
        XCTAssertTrue(prompt.user.contains("local speech models"))
    }

    func testProvenanceDetailCarriesKindProviderAndModel() {
        let detail = LiveSidecarPromptBuilder.provenanceDetail(
            kind: .research,
            providerName: "OpenAI",
            modelId: "gpt-5.2-chat-latest"
        )

        XCTAssertEqual(detail, "Live research · OpenAI · gpt-5.2-chat-latest")
    }
}
