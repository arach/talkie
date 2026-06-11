//
//  AgentLiveTrayAssetStore.swift
//  TalkieKit
//
//  Agent-owned live tray promotion for dictation sessions.
//  Reads the stable live tray storage layout, copies eligible unpinned assets
//  into durable recording storage, then drains only the assets it successfully
//  promoted. Talkie remains responsible for durable review/edit/save surfaces.
//

import Foundation

public enum LiveTrayNotifications {
    /// Distributed notification name posted after TalkieAgent mutates live tray
    /// manifests. Talkie uses this to refresh view/edit surfaces; it should not
    /// treat the notification as authority to mutate live capture state.
    public static let assetsDidChange = "to.talkie.tray.assetsDidChange"
}

public struct AgentLiveTrayAssetPromotion: Sendable {
    public let recordingId: UUID
    public let assets: TalkieObjectAssets
    public let promotedScreenshotIDs: Set<UUID>
    public let promotedClipIDs: Set<UUID>

    public var isEmpty: Bool { assets.isEmpty }

    public init(
        recordingId: UUID,
        assets: TalkieObjectAssets,
        promotedScreenshotIDs: Set<UUID>,
        promotedClipIDs: Set<UUID>
    ) {
        self.recordingId = recordingId
        self.assets = assets
        self.promotedScreenshotIDs = promotedScreenshotIDs
        self.promotedClipIDs = promotedClipIDs
    }
}

public struct AgentLiveTrayAssetSnapshot: Equatable, Sendable {
    public let screenshotCount: Int
    public let clipCount: Int
    public let pinnedScreenshotCount: Int
    public let pinnedClipCount: Int
    public let latestAssetAt: Date?

    public var totalCount: Int { screenshotCount + clipCount }
    public var pinnedCount: Int { pinnedScreenshotCount + pinnedClipCount }

    public init(
        screenshotCount: Int,
        clipCount: Int,
        pinnedScreenshotCount: Int,
        pinnedClipCount: Int,
        latestAssetAt: Date?
    ) {
        self.screenshotCount = screenshotCount
        self.clipCount = clipCount
        self.pinnedScreenshotCount = pinnedScreenshotCount
        self.pinnedClipCount = pinnedClipCount
        self.latestAssetAt = latestAssetAt
    }

    public static let empty = AgentLiveTrayAssetSnapshot(
        screenshotCount: 0,
        clipCount: 0,
        pinnedScreenshotCount: 0,
        pinnedClipCount: 0,
        latestAssetAt: nil
    )
}

public struct AgentLiveTrayStoredScreenshot: Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let fileURL: URL
    public let filename: String

    public init(id: UUID, capturedAt: Date, fileURL: URL, filename: String) {
        self.id = id
        self.capturedAt = capturedAt
        self.fileURL = fileURL
        self.filename = filename
    }
}

public enum AgentLiveTrayMediaKind: String, Codable, Sendable {
    case screenshot
    case clip
}

public struct AgentLiveTrayItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let kind: AgentLiveTrayMediaKind
    public let capturedAt: Date
    public let durationMs: Int?
    public let filename: String
    public let width: Int
    public let height: Int
    public let captureMode: String
    public let windowTitle: String?
    public let appName: String?
    public let appBundleID: String?
    public let displayName: String?
    public let pinned: Bool
    public let ocrText: String?
    public let fileURL: URL

    public var isClip: Bool { kind == .clip }
    public var isScreenshot: Bool { kind == .screenshot }

    public init(
        id: UUID,
        kind: AgentLiveTrayMediaKind,
        capturedAt: Date,
        durationMs: Int? = nil,
        filename: String,
        width: Int,
        height: Int,
        captureMode: String,
        windowTitle: String? = nil,
        appName: String? = nil,
        appBundleID: String? = nil,
        displayName: String? = nil,
        pinned: Bool = false,
        ocrText: String? = nil,
        fileURL: URL
    ) {
        self.id = id
        self.kind = kind
        self.capturedAt = capturedAt
        self.durationMs = durationMs
        self.filename = filename
        self.width = width
        self.height = height
        self.captureMode = captureMode
        self.windowTitle = windowTitle
        self.appName = appName
        self.appBundleID = appBundleID
        self.displayName = displayName
        self.pinned = pinned
        self.ocrText = ocrText
        self.fileURL = fileURL
    }
}

public struct AgentLiveTrayStoredClip: Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let fileURL: URL
    public let filename: String

    public init(id: UUID, capturedAt: Date, fileURL: URL, filename: String) {
        self.id = id
        self.capturedAt = capturedAt
        self.fileURL = fileURL
        self.filename = filename
    }
}

/// Agent-owned live tray storage and promotion service.
///
/// The storage paths are intentionally compatible with the historical Talkie
/// tray layout so existing installs do not need a file migration. The ownership
/// boundary changes here: TalkieAgent performs the dictation-window drain and
/// durable copy locally instead of asking Talkie.app to fetch tray media over XPC.
public actor AgentLiveTrayAssetStore {
    public static let shared = AgentLiveTrayAssetStore()

    private let log = Log(.system)
    private let fileManager: FileManager
    private let trayRootDirectory: URL

    public init(
        fileManager: FileManager = .default,
        trayRootDirectory: URL = URL.applicationSupportDirectory
            .appending(path: "Talkie", directoryHint: .isDirectory)
            .appending(path: "Tray", directoryHint: .isDirectory)
    ) {
        self.fileManager = fileManager
        self.trayRootDirectory = trayRootDirectory
    }

    /// Copies eligible unpinned live tray assets into durable recording storage.
    ///
    /// This does not mutate live tray manifests. Call `drainPromotedAssets(_:)`
    /// only after the durable recording database row has been merged
    /// successfully.
    ///
    /// - Parameters:
    ///   - recordingId: Durable recording id to attach assets to.
    ///   - recordingStartedAt: Start of the dictation window.
    ///   - recordingEndedAt: End of the dictation window.
    ///   - includeScreenshots: False when the recording already has live
    ///     screenshots captured through the low-latency side channel.
    /// - Returns: Durable assets and source live-tray ids for a later drain, or
    ///   nil if nothing eligible was promoted.
    public func promoteAssetsForRecording(
        recordingId: UUID,
        recordingStartedAt: Date?,
        recordingEndedAt: Date?,
        includeScreenshots: Bool
    ) async -> AgentLiveTrayAssetPromotion? {
        guard let recordingStartedAt,
              let recordingEndedAt,
              recordingEndedAt >= recordingStartedAt else {
            log.warning(
                "[Tray] Agent live tray promotion skipped: invalid recording window",
                detail: "id=\(recordingId.uuidString.prefix(8))"
            )
            return nil
        }

        let screenshotManifest = Manifest<StoredTrayScreenshot>(
            directory: screenshotsDirectory,
            fileManager: fileManager
        )
        let clipManifest = Manifest<StoredTrayClip>(
            directory: clipsDirectory,
            fileManager: fileManager
        )

        let screenshotItems = includeScreenshots ? screenshotManifest.loadExistingItems() : []
        let clipItems = clipManifest.loadExistingItems()

        let eligibleScreenshots = screenshotItems.filter {
            !$0.pinned
            && $0.capturedAt >= recordingStartedAt
            && $0.capturedAt <= recordingEndedAt
        }
        let eligibleClips = clipItems.filter {
            !$0.pinned && $0.overlaps(start: recordingStartedAt, end: recordingEndedAt)
        }

        if !includeScreenshots {
            log.debug("[Tray] Agent live tray promotion skipping screenshots; live screenshots already attached")
        }

        guard !eligibleScreenshots.isEmpty || !eligibleClips.isEmpty else {
            log.debug(
                "[Tray] Agent live tray promotion found no in-window assets",
                detail: "id=\(recordingId.uuidString.prefix(8))"
            )
            return nil
        }

        let screenshotPromotion = promoteScreenshots(
            eligibleScreenshots,
            recordingId: recordingId,
            recordingStartedAt: recordingStartedAt
        )
        let clipPromotion = promoteClips(
            eligibleClips,
            recordingId: recordingId,
            recordingStartedAt: recordingStartedAt
        )

        let assets = TalkieObjectAssets(
            screenshots: screenshotPromotion.assets.isEmpty ? nil : screenshotPromotion.assets,
            clips: clipPromotion.assets.isEmpty ? nil : clipPromotion.assets,
            visualContexts: clipPromotion.visualContexts.isEmpty ? nil : clipPromotion.visualContexts
        )

        guard !assets.isEmpty else {
            log.warning(
                "[Tray] Agent live tray promotion produced no usable assets",
                detail: "id=\(recordingId.uuidString.prefix(8)) eligibleScreenshots=\(eligibleScreenshots.count) eligibleClips=\(eligibleClips.count)"
            )
            return nil
        }

        log.info(
            "[Tray] Agent promoted live tray assets",
            detail: "id=\(recordingId.uuidString.prefix(8)) screenshots=\(screenshotPromotion.assets.count) clips=\(clipPromotion.assets.count) visualContexts=\(clipPromotion.visualContexts.count)"
        )

        return AgentLiveTrayAssetPromotion(
            recordingId: recordingId,
            assets: assets,
            promotedScreenshotIDs: screenshotPromotion.drainedIDs,
            promotedClipIDs: clipPromotion.drainedIDs
        )
    }

    /// Removes live tray files and manifest entries for assets already promoted
    /// into durable recording storage. Call after database merge succeeds.
    public func drainPromotedAssets(_ promotion: AgentLiveTrayAssetPromotion) async {
        if !promotion.promotedScreenshotIDs.isEmpty {
            let screenshotManifest = Manifest<StoredTrayScreenshot>(
                directory: screenshotsDirectory,
                fileManager: fileManager
            )
            let items = screenshotManifest.loadExistingItems()
            let promoted = items.filter { promotion.promotedScreenshotIDs.contains($0.id) }
            let remaining = items.filter { !promotion.promotedScreenshotIDs.contains($0.id) }
            screenshotManifest.save(remaining)
            screenshotManifest.removeFiles(for: promoted)
        }

        if !promotion.promotedClipIDs.isEmpty {
            let clipManifest = Manifest<StoredTrayClip>(
                directory: clipsDirectory,
                fileManager: fileManager
            )
            let items = clipManifest.loadExistingItems()
            let promoted = items.filter { promotion.promotedClipIDs.contains($0.id) }
            let remaining = items.filter { !promotion.promotedClipIDs.contains($0.id) }
            clipManifest.save(remaining)
            clipManifest.removeFiles(for: promoted)
        }

        log.info(
            "[Tray] Agent drained promoted live tray assets",
            detail: "id=\(promotion.recordingId.uuidString.prefix(8)) screenshots=\(promotion.promotedScreenshotIDs.count) clips=\(promotion.promotedClipIDs.count)"
        )
    }

    /// Convenience one-step promotion + drain for callers that do not need to
    /// coordinate a separate database merge. Dictation uses the two-phase API.
    public func drainAssetsForRecording(
        recordingId: UUID,
        recordingStartedAt: Date?,
        recordingEndedAt: Date?,
        includeScreenshots: Bool
    ) async -> TalkieObjectAssets? {
        guard let promotion = await promoteAssetsForRecording(
            recordingId: recordingId,
            recordingStartedAt: recordingStartedAt,
            recordingEndedAt: recordingEndedAt,
            includeScreenshots: includeScreenshots
        ) else {
            return nil
        }

        await drainPromotedAssets(promotion)
        return promotion.assets
    }

    /// Lightweight manifest snapshot for Agent Home and diagnostics.
    /// This is read-only and intentionally exposes counts instead of leaking
    /// the private on-disk manifest item types into app UI.
    public func snapshot() -> AgentLiveTrayAssetSnapshot {
        let screenshotItems = Manifest<StoredTrayScreenshot>(
            directory: screenshotsDirectory,
            fileManager: fileManager
        ).loadExistingItems()
        let clipItems = Manifest<StoredTrayClip>(
            directory: clipsDirectory,
            fileManager: fileManager
        ).loadExistingItems()
        let latest = (screenshotItems.map(\.capturedAt) + clipItems.map(\.capturedAt)).max()

        return AgentLiveTrayAssetSnapshot(
            screenshotCount: screenshotItems.count,
            clipCount: clipItems.count,
            pinnedScreenshotCount: screenshotItems.filter(\.pinned).count,
            pinnedClipCount: clipItems.filter(\.pinned).count,
            latestAssetAt: latest
        )
    }

    /// Returns recent live tray media items, newest first, using the same
    /// manifest/file layout Talkie already reads for review surfaces.
    public func recentItems(limit: Int = 5) -> [AgentLiveTrayItem] {
        let screenshotItems = Manifest<StoredTrayScreenshot>(
            directory: screenshotsDirectory,
            fileManager: fileManager
        ).loadExistingItems().map { item in
            AgentLiveTrayItem(
                id: item.id,
                kind: .screenshot,
                capturedAt: item.capturedAt,
                filename: item.filename,
                width: item.width,
                height: item.height,
                captureMode: item.mode,
                windowTitle: item.windowTitle,
                appName: item.appName,
                appBundleID: item.appBundleID,
                displayName: item.displayName,
                pinned: item.pinned,
                ocrText: item.ocrText,
                fileURL: item.fileURL
            )
        }
        let clipItems = Manifest<StoredTrayClip>(
            directory: clipsDirectory,
            fileManager: fileManager
        ).loadExistingItems().map { item in
            AgentLiveTrayItem(
                id: item.id,
                kind: .clip,
                capturedAt: item.capturedAt,
                durationMs: item.durationMs,
                filename: item.filename,
                width: item.width,
                height: item.height,
                captureMode: item.captureMode,
                windowTitle: item.windowTitle,
                appName: item.appName,
                appBundleID: nil,
                displayName: item.displayName,
                pinned: item.pinned,
                ocrText: nil,
                fileURL: item.fileURL
            )
        }

        return (screenshotItems + clipItems)
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// Deletes one live tray item from the manifest and removes its stored
    /// file plus sidecars. Used by lightweight Agent preview controls.
    @discardableResult
    public func deleteItem(_ item: AgentLiveTrayItem) -> Bool {
        deleteItem(id: item.id, kind: item.kind)
    }

    /// Deletes one live tray item from the manifest and removes its stored
    /// file plus sidecars. Returns false if the item is already gone.
    @discardableResult
    public func deleteItem(id: UUID, kind: AgentLiveTrayMediaKind) -> Bool {
        let deleted: Bool
        switch kind {
        case .screenshot:
            deleted = deleteStoredItem(
                id: id,
                manifest: Manifest<StoredTrayScreenshot>(
                    directory: screenshotsDirectory,
                    fileManager: fileManager
                )
            )
        case .clip:
            deleted = deleteStoredItem(
                id: id,
                manifest: Manifest<StoredTrayClip>(
                    directory: clipsDirectory,
                    fileManager: fileManager
                )
            )
        }

        if deleted {
            postAssetsDidChange()
            log.info(
                "[Tray] Agent deleted live tray asset",
                detail: "id=\(id.uuidString.prefix(8)) kind=\(kind.rawValue)"
            )
        }
        return deleted
    }

    /// Stores a live tray screenshot using the same manifest/file layout Talkie
    /// already reads. This is the capture-time write side of the ownership
    /// inversion: Agent produces the asset, Talkie observes it for view/edit.
    public func storeScreenshot(
        data: Data,
        capturedAt: Date = Date(),
        mode: String,
        width: Int,
        height: Int,
        windowTitle: String? = nil,
        appName: String? = nil,
        appBundleID: String? = nil,
        displayName: String? = nil,
        pinned: Bool = false,
        ocrText: String? = nil
    ) throws -> AgentLiveTrayStoredScreenshot {
        let id = UUID()
        let filename = CaptureFilenameFormatter.screenshotFilename(
            id: id,
            capturedAt: capturedAt,
            mode: mode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )
        let fileURL = screenshotsDirectory.appending(path: filename, directoryHint: .notDirectory)

        try fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)

        let manifest = Manifest<StoredTrayScreenshot>(
            directory: screenshotsDirectory,
            fileManager: fileManager
        )
        var items = manifest.loadExistingItems()
        items.append(StoredTrayScreenshot(
            id: id,
            capturedAt: capturedAt,
            mode: mode,
            width: width,
            height: height,
            filename: filename,
            windowTitle: windowTitle,
            appName: appName,
            appBundleID: appBundleID,
            displayName: displayName,
            pinned: pinned,
            ocrText: ocrText,
            fileURL: fileURL
        ))
        manifest.save(items)
        postAssetsDidChange()

        log.info(
            "[Tray] Agent stored live tray screenshot",
            detail: "id=\(id.uuidString.prefix(8)) mode=\(mode) size=\(width)x\(height)"
        )

        return AgentLiveTrayStoredScreenshot(
            id: id,
            capturedAt: capturedAt,
            fileURL: fileURL,
            filename: filename
        )
    }

    /// Stores a live tray screen clip using the same manifest/file layout Talkie
    /// already reads. Agent produces the clip; Talkie observes it for view/edit.
    public func storeClip(
        tempURL: URL,
        capturedAt: Date = Date(),
        durationMs: Int,
        width: Int,
        height: Int,
        captureMode: String,
        windowTitle: String? = nil,
        appName: String? = nil,
        displayName: String? = nil,
        metadataEvents: [RecordingVisualContextEvent] = [],
        pinned: Bool = false
    ) throws -> AgentLiveTrayStoredClip {
        let id = UUID()
        var filename = CaptureFilenameFormatter.clipFilename(
            id: id,
            capturedAt: capturedAt,
            mode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )
        var fileURL = clipsDirectory.appending(path: filename, directoryHint: .notDirectory)

        try fileManager.createDirectory(at: clipsDirectory, withIntermediateDirectories: true)
        if tempURL.deletingLastPathComponent().standardizedFileURL == clipsDirectory.standardizedFileURL {
            filename = tempURL.lastPathComponent
            fileURL = tempURL
        } else {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            try fileManager.moveItem(at: tempURL, to: fileURL)
        }

        let manifest = Manifest<StoredTrayClip>(
            directory: clipsDirectory,
            fileManager: fileManager
        )
        var items = manifest.loadExistingItems()
        items.append(StoredTrayClip(
            id: id,
            capturedAt: capturedAt,
            durationMs: durationMs,
            filename: filename,
            width: width,
            height: height,
            captureMode: captureMode,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName,
            metadataEvents: metadataEvents,
            pinned: pinned,
            fileURL: fileURL
        ))
        manifest.save(items)
        postAssetsDidChange()

        log.info(
            "[Tray] Agent stored live tray clip",
            detail: "id=\(id.uuidString.prefix(8)) mode=\(captureMode) durationMs=\(durationMs) size=\(width)x\(height)"
        )

        return AgentLiveTrayStoredClip(
            id: id,
            capturedAt: capturedAt,
            fileURL: fileURL,
            filename: filename
        )
    }

    private var screenshotsDirectory: URL {
        trayRootDirectory.appending(path: "screenshots", directoryHint: .isDirectory)
    }

    private var clipsDirectory: URL {
        trayRootDirectory.appending(path: "clips", directoryHint: .isDirectory)
    }

    private func postAssetsDidChange() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(LiveTrayNotifications.assetsDidChange),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func deleteStoredItem<Item: StoredTrayAsset>(
        id: UUID,
        manifest: Manifest<Item>
    ) -> Bool {
        let items = manifest.loadExistingItems()
        guard let deleted = items.first(where: { $0.id == id }) else { return false }
        manifest.save(items.filter { $0.id != id })
        manifest.removeFiles(for: [deleted])
        CaptureMarkupStorage.deleteSidecar(forImageURL: deleted.fileURL)
        return true
    }

    private func promoteScreenshots(
        _ items: [StoredTrayScreenshot],
        recordingId: UUID,
        recordingStartedAt: Date
    ) -> (assets: [RecordingScreenshot], drainedIDs: Set<UUID>) {
        var screenshots: [RecordingScreenshot] = []
        var drainedIDs = Set<UUID>()

        for (index, item) in items.enumerated() {
            let timestampMs = max(0, Int(item.capturedAt.timeIntervalSince(recordingStartedAt) * 1000))
            guard let data = try? Data(contentsOf: item.fileURL),
                  let savedURL = ScreenshotStorage.save(
                    data,
                    recordingId: recordingId,
                    timestampMs: timestampMs,
                    index: index,
                    capturedAt: item.capturedAt,
                    captureMode: item.mode,
                    width: item.width,
                    height: item.height,
                    windowTitle: item.windowTitle,
                    appName: item.appName,
                    displayName: item.displayName
                  ) else {
                log.warning(
                    "[Tray] Agent failed to promote live tray screenshot",
                    detail: item.filename
                )
                continue
            }

            screenshots.append(RecordingScreenshot(
                filename: savedURL.lastPathComponent,
                timestampMs: timestampMs,
                captureMode: item.mode,
                width: item.width,
                height: item.height,
                windowTitle: item.windowTitle,
                appName: item.appName,
                appBundleID: item.appBundleID,
                displayName: item.displayName
            ))
            drainedIDs.insert(item.id)
        }

        return (screenshots, drainedIDs)
    }

    private func promoteClips(
        _ items: [StoredTrayClip],
        recordingId: UUID,
        recordingStartedAt: Date
    ) -> (assets: [RecordingClip], visualContexts: [RecordingVisualContext], drainedIDs: Set<UUID>) {
        var clips: [RecordingClip] = []
        var visualContexts: [RecordingVisualContext] = []
        var drainedIDs = Set<UUID>()

        for (index, item) in items.enumerated() {
            let timestampMs = max(0, Int(item.capturedAt.timeIntervalSince(recordingStartedAt) * 1000))
            guard let savedURL = VideoClipStorage.save(
                item.fileURL,
                recordingId: recordingId,
                timestampMs: timestampMs,
                index: index,
                capturedAt: item.capturedAt,
                captureMode: item.captureMode,
                width: item.width,
                height: item.height,
                windowTitle: item.windowTitle,
                appName: item.appName,
                displayName: item.displayName
            ) else {
                log.warning(
                    "[Tray] Agent failed to promote live tray clip",
                    detail: item.filename
                )
                continue
            }

            clips.append(RecordingClip(
                filename: savedURL.lastPathComponent,
                timestampMs: timestampMs,
                durationMs: item.durationMs,
                width: item.width,
                height: item.height,
                captureMode: item.captureMode,
                windowTitle: item.windowTitle,
                appName: item.appName,
                displayName: item.displayName
            ))

            if let visualContext = VisualContextStorage.createBundle(
                sourceClipURL: savedURL,
                recordingId: recordingId,
                timestampMs: timestampMs,
                capturedAt: item.capturedAt,
                durationMs: item.durationMs,
                captureMode: item.captureMode,
                width: item.width,
                height: item.height,
                windowTitle: item.windowTitle,
                appName: item.appName,
                displayName: item.displayName,
                metadataEvents: item.metadataEvents
            ) {
                visualContexts.append(visualContext)
            } else if RecordingVisualContext.isScreenCaptureMode(item.captureMode) {
                log.warning(
                    "[Tray] Agent failed to create visual context bundle for live tray clip",
                    detail: item.filename
                )
            }

            drainedIDs.insert(item.id)
        }

        return (clips, visualContexts, drainedIDs)
    }
}

// MARK: - Stored Manifests

private protocol StoredTrayAsset: Codable, Identifiable where ID == UUID {
    var filename: String { get }
    var fileURL: URL { get set }
}

private struct StoredTrayScreenshot: StoredTrayAsset {
    let id: UUID
    let capturedAt: Date
    let mode: String
    let width: Int
    let height: Int
    let filename: String
    let windowTitle: String?
    let appName: String?
    let appBundleID: String?
    let displayName: String?
    var pinned: Bool
    var ocrText: String?

    var fileURL: URL = URL(fileURLWithPath: "/")

    enum CodingKeys: String, CodingKey {
        case id
        case capturedAt
        case mode
        case width
        case height
        case filename
        case windowTitle
        case appName
        case appBundleID
        case displayName
        case pinned
        case ocrText
    }

    init(
        id: UUID,
        capturedAt: Date,
        mode: String,
        width: Int,
        height: Int,
        filename: String,
        windowTitle: String?,
        appName: String?,
        appBundleID: String?,
        displayName: String?,
        pinned: Bool,
        ocrText: String?,
        fileURL: URL
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.mode = mode
        self.width = width
        self.height = height
        self.filename = filename
        self.windowTitle = windowTitle
        self.appName = appName
        self.appBundleID = appBundleID
        self.displayName = displayName
        self.pinned = pinned
        self.ocrText = ocrText
        self.fileURL = fileURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        mode = try container.decode(String.self, forKey: .mode)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        filename = try container.decode(String.self, forKey: .filename)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        appBundleID = try container.decodeIfPresent(String.self, forKey: .appBundleID)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(mode, forKey: .mode)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(filename, forKey: .filename)
        try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
        try container.encodeIfPresent(appName, forKey: .appName)
        try container.encodeIfPresent(appBundleID, forKey: .appBundleID)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(pinned, forKey: .pinned)
        try container.encodeIfPresent(ocrText, forKey: .ocrText)
    }
}

private struct StoredTrayClip: StoredTrayAsset {
    let id: UUID
    let capturedAt: Date
    let durationMs: Int
    let filename: String
    let width: Int
    let height: Int
    let captureMode: String
    let windowTitle: String?
    let appName: String?
    let displayName: String?
    let metadataEvents: [RecordingVisualContextEvent]
    var pinned: Bool

    var fileURL: URL = URL(fileURLWithPath: "/")

    enum CodingKeys: String, CodingKey {
        case id
        case capturedAt
        case durationMs
        case filename
        case width
        case height
        case captureMode
        case windowTitle
        case appName
        case displayName
        case metadataEvents
        case pinned
    }

    init(
        id: UUID,
        capturedAt: Date,
        durationMs: Int,
        filename: String,
        width: Int,
        height: Int,
        captureMode: String,
        windowTitle: String?,
        appName: String?,
        displayName: String?,
        metadataEvents: [RecordingVisualContextEvent],
        pinned: Bool,
        fileURL: URL
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.durationMs = durationMs
        self.filename = filename
        self.width = width
        self.height = height
        self.captureMode = captureMode
        self.windowTitle = windowTitle
        self.appName = appName
        self.displayName = displayName
        self.metadataEvents = metadataEvents
        self.pinned = pinned
        self.fileURL = fileURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        filename = try container.decode(String.self, forKey: .filename)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        captureMode = try container.decode(String.self, forKey: .captureMode)
        windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        metadataEvents = try container.decodeIfPresent([RecordingVisualContextEvent].self, forKey: .metadataEvents) ?? []
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(capturedAt, forKey: .capturedAt)
        try container.encode(durationMs, forKey: .durationMs)
        try container.encode(filename, forKey: .filename)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(captureMode, forKey: .captureMode)
        try container.encodeIfPresent(windowTitle, forKey: .windowTitle)
        try container.encodeIfPresent(appName, forKey: .appName)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(metadataEvents, forKey: .metadataEvents)
        try container.encode(pinned, forKey: .pinned)
    }

    func overlaps(start: Date, end: Date) -> Bool {
        let clipEnd = capturedAt.addingTimeInterval(Double(max(0, durationMs)) / 1000.0)
        return capturedAt <= end && clipEnd >= start
    }
}

private struct Manifest<Item: StoredTrayAsset> {
    let directory: URL
    let fileManager: FileManager

    private var url: URL {
        directory.appending(path: "manifest.json", directoryHint: .notDirectory)
    }

    func loadExistingItems() -> [Item] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }

        do {
            let data = try Data(contentsOf: url)
            var items = try Self.decoder.decode([Item].self, from: data)
            for index in items.indices {
                items[index].fileURL = directory.appending(path: items[index].filename, directoryHint: .notDirectory)
            }
            return items.filter { item in
                fileManager.fileExists(atPath: item.fileURL.path)
            }
        } catch {
            Log(.system).error("[Tray] Failed to read live tray manifest: \(error)", detail: url.path)
            return []
        }
    }

    func save(_ items: [Item]) {
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(items)
            try data.write(to: url, options: .atomic)
        } catch {
            Log(.system).error("[Tray] Failed to write live tray manifest: \(error)", detail: url.path)
        }
    }

    func removeFiles(for items: [Item]) {
        for item in items {
            try? fileManager.removeItem(at: item.fileURL)
            TKSidecarStore.delete(forAsset: item.fileURL)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                if let date = ISO8601DateFormatter.talkieLiveTray.date(from: string) {
                    return date
                }
                if let date = ISO8601DateFormatter.talkieLiveTrayFractional.date(from: string) {
                    return date
                }
            }
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported live tray date encoding"
            )
        }
        return decoder
    }
}

private extension ISO8601DateFormatter {
    static let talkieLiveTray: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let talkieLiveTrayFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
