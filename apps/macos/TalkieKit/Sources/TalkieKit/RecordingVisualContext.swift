//
//  RecordingVisualContext.swift
//  TalkieKit
//
//  Durable screen-recording context bundles for agent workflows.
//

import CoreGraphics
import Foundation

// MARK: - Recording Visual Context

/// Lightweight pointer stored in TalkieObjectAssets for a durable visual
/// context bundle on disk. Rich frame/timeline details live in the manifest.
public struct RecordingVisualContext: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case recording
        case captured
        case processing
        case ready
        case failed
    }

    public var id: UUID
    public var recordingId: UUID
    public var relativeDirectory: String
    public var sourceClipFilename: String
    public var captureMode: String
    public var timestampMs: Int
    public var startedAt: Date
    public var endedAt: Date?
    public var durationMs: Int?
    public var width: Int?
    public var height: Int?
    public var displayName: String?
    public var windowTitle: String?
    public var appName: String?
    public var manifestFilename: String?
    public var summaryFilename: String?
    public var contactSheetFilename: String?
    public var frameCount: Int?
    public var status: Status
    public var processorVersion: String?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        recordingId: UUID,
        relativeDirectory: String,
        sourceClipFilename: String,
        captureMode: String,
        timestampMs: Int,
        startedAt: Date,
        endedAt: Date? = nil,
        durationMs: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        displayName: String? = nil,
        windowTitle: String? = nil,
        appName: String? = nil,
        manifestFilename: String? = nil,
        summaryFilename: String? = nil,
        contactSheetFilename: String? = nil,
        frameCount: Int? = nil,
        status: Status = .captured,
        processorVersion: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.recordingId = recordingId
        self.relativeDirectory = relativeDirectory
        self.sourceClipFilename = sourceClipFilename
        self.captureMode = captureMode
        self.timestampMs = timestampMs
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.width = width
        self.height = height
        self.displayName = displayName
        self.windowTitle = windowTitle
        self.appName = appName
        self.manifestFilename = manifestFilename
        self.summaryFilename = summaryFilename
        self.contactSheetFilename = contactSheetFilename
        self.frameCount = frameCount
        self.status = status
        self.processorVersion = processorVersion
        self.errorMessage = errorMessage
    }

    public static func isScreenCaptureMode(_ captureMode: String?) -> Bool {
        guard let captureMode else { return false }
        return ["fullscreen", "region", "window"].contains(captureMode)
    }
}

// MARK: - Visual Context Manifest

public struct RecordingVisualContextRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.width),
            height: Double(rect.height)
        )
    }
}

public struct RecordingVisualContextEvent: Codable, Sendable, Equatable {
    public enum EventType: String, Codable, Sendable {
        case captureTarget
        case activeWindow
        case screenshot
        case captureMarkup
    }

    public var startMs: Int
    public var endMs: Int?
    public var type: EventType
    public var appName: String?
    public var appBundleID: String?
    public var windowTitle: String?
    public var displayName: String?
    public var displayID: UInt32?
    public var captureMode: String?
    public var bounds: RecordingVisualContextRect?
    public var assetKind: String?
    public var assetFilename: String?
    public var width: Int?
    public var height: Int?
    public var markupLayers: [CaptureMarkupLayer]?

    public init(
        startMs: Int,
        endMs: Int? = nil,
        type: EventType,
        appName: String? = nil,
        appBundleID: String? = nil,
        windowTitle: String? = nil,
        displayName: String? = nil,
        displayID: UInt32? = nil,
        captureMode: String? = nil,
        bounds: RecordingVisualContextRect? = nil,
        assetKind: String? = nil,
        assetFilename: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        markupLayers: [CaptureMarkupLayer]? = nil
    ) {
        self.startMs = startMs
        self.endMs = endMs
        self.type = type
        self.appName = appName
        self.appBundleID = appBundleID
        self.windowTitle = windowTitle
        self.displayName = displayName
        self.displayID = displayID
        self.captureMode = captureMode
        self.bounds = bounds
        self.assetKind = assetKind
        self.assetFilename = assetFilename
        self.width = width
        self.height = height
        self.markupLayers = markupLayers
    }
}

public struct RecordingVisualContextCapture: Codable, Sendable, Equatable {
    public var mode: String
    public var displayName: String?
    public var width: Int?
    public var height: Int?
    public var windowTitle: String?
    public var appName: String?

    public init(
        mode: String,
        displayName: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        windowTitle: String? = nil,
        appName: String? = nil
    ) {
        self.mode = mode
        self.displayName = displayName
        self.width = width
        self.height = height
        self.windowTitle = windowTitle
        self.appName = appName
    }
}

public struct RecordingVisualContextFrame: Codable, Sendable, Equatable {
    public var index: Int
    public var timeSeconds: Double
    public var path: String

    public init(index: Int, timeSeconds: Double, path: String) {
        self.index = index
        self.timeSeconds = timeSeconds
        self.path = path
    }
}

public struct RecordingVisualContextProcessorRun: Codable, Sendable, Equatable {
    public var kind: String
    public var version: String?
    public var command: String?
    public var ranAt: Date
    public var status: RecordingVisualContext.Status
    public var errorMessage: String?

    public init(
        kind: String,
        version: String? = nil,
        command: String? = nil,
        ranAt: Date = Date(),
        status: RecordingVisualContext.Status,
        errorMessage: String? = nil
    ) {
        self.kind = kind
        self.version = version
        self.command = command
        self.ranAt = ranAt
        self.status = status
        self.errorMessage = errorMessage
    }
}

public struct RecordingVisualContextManifest: Codable, Sendable, Equatable {
    public var schema: Int
    public var recordingId: UUID
    public var visualContextId: UUID
    public var sourceClip: String
    public var durationSeconds: Double?
    public var capture: RecordingVisualContextCapture
    public var frames: [RecordingVisualContextFrame]
    public var metadataEvents: [RecordingVisualContextEvent]
    public var processors: [RecordingVisualContextProcessorRun]

    public init(
        schema: Int = 1,
        recordingId: UUID,
        visualContextId: UUID,
        sourceClip: String,
        durationSeconds: Double? = nil,
        capture: RecordingVisualContextCapture,
        frames: [RecordingVisualContextFrame] = [],
        metadataEvents: [RecordingVisualContextEvent] = [],
        processors: [RecordingVisualContextProcessorRun] = []
    ) {
        self.schema = schema
        self.recordingId = recordingId
        self.visualContextId = visualContextId
        self.sourceClip = sourceClip
        self.durationSeconds = durationSeconds
        self.capture = capture
        self.frames = frames
        self.metadataEvents = metadataEvents
        self.processors = processors
    }
}

// MARK: - Visual Context Storage

public enum VisualContextStorage {
    public static let manifestFilename = "visual-context.json"
    public static let summaryFilename = "visual-context.md"

    public static var visualContextsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return appSupport.appendingPathComponent("Talkie/VisualContexts", isDirectory: true)
    }

    public static func bundleURL(for context: RecordingVisualContext) -> URL {
        bundleURL(relativeDirectory: context.relativeDirectory)
    }

    public static func bundleURL(relativeDirectory: String) -> URL {
        let components = relativeDirectory
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }

        return components.reduce(visualContextsDirectory) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }

    public static func fileURL(for context: RecordingVisualContext, filename: String) -> URL {
        bundleURL(for: context).appendingPathComponent(filename)
    }

    public static func createBundle(
        sourceClipURL: URL,
        recordingId: UUID,
        timestampMs: Int,
        capturedAt: Date,
        durationMs: Int,
        captureMode: String,
        width: Int?,
        height: Int?,
        windowTitle: String?,
        appName: String?,
        displayName: String?,
        metadataEvents: [RecordingVisualContextEvent] = [],
        rootDirectory: URL? = nil
    ) -> RecordingVisualContext? {
        guard RecordingVisualContext.isScreenCaptureMode(captureMode) else { return nil }

        let id = UUID()
        let rootDirectory = rootDirectory ?? visualContextsDirectory
        let relativeDirectory = "\(recordingId.uuidString.lowercased())/\(id.uuidString.lowercased())"
        let bundleURL = rootDirectory
            .appendingPathComponent(recordingId.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let sourceExtension = sourceClipURL.pathExtension.isEmpty ? "mp4" : sourceClipURL.pathExtension
        let sourceFilename = "source.\(sourceExtension.lowercased())"
        let sourceDestination = bundleURL.appendingPathComponent(sourceFilename)
        let endedAt = capturedAt.addingTimeInterval(Double(durationMs) / 1000.0)

        var context = RecordingVisualContext(
            id: id,
            recordingId: recordingId,
            relativeDirectory: relativeDirectory,
            sourceClipFilename: sourceFilename,
            captureMode: captureMode,
            timestampMs: timestampMs,
            startedAt: capturedAt,
            endedAt: endedAt,
            durationMs: durationMs,
            width: width,
            height: height,
            displayName: displayName,
            windowTitle: windowTitle,
            appName: appName,
            manifestFilename: manifestFilename,
            summaryFilename: summaryFilename,
            status: .captured
        )

        let manifest = RecordingVisualContextManifest(
            recordingId: recordingId,
            visualContextId: id,
            sourceClip: sourceFilename,
            durationSeconds: Double(durationMs) / 1000.0,
            capture: RecordingVisualContextCapture(
                mode: captureMode,
                displayName: displayName,
                width: width,
                height: height,
                windowTitle: windowTitle,
                appName: appName
            ),
            metadataEvents: normalizedEvents(
                metadataEvents,
                captureMode: captureMode,
                displayName: displayName,
                width: width,
                height: height,
                windowTitle: windowTitle,
                appName: appName,
                durationMs: durationMs
            )
        )

        do {
            try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: sourceDestination.path) {
                try FileManager.default.removeItem(at: sourceDestination)
            }
            try FileManager.default.copyItem(at: sourceClipURL, to: sourceDestination)
            try writeManifest(manifest, to: bundleURL.appendingPathComponent(manifestFilename))
            try writeSummary(
                context: context,
                manifest: manifest,
                to: bundleURL.appendingPathComponent(summaryFilename)
            )
            VisualContextFrameProcessor.schedule(for: context)
            return context
        } catch {
            context.status = .failed
            context.errorMessage = error.localizedDescription
            Log(.system).error("Failed to create visual context bundle: \(error)")
            return nil
        }
    }

    public static func loadManifest(from bundleURL: URL) throws -> RecordingVisualContextManifest {
        let url = bundleURL.appendingPathComponent(manifestFilename)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingVisualContextManifest.self, from: data)
    }

    public static func writeProcessedBundle(
        context: RecordingVisualContext,
        manifest: RecordingVisualContextManifest,
        bundleURL: URL
    ) throws {
        try writeManifest(manifest, to: bundleURL.appendingPathComponent(manifestFilename))
        try writeSummary(
            context: context,
            manifest: manifest,
            to: bundleURL.appendingPathComponent(summaryFilename)
        )
    }

    private static func writeManifest(_ manifest: RecordingVisualContextManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private static func writeSummary(
        context: RecordingVisualContext,
        manifest: RecordingVisualContextManifest,
        to url: URL
    ) throws {
        let markdown = summaryMarkdown(context: context, manifest: manifest)
        guard let data = markdown.data(using: .utf8) else { return }
        try data.write(to: url, options: .atomic)
    }

    public static func summaryMarkdown(
        context: RecordingVisualContext,
        manifest: RecordingVisualContextManifest
    ) -> String {
        var lines: [String] = [
            "# Visual Context",
            "",
            "Duration: \(formatDuration(context.durationMs))",
            "Capture: \(captureDescription(context))",
            "Source clip: \(context.sourceClipFilename)",
            "Status: \(context.status.rawValue)"
        ]

        if let contactSheet = context.contactSheetFilename {
            lines.append("Frame canvas: \(contactSheet)")
        }
        if context.frameCount != nil {
            lines.append("Frames: frames/")
        }

        lines.append("")
        lines.append("## Timeline")
        lines.append("")

        let timelineLines = manifest.metadataEvents
            .sorted { $0.startMs < $1.startMs }
            .map(formatTimelineEvent)

        if timelineLines.isEmpty {
            lines.append("No metadata events captured.")
        } else {
            lines.append(contentsOf: timelineLines)
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func normalizedEvents(
        _ events: [RecordingVisualContextEvent],
        captureMode: String,
        displayName: String?,
        width: Int?,
        height: Int?,
        windowTitle: String?,
        appName: String?,
        durationMs: Int
    ) -> [RecordingVisualContextEvent] {
        if !events.isEmpty { return events }

        return [
            RecordingVisualContextEvent(
                startMs: 0,
                endMs: max(0, durationMs),
                type: .captureTarget,
                appName: appName,
                windowTitle: windowTitle,
                displayName: displayName,
                captureMode: captureMode,
                bounds: width.flatMap { w in
                    height.map { h in
                        RecordingVisualContextRect(
                            x: 0,
                            y: 0,
                            width: Double(w),
                            height: Double(h)
                        )
                    }
                }
            )
        ]
    }

    private static func captureDescription(_ context: RecordingVisualContext) -> String {
        var parts = [context.captureMode]
        if let displayName = context.displayName, !displayName.isEmpty {
            parts.append(displayName)
        }
        if let width = context.width, let height = context.height {
            parts.append("\(width)x\(height)")
        }
        if let appName = context.appName, !appName.isEmpty {
            parts.append(appName)
        }
        if let windowTitle = context.windowTitle, !windowTitle.isEmpty {
            parts.append("window: \"\(windowTitle)\"")
        }
        return parts.joined(separator: ", ")
    }

    private static func formatTimelineEvent(_ event: RecordingVisualContextEvent) -> String {
        let range = "\(formatTimestamp(event.startMs))-\(formatTimestamp(event.endMs ?? event.startMs))"
        let subject: String
        switch event.type {
        case .captureTarget:
            subject = "Capture target: \(event.captureMode ?? "screen")"
        case .activeWindow:
            subject = [event.appName, event.windowTitle.map { "window: \"\($0)\"" }]
                .compactMap { $0 }
                .joined(separator: ", ")
        case .screenshot:
            let size = event.width.flatMap { width in event.height.map { "\(width)x\($0)" } }
            subject = [
                "Screenshot marker",
                event.assetFilename,
                event.captureMode,
                size,
                event.appName,
                event.windowTitle.map { "window: \"\($0)\"" }
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        case .captureMarkup:
            let count = event.markupLayers?.count ?? 0
            let size = event.width.flatMap { width in event.height.map { "\(width)x\($0)" } }
            subject = [
                "Capture markup",
                "\(count) layer\(count == 1 ? "" : "s")",
                event.captureMode,
                size
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        }

        let text = subject.isEmpty ? event.type.rawValue : subject
        return "\(range)  \(text)"
    }

    private static func formatDuration(_ durationMs: Int?) -> String {
        guard let durationMs else { return "unknown" }
        return formatTimestamp(max(0, durationMs))
    }

    private static func formatTimestamp(_ milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds) / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let paddedSeconds = seconds < 10 ? "0\(seconds)" : "\(seconds)"
        return "\(minutes):\(paddedSeconds)"
    }
}
