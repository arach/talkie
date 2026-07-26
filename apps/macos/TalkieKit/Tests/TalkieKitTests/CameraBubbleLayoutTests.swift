import CoreGraphics
import Testing
@testable import TalkieKit

@Test("Camera bubble corner placements respect the visible screen")
func cameraBubbleCornerPlacements() {
    let frame = CGRect(x: -1200, y: 40, width: 1200, height: 800)
    let size = CGSize(width: 155, height: 100)

    #expect(CameraBubbleLayout.origin(for: .topLeading, requested: nil, size: size, visibleFrame: frame) == CGPoint(x: -1176, y: 716))
    #expect(CameraBubbleLayout.origin(for: .topTrailing, requested: nil, size: size, visibleFrame: frame) == CGPoint(x: -179, y: 716))
    #expect(CameraBubbleLayout.origin(for: .bottomLeading, requested: nil, size: size, visibleFrame: frame) == CGPoint(x: -1176, y: 64))
    #expect(CameraBubbleLayout.origin(for: .bottomTrailing, requested: nil, size: size, visibleFrame: frame) == CGPoint(x: -179, y: 64))
}

@Test("Custom camera placement remains fully visible")
func cameraBubbleCustomPlacementClamps() {
    let frame = CGRect(x: 0, y: 0, width: 900, height: 600)
    let size = CGSize(width: 200, height: 130)

    let low = CameraBubbleLayout.origin(
        for: .custom,
        requested: CGPoint(x: -80, y: -20),
        size: size,
        visibleFrame: frame
    )
    let high = CameraBubbleLayout.origin(
        for: .custom,
        requested: CGPoint(x: 850, y: 590),
        size: size,
        visibleFrame: frame
    )

    #expect(low == CGPoint(x: 24, y: 24))
    #expect(high == CGPoint(x: 676, y: 446))
}

@Test("Camera placement handles a viewport smaller than its configured margin")
func cameraBubblePlacementHandlesSmallViewport() {
    let result = CameraBubbleLayout.clamped(
        CGPoint(x: 100, y: 100),
        size: CGSize(width: 180, height: 120),
        to: CGRect(x: 0, y: 0, width: 200, height: 140)
    )

    #expect(result == CGPoint(x: 24, y: 24))
}
