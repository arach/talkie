import XCTest
@testable import TalkieKit

final class TokenNormalizationTests: XCTestCase {
    func testNaturalSpacingPreservesSpaceAfterNumberToken() {
        let processor = ComposedTokenProcessor(
            ruleSets: [PunctuationProcessor(), NumberProcessor(convertSingleDigits: false)],
            spacing: .natural
        )

        let result = processor.process("chapter forty two begins")

        XCTAssertEqual(result, "chapter 42 begins")
    }

    func testNaturalSpacingPreservesSpaceAfterSentencePunctuationFollowingNumber() {
        let processor = ComposedTokenProcessor(
            ruleSets: [PunctuationProcessor(), NumberProcessor(convertSingleDigits: false)],
            spacing: .natural
        )

        let result = processor.process("chapter forty two period next sentence")

        XCTAssertEqual(result, "chapter 42. next sentence")
    }

    func testNaturalSpacingConvertsCompoundHundreds() {
        let processor = ComposedTokenProcessor(
            ruleSets: [PunctuationProcessor(), NumberProcessor(convertSingleDigits: false)],
            spacing: .natural
        )

        let result = processor.process("budget two hundred five dollars")

        XCTAssertEqual(result, "budget 205 dollars")
    }

    func testNaturalSpacingConvertsThousands() {
        let processor = ComposedTokenProcessor(
            ruleSets: [PunctuationProcessor(), NumberProcessor(convertSingleDigits: false)],
            spacing: .natural
        )

        let result = processor.process("year two thousand twenty four")

        XCTAssertEqual(result, "year 2024")
    }

    func testInverseTextNormalizerUpdatesTimedTranscriptionTextOnly() {
        let timed = TimedTranscription(
            text: "chapter forty two begins",
            words: [
                WordSegment(word: "chapter", start: 0, end: 0.5),
                WordSegment(word: " forty", start: 0.5, end: 0.8),
                WordSegment(word: " two", start: 0.8, end: 1.1),
                WordSegment(word: " begins", start: 1.1, end: 1.6),
            ]
        )

        let normalized = InverseTextNormalizer.normalize(timed)

        XCTAssertEqual(normalized.text, "chapter 42 begins")
        XCTAssertEqual(normalized.words, timed.words)
    }
}
