import Foundation
import Testing
@testable import TalkieKit

@Test("Visual context bundle preserves source clip and manifest metadata")
func visualContextBundlePreservesSourceClipAndManifestMetadata() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory
        .appendingPathComponent("talkie-visual-context-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: root) }

    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let sourceURL = root.appendingPathComponent("input.mp4")
    try Data([0, 1, 2, 3]).write(to: sourceURL)

    let recordingId = UUID()
    let metadataEvent = RecordingVisualContextEvent(
        startMs: 0,
        endMs: 1200,
        type: .activeWindow,
        appName: "Codex",
        appBundleID: "com.openai.codex",
        windowTitle: "Talkie"
    )

    let context = try #require(VisualContextStorage.createBundle(
        sourceClipURL: sourceURL,
        recordingId: recordingId,
        timestampMs: 250,
        capturedAt: Date(timeIntervalSince1970: 1000),
        durationMs: 1200,
        captureMode: "region",
        width: 640,
        height: 360,
        windowTitle: "Talkie",
        appName: "Codex",
        displayName: "Built-in Display",
        metadataEvents: [metadataEvent],
        rootDirectory: root
    ))

    let bundleURL = bundleURL(for: context, root: root)
    #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent(context.sourceClipFilename).path))
    #expect(fm.fileExists(atPath: bundleURL.appendingPathComponent("visual-context.md").path))

    let manifestURL = bundleURL.appendingPathComponent("visual-context.json")
    let manifestData = try Data(contentsOf: manifestURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(RecordingVisualContextManifest.self, from: manifestData)

    #expect(manifest.recordingId == recordingId)
    #expect(manifest.visualContextId == context.id)
    #expect(manifest.sourceClip == context.sourceClipFilename)
    #expect(manifest.capture.mode == "region")
    #expect(manifest.metadataEvents == [metadataEvent])

    let encodedAssets = TalkieObjectAssets(visualContexts: [context]).toJSON()
    let decodedAssets = TalkieObjectAssets.from(json: encodedAssets)
    #expect(decodedAssets?.visualContexts == [context])
}

@Test("Visual context storage ignores non-screen clips")
func visualContextStorageIgnoresNonScreenClips() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory
        .appendingPathComponent("talkie-visual-context-test-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: root) }

    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let sourceURL = root.appendingPathComponent("camera.mp4")
    try Data([4, 5, 6]).write(to: sourceURL)

    let context = VisualContextStorage.createBundle(
        sourceClipURL: sourceURL,
        recordingId: UUID(),
        timestampMs: 0,
        capturedAt: Date(),
        durationMs: 1000,
        captureMode: "camera",
        width: 320,
        height: 240,
        windowTitle: nil,
        appName: nil,
        displayName: nil,
        rootDirectory: root
    )

    #expect(context == nil)
}

private func bundleURL(for context: RecordingVisualContext, root: URL) -> URL {
    context.relativeDirectory
        .split(separator: "/")
        .map(String.init)
        .reduce(root) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
}
