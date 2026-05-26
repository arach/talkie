import Foundation
import Testing
@testable import TalkieKit

@Test("Delivery markdown appends screenshot links")
func deliveryMarkdownAppendsScreenshotLinks() {
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
