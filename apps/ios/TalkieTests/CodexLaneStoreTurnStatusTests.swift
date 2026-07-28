//
//  CodexLaneStoreTurnStatusTests.swift
//  TalkieTests
//

import XCTest
@testable import Talkie_iOS

@MainActor
final class CodexLaneStoreTurnStatusTests: XCTestCase {
    func testMissingReceiptIsTerminal() {
        let error = BridgeError.httpError(
            404,
            detail: "This Codex turn receipt is no longer available."
        )

        XCTAssertFalse(CodexLaneStore.shouldRetryTurnStatus(after: error))
    }

    func testServerAndNetworkFailuresRemainRetryable() {
        XCTAssertTrue(
            CodexLaneStore.shouldRetryTurnStatus(
                after: BridgeError.httpError(503, detail: "Restarting")
            )
        )
        XCTAssertTrue(
            CodexLaneStore.shouldRetryTurnStatus(
                after: URLError(.networkConnectionLost)
            )
        )
    }

    func testAuthenticationAndProtocolFailuresAreTerminal() {
        XCTAssertFalse(
            CodexLaneStore.shouldRetryTurnStatus(
                after: BridgeError.httpError(401, detail: "Pair again")
            )
        )
        XCTAssertFalse(
            CodexLaneStore.shouldRetryTurnStatus(after: BridgeError.invalidResponse)
        )
    }
}
