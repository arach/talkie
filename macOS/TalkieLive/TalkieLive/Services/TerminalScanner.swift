//
//  TerminalScanner.swift
//  TalkieLive
//
//  Scans all running terminal windows using Accessibility API.
//  Used for mapping Claude sessions to terminal windows.
//

import Foundation
import AppKit
import ApplicationServices
import TalkieKit

private let log = Log(.system)

/// Information about a terminal window
struct TerminalWindow: Identifiable, Codable {
    var id: String { "\(pid)-\(windowIndex)" }
    let pid: pid_t
    let windowIndex: Int
    let appName: String
    let bundleID: String
    let windowTitle: String
    let workingDirectory: String?
    let isClaudeSession: Bool
    let claudeSessionId: String?
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case pid, windowIndex, appName, bundleID, windowTitle
        case workingDirectory, isClaudeSession, claudeSessionId, timestamp
    }
}

/// Result of a terminal scan
struct TerminalScanResult: Codable {
    let terminals: [TerminalWindow]
    let scanTime: Date
    let durationMs: Int
}

/// Service for scanning terminal windows
final class TerminalScanner {
    static let shared = TerminalScanner()

    // Known terminal bundle IDs
    private let terminalBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "co.zeit.hyper",
        "com.github.wez.wezterm",
        "com.mitchellh.ghostty"
    ]

    private init() {}

    // MARK: - Public API

    /// Scan all terminal windows and return info about each
    @MainActor
    func scanAllTerminals() -> TerminalScanResult {
        let startTime = Date()
        var terminals: [TerminalWindow] = []

        guard AXIsProcessTrusted() else {
            log.error("Accessibility permission not granted - cannot scan terminals")
            return TerminalScanResult(terminals: [], scanTime: startTime, durationMs: 0)
        }

        // Find all running terminal apps
        let runningApps = NSWorkspace.shared.runningApplications
        let terminalApps = runningApps.filter { app in
            guard let bundleID = app.bundleIdentifier else { return false }
            return terminalBundleIDs.contains(bundleID)
        }

        log.debug("Found \(terminalApps.count) terminal app(s) running")

        for app in terminalApps {
            let appWindows = scanApp(app)
            terminals.append(contentsOf: appWindows)
        }

        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
        log.info("Terminal scan complete: \(terminals.count) windows in \(durationMs)ms")

        return TerminalScanResult(
            terminals: terminals,
            scanTime: startTime,
            durationMs: durationMs
        )
    }

    /// Find terminals that appear to be running Claude
    @MainActor
    func findClaudeTerminals() -> [TerminalWindow] {
        let result = scanAllTerminals()
        return result.terminals.filter { $0.isClaudeSession }
    }

    /// Dump scan results as JSON (for dev tools)
    @MainActor
    func dumpAsJSON() -> String {
        let result = scanAllTerminals()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{ \"error\": \"\(error.localizedDescription)\" }"
        }
    }

    // MARK: - Private

    private func scanApp(_ app: NSRunningApplication) -> [TerminalWindow] {
        var windows: [TerminalWindow] = []

        guard let bundleID = app.bundleIdentifier else { return [] }
        let appName = app.localizedName ?? bundleID

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get all windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windowList = windowsRef as? [AXUIElement] else {
            log.debug("No windows found for \(appName)")
            return []
        }

        for (index, window) in windowList.enumerated() {
            // Get window title
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? ""

            // Skip empty or minimized windows
            if title.isEmpty { continue }

            // Extract working directory from title
            let workingDir = extractWorkingDirectory(from: title)

            // Detect if this is a Claude session
            let isClaudeSession = detectClaudeSession(title: title, workingDir: workingDir)

            // Try to extract Claude session ID from working directory
            let claudeSessionId = isClaudeSession ? extractClaudeSessionId(workingDir: workingDir) : nil

            let terminalWindow = TerminalWindow(
                pid: app.processIdentifier,
                windowIndex: index,
                appName: appName,
                bundleID: bundleID,
                windowTitle: title,
                workingDirectory: workingDir,
                isClaudeSession: isClaudeSession,
                claudeSessionId: claudeSessionId,
                timestamp: Date()
            )

            windows.append(terminalWindow)
            log.debug("  Window \(index): \(title)\(isClaudeSession ? " [CLAUDE]" : "")")
        }

        return windows
    }

    private func extractWorkingDirectory(from windowTitle: String) -> String? {
        // Common patterns in terminal window titles:
        // "user@host:~/dev/project"
        // "~/dev/project"
        // "zsh - ~/dev/project"
        // "claude - /Users/arach/dev/talkie"

        // Look for path-like patterns after colon
        if let colonIndex = windowTitle.lastIndex(of: ":") {
            let afterColon = String(windowTitle[windowTitle.index(after: colonIndex)...])
            let trimmed = afterColon.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("~") || trimmed.hasPrefix("/") {
                return trimmed
            }
        }

        // Look for path after " - "
        if let dashRange = windowTitle.range(of: " - ") {
            let afterDash = String(windowTitle[dashRange.upperBound...])
            let trimmed = afterDash.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("~") || trimmed.hasPrefix("/") {
                return trimmed
            }
        }

        // Look for ~ or / patterns in components
        let components = windowTitle.components(separatedBy: " ")
        for component in components.reversed() {
            if component.hasPrefix("~") || component.hasPrefix("/") {
                return component
            }
        }

        return nil
    }

    private func detectClaudeSession(title: String, workingDir: String?) -> Bool {
        let lowerTitle = title.lowercased()

        // Direct mentions
        if lowerTitle.contains("claude") { return true }

        // Common Claude Code patterns
        if lowerTitle.contains("claude code") { return true }
        if lowerTitle.contains("anthropic") { return true }

        // Check for typical Claude Code prompts in title
        // (some terminals show the current command in title)
        if lowerTitle.hasPrefix("claude ") { return true }

        // Check if the working directory has a Claude project
        // (matches a folder in ~/.claude/projects/)
        if let workingDir = workingDir {
            let sessionId = extractClaudeSessionId(workingDir: workingDir)
            if let sessionId = sessionId {
                let projectsDir = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/projects")
                    .appendingPathComponent(sessionId)
                if FileManager.default.fileExists(atPath: projectsDir.path) {
                    log.debug("Detected Claude session via project folder: \(sessionId)")
                    return true
                }
            }
        }

        return false
    }

    private func extractClaudeSessionId(workingDir: String?) -> String? {
        // Convert working directory to Claude's session ID format
        // e.g., "/Users/arach/dev/talkie" -> "-Users-arach-dev-talkie"
        guard let path = workingDir else { return nil }

        // Expand ~ to home directory
        let expandedPath: String
        if path.hasPrefix("~") {
            expandedPath = path.replacingOccurrences(of: "~", with: FileManager.default.homeDirectoryForCurrentUser.path)
        } else {
            expandedPath = path
        }

        // Convert to Claude's format (replace / with -)
        let sessionId = expandedPath.replacingOccurrences(of: "/", with: "-")

        return sessionId
    }
}
