//
//  CodexLaneActivityTests.swift
//  TalkieTests
//

import XCTest
@testable import Talkie_iOS

final class CodexLaneActivityTests: XCTestCase {
    func testStatusSeparatesSendingFromHostReceipt() {
        var activity = CodexLaneActivity(
            instruction: "Check the iPhone bridge",
            state: .working(.steer)
        )

        XCTAssertEqual(activity.statusLabel, "SENDING")

        activity.jobID = "job-1"

        XCTAssertEqual(activity.statusLabel, "RECEIVED")
    }

    func testStatusReportsCodexAcceptanceAndResponse() {
        var activity = CodexLaneActivity(
            instruction: "Check the iPhone bridge",
            jobID: "job-1",
            state: .accepted(.startedTurn)
        )

        XCTAssertEqual(activity.statusLabel, "WORKING")

        activity.state = .receiving(.startedTurn)

        XCTAssertEqual(activity.statusLabel, "RESPONSE")
    }

    func testRetryMakesSameDispatchReconnectionVisible() {
        let activity = CodexLaneActivity(
            instruction: "Check the iPhone bridge",
            jobID: "job-1",
            retryCount: 2,
            state: .accepted(.startedTurn)
        )

        XCTAssertEqual(activity.statusLabel, "RECONNECTING")
    }
}
