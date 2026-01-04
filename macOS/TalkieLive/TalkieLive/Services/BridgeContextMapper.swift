//
//  BridgeContextMapper.swift
//  TalkieLive
//
//  Maintains a mapping of Claude session IDs to terminal app contexts.
//  Written to ~/.talkie-bridge/session-contexts.json after each dictation.
//

import Foundation
import TalkieKit

private let log = Log(.system)

/// Context information for a Claude session
struct SessionContext: Codable {
    let app: String              // e.g., "iTerm2"
    let bundleId: String         // e.g., "com.googlecode.iterm2"
    let windowTitle: String      // e.g., "claude - ~/dev/talkie"
    let pid: pid_t?              // Process ID
    let workingDirectory: String? // e.g., "~/dev/talkie"
    let timestamp: Date          // When this context was captured
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

    private let bridgeDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".talkie-bridge")
    private let contextFile: URL

    private var contextMap: SessionContextMap

    private init() {
        self.contextFile = bridgeDir.appendingPathComponent("session-contexts.json")
        self.contextMap = SessionContextMap()
        loadFromDisk()
    }

    // MARK: - Public API

    /// Update the context map after a dictation completes
    /// Call this with the captured metadata from ContextCaptureService
    @MainActor
    func updateAfterDictation(metadata: DictationMetadata) {
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

        let context = SessionContext(
            app: metadata.activeAppName ?? bundleId,
            bundleId: bundleId,
            windowTitle: metadata.activeWindowTitle ?? "",
            pid: nil, // We don't have PID in metadata currently
            workingDirectory: metadata.terminalWorkingDir,
            timestamp: Date()
        )

        contextMap.sessions[sessionId] = context
        contextMap.lastUpdated = Date()

        log.info("Updated session context: \(sessionId) -> \(context.app)")

        saveToDisk()
    }

    /// Update context from a terminal scan result
    @MainActor
    func updateFromTerminalScan(_ scanResult: TerminalScanResult) {
        for terminal in scanResult.terminals where terminal.isClaudeSession {
            if let sessionId = terminal.claudeSessionId {
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

        contextMap.lastUpdated = Date()
        saveToDisk()

        log.info("Updated \(scanResult.terminals.filter { $0.isClaudeSession }.count) session contexts from scan")
    }

    /// Get context for a session ID
    func getContext(for sessionId: String) -> SessionContext? {
        return contextMap.sessions[sessionId]
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

    private func extractSessionId(from metadata: DictationMetadata) -> String? {
        // Try to get session ID from window title or working directory
        let title = metadata.activeWindowTitle ?? ""
        let workingDir = metadata.terminalWorkingDir

        // Check if "claude" is in the title
        guard title.lowercased().contains("claude") || workingDir != nil else {
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
            try FileManager.default.createDirectory(at: bridgeDir, withIntermediateDirectories: true)
        } catch {
            log.error("Failed to create bridge directory: \(error)")
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
