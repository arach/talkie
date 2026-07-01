import Foundation
import Testing
@testable import TalkieKit

@Test("Reference screenshot tray delete preserves canonical media")
func referenceScreenshotTrayDeletePreservesCanonicalMedia() async throws {
    let fixture = try LiveTrayFixture()
    defer { fixture.cleanup() }

    let fileURL = try fixture.writeCanonicalFile(named: "canonical-shot.png", bytes: [0x89, 0x50, 0x4E, 0x47])
    let id = UUID()
    let capturedAt = Date(timeIntervalSince1970: 1_000)

    _ = try await fixture.store.registerScreenshot(
        fileURL: fileURL,
        id: id,
        capturedAt: capturedAt,
        mode: "region",
        width: 640,
        height: 360,
        windowTitle: "Window",
        appName: "App",
        appBundleID: "com.example.app",
        displayName: "Display"
    )

    let item = try #require(await fixture.store.recentItems(limit: 5).first { $0.id == id })
    #expect(item.fileURL == fileURL)
    #expect(item.filename == fileURL.lastPathComponent)

    #expect(await fixture.store.deleteItem(id: id, kind: .screenshot))
    #expect(FileManager.default.fileExists(atPath: fileURL.path))
    #expect(await fixture.store.recentItems(limit: 5).isEmpty)
}

@Test("Reference clip promotion drains tray without deleting canonical media")
func referenceClipPromotionDrainsTrayWithoutDeletingCanonicalMedia() async throws {
    let fixture = try LiveTrayFixture()
    defer { fixture.cleanup() }

    let fileURL = try fixture.writeCanonicalFile(named: "canonical-clip.mp4", bytes: [0, 0, 0, 24, 102, 116, 121, 112])
    let id = UUID()
    let capturedAt = Date(timeIntervalSince1970: 2_000)
    let recordingId = UUID()

    _ = try await fixture.store.registerClip(
        fileURL: fileURL,
        id: id,
        capturedAt: capturedAt,
        durationMs: 1_250,
        width: 1280,
        height: 720,
        captureMode: "camera",
        windowTitle: nil,
        appName: "Camera",
        displayName: "Camera",
        metadataEvents: []
    )

    let promotion = try #require(await fixture.store.promoteAssetsForRecording(
        recordingId: recordingId,
        recordingStartedAt: capturedAt.addingTimeInterval(-1),
        recordingEndedAt: capturedAt.addingTimeInterval(2),
        includeScreenshots: true
    ))

    let clip = try #require(promotion.assets.clips?.first)
    #expect(clip.filename == fileURL.lastPathComponent)
    #expect(promotion.promotedClipIDs == [id])

    await fixture.store.drainPromotedAssets(promotion)

    #expect(FileManager.default.fileExists(atPath: fileURL.path))
    #expect(await fixture.store.recentItems(limit: 5).isEmpty)
}

@Test("Reference screen clip promotion creates no-copy visual context")
func referenceScreenClipPromotionCreatesNoCopyVisualContext() async throws {
    let fixture = try LiveTrayFixture()
    defer { fixture.cleanup() }

    let fileURL = try fixture.writeCanonicalFile(named: "canonical-window.mp4", bytes: [0, 0, 0, 24, 102, 116, 121, 112])
    let id = UUID()
    let capturedAt = Date(timeIntervalSince1970: 3_000)
    let recordingId = UUID()

    _ = try await fixture.store.registerClip(
        fileURL: fileURL,
        id: id,
        capturedAt: capturedAt,
        durationMs: 2_000,
        width: 1440,
        height: 900,
        captureMode: "window",
        windowTitle: "Window",
        appName: "App",
        displayName: "Display",
        metadataEvents: []
    )

    let promotion = try #require(await fixture.store.promoteAssetsForRecording(
        recordingId: recordingId,
        recordingStartedAt: capturedAt.addingTimeInterval(-1),
        recordingEndedAt: capturedAt.addingTimeInterval(3),
        includeScreenshots: true
    ))

    let visualContext = try #require(promotion.assets.visualContexts?.first)
    let bundleURL = VisualContextStorage.bundleURL(for: visualContext)

    #expect(visualContext.sourceClipFilename == fileURL.lastPathComponent)
    #expect(visualContext.sourceClipPath == fileURL.path)
    #expect(CaptureMediaFileResolver.visualContextSourceURL(for: visualContext) == fileURL)
    #expect(!FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent(fileURL.lastPathComponent).path))

    try? FileManager.default.removeItem(at: bundleURL)
    await fixture.store.drainPromotedAssets(promotion)

    #expect(FileManager.default.fileExists(atPath: fileURL.path))
    #expect(await fixture.store.recentItems(limit: 5).isEmpty)
}

private struct LiveTrayFixture {
    let root: URL
    let canonicalDirectory: URL
    let store: AgentLiveTrayAssetStore

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("talkie-live-tray-test-\(UUID().uuidString)", isDirectory: true)
        canonicalDirectory = root.appendingPathComponent("canonical", isDirectory: true)
        try FileManager.default.createDirectory(at: canonicalDirectory, withIntermediateDirectories: true)
        store = AgentLiveTrayAssetStore(
            trayRootDirectory: root.appendingPathComponent("tray", isDirectory: true),
            schedulesVisualContextProcessing: false
        )
    }

    func writeCanonicalFile(named name: String, bytes: [UInt8]) throws -> URL {
        let url = canonicalDirectory.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
