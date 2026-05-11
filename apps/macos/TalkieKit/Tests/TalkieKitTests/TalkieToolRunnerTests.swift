import Foundation
import XCTest
@testable import TalkieKit

final class TalkieToolRunnerTests: XCTestCase {
    func testRunsShellToolAndDecodesOutput() async throws {
        let toolDirectoryURL = try makeToolDirectory(
            id: "notify-user",
            runtime: .shell,
            entry: "run.sh",
            timeoutMs: 1_000,
            script: """
            cat >/dev/null
            printf '{"effects":[{"type":"notify","message":"done"}]}'
            """
        )
        defer { try? FileManager.default.removeItem(at: toolDirectoryURL) }

        let result = try await TalkieToolRunner().run(
            manifest: try TalkieToolManifest.load(from: toolDirectoryURL.appending(path: "tool.yaml")),
            in: toolDirectoryURL,
            input: TalkieTool.Input(
                event: "selection.summarize",
                text: "summarize this",
                context: .init(appName: "Codex")
            )
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.output.effects.count, 1)
        XCTAssertEqual(result.output.effects[0].type, .notify)
        XCTAssertEqual(result.output.effects[0].message, "done")
    }

    func testTimesOutLongRunningTool() async throws {
        let toolDirectoryURL = try makeToolDirectory(
            id: "slow-tool",
            runtime: .shell,
            entry: "run.sh",
            timeoutMs: 100,
            script: """
            sleep 2
            printf '{"effects":[]}'
            """
        )
        defer { try? FileManager.default.removeItem(at: toolDirectoryURL) }

        let manifest = try TalkieToolManifest.load(from: toolDirectoryURL.appending(path: "tool.yaml"))

        do {
            _ = try await TalkieToolRunner().run(
                manifest: manifest,
                in: toolDirectoryURL,
                input: TalkieTool.Input(
                    event: "selection.summarize",
                    text: "summarize this",
                    context: .init()
                )
            )
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Tool `slow-tool` timed out after 100ms.")
        }
    }

    func testRejectsInvalidJSONOutput() async throws {
        let toolDirectoryURL = try makeToolDirectory(
            id: "broken-tool",
            runtime: .shell,
            entry: "run.sh",
            timeoutMs: 1_000,
            script: """
            cat >/dev/null
            printf 'not-json'
            """
        )
        defer { try? FileManager.default.removeItem(at: toolDirectoryURL) }

        let manifest = try TalkieToolManifest.load(from: toolDirectoryURL.appending(path: "tool.yaml"))

        do {
            _ = try await TalkieToolRunner().run(
                manifest: manifest,
                in: toolDirectoryURL,
                input: TalkieTool.Input(
                    event: "selection.summarize",
                    text: "summarize this",
                    context: .init()
                )
            )
            XCTFail("Expected invalid JSON output")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Tool `broken-tool` returned invalid JSON output: not-json"
            )
        }
    }

    private func makeToolDirectory(
        id: String,
        runtime: TalkieToolManifest.Runtime,
        entry: String,
        timeoutMs: Int,
        script: String
    ) throws -> URL {
        let toolDirectoryURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: toolDirectoryURL, withIntermediateDirectories: true)

        let manifest = """
        id: \(id)
        name: \(id)
        runtime: \(runtime.rawValue)
        entry: \(entry)
        timeoutMs: \(timeoutMs)
        """
        try manifest.write(
            to: toolDirectoryURL.appending(path: "tool.yaml"),
            atomically: true,
            encoding: .utf8
        )

        let scriptSource = """
        #!/bin/sh
        \(script)
        """
        try scriptSource.write(
            to: toolDirectoryURL.appending(path: entry),
            atomically: true,
            encoding: .utf8
        )

        return toolDirectoryURL
    }
}
