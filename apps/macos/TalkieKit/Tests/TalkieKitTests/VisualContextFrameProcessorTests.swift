import Testing
@testable import TalkieKit

@Test("Visual context sampling interval follows duration tiers")
func visualContextSamplingIntervalFollowsDurationTiers() {
    #expect(VisualContextFrameProcessor.sampleInterval(durationSeconds: 4) == 1.0 / 3.0)
    #expect(VisualContextFrameProcessor.sampleInterval(durationSeconds: 20) == 1.0)
    #expect(VisualContextFrameProcessor.sampleInterval(durationSeconds: 90) == 2.0)
    #expect(VisualContextFrameProcessor.sampleInterval(durationSeconds: 400) == 5.0)
    #expect(VisualContextFrameProcessor.sampleInterval(durationSeconds: 900) == 10.0)
}

@Test("Visual context target frame count is capped")
func visualContextTargetFrameCountIsCapped() {
    #expect(VisualContextFrameProcessor.targetFrameCount(durationSeconds: 3) >= VisualContextFrameProcessor.minFrames)
    #expect(VisualContextFrameProcessor.targetFrameCount(durationSeconds: 3) <= VisualContextFrameProcessor.maxFrames)
    #expect(VisualContextFrameProcessor.targetFrameCount(durationSeconds: 3_600) == VisualContextFrameProcessor.maxFrames)
}

@Test("Visual context tile layout grows with frame count")
func visualContextTileLayoutGrowsWithFrameCount() {
    let small = VisualContextFrameProcessor.tileLayout(for: 6)
    #expect(small.columns >= 4)
    #expect(small.rows >= 2)

    let large = VisualContextFrameProcessor.tileLayout(for: 40)
    #expect(large.columns <= 8)
    #expect(large.rows * large.columns >= 40)
}