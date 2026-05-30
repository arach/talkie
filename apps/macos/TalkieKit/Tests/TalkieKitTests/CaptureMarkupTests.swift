import CoreGraphics
import Foundation
import Testing
@testable import TalkieKit

@Test("Capture markup document round-trip")
func captureMarkupDocumentRoundTrip() throws {
    let document = CaptureMarkupDocument(
        imageWidth: 800,
        imageHeight: 600,
        layers: [
            CaptureMarkupLayer(
                kind: .rect,
                frame: CaptureMarkupRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
                label: "Error"
            ),
            CaptureMarkupLayer(
                kind: .guide,
                orientation: "both",
                interval: 50
            ),
        ]
    )

    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(CaptureMarkupDocument.self, from: data)
    #expect(decoded == document)
}

@Test("Capture markup apply ops")
func captureMarkupApplyOps() {
    var document = CaptureMarkupDocument(imageWidth: 100, imageHeight: 100)
    let layer = CaptureMarkupLayer(kind: .highlight, frame: CaptureMarkupRect(x: 0, y: 0, width: 0.5, height: 0.5))
    document.apply(ops: [CaptureMarkupLayerOp(action: "add", layer: layer)])
    #expect(document.layers.count == 1)
    document.apply(ops: [CaptureMarkupLayerOp(action: "remove", layer: layer)])
    #expect(document.layers.isEmpty)
}

@Test("Capture markup layer decode supplies agent defaults")
func captureMarkupLayerDecodeDefaults() throws {
    let data = """
    {
      "id": "agent-highlight",
      "kind": "highlight",
      "frame": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4},
      "label": "Agent"
    }
    """.data(using: .utf8)!

    let layer = try JSONDecoder().decode(CaptureMarkupLayer.self, from: data)
    #expect(layer.color == "#C47D1C")
    #expect(layer.visible)
    #expect(layer.author == .agent)
    // Older sidecars carry no stroke/font — they stay nil and the renderer
    // falls back to its historical defaults.
    #expect(layer.strokeWidth == nil)
    #expect(layer.fontSize == nil)
}

@Test("Capture markup layer persists stroke width and font size")
func captureMarkupLayerStyleRoundTrip() throws {
    let layer = CaptureMarkupLayer(
        kind: .rect,
        frame: CaptureMarkupRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
        color: "#D03A1C",
        strokeWidth: 5,
        author: .user
    )
    let label = CaptureMarkupLayer(
        kind: .label,
        frame: CaptureMarkupRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
        text: "Hi",
        fontSize: 22
    )
    let document = CaptureMarkupDocument(imageWidth: 800, imageHeight: 600, layers: [layer, label])

    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(CaptureMarkupDocument.self, from: data)
    #expect(decoded == document)
    #expect(decoded.layers[0].strokeWidth == 5)
    #expect(decoded.layers[1].fontSize == 22)
}

@Test("Screenshot vision description payload caches target variants")
func screenshotVisionDescriptionPayloadCachesTargetVariants() throws {
    let generic = ScreenshotVisionDescriptionVariant(
        target: "generic-ai",
        providerId: "gemini",
        modelId: "gemini-2.0-flash",
        description: ScreenshotDescription(primaryFocus: "Settings window is open.")
    )
    let terminal = ScreenshotVisionDescriptionVariant(
        target: "terminal-cli",
        providerId: "openai",
        modelId: "gpt-4.1-mini",
        description: ScreenshotDescription(primaryFocus: "Terminal shows a failed SSH login.")
    )

    var payload = ScreenshotVisionDescriptionPayload()
    payload.upsert(generic)
    payload.upsert(terminal)

    let data = try JSONEncoder().encode(payload)
    let decoded = try JSONDecoder().decode(ScreenshotVisionDescriptionPayload.self, from: data)

    #expect(decoded.variant(target: "generic-ai")?.contextString == "Primary focus: Settings window is open.")
    #expect(decoded.variant(target: "terminal-cli")?.providerId == "openai")
}
