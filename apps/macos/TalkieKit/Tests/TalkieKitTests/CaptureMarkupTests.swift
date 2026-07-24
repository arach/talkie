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

@Test("Auto blur converts OCR observations into padded privacy layers")
func captureMarkupAutoBlurLayers() throws {
    let result = OCRGeometryResult(
        imageWidth: 1000,
        imageHeight: 500,
        observations: [
            OCRTextObservation(
                text: "private@example.com",
                boundingBox: CaptureMarkupRect(x: 0.2, y: 0.7, width: 0.3, height: 0.08),
                confidence: 0.94
            ),
            OCRTextObservation(
                text: "low confidence",
                boundingBox: CaptureMarkupRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05),
                confidence: 0.1
            ),
        ],
        fullText: "private@example.com"
    )

    let layers = CaptureMarkupAutoBlur.layers(for: result)
    let layer = try #require(layers.first)
    let frame = try #require(layer.frame)
    #expect(layers.count == 1)
    #expect(layer.kind == .highlight)
    #expect(layer.label == CaptureMarkupAutoBlur.layerLabel)
    #expect(layer.stylePreset == CaptureMarkupAutoBlur.stylePreset)
    #expect(layer.author == .user)
    #expect(frame.x < 0.2)
    #expect(frame.y < 0.22)
    #expect(frame.width > 0.3)
    #expect(frame.height > 0.08)
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
    #expect(layer.color == "#4F7DFF")
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
        fillStyle: "tint",
        fillColor: "#D03A1C",
        fillAlpha: 0.22,
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
    #expect(decoded.layers[0].fillStyle == "tint")
    #expect(decoded.layers[0].fillColor == "#D03A1C")
    #expect(decoded.layers[0].fillAlpha == 0.22)
    #expect(decoded.layers[1].fontSize == 22)
}

@Test("Capture markup layer persists turn provenance")
func captureMarkupLayerTurnProvenanceRoundTrip() throws {
    let layer = CaptureMarkupLayer(
        kind: .rect,
        frame: CaptureMarkupRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
        turnPass: 2,
        turnInstruction: "circle the error",
        turnModel: "OpenAI · gpt-4.1",
        turnSummary: "circled error row · 1 op",
        turnElapsed: 1.4
    )
    let document = CaptureMarkupDocument(imageWidth: 800, imageHeight: 600, layers: [layer])

    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(CaptureMarkupDocument.self, from: data)
    #expect(decoded == document)
    #expect(decoded.layers[0].turnPass == 2)
    #expect(decoded.layers[0].turnInstruction == "circle the error")
    #expect(decoded.layers[0].turnModel == "OpenAI · gpt-4.1")
    #expect(decoded.layers[0].turnSummary == "circled error row · 1 op")
    #expect(decoded.layers[0].turnElapsed == 1.4)
}

@Test("Capture markup label persists font family / weight / style / plain")
func captureMarkupLabelTypographyRoundTrip() throws {
    let label = CaptureMarkupLayer(
        kind: .label,
        frame: CaptureMarkupRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
        text: "Note",
        fontSize: 22,
        fontFamily: "serif",
        bold: true,
        italic: true,
        plain: true
    )
    let document = CaptureMarkupDocument(imageWidth: 800, imageHeight: 600, layers: [label])
    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(CaptureMarkupDocument.self, from: data)
    #expect(decoded == document)
    #expect(decoded.layers[0].fontFamily == "serif")
    #expect(decoded.layers[0].bold == true)
    #expect(decoded.layers[0].italic == true)
    #expect(decoded.layers[0].plain == true)
}

@Test("Capture markup label decode tolerates absent typography fields")
func captureMarkupLabelTypographyDefaults() throws {
    let data = """
    { "kind": "label", "frame": {"x": 0, "y": 0, "width": 0.2, "height": 0.05}, "text": "Old" }
    """.data(using: .utf8)!
    let layer = try JSONDecoder().decode(CaptureMarkupLayer.self, from: data)
    // Legacy labels carry none of the new fields → all nil, renderer falls back
    // to mono / pill / size 16.
    #expect(layer.fontFamily == nil)
    #expect(layer.bold == nil)
    #expect(layer.italic == nil)
    #expect(layer.plain == nil)
}

@Test("Capture markup persists arrow pointers and text presets")
func captureMarkupPointerAndTextPresetRoundTrip() throws {
    let arrow = CaptureMarkupLayer(
        kind: .arrow,
        from: CaptureMarkupPoint(x: 0.1, y: 0.2),
        to: CaptureMarkupPoint(x: 0.8, y: 0.6),
        pointerStart: "dot",
        pointerEnd: "bar",
        pointerStyle: "dot",
        arrowStyle: "curved",
        curveOffset: 0.24
    )
    let label = CaptureMarkupLayer(
        kind: .label,
        frame: CaptureMarkupRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
        text: "On dark",
        textPreset: "on-dark",
        textColor: "#232423",
        backgroundColor: "#F4E8D4",
        backgroundAlpha: 0.94,
        borderColor: "#4F7DFF",
        borderAlpha: 0.34,
        backgroundBlur: 14,
        noteStyle: "glass"
    )
    let document = CaptureMarkupDocument(imageWidth: 800, imageHeight: 600, layers: [arrow, label])

    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(CaptureMarkupDocument.self, from: data)
    #expect(decoded == document)
    #expect(decoded.layers[0].pointerStart == "dot")
    #expect(decoded.layers[0].pointerEnd == "bar")
    #expect(decoded.layers[0].arrowStyle == "curved")
    #expect(decoded.layers[0].curveOffset == 0.24)
    #expect(decoded.layers[1].textPreset == "on-dark")
    #expect(decoded.layers[1].backgroundAlpha == 0.94)
    #expect(decoded.layers[1].backgroundBlur == 14)
    #expect(decoded.layers[1].noteStyle == "glass")
}

@Test("Capture markup patch (clone) round-trips source + frame")
func captureMarkupPatchRoundTrip() throws {
    let patch = CaptureMarkupLayer(
        kind: .patch,
        frame: CaptureMarkupRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
        source: CaptureMarkupRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
        author: .user
    )
    let document = CaptureMarkupDocument(imageWidth: 400, imageHeight: 300, layers: [patch])
    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(CaptureMarkupDocument.self, from: data)
    #expect(decoded == document)
    #expect(decoded.layers[0].kind == .patch)
    #expect(decoded.layers[0].source == CaptureMarkupRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
}

@Test("Capture markup ellipse and ink round-trip")
func captureMarkupEllipseAndInkRoundTrip() throws {
    let ellipse = CaptureMarkupLayer(
        kind: .ellipse,
        frame: CaptureMarkupRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2),
        color: "#D03A1C",
        strokeWidth: 3,
        author: .user
    )
    let ink = CaptureMarkupLayer(
        kind: .ink,
        points: [
            CaptureMarkupPoint(x: 0.1, y: 0.1),
            CaptureMarkupPoint(x: 0.2, y: 0.16),
            CaptureMarkupPoint(x: 0.34, y: 0.14),
        ],
        color: "#12A594",
        strokeWidth: 5,
        author: .user
    )
    let document = CaptureMarkupDocument(imageWidth: 400, imageHeight: 300, layers: [ellipse, ink])
    let data = try JSONEncoder().encode(document)
    let decoded = try JSONDecoder().decode(CaptureMarkupDocument.self, from: data)
    #expect(decoded == document)
    #expect(decoded.layers[0].kind == .ellipse)
    #expect(decoded.layers[1].points?.count == 3)
}

@Test("Capture markup renders ellipse and ink layers without error")
func captureMarkupRenderEllipseAndInk() throws {
    let image = makeSolidImage(width: 200, height: 120)
    let document = CaptureMarkupDocument(
        imageWidth: 200,
        imageHeight: 120,
        layers: [
            CaptureMarkupLayer(
                kind: .ellipse,
                frame: CaptureMarkupRect(x: 0.15, y: 0.2, width: 0.5, height: 0.35),
                strokeWidth: 3,
                fillStyle: "wash",
                fillColor: "#4F7DFF",
                fillAlpha: 0.10
            ),
            CaptureMarkupLayer(
                kind: .rect,
                frame: CaptureMarkupRect(x: 0.56, y: 0.12, width: 0.34, height: 0.28),
                color: "#D03A1C",
                strokeWidth: 4,
                fillStyle: "solid",
                fillColor: "#D03A1C",
                fillAlpha: 0.82
            ),
            CaptureMarkupLayer(
                kind: .ink,
                points: [
                    CaptureMarkupPoint(x: 0.1, y: 0.8),
                    CaptureMarkupPoint(x: 0.25, y: 0.7),
                    CaptureMarkupPoint(x: 0.4, y: 0.76),
                ],
                strokeWidth: 4
            ),
        ]
    )
    let output = CaptureMarkupRenderer.render(image: image, document: document, scale: 1)
    #expect(output?.width == 200)
    #expect(output?.height == 120)
}

@Test("Capture markup renders all styled arrows without error")
func captureMarkupRenderStyledArrows() throws {
    let image = makeSolidImage(width: 240, height: 160)
    let document = CaptureMarkupDocument(
        imageWidth: 240,
        imageHeight: 160,
        layers: [
            CaptureMarkupLayer(
                kind: .arrow,
                from: CaptureMarkupPoint(x: 0.12, y: 0.72),
                to: CaptureMarkupPoint(x: 0.62, y: 0.18),
                color: "#D03A1C",
                strokeWidth: 4,
                pointerEnd: "open",
                pointerStyle: "open",
                arrowStyle: "curved",
                curveOffset: 0.2
            ),
            CaptureMarkupLayer(
                kind: .arrow,
                from: CaptureMarkupPoint(x: 0.18, y: 0.84),
                to: CaptureMarkupPoint(x: 0.48, y: 0.74),
                color: "#12A594",
                strokeWidth: 3,
                pointerEnd: "open",
                arrowStyle: "elbow"
            ),
            CaptureMarkupLayer(
                kind: .arrow,
                from: CaptureMarkupPoint(x: 0.08, y: 0.48),
                to: CaptureMarkupPoint(x: 0.78, y: 0.62),
                color: "#DFA13A",
                strokeWidth: 4,
                pointerEnd: "filled",
                pointerStyle: "filled",
                arrowStyle: "swoop",
                curveOffset: 0.22
            ),
            CaptureMarkupLayer(
                kind: .arrow,
                from: CaptureMarkupPoint(x: 0.52, y: 0.86),
                to: CaptureMarkupPoint(x: 0.90, y: 0.76),
                color: "#4F7DFF",
                strokeWidth: 6,
                pointerEnd: "filled",
                pointerStyle: "filled",
                arrowStyle: "shaped"
            ),
            CaptureMarkupLayer(
                kind: .arrow,
                from: CaptureMarkupPoint(x: 0.08, y: 0.30),
                to: CaptureMarkupPoint(x: 0.68, y: 0.14),
                color: "#D03A1C",
                strokeWidth: 4,
                pointerEnd: "grow",
                pointerStyle: "grow",
                arrowStyle: "straight"
            ),
            CaptureMarkupLayer(
                kind: .arrow,
                from: CaptureMarkupPoint(x: 0.42, y: 0.92),
                to: CaptureMarkupPoint(x: 0.92, y: 0.42),
                color: "#4F7DFF",
                strokeWidth: 5,
                pointerEnd: "block",
                pointerStyle: "block",
                arrowStyle: "curved",
                curveOffset: 0.18
            ),
        ]
    )
    let output = CaptureMarkupRenderer.render(image: image, document: document, scale: 1)
    #expect(output?.width == 240)
    #expect(output?.height == 160)
}

@Test("Capture markup renders refined note presets without error")
func captureMarkupRenderRefinedNotes() throws {
    let image = makeSolidImage(width: 300, height: 180)
    let styles = ["sticky", "bubble", "glass", "caption", "signal"]
    let layers = styles.enumerated().map { index, style in
        CaptureMarkupLayer(
            kind: .label,
            frame: CaptureMarkupRect(x: 0.06, y: 0.05 + Double(index) * 0.18, width: 0.42, height: 0.13),
            text: style.capitalized,
            textColor: style == "glass" ? "#F6F1E8" : "#1C2230",
            backgroundColor: style == "glass" ? "#17191E" : "#FFFDF8",
            backgroundAlpha: 0.94,
            borderColor: "#DFA13A",
            borderAlpha: 0.24,
            borderWidth: 0.75,
            cornerRadius: style == "bubble" ? 12 : 4,
            paddingX: 11,
            paddingY: 8,
            backgroundBlur: style == "glass" ? 14 : nil,
            noteStyle: style,
            shadow: true,
            shadowColor: "rgba(0, 0, 0, 0.16)",
            shadowBlur: 8,
            shadowOffsetY: 2,
            author: .user
        )
    }
    let document = CaptureMarkupDocument(imageWidth: 300, imageHeight: 180, layers: layers)
    let output = CaptureMarkupRenderer.render(image: image, document: document, scale: 1)
    #expect(output?.width == 300)
    #expect(output?.height == 180)
}

@Test("Capture markup renders a patch (clone) layer without error")
func captureMarkupRenderPatch() throws {
    let image = makeSolidImage(width: 200, height: 120)
    let document = CaptureMarkupDocument(
        imageWidth: 200,
        imageHeight: 120,
        layers: [
            CaptureMarkupLayer(
                kind: .patch,
                frame: CaptureMarkupRect(x: 0.5, y: 0.1, width: 0.3, height: 0.3),
                source: CaptureMarkupRect(x: 0.0, y: 0.0, width: 0.3, height: 0.3)
            ),
        ]
    )
    let output = CaptureMarkupRenderer.render(image: image, document: document, scale: 1)
    #expect(output?.width == 200)
    #expect(output?.height == 120)
}

@Test("Capture markup renders privacy blur without error")
func captureMarkupRenderPrivacyBlur() throws {
    let image = makeSolidImage(width: 200, height: 120)
    let document = CaptureMarkupDocument(
        imageWidth: 200,
        imageHeight: 120,
        layers: [
            CaptureMarkupLayer(
                kind: .highlight,
                frame: CaptureMarkupRect(x: 0.2, y: 0.2, width: 0.5, height: 0.3),
                stylePreset: CaptureMarkupAutoBlur.stylePreset,
                label: CaptureMarkupAutoBlur.layerLabel,
                author: .user
            ),
        ]
    )
    let output = CaptureMarkupRenderer.render(image: image, document: document, scale: 1)
    #expect(output?.width == 200)
    #expect(output?.height == 120)
}

private func makeSolidImage(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

@Test("Markup export scale multiplies output pixel dimensions")
func captureMarkupExportScale() throws {
    let image = makeSolidImage(width: 200, height: 120)
    let document = CaptureMarkupDocument(
        imageWidth: 200,
        imageHeight: 120,
        layers: [
            CaptureMarkupLayer(kind: .rect, frame: CaptureMarkupRect(x: 0.1, y: 0.1, width: 0.4, height: 0.3)),
        ]
    )
    let at1x = CaptureMarkupRenderer.render(image: image, document: document, scale: 1)
    let at2x = CaptureMarkupRenderer.render(image: image, document: document, scale: 2)
    #expect(at1x?.width == 200)
    #expect(at1x?.height == 120)
    #expect(at2x?.width == 400)
    #expect(at2x?.height == 240)
}

@Test("Markup export emits format-specific bytes")
func captureMarkupExportFormatBytes() throws {
    let image = makeSolidImage(width: 64, height: 64)
    let document = CaptureMarkupDocument(imageWidth: 64, imageHeight: 64)
    let png = try #require(CaptureMarkupRenderer.encodedData(image: image, document: document, format: .png))
    let jpeg = try #require(CaptureMarkupRenderer.encodedData(image: image, document: document, format: .jpeg))
    // PNG magic signature.
    #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    // JPEG start-of-image marker.
    #expect(Array(jpeg.prefix(2)) == [0xFF, 0xD8])
}

@Test("Markup export filename carries scale suffix and format extension")
func captureMarkupExportFilename() {
    let url = URL(fileURLWithPath: "/tmp/shot.png")
    #expect(CaptureMarkupStorage.exportBaseName(forImageURL: url, scale: 1) == "shot")
    #expect(CaptureMarkupStorage.exportBaseName(forImageURL: url, scale: 2) == "shot@2x")
    #expect(CaptureMarkupExportFormat.png.fileExtension == "png")
    #expect(CaptureMarkupExportFormat.jpeg.fileExtension == "jpg")
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
