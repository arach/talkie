import XCTest
@testable import TalkieKit

#if os(macOS)
import AppKit

final class SimpleGlassFallbackPaletteTests: XCTestCase {
    func testCardFillResolvesToLightSurfaceInLightAppearance() {
        let lightFill = resolvedColor(SimpleGlassFallbackPalette.cardFill, appearance: .aqua)
        let darkFill = resolvedColor(SimpleGlassFallbackPalette.cardFill, appearance: .darkAqua)

        XCTAssertGreaterThan(lightFill.perceivedBrightness, 0.85)
        XCTAssertLessThan(darkFill.perceivedBrightness, 0.30)
        XCTAssertGreaterThan(lightFill.perceivedBrightness, darkFill.perceivedBrightness)
    }

    func testCardStrokeMaintainsContrastInBothAppearances() {
        let lightFill = resolvedColor(SimpleGlassFallbackPalette.cardFill, appearance: .aqua)
        let lightStroke = resolvedColor(SimpleGlassFallbackPalette.cardStroke, appearance: .aqua)
        let darkFill = resolvedColor(SimpleGlassFallbackPalette.cardFill, appearance: .darkAqua)
        let darkStroke = resolvedColor(SimpleGlassFallbackPalette.cardStroke, appearance: .darkAqua)

        XCTAssertLessThan(lightStroke.perceivedBrightness, lightFill.perceivedBrightness - 0.02)
        XCTAssertGreaterThan(darkStroke.perceivedBrightness, darkFill.perceivedBrightness + 0.02)
    }

    private func resolvedColor(_ color: NSColor, appearance: NSAppearance.Name) -> NSColor {
        let targetAppearance =
            NSAppearance(named: appearance) ??
            NSAppearance.currentDrawing()

        var resolvedColor = color
        targetAppearance.performAsCurrentDrawingAppearance {
            resolvedColor = color.usingColorSpace(.extendedSRGB) ?? color
        }
        return resolvedColor
    }
}

private extension NSColor {
    var perceivedBrightness: CGFloat {
        let rgb = usingColorSpace(.extendedSRGB) ?? self
        return (0.2126 * rgb.redComponent) + (0.7152 * rgb.greenComponent) + (0.0722 * rgb.blueComponent)
    }
}
#endif
