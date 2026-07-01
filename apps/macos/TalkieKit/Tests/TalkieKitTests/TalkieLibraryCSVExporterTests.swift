import Foundation
import Testing
@testable import TalkieKit

@Test("CSV field escaping quotes commas and newlines")
func csvFieldEscaping() {
    #expect(TalkieLibraryCSVExporter.csvField("plain") == "plain")
    #expect(TalkieLibraryCSVExporter.csvField("a,b") == "\"a,b\"")
    #expect(TalkieLibraryCSVExporter.csvField("say \"hi\"") == "\"say \"\"hi\"\"\"")
    #expect(TalkieLibraryCSVExporter.csvField("line\nbreak") == "\"line\nbreak\"")
}

@Test("Dictation CSV includes header and row values")
func dictationCSVRows() {
    let object = TalkieObject(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        type: .dictation,
        text: "Hello, world",
        duration: 12.5,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        source: .mac,
        metadataJSON: RecordingMetadata(
            app: AppContext(bundleId: "com.example.app", name: "Example", windowTitle: "Doc")
        ).toJSON()
    )

    let csv = TalkieLibraryCSVExporter.makeCSV(kind: .dictations, objects: [object])
    let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

    #expect(lines.count == 3)
    #expect(lines[0].contains("created_at"))
    #expect(lines[1].contains("11111111-1111-1111-1111-111111111111"))
    #expect(lines[1].contains("\"Hello, world\""))
    #expect(lines[1].contains("Example"))
    #expect(lines[1].contains("com.example.app"))
    #expect(lines[1].contains("Doc"))
}

@Test("Capture CSV includes media path column")
func captureCSVRows() {
    let object = TalkieObject(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        type: .capture,
        text: "OCR text",
        title: "Region capture",
        createdAt: Date(timeIntervalSince1970: 1_700_000_100),
        source: .mac,
        assetsJSON: TalkieObjectAssets(
            screenshots: [
                RecordingScreenshot(
                    filename: "shot.png",
                    timestampMs: 0,
                    captureMode: "region",
                    appName: "Safari",
                    appBundleID: "com.apple.Safari"
                ),
            ]
        ).toJSON()
    )

    let csv = TalkieLibraryCSVExporter.makeCSV(kind: .captures, objects: [object])
    #expect(csv.contains("capture_mode"))
    #expect(csv.contains("Region capture"))
    #expect(csv.contains("region"))
    #expect(csv.contains("Safari"))
}