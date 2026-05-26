import Foundation
import Testing
@testable import TalkieKit

@Test("Delivery markdown inserts timed screenshot markers inline")
func deliveryMarkdownInsertsTimedScreenshotMarkersInline() {
    let screenshot = RecordingScreenshot(
        filename: "Talkie Capture - Region.png",
        timestampMs: 1200,
        captureMode: "region",
        width: 640,
        height: 360
    )
    let timed = TimedTranscription(
        text: "Look here then continue.",
        words: [
            WordSegment(word: "Look", start: 0.0, end: 0.3),
            WordSegment(word: " here", start: 0.5, end: 0.8),
            WordSegment(word: " then", start: 2.0, end: 2.2),
            WordSegment(word: " continue", start: 2.5, end: 3.0),
        ]
    )

    let markdown = ScreenshotInserter.deliveryMarkdown(
        text: "Look here then continue.",
        timedTranscription: timed,
        screenshots: [screenshot],
        screenshotDirectory: URL(fileURLWithPath: "/Users/art/Library/Application Support/Talkie/Screenshots")
    )

    #expect(markdown == """
    Look here [1] then continue.

    [1](</Users/art/Library/Application Support/Talkie/Screenshots/Talkie Capture - Region.png>)
    """)
}

@Test("Delivery markdown appends screenshot links without timings")
func deliveryMarkdownAppendsScreenshotLinksWithoutTimings() {
    let screenshot = RecordingScreenshot(
        filename: "Talkie Capture - Region.png",
        timestampMs: 1200,
        captureMode: "region",
        width: 640,
        height: 360
    )

    let markdown = ScreenshotInserter.deliveryMarkdown(
        text: "Here is the thing.",
        timedTranscription: nil,
        screenshots: [screenshot],
        screenshotDirectory: URL(fileURLWithPath: "/Users/art/Library/Application Support/Talkie/Screenshots")
    )

    #expect(markdown == """
    Here is the thing.

    [Screenshot 1](</Users/art/Library/Application Support/Talkie/Screenshots/Talkie Capture - Region.png>)
    """)
}

@Test("Delivery markdown appends screenshot links when delivery text was transformed")
func deliveryMarkdownAppendsScreenshotLinksWhenTextWasTransformed() {
    let screenshot = RecordingScreenshot(
        filename: "Talkie Capture - Region.png",
        timestampMs: 1200,
        captureMode: "region",
        width: 640,
        height: 360
    )
    let timed = TimedTranscription(
        text: "Look here then continue.",
        words: [
            WordSegment(word: "Look", start: 0.0, end: 0.3),
            WordSegment(word: " here", start: 0.5, end: 0.8),
            WordSegment(word: " then", start: 2.0, end: 2.2),
            WordSegment(word: " continue", start: 2.5, end: 3.0),
        ]
    )

    let markdown = ScreenshotInserter.deliveryMarkdown(
        text: "Please review this section and continue.",
        timedTranscription: timed,
        screenshots: [screenshot],
        screenshotDirectory: URL(fileURLWithPath: "/Users/art/Library/Application Support/Talkie/Screenshots")
    )

    #expect(markdown == """
    Please review this section and continue.

    [Screenshot 1](</Users/art/Library/Application Support/Talkie/Screenshots/Talkie Capture - Region.png>)
    """)
}

@Test("Delivery markdown preserves plain text when no screenshots")
func deliveryMarkdownPreservesPlainTextWithoutScreenshots() {
    #expect(
        ScreenshotInserter.deliveryMarkdown(
            text: "Plain transcript",
            timedTranscription: nil,
            screenshots: []
        ) == "Plain transcript"
    )
}
