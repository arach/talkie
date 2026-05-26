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
}
