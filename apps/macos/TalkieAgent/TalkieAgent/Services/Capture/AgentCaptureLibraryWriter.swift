//
//  AgentCaptureLibraryWriter.swift
//  TalkieAgent
//
//  Persists Agent-owned captures into Talkie's shared Library.
//

import Foundation
import GRDB
import TalkieKit

private let agentCaptureLibraryLog = Log(.database)

struct AgentPersistedCaptureMedia {
    let object: TalkieObject
    let fileURL: URL
    let filename: String
}

enum AgentCaptureLibraryWriter {
    @discardableResult
    static func persistScreenshot(
        data: Data,
        id: UUID,
        capturedAt: Date,
        captureMode: String,
        width: Int,
        height: Int,
        windowTitle: String?,
        appName: String?,
        appBundleID: String?,
        displayName: String?,
        ocrText: String? = nil
    ) -> AgentPersistedCaptureMedia? {
        guard let savedURL = ScreenshotStorage.save(
            data,
            recordingId: id,
            timestampMs: 0,
            index: 0,
            capturedAt: capturedAt,
            captureMode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        ) else {
            agentCaptureLibraryLog.error("Agent screenshot capture failed to save permanent asset")
            return nil
        }

        return persistScreenshotReference(
            fileURL: savedURL,
            id: id,
            capturedAt: capturedAt,
            captureMode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            appBundleID: appBundleID,
            displayName: displayName,
            ocrText: ocrText
        )
    }

    @discardableResult
    static func persistScreenshotReference(
        fileURL: URL,
        id: UUID,
        capturedAt: Date,
        captureMode: String,
        width: Int,
        height: Int,
        windowTitle: String?,
        appName: String?,
        appBundleID: String?,
        displayName: String?,
        ocrText: String? = nil
    ) -> AgentPersistedCaptureMedia? {
        let screenshot = RecordingScreenshot(
            filename: fileURL.lastPathComponent,
            timestampMs: 0,
            captureMode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            appBundleID: appBundleID,
            displayName: displayName
        )

        var assets = TalkieObjectAssets(screenshots: [screenshot])
        if let text = normalized(ocrText) {
            assets.textProvenance = [
                ProvenanceSegment(
                    source: .ocr,
                    originalText: text,
                    sourceAssetId: fileURL.lastPathComponent,
                    sourceDetail: "Vision"
                )
            ]
        }

        guard let object = persistCapture(
            id: id,
            createdAt: capturedAt,
            title: captureTitle(
                captureMode: captureMode,
                appName: appName,
                windowTitle: windowTitle,
                displayName: displayName
            ),
            assets: assets,
            appBundleID: appBundleID,
            appName: appName,
            windowTitle: windowTitle
        ) else {
            return nil
        }

        return AgentPersistedCaptureMedia(
            object: object,
            fileURL: fileURL,
            filename: fileURL.lastPathComponent
        )
    }

    @discardableResult
    static func persistClip(
        sourceURL: URL,
        id: UUID,
        capturedAt: Date,
        durationMs: Int,
        captureMode: String,
        width: Int,
        height: Int,
        windowTitle: String?,
        appName: String?,
        displayName: String?,
        metadataEvents: [RecordingVisualContextEvent] = []
    ) -> AgentPersistedCaptureMedia? {
        guard let savedURL = VideoClipStorage.save(
            sourceURL,
            recordingId: id,
            timestampMs: 0,
            index: 0,
            capturedAt: capturedAt,
            captureMode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName,
            moveSource: true
        ) else {
            agentCaptureLibraryLog.error("Agent screen clip failed to save permanent asset")
            return nil
        }

        let clip = RecordingClip(
            filename: savedURL.lastPathComponent,
            timestampMs: 0,
            durationMs: durationMs,
            width: width,
            height: height,
            captureMode: captureMode,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )

        let visualContext = VisualContextStorage.createBundle(
            sourceClipURL: savedURL,
            recordingId: id,
            timestampMs: 0,
            capturedAt: capturedAt,
            durationMs: durationMs,
            captureMode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName,
            metadataEvents: metadataEvents,
            copiesSourceClip: false
        )

        let assets = TalkieObjectAssets(
            clips: [clip],
            visualContexts: visualContext.map { [$0] }
        )
        let activeWindow = metadataEvents.first { $0.type == .activeWindow }

        guard let object = persistCapture(
            id: id,
            createdAt: capturedAt,
            title: captureTitle(
                captureMode: captureMode,
                appName: appName,
                windowTitle: windowTitle,
                displayName: displayName
            ),
            assets: assets,
            appBundleID: activeWindow?.appBundleID,
            appName: appName ?? activeWindow?.appName,
            windowTitle: windowTitle ?? activeWindow?.windowTitle
        ) else {
            return nil
        }

        return AgentPersistedCaptureMedia(
            object: object,
            fileURL: savedURL,
            filename: savedURL.lastPathComponent
        )
    }

    @discardableResult
    private static func persistCapture(
        id: UUID,
        createdAt: Date,
        title: String?,
        assets: TalkieObjectAssets,
        appBundleID: String?,
        appName: String?,
        windowTitle: String?
    ) -> TalkieObject? {
        var capture = TalkieObject.newCapture(id: id, title: title)
        capture.createdAt = createdAt
        capture.lastModified = Date()
        capture.assetsJSON = assets.toJSON()
        capture.metadataJSON = metadataJSON(
            appBundleID: appBundleID,
            appName: appName,
            windowTitle: windowTitle
        )

        do {
            try UnifiedDatabase.shared.write { db in
                try capture.save(db)
            }
            postLibraryDidChange()
            agentCaptureLibraryLog.info(
                "Agent capture saved to Library",
                detail: "id=\(id.uuidString.prefix(8))"
            )
            return capture
        } catch {
            agentCaptureLibraryLog.error("Agent capture Library write failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func metadataJSON(
        appBundleID: String?,
        appName: String?,
        windowTitle: String?
    ) -> String? {
        guard normalized(appBundleID) != nil
            || normalized(appName) != nil
            || normalized(windowTitle) != nil else {
            return nil
        }

        return RecordingMetadata(
            app: AppContext(
                bundleId: normalized(appBundleID),
                name: normalized(appName),
                windowTitle: normalized(windowTitle)
            )
        ).toJSON()
    }

    private static func captureTitle(
        captureMode: String,
        appName: String?,
        windowTitle: String?,
        displayName: String?
    ) -> String? {
        if let appName = normalized(appName) {
            return "\(appName) capture"
        }
        if let windowTitle = normalized(windowTitle) {
            return "\(windowTitle) capture"
        }
        if let displayName = normalized(displayName) {
            return "\(displayName) capture"
        }
        return "\(captureMode.capitalized) capture"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func postLibraryDidChange() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(TalkieLibraryNotifications.recordsDidChange),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
