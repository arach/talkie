//
//  CodexChannelHistoryTests.swift
//  TalkieTests
//

import XCTest
@testable import Talkie_iOS

final class CodexChannelHistoryTests: XCTestCase {
    func testDecodesPublicChannelHistory() throws {
        let history = try JSONDecoder().decode(
            CodexChannelHistory.self,
            from: Data(historyJSON.utf8)
        )

        XCTAssertEqual(history.task.id, "task-1")
        XCTAssertEqual(history.turns.first?.latestInstruction, "Show me what changed")
        XCTAssertEqual(history.turns.first?.updates.first?.text, "Loaded the selected task")
        XCTAssertEqual(history.turns.first?.publicResponse, "History is ready.")
    }

    private var historyJSON: String {
        """
        {
          "task": {
            "id": "task-1",
            "title": "Improve Talkie history",
            "preview": "Add a useful activity trail",
            "cwd": "/Users/example/dev/talkie",
            "project": "talkie",
            "gitBranch": "codex/history",
            "gitOriginURL": null,
            "updatedAt": 1785456000
          },
          "turns": [
            {
              "id": "turn-1",
              "status": "completed",
              "startedAt": "2026-07-30T20:00:00.000Z",
              "completedAt": "2026-07-30T20:01:00.000Z",
              "durationMs": 60000,
              "instructions": ["Show me what changed"],
              "updates": [
                {
                  "id": "update-1",
                  "kind": "message",
                  "text": "Loaded the selected task",
                  "timestamp": "2026-07-30T20:00:10.000Z"
                }
              ],
              "response": "History is ready.\\n\\n<oai-mem-citation>private metadata</oai-mem-citation>",
              "error": null
            }
          ]
        }
        """
    }
}
