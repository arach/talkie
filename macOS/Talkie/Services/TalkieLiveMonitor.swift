//
//  TalkieLiveMonitor.swift
//  Talkie macOS
//
//  Monitors TalkieLive app - the always-on voice companion.
//  Provides process lifecycle management and log streaming.
//

import Foundation
import AppKit
import os
import TalkieKit

private let logger = Logger(subsystem: "jdi.talkie.core", category: "TalkieLiveMonitor")

/// Bundle identifier for TalkieLive (environment-aware)
private var kTalkieLiveBundleId: String {
    TalkieEnvironment.current.liveBundleId
}

/// Process state for TalkieLive
public enum TalkieLiveState: String {
    case running = "Running"
    case stopped = "Stopped"
    case launching = "Launching..."
    case terminating = "Terminating..."
    case unknown = "Unknown"
}

/// Log entry from TalkieLive
public struct TalkieLiveLogEntry: Identifiable, Equatable {
    public let id = UUID()
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String

    public enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case fault = "FAULT"

        var color: String {
            switch self {
            case .debug: return "gray"
            case .info: return "blue"
            case .warning: return "orange"
            case .error: return "red"
            case .fault: return "purple"
            }
        }
    }
}

/// Monitors TalkieLive app process and streams its logs
@MainActor
@Observable
public final class TalkieLiveMonitor {
    public static let shared = TalkieLiveMonitor()

    // MARK: - Published State

    public private(set) var state: TalkieLiveState = .unknown
    public private(set) var processId: pid_t?
    public private(set) var cpuUsage: Double = 0
    public private(set) var memoryUsage: UInt64 = 0  // in bytes
    public private(set) var uptime: TimeInterval = 0
    public private(set) var launchedAt: Date?

    /// Recent logs from TalkieLive (keeps last 500)
    public private(set) var logs: [TalkieLiveLogEntry] = []

    /// Error message if something goes wrong
    public private(set) var lastError: String?

    // MARK: - Private

    @ObservationIgnored private var monitorTimer: Timer?
    @ObservationIgnored private var logStreamTask: Process?
    @ObservationIgnored private let maxLogEntries = 500

    private init() {
        logger.info("[TalkieLive] Monitor initialized (lazy - call startMonitoring() when needed)")
        // Don't auto-start - let views call startMonitoring() when they appear
        // This prevents CPU drain when monitoring views aren't visible
    }

    deinit {
        // Defensive cleanup - singleton shouldn't deinit but if it does, clean up
        // Access to main actor properties is unsafe here, but cleanup is critical
        Task { @MainActor in
            monitorTimer?.invalidate()
            logStreamTask?.terminate()
        }
    }

    // MARK: - Monitoring

    /// Start monitoring TalkieLive process
    public func startMonitoring() {
        guard monitorTimer == nil else { return }

        logger.info("[TalkieLive] Starting process monitor")

        // Initial check
        refreshState()

        // Poll every 2 seconds
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshState()
            }
        }

        // Start log streaming
        startLogStream()
    }

    /// Stop monitoring
    public func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        stopLogStream()
        logger.info("[TalkieLive] Monitor stopped")
    }

    /// Refresh process state by checking for TalkieLive process
    public func refreshState() {
        // Check for TalkieLive using NSRunningApplication (environment-specific)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: kTalkieLiveBundleId)

        if let app = apps.first {
            let wasRunning = state == .running
            state = .running
            processId = app.processIdentifier

            if !wasRunning {
                launchedAt = Date()
                logger.info("[TalkieLive] Process detected - PID: \(app.processIdentifier)")
            }

            // Update uptime
            if let launched = launchedAt {
                uptime = Date().timeIntervalSince(launched)
            }

            // Get resource usage
            updateResourceUsage(pid: app.processIdentifier)
        } else {
            if state == .running {
                logger.info("[TalkieLive] Process terminated")
            }
            state = .stopped
            processId = nil
            cpuUsage = 0
            memoryUsage = 0
            uptime = 0
            launchedAt = nil
        }
    }

    private func updateResourceUsage(pid: pid_t) {
        // Get CPU and memory usage via ps command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "%cpu=,rss="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let parts = output.split(separator: " ").map { String($0) }
                if parts.count >= 2 {
                    cpuUsage = Double(parts[0]) ?? 0
                    // RSS is in KB, convert to bytes
                    memoryUsage = (UInt64(parts[1]) ?? 0) * 1024
                }
            }
        } catch {
            // Silently fail - not critical
        }
    }

    // MARK: - Process Control

    /// Launch TalkieLive
    public func launch() {
        guard state != .running && state != .launching else {
            logger.warning("[TalkieLive] Already running or launching")
            return
        }

        state = .launching
        lastError = nil

        logger.info("[TalkieLive] Launching...")

        // Try to find TalkieLive in common locations
        let possiblePaths = [
            "/Applications/TalkieLive.app",
            "~/Applications/TalkieLive.app",
            Bundle.main.bundlePath.replacingOccurrences(of: "Talkie.app", with: "TalkieLive.app")
        ].map { NSString(string: $0).expandingTildeInPath }

        var launched = false

        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false  // Don't bring to front

                NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] app, error in
                    Task { @MainActor in
                        if let error = error {
                            logger.error("[TalkieLive] Launch failed: \(error.localizedDescription)")
                            self?.lastError = error.localizedDescription
                            self?.state = .stopped
                        } else {
                            logger.info("[TalkieLive] Launched successfully")
                            self?.launchedAt = Date()
                            // State will be updated by monitor
                        }
                    }
                }
                launched = true
                break
            }
        }

        if !launched {
            logger.error("[TalkieLive] App not found in expected locations")
            lastError = "TalkieLive.app not found. Please install it first."
            state = .stopped
        }
    }

    /// Terminate TalkieLive gracefully
    public func terminate() {
        guard state == .running else {
            logger.warning("[TalkieLive] Not running")
            return
        }

        state = .terminating

        // Terminate running instance for current environment
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: kTalkieLiveBundleId)
        for app in apps {
            logger.info("[TalkieLive] Terminating PID \(app.processIdentifier)")
            app.terminate()
        }

        // Force kill after 3 seconds if still running
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            let stillRunning = NSRunningApplication.runningApplications(withBundleIdentifier: kTalkieLiveBundleId)
            for app in stillRunning {
                logger.warning("[TalkieLive] Force killing PID \(app.processIdentifier)")
                app.forceTerminate()
            }
            self?.refreshState()
        }
    }

    /// Restart TalkieLive
    public func restart() {
        logger.info("[TalkieLive] Restarting...")
        terminate()

        // Wait for termination then launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.launch()
        }
    }

    // MARK: - Log Streaming

    /// Start streaming logs from TalkieLive using `log stream`
    private func startLogStream() {
        stopLogStream()  // Clean up any existing stream

        logger.info("[TalkieLive] Starting log stream")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = [
            "stream",
            "--predicate", "subsystem == 'jdi.talkie.live'",
            "--style", "compact",
            "--level", "debug"
        ]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        // Read output asynchronously
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let line = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self?.parseLogLine(line)
                }
            }
        }

        do {
            try task.run()
            logStreamTask = task
            logger.info("[TalkieLive] Log stream started")
        } catch {
            logger.error("[TalkieLive] Failed to start log stream: \(error.localizedDescription)")
        }
    }

    /// Stop log streaming
    private func stopLogStream() {
        if let task = logStreamTask, task.isRunning {
            task.terminate()
            logger.info("[TalkieLive] Log stream stopped")
        }
        logStreamTask = nil
    }

    /// Parse a log line from `log stream`
    private func parseLogLine(_ rawLine: String) {
        let lines = rawLine.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            // Skip header lines
            if line.contains("Filtering the log data") || line.hasPrefix("Timestamp") { continue }

            // Parse the log entry
            let entry = parseCompactLogEntry(line)
            if let entry = entry {
                addLogEntry(entry)
            }
        }
    }

    private func parseCompactLogEntry(_ line: String) -> TalkieLiveLogEntry? {
        // Very simplified parsing - just extract key parts
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Try to extract level
        var level: TalkieLiveLogEntry.LogLevel = .info
        if trimmed.contains(" Debug ") || trimmed.contains(" Default ") {
            level = .debug
        } else if trimmed.contains(" Info ") {
            level = .info
        } else if trimmed.contains(" Notice ") || trimmed.contains(" Warning ") {
            level = .warning
        } else if trimmed.contains(" Error ") {
            level = .error
        } else if trimmed.contains(" Fault ") {
            level = .fault
        }

        // Extract category from [subsystem:category]
        var category = "General"
        if let bracketStart = trimmed.firstIndex(of: "["),
           let bracketEnd = trimmed.firstIndex(of: "]") {
            let bracketContent = String(trimmed[bracketStart...bracketEnd])
            if let colonIndex = bracketContent.firstIndex(of: ":") {
                category = String(bracketContent[bracketContent.index(after: colonIndex)..<bracketContent.index(before: bracketContent.endIndex)])
            }
        }

        // Extract message (everything after the last ])
        var message = trimmed
        if let lastBracket = trimmed.lastIndex(of: "]") {
            message = String(trimmed[trimmed.index(after: lastBracket)...]).trimmingCharacters(in: .whitespaces)
        }

        guard !message.isEmpty else { return nil }

        return TalkieLiveLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
    }

    private func addLogEntry(_ entry: TalkieLiveLogEntry) {
        logs.insert(entry, at: 0)
        if logs.count > maxLogEntries {
            logs = Array(logs.prefix(maxLogEntries))
        }
    }

    /// Clear all logs
    public func clearLogs() {
        logs.removeAll()
        logger.info("[TalkieLive] Logs cleared")
    }

    // MARK: - Helpers

    /// Format memory usage for display
    public var formattedMemory: String {
        let mb = Double(memoryUsage) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    /// Format uptime for display
    public var formattedUptime: String {
        let hours = Int(uptime) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        let seconds = Int(uptime) % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }

    /// Check if TalkieLive is installed
    public var isInstalled: Bool {
        let possiblePaths = [
            "/Applications/TalkieLive.app",
            "~/Applications/TalkieLive.app",
            Bundle.main.bundlePath.replacingOccurrences(of: "Talkie.app", with: "TalkieLive.app")
        ].map { NSString(string: $0).expandingTildeInPath }

        return possiblePaths.contains { FileManager.default.fileExists(atPath: $0) }
    }
}
