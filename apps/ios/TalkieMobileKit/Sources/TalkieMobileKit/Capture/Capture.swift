//
//  Capture.swift
//  TalkieMobileKit
//
//  Model and store for captured/shared content.
//  Stored in App Group as JSON, following KeyboardDictationStore pattern.
//

import Foundation

/// A single captured item from the share sheet or other import sources.
public struct Capture: Codable, Identifiable, Hashable {
    public let id: UUID
    public let sourceType: String          // "url", "text", "photo"
    public let text: String                // OCR'd or extracted text
    public let title: String?
    public let sourceURL: String?
    public let bookmark: CaptureBookmark?
    public let imageFilename: String?      // Local filename in capture-images/
    public let deferredPageFilenames: [String]?  // Lossless PNG filenames of unprocessed pages
    public let totalPageCount: Int?              // Total pages from scanner (including page 1)
    public let timestamp: Date
    public let wordCount: Int
    public var syncedToMac: Bool

    public init(
        id: UUID = UUID(),
        sourceType: String,
        text: String,
        title: String? = nil,
        sourceURL: String? = nil,
        bookmark: CaptureBookmark? = nil,
        imageFilename: String? = nil,
        deferredPageFilenames: [String]? = nil,
        totalPageCount: Int? = nil,
        timestamp: Date = Date(),
        syncedToMac: Bool = false
    ) {
        self.id = id
        self.sourceType = sourceType
        self.text = text
        self.title = title
        self.sourceURL = sourceURL
        self.bookmark = bookmark
        self.imageFilename = imageFilename
        self.deferredPageFilenames = deferredPageFilenames
        self.totalPageCount = totalPageCount
        self.timestamp = timestamp
        self.wordCount = text.split(separator: " ").count
        self.syncedToMac = syncedToMac
    }

    /// Return a copy with an updated title
    public func withTitle(_ newTitle: String) -> Capture {
        Capture(
            id: id,
            sourceType: sourceType,
            text: text,
            title: newTitle,
            sourceURL: sourceURL,
            bookmark: bookmark,
            imageFilename: imageFilename,
            deferredPageFilenames: deferredPageFilenames,
            totalPageCount: totalPageCount,
            timestamp: timestamp,
            syncedToMac: syncedToMac
        )
    }

    /// Return a copy with updated text
    public func withUpdatedText(_ newText: String) -> Capture {
        Capture(
            id: id,
            sourceType: sourceType,
            text: newText,
            title: title,
            sourceURL: sourceURL,
            bookmark: bookmark,
            imageFilename: imageFilename,
            deferredPageFilenames: nil,
            totalPageCount: totalPageCount,
            timestamp: timestamp,
            syncedToMac: syncedToMac
        )
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when captures list changes (add, delete, sync status update)
    public static let capturesDidChange = Notification.Name("com.jdi.talkie.capturesDidChange")
}

// MARK: - Capture Store

/// File-based store for captures in App Group
public final class CaptureStore {
    public static let shared = CaptureStore()

    private let log = Log(.sync)
    private let fileManager = FileManager.default
    private let maxEntries = 200

    private var cache: [Capture]?

    private init() {}

    // MARK: - File Storage

    private var storageURL: URL? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: kTalkieAppGroup) else {
            log.error("Cannot access App Group container")
            return nil
        }
        return containerURL.appendingPathComponent("captures.json")
    }

    /// Directory for captured photo images
    public var imageDirectoryURL: URL? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: kTalkieAppGroup) else {
            return nil
        }
        let dir = containerURL.appendingPathComponent("capture-images")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Public API

    /// Get all captures (most recent first)
    public func all() -> [Capture] {
        if let cache = cache {
            return cache
        }

        guard let url = storageURL else { return [] }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let captures = try decoder.decode([Capture].self, from: data)
            cache = captures.sorted { $0.timestamp > $1.timestamp }
            return cache ?? []
        } catch {
            log.debug("No existing captures file: \(error.localizedDescription)")
            cache = []
            return []
        }
    }

    /// Add a new capture
    public func add(_ capture: Capture) {
        var captures = all()
        captures.insert(capture, at: 0)

        if captures.count > maxEntries {
            // Remove oldest, clean up image files
            let removed = captures.suffix(from: maxEntries)
            for old in removed {
                deleteImageFile(for: old)
            }
            captures = Array(captures.prefix(maxEntries))
        }

        save(captures)
        log.info("Added capture: \(capture.sourceType), \(capture.wordCount) words")
        NotificationCenter.default.post(name: .capturesDidChange, object: nil)
    }

    /// Delete a capture by ID
    public func delete(_ id: UUID) {
        var captures = all()
        guard let capture = captures.first(where: { $0.id == id }) else { return }
        delete(capture, from: &captures)
    }

    /// Delete a capture and its stored image/audio artifacts.
    public func delete(_ capture: Capture) {
        var captures = all()
        delete(capture, from: &captures)
    }

    /// Mark a capture as synced to Mac
    public func markSynced(_ id: UUID) {
        var captures = all()
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[index].syncedToMac = true
        save(captures)
        log.info("Marked capture synced: \(id)")
        NotificationCenter.default.post(name: .capturesDidChange, object: nil)
    }

    /// Update a capture's title (e.g. after auto-titling with Apple Intelligence)
    public func updateTitle(_ title: String, for id: UUID) {
        var captures = all()
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        captures[index] = captures[index].withTitle(title)
        save(captures)
        log.info("Updated capture title: \(title)")
        NotificationCenter.default.post(name: .capturesDidChange, object: nil)
    }

    /// Get all unsynced captures
    public func unsyncedCaptures() -> [Capture] {
        all().filter { !$0.syncedToMac }
    }

    /// Clear all captures
    public func clear() {
        for capture in all() {
            deleteImageFile(for: capture)
        }
        save([])
        log.info("Cleared all captures")
    }

    public var count: Int { all().count }
    public var isEmpty: Bool { all().isEmpty }

    /// Force reload from disk
    public func reload() {
        cache = nil
        _ = all()
    }

    // MARK: - Image Files

    /// Save image data for a capture, returns the filename
    public func saveImage(_ data: Data, id: UUID) -> String? {
        guard let dir = imageDirectoryURL else { return nil }
        let filename = "\(id.uuidString).jpg"
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: .atomic)
            return filename
        } catch {
            log.error("Failed to save capture image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Load image data for a capture
    public func loadImageData(filename: String) -> Data? {
        guard let dir = imageDirectoryURL else { return nil }
        let fileURL = dir.appendingPathComponent(filename)
        return try? Data(contentsOf: fileURL)
    }

    // MARK: - Audio Files

    /// Directory for cached TTS audio
    public var audioDirectoryURL: URL? {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: kTalkieAppGroup) else {
            return nil
        }
        let dir = containerURL.appendingPathComponent("capture-audio")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Save TTS audio data for a capture
    public func saveAudio(_ data: Data, id: UUID) -> URL? {
        guard let dir = audioDirectoryURL else { return nil }
        let ext = data.prefix(4).starts(with: [0x52, 0x49, 0x46, 0x46]) ? "wav" : "mp3"
        let fileURL = dir.appendingPathComponent("\(id.uuidString).\(ext)")
        do {
            for old in ["mp3", "wav"] where old != ext {
                let stale = dir.appendingPathComponent("\(id.uuidString).\(old)")
                try? fileManager.removeItem(at: stale)
            }
            try data.write(to: fileURL, options: .atomic)
            log.info("Saved TTS audio: \(fileURL.lastPathComponent) (\(data.count) bytes)")
            return fileURL
        } catch {
            log.error("Failed to save TTS audio: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get URL for cached TTS audio (nil if not yet generated)
    public func audioURL(for id: UUID) -> URL? {
        guard let dir = audioDirectoryURL else { return nil }
        for ext in ["wav", "mp3"] {
            let fileURL = dir.appendingPathComponent("\(id.uuidString).\(ext)")
            if fileManager.fileExists(atPath: fileURL.path) { return fileURL }
        }
        return nil
    }

    // MARK: - Private

    private func save(_ captures: [Capture]) {
        guard let url = storageURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(captures)
            try data.write(to: url, options: .atomic)
            cache = captures
        } catch {
            log.error("Failed to save captures: \(error.localizedDescription)")
        }
    }

    /// Save a deferred page image (lossless PNG), returns filename
    public func saveDeferredPage(_ data: Data, captureId: UUID, pageIndex: Int) -> String? {
        guard let dir = imageDirectoryURL else { return nil }
        let filename = "\(captureId.uuidString)-page\(pageIndex).png"
        let fileURL = dir.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL, options: .atomic)
            return filename
        } catch {
            log.error("Failed to save deferred page: \(error.localizedDescription)")
            return nil
        }
    }

    /// Update capture text and clear deferred pages after on-device OCR
    public func updateTextAndClearDeferred(_ id: UUID, newText: String) {
        var captures = all()
        guard let index = captures.firstIndex(where: { $0.id == id }) else { return }
        let old = captures[index]
        if let dir = imageDirectoryURL {
            for filename in old.deferredPageFilenames ?? [] {
                try? fileManager.removeItem(at: dir.appendingPathComponent(filename))
            }
        }
        captures[index] = old.withUpdatedText(newText)
        save(captures)
        log.info("Updated capture text and cleared deferred pages: \(id)")
        NotificationCenter.default.post(name: .capturesDidChange, object: nil)
    }

    private func delete(_ capture: Capture, from captures: inout [Capture]) {
        deleteImageFile(for: capture)
        deleteAudioFile(for: capture)
        captures.removeAll { $0.id == capture.id }
        save(captures)
        log.info("Deleted capture: \(capture.id)")
        NotificationCenter.default.post(name: .capturesDidChange, object: nil)
    }

    private func deleteImageFile(for capture: Capture) {
        guard let dir = imageDirectoryURL else { return }
        if let filename = capture.imageFilename {
            try? fileManager.removeItem(at: dir.appendingPathComponent(filename))
        }
        for filename in capture.deferredPageFilenames ?? [] {
            try? fileManager.removeItem(at: dir.appendingPathComponent(filename))
        }
    }

    private func deleteAudioFile(for capture: Capture) {
        guard let dir = audioDirectoryURL else { return }
        for ext in ["wav", "mp3"] {
            try? fileManager.removeItem(at: dir.appendingPathComponent("\(capture.id.uuidString).\(ext)"))
        }
    }
}
