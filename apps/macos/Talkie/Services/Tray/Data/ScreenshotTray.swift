//
//  ScreenshotTray.swift
//  Talkie
//
//  Staging area for screenshots captured via Hyper+S.
//  Accumulates captures until the user decides: attach to recording, save as Note, or discard.
//  Persists metadata to ~/Library/Application Support/Talkie/Tray/screenshots/manifest.json
//  so tray captures survive app restarts.
//

import AppKit
import TalkieKit

extension CaptureMode: Codable {}

// MARK: - Tray Directory

private let screenshotTrayDir: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Talkie/Tray/screenshots", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

// MARK: - Tray Screenshot

struct TrayScreenshot: Identifiable, Codable {
    let id: UUID
    let capturedAt: Date
    let mode: CaptureMode
    let width: Int
    let height: Int
    let filename: String
    let windowTitle: String?
    let appName: String?
    let displayName: String?
    /// Whether this item is pinned to the tray (won't drain into the next recording)
    var pinned: Bool
    /// Background OCR result (nil = not yet attempted, empty = no text found)
    var ocrText: String?
    /// Scaled-down thumbnail for display, generated async from disk
    var thumbnail: NSImage?

    var tempURL: URL {
        screenshotTrayDir.appendingPathComponent(filename)
    }

    var image: NSImage? { thumbnail }

    /// Load full PNG data from disk on demand (for clipboard copy). Not kept in memory.
    func loadData() -> Data? {
        try? Data(contentsOf: tempURL)
    }

    // Codable — exclude thumbnail (regenerated on restore)
    enum CodingKeys: String, CodingKey {
        case id, capturedAt, mode, width, height, filename, windowTitle, appName, displayName, pinned, ocrText
    }

    init(id: UUID, capturedAt: Date, mode: CaptureMode, width: Int, height: Int,
         filename: String, windowTitle: String? = nil, appName: String? = nil,
         displayName: String? = nil, pinned: Bool = false, ocrText: String? = nil, thumbnail: NSImage? = nil) {
        self.id = id
        self.capturedAt = capturedAt
        self.mode = mode
        self.width = width
        self.height = height
        self.filename = filename
        self.windowTitle = windowTitle
        self.appName = appName
        self.displayName = displayName
        self.pinned = pinned
        self.ocrText = ocrText
        self.thumbnail = thumbnail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        mode = try c.decode(CaptureMode.self, forKey: .mode)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        filename = try c.decode(String.self, forKey: .filename)
        windowTitle = try c.decodeIfPresent(String.self, forKey: .windowTitle)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        thumbnail = nil
    }
}

// MARK: - Screenshot Tray

@MainActor
@Observable
final class ScreenshotTray {
    static let shared = ScreenshotTray()

    private(set) var items: [TrayScreenshot] = []
    private var manifestSaveTask: Task<Void, Never>?
    private var manifestSaveGeneration: UInt64 = 0
    private let captureHotPathLoggingEnabled = ProcessInfo.processInfo.environment["CAPTURE_PERF"] == "1"

    /// One-time migration from old Buffer/ path to Tray/
    private static func migrateFromBufferIfNeeded() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldDir = appSupport.appendingPathComponent("Talkie/Buffer/screenshots", isDirectory: true)
        let newDir = appSupport.appendingPathComponent("Talkie/Tray/screenshots", isDirectory: true)
        guard fm.fileExists(atPath: oldDir.path), !fm.fileExists(atPath: newDir.path) else { return }
        do {
            try fm.createDirectory(at: newDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: oldDir, to: newDir)
            Log(.system).info("Migrated screenshot tray from Buffer/ to Tray/")
        } catch {
            Log(.system).error("Screenshot tray migration failed: \(error)")
        }
    }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    var isNotEmpty: Bool { !items.isEmpty }

    // MARK: - Pin State

    /// Items that will drain into the next recording (everything not pinned)
    var unpinnedItems: [TrayScreenshot] { items.filter { !$0.pinned } }
    var unpinnedCount: Int { items.filter { !$0.pinned }.count }
    var pinnedCount: Int { items.filter(\.pinned).count }
    var hasUnpinnedItems: Bool { items.contains { !$0.pinned } }

    func togglePinned(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        saveManifest()
    }

    /// Remove unpinned items from disk and array after successful delivery.
    /// Pinned items remain in the tray.
    func clearUnpinned() {
        let unpinned = items.filter { !$0.pinned }
        for item in unpinned {
            try? FileManager.default.removeItem(at: item.tempURL)
        }
        items.removeAll { !$0.pinned }
        saveManifest()
        Log(.system).info("Cleared \(unpinned.count) unpinned screenshots, \(items.count) pinned remaining")
    }

    /// Remove specific items by ID from disk and array.
    func clearItems(ids: Set<UUID>) {
        let toRemove = items.filter { ids.contains($0.id) }
        for item in toRemove {
            try? FileManager.default.removeItem(at: item.tempURL)
        }
        items.removeAll { ids.contains($0.id) }
        saveManifest()
        Log(.system).info("Cleared \(toRemove.count) screenshots by ID, \(items.count) remaining")
    }

    private static var manifestURL: URL {
        screenshotTrayDir.appendingPathComponent("manifest.json")
    }

    private init() {
        Self.migrateFromBufferIfNeeded()
        restoreFromDisk()
    }

    // MARK: - Add

    /// Add a captured screenshot to the buffer.
    func add(data: Data, width: Int, height: Int, mode: CaptureMode,
             windowTitle: String? = nil, appName: String? = nil, displayName: String? = nil) async {
        _ = await addReturningItem(
            data: data,
            width: width,
            height: height,
            mode: mode,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )
    }

    /// Add a captured screenshot to the tray and return the stored item.
    func addReturningItem(data: Data, width: Int, height: Int, mode: CaptureMode,
                          windowTitle: String? = nil, appName: String? = nil, displayName: String? = nil) async -> TrayScreenshot? {
        let itemId = UUID()
        let capturedAt = Date()
        let filename = CaptureFilenameFormatter.screenshotFilename(
            id: itemId,
            capturedAt: capturedAt,
            mode: mode.rawValue,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )
        let fileURL = screenshotTrayDir.appendingPathComponent(filename)

        let writeError = await Task.detached(priority: .userInitiated) { () -> Error? in
            do {
                try data.write(to: fileURL, options: .atomic)
                return nil
            } catch {
                return error
            }
        }.value
        if let writeError {
            Log(.system).error("Failed to write tray screenshot: \(writeError)")
            return nil
        }

        let item = TrayScreenshot(
            id: itemId,
            capturedAt: capturedAt,
            mode: mode,
            width: width,
            height: height,
            filename: filename,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )

        items.append(item)
        saveManifest()
        if captureHotPathLoggingEnabled {
            Log(.system).info("Screenshot added to tray (\(count) total), \(width)x\(height) mode=\(mode.rawValue)")
        }

        // Generate display thumbnail async (not full-res PNG in memory)
        Task {
            let thumb = await Task.detached(priority: .utility) {
                Self.generateThumbnail(for: fileURL)
            }.value
            if let idx = self.items.firstIndex(where: { $0.id == itemId }) {
                self.items[idx].thumbnail = thumb
            }
        }

        // Background OCR: fast scan → accurate upgrade
        runBackgroundOCR(for: itemId)

        return item
    }

    /// Two-pass background OCR: fast scan to detect text, then accurate pass if text found.
    private func runBackgroundOCR(for itemId: UUID) {
        Task {
            guard let idx = items.firstIndex(where: { $0.id == itemId }),
                  items[idx].ocrText == nil else { return }
            let url = items[idx].tempURL

            // Pass 1: fast scan
            let fastText: String? = await Task.detached(priority: .utility) {
                try? await VisionOCRService.shared.recognizeText(atURL: url, quality: .fast)
            }.value

            guard let fastText, !fastText.isEmpty else {
                // No text detected — mark as scanned (empty string = no text)
                if let idx = self.items.firstIndex(where: { $0.id == itemId }) {
                    self.items[idx].ocrText = ""
                    self.saveManifest()
                }
                return
            }

            // Store fast result immediately so it's available if the user acts now
            if let idx = self.items.firstIndex(where: { $0.id == itemId }) {
                self.items[idx].ocrText = fastText
                self.saveManifest()
            }

            // Pass 2: accurate upgrade at background priority
            let accurateText: String? = await Task.detached(priority: .background) {
                try? await VisionOCRService.shared.recognizeText(atURL: url, quality: .accurate)
            }.value

            if let accurateText, !accurateText.isEmpty,
               let idx = self.items.firstIndex(where: { $0.id == itemId }) {
                self.items[idx].ocrText = accurateText
                self.saveManifest()
            }
        }
    }

    /// Scale down an image from disk for display. Thread-safe (no lockFocus).
    nonisolated static func generateThumbnail(for url: URL, maxSize: CGFloat = 400) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    // MARK: - Drain to Recording

    /// Move all buffered screenshots into permanent storage for a recording.
    /// Pre-recording items get timestampMs = 0.
    func drainToRecording(recordingId: UUID, recordingStartTime: Date) -> [RecordingScreenshot] {
        guard !items.isEmpty else { return [] }

        var screenshots: [RecordingScreenshot] = []

        for (index, item) in items.enumerated() {
            // Items captured before recording started get timestamp 0
            let timestampMs: Int
            if item.capturedAt < recordingStartTime {
                timestampMs = 0
            } else {
                timestampMs = Int(item.capturedAt.timeIntervalSince(recordingStartTime) * 1000)
            }

            // Save to permanent storage (read PNG from disk, not memory)
            guard let data = item.loadData(),
                  let savedURL = ScreenshotStorage.save(
                    data,
                    recordingId: recordingId,
                    timestampMs: timestampMs,
                    index: index,
                    capturedAt: item.capturedAt,
                    captureMode: item.mode.rawValue,
                    width: item.width,
                    height: item.height,
                    windowTitle: item.windowTitle,
                    appName: item.appName,
                    displayName: item.displayName
                  ) else {
                continue
            }

            screenshots.append(RecordingScreenshot(
                filename: savedURL.lastPathComponent,
                timestampMs: timestampMs,
                captureMode: item.mode.rawValue,
                width: item.width,
                height: item.height,
                windowTitle: item.windowTitle,
                appName: item.appName,
                displayName: item.displayName
            ))
        }

        let drained = items.count
        cleanBufferFiles()
        items.removeAll()
        saveManifest()
        Log(.system).info("Drained \(drained) tray screenshots to recording \(recordingId.uuidString.prefix(8))")

        return screenshots
    }

    // MARK: - Drain to Capture

    /// Create a new Capture TalkieObject from all buffered screenshots.
    /// Canonical text stays empty — OCR is opt-in, attached as provenance segments.
    func drainToCapture() async -> TalkieObject? {
        guard !items.isEmpty else { return nil }

        let captureId = UUID()
        var screenshots: [RecordingScreenshot] = []

        let baseTime = items.first!.capturedAt
        for (index, item) in items.enumerated() {
            let timestampMs = index == 0 ? 0 : Int(item.capturedAt.timeIntervalSince(baseTime) * 1000)

            guard let data = item.loadData(),
                  let savedURL = ScreenshotStorage.save(
                    data,
                    recordingId: captureId,
                    timestampMs: timestampMs,
                    index: index,
                    capturedAt: item.capturedAt,
                    captureMode: item.mode.rawValue,
                    width: item.width,
                    height: item.height,
                    windowTitle: item.windowTitle,
                    appName: item.appName,
                    displayName: item.displayName
                  ) else {
                continue
            }

            screenshots.append(RecordingScreenshot(
                filename: savedURL.lastPathComponent,
                timestampMs: timestampMs,
                captureMode: item.mode.rawValue,
                width: item.width,
                height: item.height,
                windowTitle: item.windowTitle,
                appName: item.appName,
                displayName: item.displayName
            ))
        }

        guard !screenshots.isEmpty else { return nil }

        var capture = TalkieObject.newCapture(id: captureId)
        var assets = capture.assets ?? TalkieObjectAssets()
        assets.screenshots = screenshots
        capture.assetsJSON = assets.toJSON()

        do {
            let repository = TalkieObjectRepository()
            try await repository.saveRecording(capture)
            await RecordingsViewModel.shared.loadRecordings()

            let drained = items.count
            cleanBufferFiles()
            items.removeAll()
            saveManifest()
            NotificationCenter.default.post(name: .init("NotesDidChange"), object: nil)
            Log(.system).info("Created capture from \(drained) tray screenshots: \(captureId.uuidString.prefix(8))")

            return capture
        } catch {
            Log(.system).error("Failed to save capture: \(error)")
            return nil
        }
    }

    // MARK: - Remove / Clear

    /// Remove a single item from the buffer.
    func remove(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        try? FileManager.default.removeItem(at: item.tempURL)
        saveManifest()
        Log(.system).info("Removed tray screenshot, \(count) remaining")
    }

    /// Discard all buffered screenshots.
    func clear() {
        cleanBufferFiles()
        items.removeAll()
        saveManifest()
        Log(.system).info("Screenshot tray cleared")
    }

    // MARK: - Persistence

    private func saveManifest() {
        let snapshot = items
        let manifestURL = Self.manifestURL
        manifestSaveGeneration &+= 1
        let generation = manifestSaveGeneration

        manifestSaveTask?.cancel()
        manifestSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled else { return }

            let writeError = await Task.detached(priority: .utility) { () -> Error? in
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(snapshot)
                    try data.write(to: manifestURL, options: .atomic)
                    return nil
                } catch {
                    return error
                }
            }.value

            if let writeError {
                Log(.system).error("Failed to save screenshot manifest: \(writeError)")
            }

            if generation == self.manifestSaveGeneration {
                self.manifestSaveTask = nil
            }
        }
    }

    private func restoreFromDisk() {
        let url = Self.manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([TrayScreenshot].self, from: data)

            // Verify files still exist on disk, skip orphans
            let valid = decoded.filter { item in
                let exists = FileManager.default.fileExists(atPath: item.tempURL.path)
                if !exists {
                    Log(.system).debug("Skipping orphaned tray screenshot manifest entry: \(item.filename)")
                }
                return exists
            }

            items = valid

            if !items.isEmpty {
                Log(.system).info("Restored \(items.count) tray screenshot(s) from disk")

                // Regenerate thumbnails async + backfill OCR for items not yet scanned
                for item in items {
                    Task {
                        let thumb = await Task.detached(priority: .utility) {
                            Self.generateThumbnail(for: item.tempURL)
                        }.value
                        if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                            self.items[idx].thumbnail = thumb
                        }
                    }
                    if item.ocrText == nil {
                        runBackgroundOCR(for: item.id)
                    }
                }
            }

            // Clean up manifest if we dropped orphans
            if valid.count < decoded.count {
                saveManifest()
            }
        } catch {
            Log(.system).error("Failed to restore screenshot manifest: \(error)")
        }
    }

    // MARK: - Private

    private func cleanBufferFiles() {
        for item in items {
            try? FileManager.default.removeItem(at: item.tempURL)
        }
    }
}
