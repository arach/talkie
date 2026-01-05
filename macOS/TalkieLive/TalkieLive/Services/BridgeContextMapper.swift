//
//  BridgeContextMapper.swift
//  TalkieLive
//
//  Maintains a mapping of Claude session IDs to terminal app contexts.
//  Written to ~/Library/Application Support/Talkie/.context/session-contexts.json after each dictation.
//

import Foundation
import TalkieKit

private let log = Log(.system)

/// A single dictation record
struct DictationRecord: Codable, Identifiable {
    let id: String               // Unique ID (UUID)
    let text: String             // Preview of the dictation text
    let app: String              // e.g., "Ghostty"
    let bundleId: String         // e.g., "com.mitchellh.ghostty"
    let windowTitle: String      // e.g., "claude ✳ talkie"
    let timestamp: Date          // When this dictation occurred
}

/// Context information for a Claude session (with history)
struct SessionContext: Codable {
    let app: String              // Most recent app (e.g., "iTerm2")
    let bundleId: String         // Most recent bundle ID
    let windowTitle: String      // Most recent window title
    let pid: pid_t?              // Process ID
    let workingDirectory: String? // e.g., "~/dev/talkie"
    let timestamp: Date          // When this context was last updated

    // History tracking
    var apps: [String]           // All apps used for this session
    var dictations: [DictationRecord] // History of dictations

    init(app: String, bundleId: String, windowTitle: String, pid: pid_t?, workingDirectory: String?, timestamp: Date) {
        self.app = app
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.pid = pid
        self.workingDirectory = workingDirectory
        self.timestamp = timestamp
        self.apps = [app]
        self.dictations = []
    }

    /// Create updated context preserving history
    func updated(app: String, bundleId: String, windowTitle: String, pid: pid_t?, workingDirectory: String?, timestamp: Date) -> SessionContext {
        var updatedApps = self.apps
        if !updatedApps.contains(app) {
            updatedApps.append(app)
        }

        var updated = SessionContext(
            app: app,
            bundleId: bundleId,
            windowTitle: windowTitle,
            pid: pid,
            workingDirectory: workingDirectory ?? self.workingDirectory,
            timestamp: timestamp
        )
        updated.apps = updatedApps
        updated.dictations = self.dictations
        return updated
    }

    /// Add a dictation record
    mutating func addDictation(_ record: DictationRecord) {
        dictations.append(record)
        // Keep last 50 dictations per session
        if dictations.count > 50 {
            dictations.removeFirst(dictations.count - 50)
        }
    }
}

/// Maps session IDs to their terminal contexts
struct SessionContextMap: Codable {
    var sessions: [String: SessionContext]
    var lastUpdated: Date

    init() {
        self.sessions = [:]
        self.lastUpdated = Date()
    }
}

/// Service for maintaining session-to-terminal mappings
final class BridgeContextMapper {
    static let shared = BridgeContextMapper()

    private let contextDir: URL
    private let contextFile: URL

    private var contextMap: SessionContextMap

    private init() {
        self.contextDir = BridgePaths.contextDir
        self.contextFile = BridgePaths.sessionContexts
        self.contextMap = SessionContextMap()
        loadFromDisk()
    }

    // MARK: - Public API

    /// Update the context map after a dictation completes
    /// Call this with the captured metadata from ContextCaptureService
    @MainActor
    func updateAfterDictation(metadata: DictationMetadata, dictationText: String? = nil) {
        guard let bundleId = metadata.activeAppBundleID,
              isTerminalApp(bundleId: bundleId) else {
            // Not a terminal app, nothing to map
            return
        }

        // Try to determine which Claude session this is
        guard let sessionId = extractSessionId(from: metadata) else {
            log.debug("Could not extract session ID from context")
            return
        }

        let appName = metadata.activeAppName ?? bundleId
        let windowTitle = metadata.activeWindowTitle ?? ""
        let now = Date()

        // Get or create session context
        var context: SessionContext
        if let existing = contextMap.sessions[sessionId] {
            context = existing.updated(
                app: appName,
                bundleId: bundleId,
                windowTitle: windowTitle,
                pid: nil,
                workingDirectory: metadata.terminalWorkingDir,
                timestamp: now
            )
        } else {
            context = SessionContext(
                app: appName,
                bundleId: bundleId,
                windowTitle: windowTitle,
                pid: nil,
                workingDirectory: metadata.terminalWorkingDir,
                timestamp: now
            )
        }

        // Record the dictation if text was provided
        if let text = dictationText, !text.isEmpty {
            let record = DictationRecord(
                id: UUID().uuidString,
                text: String(text.prefix(200)),  // Preview only
                app: appName,
                bundleId: bundleId,
                windowTitle: windowTitle,
                timestamp: now
            )
            context.addDictation(record)
            log.debug("Recorded dictation for session \(sessionId): \(text.prefix(50))...")
        }

        contextMap.sessions[sessionId] = context
        contextMap.lastUpdated = now

        log.info("Updated session context: \(sessionId) -> \(context.app) (apps: \(context.apps.joined(separator: ", ")), dictations: \(context.dictations.count))")

        saveToDisk()
    }

    /// Update context from a terminal scan result
    @MainActor
    func updateFromTerminalScan(_ scanResult: TerminalScanResult) {
        for terminal in scanResult.terminals where terminal.isClaudeSession {
            if let sessionId = terminal.claudeSessionId {
                // Preserve existing history
                if let existing = contextMap.sessions[sessionId] {
                    let updated = existing.updated(
                        app: terminal.appName,
                        bundleId: terminal.bundleID,
                        windowTitle: terminal.windowTitle,
                        pid: terminal.pid,
                        workingDirectory: terminal.workingDirectory,
                        timestamp: terminal.timestamp
                    )
                    contextMap.sessions[sessionId] = updated
                } else {
                    let context = SessionContext(
                        app: terminal.appName,
                        bundleId: terminal.bundleID,
                        windowTitle: terminal.windowTitle,
                        pid: terminal.pid,
                        workingDirectory: terminal.workingDirectory,
                        timestamp: terminal.timestamp
                    )
                    contextMap.sessions[sessionId] = context
                }
            }
        }

        contextMap.lastUpdated = Date()
        saveToDisk()

        log.info("Updated \(scanResult.terminals.filter { $0.isClaudeSession }.count) session contexts from scan")
    }

    /// Get context for a session ID
    func getContext(for sessionId: String) -> SessionContext? {
        return contextMap.sessions[sessionId]
    }

    /// Get context by matching project path against working directories
    func getContextByProjectPath(_ projectPath: String) -> SessionContext? {
        // Normalize the project path
        let normalizedPath = projectPath.hasPrefix("~")
            ? projectPath.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
            : projectPath

        // Look through all contexts for a matching working directory
        for (_, context) in contextMap.sessions {
            guard let workingDir = context.workingDirectory else { continue }

            // Normalize the working directory
            let normalizedWorkingDir = workingDir.hasPrefix("~")
                ? workingDir.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
                : workingDir

            // Check if paths match (handle trailing slashes)
            let cleanPath = normalizedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let cleanWorkingDir = normalizedWorkingDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            if cleanPath == cleanWorkingDir {
                log.debug("Found context for project path: \(projectPath) -> \(context.app)")
                return context
            }
        }

        log.debug("No context found for project path: \(projectPath)")
        return nil
    }

    /// Get all mapped sessions
    func getAllMappedSessions() -> [String: SessionContext] {
        return contextMap.sessions
    }

    /// Get the full context map (for debugging/dev tools)
    func getContextMap() -> SessionContextMap {
        return contextMap
    }

    /// Dump context map as JSON (for dev tools)
    func dumpAsJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(contextMap)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{ \"error\": \"\(error.localizedDescription)\" }"
        }
    }

    /// Force a refresh from terminal scan
    @MainActor
    func refreshFromScan() {
        let scanResult = TerminalScanner.shared.scanAllTerminals()
        updateFromTerminalScan(scanResult)
    }

    // MARK: - Private

    private let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty"
    ]

    private func isTerminalApp(bundleId: String) -> Bool {
        return terminalBundleIDs.contains(bundleId)
    }

    @MainActor
    private func extractSessionId(from metadata: DictationMetadata) -> String? {
        // Try to get session ID from window title or working directory
        let title = metadata.activeWindowTitle ?? ""
        let workingDir = metadata.terminalWorkingDir

        // Detect Claude session by:
        // 1. "claude" in the title
        // 2. ✳ prefix (Claude Code's task indicator)
        // 3. Working directory available
        let isClaudeSession = title.lowercased().contains("claude") ||
                              title.hasPrefix("✳") ||
                              workingDir != nil

        guard isClaudeSession else {
            return nil
        }

        // Use working directory to create session ID
        if let dir = workingDir {
            let expandedPath: String
            if dir.hasPrefix("~") {
                expandedPath = dir.replacingOccurrences(
                    of: "~",
                    with: FileManager.default.homeDirectoryForCurrentUser.path
                )
            } else {
                expandedPath = dir
            }

            // Convert to Claude's format
            return expandedPath.replacingOccurrences(of: "/", with: "-")
        }

        // Try to extract from title
        // e.g., "claude - /Users/arach/dev/talkie" -> "-Users-arach-dev-talkie"
        if let dashRange = title.range(of: " - "),
           title.lowercased().hasPrefix("claude") {
            let path = String(title[dashRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if path.hasPrefix("/") || path.hasPrefix("~") {
                let expandedPath = path.hasPrefix("~")
                    ? path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
                    : path
                return expandedPath.replacingOccurrences(of: "/", with: "-")
            }
        }

        // Fallback: Try to find matching window from TerminalScanner
        // This helps when we have ✳ title but no working directory in metadata
        if title.hasPrefix("✳"), let bundleId = metadata.activeAppBundleID {
            let scanResult = TerminalScanner.shared.scanAllTerminals()
            for terminal in scanResult.terminals {
                if terminal.bundleID == bundleId && terminal.windowTitle == title {
                    if let sessionId = terminal.claudeSessionId {
                        log.debug("Found session ID via TerminalScanner fallback: \(sessionId)")
                        return sessionId
                    }
                }
            }
        }

        return nil
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: contextFile.path) else {
            log.debug("No existing session-contexts.json")
            return
        }

        do {
            let data = try Data(contentsOf: contextFile)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            contextMap = try decoder.decode(SessionContextMap.self, from: data)
            log.info("Loaded \(contextMap.sessions.count) session contexts from disk")
        } catch {
            log.error("Failed to load session contexts: \(error)")
        }
    }

    private func saveToDisk() {
        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: contextDir, withIntermediateDirectories: true)
        } catch {
            log.error("Failed to create context directory: \(error)")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(contextMap)
            try data.write(to: contextFile, options: .atomic)
            log.debug("Saved session contexts to \(contextFile.path)")
        } catch {
            log.error("Failed to save session contexts: \(error)")
        }
    }
}
