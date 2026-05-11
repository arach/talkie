import XCTest
@testable import TalkieKit

final class FeedbackLogRedactorTests: XCTestCase {
    func testRedactsPromptAndPreservesOperationalMetadata() {
        let line = "2026-04-29T12:00:00Z|Talkie|WORKFLOW|LLM: Starting generation (prompt: please rewrite my private note, hasSystemPrompt: true)|"

        let redacted = FeedbackLogRedactor.redact(line)

        XCTAssertFalse(redacted.contains("private note"))
        XCTAssertTrue(redacted.contains("prompt: [redacted], hasSystemPrompt: true"))
    }

    func testRedactsTranscriptionSnippets() {
        let line = "2026-04-29T12:00:00Z|Talkie|TRANSCRIPTION|Apple Speech transcription complete: call Sam about the acquisition..."

        let redacted = FeedbackLogRedactor.redact(line)

        XCTAssertFalse(redacted.contains("call Sam"))
        XCTAssertTrue(redacted.contains("Apple Speech transcription complete: [redacted]"))
    }

    func testRedactsSensitiveJSONAndPaths() {
        let line = #"detail={"prompt":"summarize my diary","transcript":"I feel worried","content":"raw user message","file":"/Users/example/Documents/a.wav"}"#

        let redacted = FeedbackLogRedactor.redact(line)

        XCTAssertFalse(redacted.contains("summarize my diary"))
        XCTAssertFalse(redacted.contains("I feel worried"))
        XCTAssertFalse(redacted.contains("raw user message"))
        XCTAssertFalse(redacted.contains("/Users/example"))
        XCTAssertTrue(redacted.contains(#""prompt":"[redacted]""#))
        XCTAssertTrue(redacted.contains(#""transcript":"[redacted]""#))
        XCTAssertTrue(redacted.contains("/Users/***"))
    }

    func testRedactsPromptAndTranscriptQueryValues() {
        let line = "talkie://capture?prompt=fix%20this%20private%20text&transcript=secret&q=search"

        let redacted = FeedbackLogRedactor.redact(line)

        XCTAssertFalse(redacted.contains("private"))
        XCTAssertFalse(redacted.contains("secret"))
        XCTAssertFalse(redacted.contains("search"))
        XCTAssertTrue(redacted.contains("prompt=[redacted]"))
        XCTAssertTrue(redacted.contains("transcript=[redacted]"))
        XCTAssertTrue(redacted.contains("q=[redacted]"))
    }
}
