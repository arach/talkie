//
//  ClipTray.swift
//  Talkie
//
//  Staging area for video clips captured via the face camera bubble.
//  Accumulates clips until the user decides: attach to recording, save as Note, or discard.
//  Persists metadata to ~/Library/Application Support/Talkie/Tray/clips/manifest.json
//  so tray captures survive app restarts. Mirrors ScreenshotTray.swift.
//

import AppKit
import AVFoundation
import TalkieKit

// MARK: - Tray Directory

private let clipTrayDir: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Talkie/Tray/clips", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

// MARK: - Tray Clip

struct TrayClip: Identifiable, Codable {
    let id: UUID
    let capturedAt: Date
    let durationMs: Int
    let filename: String
    let width: Int
    let height: Int
    let captureMode: String       // "camera", "region", "fullscreen", "window"
    let windowTitle: String?
    let appName: String?
    let displayName: String?
    /// Whether this item is pinned to the tray (won't drain into the next recording)
    var pinned: Bool
    /// First-frame thumbnail, generated eagerly on buffer add
    var thumbnail: NSImage?

    var tempURL: URL {
        clipTrayDir.appendingPathComponent(filename)
    }

    // Codable — exclude thumbnail (regenerated on restore)
    enum CodingKeys: String, CodingKey {
        case id, capturedAt, durationMs, filename, width, height, captureMode, windowTitle, appName, displayName, pinned
    }

    init(id: UUID, capturedAt: Date, durationMs: Int, filename: String,
         width: Int, height: Int, captureMode: String = "camera",
         windowTitle: String? = nil, appName: String? = nil,
         displayName: String? = nil, pinned: Bool = false, thumbnail: NSImage? = nil) {
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
        self.pinned = pinned
        self.thumbnail = thumbnail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        filename = try c.decode(String.self, forKey: .filename)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        captureMode = try c.decode(String.self, forKey: .captureMode)
        windowTitle = try c.decodeIfPresent(String.self, forKey: .windowTitle)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        thumbnail = nil
    }
}

// MARK: - Clip Tray

@MainActor
@Observable
final class ClipTray {
    static let shared = ClipTray()

    private(set) var items: [TrayClip] = []

    /// One-time migration from old Buffer/ path to Tray/
    private static func migrateFromBufferIfNeeded() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldDir = appSupport.appendingPathComponent("Talkie/Buffer/clips", isDirectory: true)
        let newDir = appSupport.appendingPathComponent("Talkie/Tray/clips", isDirectory: true)
        guard fm.fileExists(atPath: oldDir.path), !fm.fileExists(atPath: newDir.path) else { return }
        do {
            try fm.createDirectory(at: newDir.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: oldDir, to: newDir)
            Log(.system).info("Migrated clip tray from Buffer/ to Tray/")
        } catch {
            Log(.system).error("Clip tray migration failed: \(error)")
        }
    }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }
    var isNotEmpty: Bool { !items.isEmpty }

    // MARK: - Pin State

    /// Items that will drain into the next recording (everything not pinned)
    var unpinnedItems: [TrayClip] { items.filter { !$0.pinned } }
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
        Log(.system).info("Cleared \(unpinned.count) unpinned clips, \(items.count) pinned remaining")
    }

    private static var manifestURL: URL {
        clipTrayDir.appendingPathComponent("manifest.json")
    }

    private init() {
        Self.migrateFromBufferIfNeeded()
        restoreFromDisk()
    }

    // MARK: - Add

    /// Add a captured clip to the buffer. Moves the file from the provided URL to the persistent buffer directory.
    func add(
        tempURL: URL,
        durationMs: Int,
        width: Int,
        height: Int,
        captureMode: String = "camera",
        windowTitle: String? = nil,
        appName: String? = nil,
        displayName: String? = nil
    ) {
        let itemId = UUID()
        let capturedAt = Date()
        var filename = CaptureFilenameFormatter.clipFilename(
            id: itemId,
            capturedAt: capturedAt,
            mode: captureMode,
            width: width,
            height: height,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )
        var destURL = clipTrayDir.appendingPathComponent(filename)

        // Move file to persistent buffer directory (instant rename on same volume)
        do {
            if tempURL.deletingLastPathComponent().path == clipTrayDir.path {
                filename = tempURL.lastPathComponent
                destURL = tempURL
            } else {
                try FileManager.default.moveItem(at: tempURL, to: destURL)
            }
        } catch {
            Log(.system).error("Failed to move clip to tray: \(error)")
            return
        }

        let item = TrayClip(
            id: itemId,
            capturedAt: capturedAt,
            durationMs: durationMs,
            filename: filename,
            width: width,
            height: height,
            captureMode: captureMode,
            windowTitle: windowTitle,
            appName: appName,
            displayName: displayName
        )

        items.append(item)
        saveManifest()
        Log(.system).info("Clip added to tray (\(count) total), \(durationMs)ms \(width)x\(height)")

        // Generate thumbnail async
        Task {
            let thumb = await Self.generateThumbnail(for: destURL)
            if let idx = self.items.firstIndex(where: { $0.id == itemId }) {
                self.items[idx].thumbnail = thumb
            }
        }
    }

    /// Generate a first-frame thumbnail from a video URL.
    static func generateThumbnail(for url: URL, maxSize: CGFloat = 160) async -> NSImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxSize, height: maxSize)

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            Log(.system).debug("Failed to generate clip thumbnail: \(error)")
            return nil
        }
    }

    // MARK: - Drain to Recording

    /// Move all buffered clips into permanent storage for a recording.
    /// Pre-recording items get timestampMs = 0.
    func drainToRecording(recordingId: UUID, recordingStartTime: Date) -> [RecordingClip] {
        guard !items.isEmpty else { return [] }

        var clips: [RecordingClip] = []

        for (index, item) in items.enumerated() {
            // Items captured before recording started get timestamp 0
            let timestampMs: Int
            if item.capturedAt < recordingStartTime {
                timestampMs = 0
            } else {
                timestampMs = Int(item.capturedAt.timeIntervalSince(recordingStartTime) * 1000)
            }

            // Save to permanent storage
            guard let savedURL = VideoClipStorage.save(
                item.tempURL,
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
        }

        let drained = items.count
        cleanBufferFiles()
        items.removeAll()
        saveManifest()
        Log(.system).info("Drained \(drained) tray clips to recording \(recordingId.uuidString.prefix(8))")

        return clips
    }

    // MARK: - Drain to Note

    /// Create a new Note recording from all buffered clips.
    func drainToNote() async -> TalkieObject? {
        guard !items.isEmpty else { return nil }

        let noteId = UUID()
        var clips: [RecordingClip] = []

        let baseTime = items.first!.capturedAt
        for (index, item) in items.enumerated() {
            let timestampMs = index == 0 ? 0 : Int(item.capturedAt.timeIntervalSince(baseTime) * 1000)

            guard let savedURL = VideoClipStorage.save(
                item.tempURL,
                recordingId: noteId,
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
        }

        guard !clips.isEmpty else { return nil }

        var note = TalkieObject.newNote(
            id: noteId,
            text: "\(clips.count) clip\(clips.count == 1 ? "" : "s")"
        )
        var assets = note.assets ?? TalkieObjectAssets()
        assets.clips = clips
        note.assetsJSON = assets.toJSON()

        do {
            let repository = TalkieObjectRepository()
            try await repository.saveRecording(note)
            await RecordingsViewModel.shared.loadRecordings()

            let drained = items.count
            cleanBufferFiles()
            items.removeAll()
            saveManifest()
            NotificationCenter.default.post(name: .init("NotesDidChange"), object: nil)
            Log(.system).info("Created note from \(drained) tray clips: \(noteId.uuidString.prefix(8))")

            return note
        } catch {
            Log(.system).error("Failed to save clip note: \(error)")
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
        Log(.system).info("Removed tray clip, \(count) remaining")
    }

    /// Discard all buffered clips.
    func clear() {
        cleanBufferFiles()
        items.removeAll()
        saveManifest()
        Log(.system).info("Clip tray cleared")
    }

    /// Remove specific items by ID from disk and array.
    func clearItems(ids: Set<UUID>) {
        let toRemove = items.filter { ids.contains($0.id) }
        for item in toRemove {
            try? FileManager.default.removeItem(at: item.tempURL)
        }
        items.removeAll { ids.contains($0.id) }
        saveManifest()
        Log(.system).info("Cleared \(toRemove.count) clips by ID, \(items.count) remaining")
    }

    // MARK: - Persistence

    private func saveManifest() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(items)
            try data.write(to: Self.manifestURL, options: .atomic)
        } catch {
            Log(.system).error("Failed to save clip manifest: \(error)")
        }
    }

    private func restoreFromDisk() {
        let url = Self.manifestURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([TrayClip].self, from: data)

            // Verify files still exist on disk, skip orphans
            let valid = decoded.filter { item in
                let exists = FileManager.default.fileExists(atPath: item.tempURL.path)
                if !exists {
                    Log(.system).debug("Skipping orphaned tray clip manifest entry: \(item.filename)")
                }
                return exists
            }

            items = valid

            if !items.isEmpty {
                Log(.system).info("Restored \(items.count) tray clip(s) from disk")

                // Regenerate thumbnails async
                for item in items {
                    Task {
                        let thumb = await Self.generateThumbnail(for: item.tempURL)
                        if let idx = self.items.firstIndex(where: { $0.id == item.id }) {
                            self.items[idx].thumbnail = thumb
                        }
                    }
                }
            }

            // Clean up manifest if we dropped orphans
            if valid.count < decoded.count {
                saveManifest()
            }
        } catch {
            Log(.system).error("Failed to restore clip manifest: \(error)")
        }
    }

    // MARK: - Private

    private func cleanBufferFiles() {
        for item in items {
            try? FileManager.default.removeItem(at: item.tempURL)
        }
    }
}
