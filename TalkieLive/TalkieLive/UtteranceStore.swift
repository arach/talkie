//
//  UtteranceStore.swift
//  TalkieLive
//
//  Local storage for utterances with TTL
//

import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "jdi.talkie.live", category: "UtteranceStore")

// MARK: - Utterance Metadata

struct UtteranceMetadata: Codable, Hashable {
    // Context: where was the user when they recorded?
    var activeAppBundleID: String?
    var activeAppName: String?
    var activeWindowTitle: String?

    // Routing: what happened after transcription?
    var routingMode: String?  // "paste", "clipboardOnly"
    var wasRouted: Bool = false

    // Transcription details
    var whisperModel: String?
    var transcriptionDurationMs: Int?
    var language: String?
    var confidence: Double?

    // Audio details
    var peakAmplitude: Float?
    var averageAmplitude: Float?
    var audioFilename: String?

    // User edits
    var wasEdited: Bool = false
    var originalText: String?

    init() {}

    /// Full URL to the audio file if it exists
    var audioURL: URL? {
        guard let filename = audioFilename else { return nil }
        return AudioStorage.audioDirectory.appendingPathComponent(filename)
    }

    /// Whether the audio file exists on disk
    var hasAudio: Bool {
        guard let url = audioURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

// MARK: - Utterance

struct Utterance: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    let timestamp: Date
    let durationSeconds: Double?
    var metadata: UtteranceMetadata

    // Computed properties
    var wordCount: Int {
        text.split(separator: " ").count
    }

    var characterCount: Int {
        text.count
    }

    init(text: String, durationSeconds: Double? = nil, metadata: UtteranceMetadata = UtteranceMetadata()) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.durationSeconds = durationSeconds
        self.metadata = metadata
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Utterance, rhs: Utterance) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Context Capture

@MainActor
struct ContextCapture {
    /// Our own bundle identifier
    static let talkieLiveBundleID = Bundle.main.bundleIdentifier ?? "live.talkie.TalkieLive"

    /// Check if Talkie Live is the frontmost app
    static func isTalkieLiveFrontmost() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        return frontApp.bundleIdentifier == talkieLiveBundleID
    }

    static func captureCurrentContext() -> UtteranceMetadata {
        var metadata = UtteranceMetadata()

        // Get frontmost app info
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            metadata.activeAppBundleID = frontApp.bundleIdentifier
            metadata.activeAppName = frontApp.localizedName
        }

        // Try to get active window title via Accessibility API
        // (requires accessibility permissions)
        if let windowTitle = getActiveWindowTitle() {
            metadata.activeWindowTitle = windowTitle
        }

        return metadata
    }

    private static func getActiveWindowTitle() -> String? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }

        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedWindow: CFTypeRef?

        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard result == .success, let window = focusedWindow else { return nil }

        var title: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            window as! AXUIElement,
            kAXTitleAttribute as CFString,
            &title
        )

        guard titleResult == .success, let titleString = title as? String else { return nil }
        return titleString
    }
}

@MainActor
final class UtteranceStore: ObservableObject {
    static let shared = UtteranceStore()

    @Published private(set) var utterances: [Utterance] = []

    /// TTL in seconds - default 48 hours
    var ttlSeconds: TimeInterval = 48 * 60 * 60

    private let storageURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("TalkieLive", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storageURL = appDir.appendingPathComponent("utterances.json")

        load()
        pruneExpired()
    }

    func add(_ text: String, durationSeconds: Double? = nil, metadata: UtteranceMetadata = UtteranceMetadata()) {
        let utterance = Utterance(text: text, durationSeconds: durationSeconds, metadata: metadata)
        utterances.insert(utterance, at: 0)
        logger.info("Added utterance: \(text.prefix(50))... from \(metadata.activeAppName ?? "unknown")")
        save()
    }

    func update(_ utterance: Utterance) {
        if let index = utterances.firstIndex(where: { $0.id == utterance.id }) {
            utterances[index] = utterance
            save()
        }
    }

    func clear() {
        utterances.removeAll()
        save()
        logger.info("Cleared all utterances")
    }

    func pruneExpired() {
        let cutoff = Date().addingTimeInterval(-ttlSeconds)
        let before = utterances.count
        utterances.removeAll { $0.timestamp < cutoff }
        let removed = before - utterances.count
        if removed > 0 {
            logger.info("Pruned \(removed) expired utterances")
            save()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(utterances)
            try data.write(to: storageURL)
        } catch {
            logger.error("Failed to save utterances: \(error.localizedDescription)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            utterances = try JSONDecoder().decode([Utterance].self, from: data)
            logger.info("Loaded \(self.utterances.count) utterances")
        } catch {
            logger.error("Failed to load utterances: \(error.localizedDescription)")
        }
    }
}
