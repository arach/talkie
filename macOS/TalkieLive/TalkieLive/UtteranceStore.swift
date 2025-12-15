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
    // Start context: where was the user when recording STARTED?
    var activeAppBundleID: String?
    var activeAppName: String?
    var activeWindowTitle: String?

    // End context: where was the user when recording STOPPED?
    var endAppBundleID: String?
    var endAppName: String?
    var endWindowTitle: String?

    // Rich context: deeper insight into what user was doing
    var documentURL: String?           // File path or web URL
    var focusedElementRole: String?    // AXTextArea, AXWebArea, etc.
    var focusedElementValue: String?   // Code snippet, terminal excerpt, form content (truncated)
    var browserURL: String?            // Full URL for browsers (extracted from AX)
    var terminalWorkingDir: String?    // For terminal apps, the cwd if detectable

    // Routing: what happened after transcription?
    var routingMode: String?  // "paste", "clipboardOnly"
    var wasRouted: Bool = false

    // Transcription details
    var whisperModel: String?
    var language: String?
    var confidence: Double?

    // Performance metrics (perf prefix)
    var perfEngineMs: Int?        // Time in TalkieEngine
    var perfEndToEndMs: Int?      // Stop recording → delivery
    var perfInAppMs: Int?         // TalkieLive processing (endToEnd - engine)
    var perfPreMs: Int?           // Debug: pre-engine time
    var perfPostMs: Int?          // Debug: post-engine time

    // Audio details
    var peakAmplitude: Float?
    var averageAmplitude: Float?
    var audioFilename: String?

    // User edits
    var wasEdited: Bool = false
    var originalText: String?

    init() {}

    /// Initialize with specific fields (used when converting from LiveUtterance)
    init(
        activeAppBundleID: String? = nil,
        activeAppName: String? = nil,
        activeWindowTitle: String? = nil,
        whisperModel: String? = nil,
        perfEngineMs: Int? = nil,
        perfEndToEndMs: Int? = nil,
        perfInAppMs: Int? = nil,
        perfPreMs: Int? = nil,
        perfPostMs: Int? = nil,
        audioFilename: String? = nil
    ) {
        self.activeAppBundleID = activeAppBundleID
        self.activeAppName = activeAppName
        self.activeWindowTitle = activeWindowTitle
        self.whisperModel = whisperModel
        self.perfEngineMs = perfEngineMs
        self.perfEndToEndMs = perfEndToEndMs
        self.perfInAppMs = perfInAppMs
        self.perfPreMs = perfPreMs
        self.perfPostMs = perfPostMs
        self.audioFilename = audioFilename
    }

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

    /// Whether start and end contexts are different apps
    var contextChanged: Bool {
        guard let startApp = activeAppBundleID, let endApp = endAppBundleID else {
            return false
        }
        return startApp != endApp
    }

    /// Primary app name based on settings (defaults to start app)
    func primaryAppName(preferEnd: Bool = false) -> String? {
        if preferEnd {
            return endAppName ?? activeAppName
        }
        return activeAppName ?? endAppName
    }

    /// Primary bundle ID based on settings (defaults to start app)
    func primaryBundleID(preferEnd: Bool = false) -> String? {
        if preferEnd {
            return endAppBundleID ?? activeAppBundleID
        }
        return activeAppBundleID ?? endAppBundleID
    }

    /// Merge missing values from another metadata instance without overwriting existing fields
    func mergingMissing(from other: UtteranceMetadata) -> UtteranceMetadata {
        var merged = self
        if merged.activeAppBundleID == nil { merged.activeAppBundleID = other.activeAppBundleID }
        if merged.activeAppName == nil { merged.activeAppName = other.activeAppName }
        if merged.activeWindowTitle == nil { merged.activeWindowTitle = other.activeWindowTitle }

        if merged.endAppBundleID == nil { merged.endAppBundleID = other.endAppBundleID }
        if merged.endAppName == nil { merged.endAppName = other.endAppName }
        if merged.endWindowTitle == nil { merged.endWindowTitle = other.endWindowTitle }

        if merged.documentURL == nil { merged.documentURL = other.documentURL }
        if merged.focusedElementRole == nil { merged.focusedElementRole = other.focusedElementRole }
        if merged.focusedElementValue == nil { merged.focusedElementValue = other.focusedElementValue }
        if merged.browserURL == nil { merged.browserURL = other.browserURL }
        if merged.terminalWorkingDir == nil { merged.terminalWorkingDir = other.terminalWorkingDir }

        if merged.routingMode == nil { merged.routingMode = other.routingMode }
        if merged.whisperModel == nil { merged.whisperModel = other.whisperModel }
        if merged.perfEngineMs == nil { merged.perfEngineMs = other.perfEngineMs }
        if merged.perfEndToEndMs == nil { merged.perfEndToEndMs = other.perfEndToEndMs }
        if merged.perfInAppMs == nil { merged.perfInAppMs = other.perfInAppMs }
        if merged.perfPreMs == nil { merged.perfPreMs = other.perfPreMs }
        if merged.perfPostMs == nil { merged.perfPostMs = other.perfPostMs }
        if merged.language == nil { merged.language = other.language }
        if merged.confidence == nil { merged.confidence = other.confidence }

        if merged.peakAmplitude == nil { merged.peakAmplitude = other.peakAmplitude }
        if merged.averageAmplitude == nil { merged.averageAmplitude = other.averageAmplitude }
        if merged.audioFilename == nil { merged.audioFilename = other.audioFilename }

        if merged.originalText == nil { merged.originalText = other.originalText }
        merged.wasEdited = merged.wasEdited || other.wasEdited
        merged.wasRouted = merged.wasRouted || other.wasRouted

        return merged
    }
}

// MARK: - Utterance

struct Utterance: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    let timestamp: Date
    let durationSeconds: Double?
    var metadata: UtteranceMetadata

    /// Database ID (from LiveUtterance) - used for linking to database records
    var liveID: Int64?

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
        self.liveID = nil
    }

    /// Initialize from database record
    init(text: String, durationSeconds: Double?, metadata: UtteranceMetadata, timestamp: Date, liveID: Int64?) {
        self.id = UUID()
        self.text = text
        self.timestamp = timestamp
        self.durationSeconds = durationSeconds
        self.metadata = metadata
        self.liveID = liveID
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

    /// Capture start context (frontmost app when recording begins)
    /// Now uses ContextCaptureService for baseline capture
    @MainActor static func captureCurrentContext() -> UtteranceMetadata {
        ContextCaptureService.shared.captureBaseline()
    }

    /// Fill in end context on existing metadata (when recording stops)
    static func fillEndContext(in metadata: inout UtteranceMetadata) {
        // Get frontmost app info
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            metadata.endAppBundleID = frontApp.bundleIdentifier
            metadata.endAppName = frontApp.localizedName
        }

        // Try to get active window title
        if let windowTitle = getActiveWindowTitle() {
            metadata.endWindowTitle = windowTitle
        }
    }

    /// Get the current frontmost app for later activation
    static func getFrontmostApp() -> NSRunningApplication? {
        return NSWorkspace.shared.frontmostApplication
    }

    /// Activate an app by bringing it to front
    static func activateApp(_ app: NSRunningApplication) {
        app.activate()
    }

    /// Activate an app by bundle ID
    static func activateApp(bundleID: String) {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) else {
            return
        }
        app.activate()
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

    /// Published utterances - now backed by SQLite database
    @Published private(set) var utterances: [Utterance] = []

    /// TTL in hours - default 48 hours
    var ttlHours: Int = 48

    private init() {
        // Load from database on init
        refresh()
    }

    // MARK: - Public API

    /// Add a new utterance (stores to SQLite database)
    func add(_ text: String, durationSeconds: Double? = nil, metadata: UtteranceMetadata = UtteranceMetadata()) {
        // Build rich context metadata dictionary
        var metadataDict: [String: String] = [:]
        if let url = metadata.documentURL { metadataDict["documentURL"] = url }
        if let url = metadata.browserURL { metadataDict["browserURL"] = url }
        if let role = metadata.focusedElementRole { metadataDict["focusedElementRole"] = role }
        if let value = metadata.focusedElementValue { metadataDict["focusedElementValue"] = value }
        if let dir = metadata.terminalWorkingDir { metadataDict["terminalWorkingDir"] = dir }
        if let total = metadata.perfEndToEndMs { metadataDict["perfEndToEndMs"] = String(total) }
        if let inApp = metadata.perfInAppMs { metadataDict["perfInAppMs"] = String(inApp) }
        if let pre = metadata.perfPreMs { metadataDict["perfPreMs"] = String(pre) }
        if let post = metadata.perfPostMs { metadataDict["perfPostMs"] = String(post) }

        // Convert to LiveUtterance for database storage
        let liveUtterance = LiveUtterance(
            text: text,
            mode: metadata.routingMode ?? "typing",
            appBundleID: metadata.activeAppBundleID,
            appName: metadata.activeAppName,
            windowTitle: metadata.activeWindowTitle,
            durationSeconds: durationSeconds,
            wordCount: text.split(separator: " ").count,
            whisperModel: metadata.whisperModel,
            perfEngineMs: metadata.perfEngineMs,
            perfEndToEndMs: metadata.perfEndToEndMs,
            perfInAppMs: metadata.perfInAppMs,
            metadata: metadataDict.isEmpty ? nil : metadataDict,
            audioFilename: metadata.audioFilename,
            transcriptionStatus: .success
        )

        LiveDatabase.store(liveUtterance)
        logger.info("Added utterance: \(text.prefix(50))... from \(metadata.activeAppName ?? "unknown")")

        // Refresh to get the new utterance with its ID
        refresh()
    }

    /// Add a LiveUtterance directly (for new recordings)
    func addLive(_ liveUtterance: LiveUtterance) {
        LiveDatabase.store(liveUtterance)
        logger.info("Added live utterance: \(liveUtterance.text.prefix(50))...")
        refresh()
    }

    /// Update an existing utterance
    func update(_ utterance: Utterance) {
        // For now, just refresh - updates go through LiveDatabase directly
        refresh()
    }

    /// Delete an utterance
    func delete(_ utterance: Utterance) {
        // Use liveID if available, otherwise match by timestamp
        if let liveID = utterance.liveID,
           let live = LiveDatabase.fetch(id: liveID) {
            LiveDatabase.delete(live)
            logger.info("Deleted utterance by ID: \(utterance.text.prefix(30))...")
        } else {
            // Fallback: match by timestamp
            let liveUtterances = LiveDatabase.all()
            if let live = liveUtterances.first(where: { $0.createdAt == utterance.timestamp }) {
                LiveDatabase.delete(live)
                logger.info("Deleted utterance by timestamp: \(utterance.text.prefix(30))...")
            }
        }
        refresh()
    }

    /// Clear all utterances
    func clear() {
        LiveDatabase.deleteAll()
        logger.info("Cleared all utterances")
        refresh()
    }

    /// Prune expired utterances
    func pruneExpired() {
        LiveDatabase.prune(olderThanHours: ttlHours)
        refresh()
    }

    /// Refresh from database
    func refresh() {
        let liveUtterances = LiveDatabase.all()
        utterances = liveUtterances.map { live in
            Utterance(
                text: live.text,
                durationSeconds: live.durationSeconds,
                metadata: buildMetadata(from: live),
                timestamp: live.createdAt,
                liveID: live.id
            )
        }
        logger.debug("Refreshed \(self.utterances.count) utterances from database")
    }

    /// Build UtteranceMetadata from LiveUtterance, including rich context from metadata dict
    private func buildMetadata(from live: LiveUtterance) -> UtteranceMetadata {
        var metadata = UtteranceMetadata(
            activeAppBundleID: live.appBundleID,
            activeAppName: live.appName,
            activeWindowTitle: live.windowTitle,
            whisperModel: live.whisperModel,
            perfEngineMs: live.perfEngineMs,
            perfEndToEndMs: live.perfEndToEndMs,
            perfInAppMs: live.perfInAppMs,
            perfPreMs: nil,
            perfPostMs: nil,
            audioFilename: live.audioFilename
        )

        // Extract rich context from metadata dictionary
        if let dict = live.metadata {
            metadata.documentURL = dict["documentURL"]
            metadata.browserURL = dict["browserURL"]
            metadata.focusedElementRole = dict["focusedElementRole"]
            metadata.focusedElementValue = dict["focusedElementValue"]
            metadata.terminalWorkingDir = dict["terminalWorkingDir"]
            // Also check for legacy key names for backwards compatibility
            if metadata.perfEndToEndMs == nil {
                if let totalStr = dict["perfEndToEndMs"], let total = Int(totalStr) {
                    metadata.perfEndToEndMs = total
                } else if let totalStr = dict["latencyTotalMs"], let total = Int(totalStr) {
                    metadata.perfEndToEndMs = total
                }
            }
            if metadata.perfInAppMs == nil {
                if let inAppStr = dict["perfInAppMs"], let inApp = Int(inAppStr) {
                    metadata.perfInAppMs = inApp
                } else if let pipelineStr = dict["latencyPipelineMs"], let pipeline = Int(pipelineStr) {
                    metadata.perfInAppMs = pipeline
                }
            }
            if metadata.perfPreMs == nil {
                if let preStr = dict["perfPreMs"], let pre = Int(preStr) {
                    metadata.perfPreMs = pre
                } else if let preStr = dict["latencyPreMs"], let pre = Int(preStr) {
                    metadata.perfPreMs = pre
                }
            }
            if metadata.perfPostMs == nil {
                if let postStr = dict["perfPostMs"], let post = Int(postStr) {
                    metadata.perfPostMs = post
                } else if let postStr = dict["latencyPostMs"], let post = Int(postStr) {
                    metadata.perfPostMs = post
                }
            }
        }

        return metadata
    }

    /// Get total count
    var count: Int {
        LiveDatabase.count()
    }

    /// Search utterances
    func search(_ query: String) -> [Utterance] {
        let results = LiveDatabase.search(query)
        return results.map { live in
            Utterance(
                text: live.text,
                durationSeconds: live.durationSeconds,
                metadata: buildMetadata(from: live),
                timestamp: live.createdAt,
                liveID: live.id
            )
        }
    }
}
