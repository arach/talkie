import XCTest
@testable import TalkieKit

final class MarkdownDiffTests: XCTestCase {

    private func segments(_ old: String, _ new: String) -> [[String: Any]] {
        (MarkdownDiff.comparePayload(old: old, new: new)["segments"] as? [[String: Any]]) ?? []
    }
    private func status(_ seg: [String: Any]) -> String { seg["status"] as? String ?? "" }
    private func kind(_ seg: [String: Any]) -> String { seg["kind"] as? String ?? "" }

    func testIdenticalDocsAreAllEqual() {
        let doc = "# Title\n\nA paragraph.\n\n- one\n- two"
        let payload = MarkdownDiff.comparePayload(old: doc, new: doc)
        XCTAssertTrue(payload["identical"] as? Bool ?? false)
        let segs = payload["segments"] as? [[String: Any]] ?? []
        XCTAssertFalse(segs.isEmpty)
        XCTAssertTrue(segs.allSatisfy { status($0) == "equal" })
    }

    func testAddedParagraphIsAdded() {
        let old = "# Title\n\nFirst."
        let new = "# Title\n\nFirst.\n\nSecond."
        let segs = segments(old, new)
        XCTAssertEqual(segs.filter { status($0) == "added" }.count, 1)
        XCTAssertEqual(segs.filter { status($0) == "added" }.first.flatMap { $0["b"] as? String }, "Second.")
    }

    func testRemovedParagraphIsRemoved() {
        let old = "Keep.\n\nDrop me."
        let new = "Keep."
        let segs = segments(old, new)
        XCTAssertEqual(segs.filter { status($0) == "removed" }.count, 1)
    }

    func testEditedParagraphIsChangedWithWordOps() {
        let old = "The quick brown fox."
        let new = "The quick red fox."
        let segs = segments(old, new)
        let changed = segs.filter { status($0) == "changed" }
        XCTAssertEqual(changed.count, 1)
        let ops = changed[0]["wordOps"] as? [[String: Any]] ?? []
        XCTAssertTrue(ops.contains { ($0["t"] as? String) == "del" && ($0["w"] as? String) == "brown" })
        XCTAssertTrue(ops.contains { ($0["t"] as? String) == "ins" && ($0["w"] as? String) == "red" })
    }

    func testDictationBlockKeyedByIdShowsAsChangedWhenTranscriptEdited() {
        let old = "::: dictation id=\"tkd_a1\" duration=\"0:05\"\nHello there world.\n:::"
        let new = "::: dictation id=\"tkd_a1\" duration=\"0:05\"\nHello there, brave world.\n:::"
        let segs = segments(old, new)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(status(segs[0]), "changed")
        XCTAssertEqual(kind(segs[0]), "dictation")
        // atomic block — no word-dicing inside the fence
        XCTAssertNil(segs[0]["wordOps"])
    }

    func testDifferentDictationIdIsRemovePlusAdd() {
        let old = "::: dictation id=\"tkd_a1\"\nOne.\n:::"
        let new = "::: dictation id=\"tkd_b2\"\nTwo.\n:::"
        let segs = segments(old, new)
        XCTAssertEqual(segs.filter { status($0) == "removed" }.count, 1)
        XCTAssertEqual(segs.filter { status($0) == "added" }.count, 1)
    }

    func testHeadingEditIsChanged() {
        let old = "# Home screen — notes\n\nBody."
        let new = "# Home screen — redesign notes\n\nBody."
        let segs = segments(old, new)
        let changed = segs.filter { status($0) == "changed" && kind($0) == "heading" }
        XCTAssertEqual(changed.count, 1)
    }

    func testCodeFenceIsAtomicAndKindedCode() {
        let old = "```bash\ntalkie export\n```"
        let new = "```bash\ntalkie export --home\n```"
        let segs = segments(old, new)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(kind(segs[0]), "code")
        XCTAssertEqual(status(segs[0]), "changed")
        XCTAssertNil(segs[0]["wordOps"]) // atomic
    }
}
