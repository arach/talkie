//
//  TalkieAIProviderCredentialOCRServiceTests.swift
//  TalkieTests
//
//  Tests for `TalkieAIProviderCredentialOCRService`, the static utility that
//  extracts API keys (OpenAI `sk-...`, Groq `gsk_...`) from noisy OCR text.
//
//  These tests deliberately avoid asserting on internal heuristic scores or
//  exact stitch ordering beyond the documented invariants in the source —
//  see comments in `TalkieAIProviderCredentialOCRService.swift` for details.
//

import XCTest
@testable import Talkie_iOS

final class TalkieAIProviderCredentialOCRServiceTests: XCTestCase {

    // MARK: - candidates(in:)

    func test_candidates_findsStandaloneOpenAIKey() {
        let text = "Header line\nYour key: sk-ABCDEFGHIJKLMNOPQRST\nFooter"
        let candidates = TalkieAIProviderCredentialOCRService.candidates(in: text)

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.apiKey, "sk-ABCDEFGHIJKLMNOPQRST")
        XCTAssertEqual(candidates.first?.providerId, "openai")
    }

    func test_candidates_findsStandaloneGroqKey() {
        let text = "Provider: Groq\ngsk_ABCDEFGHIJKLMNOPQRSTUV\nDone."
        let candidates = TalkieAIProviderCredentialOCRService.candidates(in: text)

        XCTAssertTrue(candidates.contains(where: { $0.apiKey == "gsk_ABCDEFGHIJKLMNOPQRSTUV" && $0.providerId == "groq" }))
    }

    func test_candidates_sortedByLengthDescending() {
        let shorter = "sk-AAAAAAAAAAAAAAAAAAAA"           // 23 chars (sk- + 20)
        let longer  = "sk-BBBBBBBBBBBBBBBBBBBBBBBBBBBB"   // 31 chars (sk- + 28)
        let text = "first \(shorter) middle \(longer) end"

        let candidates = TalkieAIProviderCredentialOCRService.candidates(in: text)

        XCTAssertGreaterThanOrEqual(candidates.count, 2)
        // Longer key must come first.
        XCTAssertEqual(candidates.first?.apiKey, longer)
        XCTAssertGreaterThanOrEqual(candidates[0].apiKey.count, candidates[1].apiKey.count)
    }

    func test_candidates_returnsEmptyForProse() {
        let text = "The quick brown fox jumps over the lazy dog."
        let candidates = TalkieAIProviderCredentialOCRService.candidates(in: text)

        XCTAssertTrue(candidates.isEmpty)
    }

    func test_candidates_rejectsMaskedKeys() {
        let asteriskMasked = "sk-ABCDEFGH************XYZ"
        let bulletMasked   = "sk-ABCDEFGH••••••••••••XYZ"

        XCTAssertTrue(TalkieAIProviderCredentialOCRService.candidates(in: asteriskMasked).isEmpty)
        XCTAssertTrue(TalkieAIProviderCredentialOCRService.candidates(in: bulletMasked).isEmpty)
    }

    func test_candidates_recoversKeyBrokenAcrossWhitespace() {
        // The full key is sk-ABCDEFGHIJKLMNOPQRSTUV (25 chars) split by newlines.
        let text = "sk-ABCD\nEFGHIJ\nKLMNOPQRSTUV"
        let candidates = TalkieAIProviderCredentialOCRService.candidates(in: text)

        // After whitespace compaction, the key should be recovered.
        XCTAssertTrue(
            candidates.contains(where: { $0.apiKey == "sk-ABCDEFGHIJKLMNOPQRSTUV" }),
            "Expected compaction to recover the broken key; got \(candidates.map(\.apiKey))"
        )
    }

    // MARK: - stitchCandidates(from:)

    func test_stitchCandidates_mergesExactOverlapFragments() {
        // Fragments overlap by 4 chars each. The merge target is the longer
        // alphanumeric chain. We seed with an `sk-` prefixed fragment so the
        // stitcher can produce a provider-prefixed candidate.
        let fragments = [
            "sk-ABCDEFGHIJKL",
            "GHIJKLMNOPQRSTUV",
            "MNOPQRSTUVWXYZ12"
        ]

        let candidates = TalkieAIProviderCredentialOCRService.stitchCandidates(from: fragments)

        XCTAssertFalse(candidates.isEmpty, "Expected at least one stitch candidate")
        XCTAssertLessThanOrEqual(candidates.count, 4, "stitchCandidates is documented to cap at 4")

        // The best candidate should be at least as long as the longest single fragment.
        let longestFragment = fragments.map(\.count).max() ?? 0
        XCTAssertGreaterThanOrEqual(
            candidates.first?.apiKey.count ?? 0,
            longestFragment,
            "Expected stitched candidate to be at least as long as the longest fragment"
        )
    }

    func test_stitchCandidates_returnsCandidateForSinglePrefixedFragment() {
        let fragments = ["sk-ABCDEFGHIJKLMNOPQRST"] // 23 chars, valid shape
        let candidates = TalkieAIProviderCredentialOCRService.stitchCandidates(from: fragments)

        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains(where: { $0.apiKey == "sk-ABCDEFGHIJKLMNOPQRST" }))
    }

    func test_stitchCandidates_returnsEmptyForNonKeyFragments() {
        // Common English words; none look like a key fragment per isLikelyKeyFragment.
        let fragments = ["the", "quick", "brown", "fox"]
        let candidates = TalkieAIProviderCredentialOCRService.stitchCandidates(from: fragments)

        XCTAssertTrue(candidates.isEmpty, "Expected no candidates from prose fragments; got \(candidates.map(\.apiKey))")
    }

    func test_stitchCandidates_validShapeRanksFirst() {
        // Mix one fragment that is a full valid-shape key with one that isn't.
        let valid = "sk-ABCDEFGHIJKLMNOPQRSTUVWX" // 27 chars, valid shape
        let scrap = "z9q2vbnmasdfghjklqwer"       // alphanumeric, no sk- prefix

        let candidates = TalkieAIProviderCredentialOCRService.stitchCandidates(from: [valid, scrap])

        XCTAssertFalse(candidates.isEmpty)
        // The source's stitchCandidateSort puts isValidShape candidates first.
        XCTAssertTrue(
            candidates.first?.isValidShape == true,
            "Expected valid-shape candidate to rank first; got \(candidates.map { ($0.apiKey, $0.isValidShape) })"
        )
    }

    // MARK: - localComparison(candidate:expected:)

    func test_localComparison_identicalStringsMatchExactly() {
        let key = "sk-ABCDEFGHIJKLMNOPQRSTUVWX"
        let result = TalkieAIProviderCredentialOCRService.localComparison(candidate: key, expected: key)

        XCTAssertTrue(result.isMatch)
        XCTAssertEqual(result.similarity, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.editDistance, 0)
        XCTAssertEqual(result.candidateLength, key.count)
        XCTAssertEqual(result.expectedLength, key.count)
    }

    func test_localComparison_singleSubstitution() {
        let expected = "sk-ABCDEFGHIJKLMNOPQRSTUVWX"
        // Flip the last character.
        let candidate = "sk-ABCDEFGHIJKLMNOPQRSTUVWY"

        let result = TalkieAIProviderCredentialOCRService.localComparison(candidate: candidate, expected: expected)

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.editDistance, 1)
        XCTAssertGreaterThan(result.similarity, 0.9)
        XCTAssertLessThan(result.similarity, 1.0)
    }

    func test_localComparison_emptyCandidate() {
        let expected = "sk-ABCDEFGHIJKLMNOPQRSTUVWX"
        let result = TalkieAIProviderCredentialOCRService.localComparison(candidate: "", expected: expected)

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.similarity, 0)
        XCTAssertEqual(result.editDistance, max(0, expected.count))
    }

    func test_localComparison_emptyExpected() {
        let candidate = "sk-ABCDEFGHIJKLMNOPQRSTUVWX"
        let result = TalkieAIProviderCredentialOCRService.localComparison(candidate: candidate, expected: "")

        XCTAssertFalse(result.isMatch)
        XCTAssertEqual(result.similarity, 0)
        XCTAssertEqual(result.editDistance, max(candidate.count, 0))
    }

    func test_localComparison_differentLengthsSensible() {
        let candidate = "sk-AB"
        let expected = "sk-ABCDEFGHIJKLMNOPQRSTUVWX"
        let result = TalkieAIProviderCredentialOCRService.localComparison(candidate: candidate, expected: expected)

        XCTAssertFalse(result.isMatch)
        XCTAssertGreaterThan(result.similarity, 0)
        XCTAssertLessThan(result.similarity, 1)
    }

    // MARK: - keyFragments(in:)

    func test_keyFragments_extractsPrefixedFragments() {
        let text = "Capture: sk-ABCDEFGHIJ and also gsk_ZYXWVUTSRQ"
        let fragments = TalkieAIProviderCredentialOCRService.keyFragments(in: text)

        XCTAssertTrue(fragments.contains(where: { $0.hasPrefix("sk-") && $0.count >= 6 }))
        XCTAssertTrue(fragments.contains(where: { $0.hasPrefix("gsk_") && $0.count >= 6 }))
    }

    func test_keyFragments_extractsBareAlphanumericFragment() {
        // Mixed-case + digit fragment with length >= 10 -> passes isLikelyKeyFragment.
        let text = "Token: Ab1CdEf2GhIj fragment"
        let fragments = TalkieAIProviderCredentialOCRService.keyFragments(in: text)

        XCTAssertTrue(
            fragments.contains("Ab1CdEf2GhIj"),
            "Expected mixed-case digit fragment to be captured; got \(fragments)"
        )
    }

    func test_keyFragments_rejectsCommonEnglishWords() {
        let text = "The quick brown fox jumps over the lazy dog"
        let fragments = TalkieAIProviderCredentialOCRService.keyFragments(in: text)

        for word in ["the", "The", "quick", "brown", "fox", "lazy", "dog"] {
            XCTAssertFalse(
                fragments.contains(word),
                "Did not expect English word \"\(word)\" in fragments; got \(fragments)"
            )
        }
    }

    // MARK: - bestDraft(in:)

    func test_bestDraft_returnsLongestCompleteCandidateWhenAvailable() {
        let shorter = "sk-AAAAAAAAAAAAAAAAAAAA"            // 23 chars
        let longer  = "sk-BBBBBBBBBBBBBBBBBBBBBBBBBB"      // 29 chars
        let text = "noise \(shorter) more noise \(longer) end"

        let draft = TalkieAIProviderCredentialOCRService.bestDraft(in: text)

        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.apiKey, longer)
    }

    func test_bestDraft_fallsBackToPartialPrefix() {
        // Less than the 20-char threshold required for a "complete" key,
        // but still >= 8 chars after the prefix -> qualifies as a draft.
        let text = "sk-ABCDEFGH"
        let draft = TalkieAIProviderCredentialOCRService.bestDraft(in: text)

        XCTAssertNotNil(draft)
        XCTAssertEqual(draft?.apiKey, "sk-ABCDEFGH")
        XCTAssertEqual(draft?.providerId, "openai")
    }

    func test_bestDraft_returnsNilForTextWithoutAnyKeyPrefix() {
        let text = "There is no key whatsoever in this string."
        let draft = TalkieAIProviderCredentialOCRService.bestDraft(in: text)

        XCTAssertNil(draft)
    }
}
