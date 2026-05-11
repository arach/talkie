import XCTest
@testable import TalkieKit

final class TalkieLogFileWriterTests: XCTestCase {
    func testWriterPersistsCriticalAndBufferedLogLines() throws {
        let applicationSupportDirectory = try makeApplicationSupportDirectory()
        defer {
            try? FileManager.default.removeItem(at: applicationSupportDirectory)
        }

        let writer = TalkieLogFileWriter(
            source: .talkieLive,
            applicationSupportDirectory: applicationSupportDirectory
        )

        writer.log(.record, "Critical message", detail: "critical detail", mode: .critical)
        writer.log(.system, "Buffered message", detail: "buffer detail", mode: .bestEffort)
        writer.flushSynchronouslyForTesting()

        let logURL = applicationSupportDirectory
            .appendingPathComponent(LogSource.talkieLive.appSupportDirName)
            .appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("talkie-\(Self.logDateStamp(for: Date())).log")

        let contents = try String(contentsOf: logURL, encoding: .utf8)

        XCTAssertTrue(contents.contains("|TalkieAgent|RECORD|Critical message|critical detail"))
        XCTAssertTrue(contents.contains("|TalkieAgent|SYSTEM|Buffered message|buffer detail"))
    }

    private func makeApplicationSupportDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkieLogFileWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func logDateStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
