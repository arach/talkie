//
//  TalkieServiceMonitor.swift
//  Talkie macOS
//
//  Monitors and manages TalkieEngine (Talkie Service) - the background
//  XPC service that handles transcription via Whisper models.
//  Provides process lifecycle management and log streaming.
//

import Foundation
import AppKit
import os
import TalkieKit

private let logger = Logger(subsystem: "jdi.talkie.core", category: "TalkieServiceMonitor")

/// Bundle identifier for TalkieEngine (environment-aware)
private var kTalkieEngineBundleId: String {
    TalkieEnvironment.current.engineBundleId
}

/// Process state for TalkieEngine
public enum TalkieServiceState: String {
    case running = "Running"
    case stopped = "Stopped"
    case launching = "Launching..."
    case terminating = "Terminating..."
    case unknown = "Unknown"
}

/// Log entry from TalkieEngine
public struct TalkieServiceLogEntry: Identifiable, Equatable {
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

/// Monitors TalkieEngine (Talkie Service) process and streams its logs
public final class TalkieServiceMonitor: ObservableObject {
    public static let shared = TalkieServiceMonitor()

    // MARK: - Published State (MainActor isolated for SwiftUI)

    @MainActor @Published public private(set) var state: TalkieServiceState = .unknown
    @MainActor @Published public private(set) var processId: pid_t?
    @MainActor @Published public private(set) var cpuUsage: Double = 0
    @MainActor @Published public private(set) var memoryUsage: UInt64 = 0  // in bytes
    @MainActor @Published public private(set) var uptime: TimeInterval = 0
    @MainActor @Published public private(set) var launchedAt: Date?

    /// Recent logs from TalkieEngine (keeps last 500)
    @MainActor @Published public private(set) var logs: [TalkieServiceLogEntry] = []

    /// Error message if something goes wrong
    @MainActor @Published public private(set) var lastError: String?

    // MARK: - Private

    private var monitorTimer: Timer?
    private var logStreamTask: Process?
    private let maxLogEntries = 500

    private init() {
        logger.info("[TalkieService] Monitor initialized (lazy - call startMonitoring() when needed)")
        // Check initial state immediately to prevent UI flicker
        Task { @MainActor in
            refreshState()
        }
        // Don't auto-start - let views call startMonitoring() when they appear
        // This prevents CPU drain when monitoring views aren't visible
    }

    deinit {
        monitorTimer?.invalidate()
        logStreamTask?.terminate()
    }

    // MARK: - Monitoring

    /// Start monitoring TalkieEngine process
    @MainActor
    public func startMonitoring() {
        guard monitorTimer == nil else { return }

        logger.info("[TalkieService] Starting process monitor")

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
    @MainActor
    public func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        stopLogStream()
        logger.info("[TalkieService] Monitor stopped")
    }

    /// Refresh process state by checking for TalkieEngine process
    @MainActor
    public func refreshState() {
        // Check for TalkieEngine using NSRunningApplication (environment-specific)
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: kTalkieEngineBundleId)

        if let app = apps.first {
            let wasRunning = state == .running
            state = .running
            processId = app.processIdentifier

            if !wasRunning {
                launchedAt = Date()
                logger.info("[TalkieService] Process detected - PID: \(app.processIdentifier)")
            }

            // Update uptime
            if let launched = launchedAt {
                uptime = Date().timeIntervalSince(launched)
            }

            // Get resource usage asynchronously (runs Process on background thread)
            Task.detached { [weak self] in
                await self?.updateResourceUsage(pid: app.processIdentifier)
            }
        } else {
            if state == .running {
                logger.info("[TalkieService] Process terminated")
            }
            state = .stopped
            processId = nil
            cpuUsage = 0
            memoryUsage = 0
            uptime = 0
            launchedAt = nil
        }
    }

    private nonisolated func updateResourceUsage(pid: pid_t) async {
        // Get CPU and memory usage via ps command (runs on background thread)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-p", "\(pid)", "-o", "%cpu=,rss="]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()  // Blocking, but now on background thread

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                let parts = output.split(separator: " ").map { String($0) }
                if parts.count >= 2 {
                    let cpu = Double(parts[0]) ?? 0
                    let memory = (UInt64(parts[1]) ?? 0) * 1024  // RSS is in KB, convert to bytes

                    // Update UI on main actor
                    await MainActor.run {
                        self.cpuUsage = cpu
                        self.memoryUsage = memory
                    }
                }
            }
        } catch {
            // Silently fail - not critical
        }
    }

    // MARK: - Process Control

    /// Launch TalkieEngine via launchctl
    public func launch() async {
        // Check state on main actor
        let currentState = await MainActor.run { self.state }
        guard currentState != .running && currentState != .launching else {
            logger.warning("[TalkieService] Already running or launching")
            return
        }

        await MainActor.run {
            self.state = .launching
            self.lastError = nil
        }

        logger.info("[TalkieService] Launching via launchctl...")

        // Use launchctl to start the service (runs on background thread)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = ["start", "jdi.talkie.engine"]

        let errorPipe = Pipe()
        task.standardError = errorPipe
        task.standardOutput = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()  // Blocking, but now on background thread

            if task.terminationStatus == 0 {
                logger.info("[TalkieService] Launch command sent successfully")
                await MainActor.run {
                    self.launchedAt = Date()
                }
                // State will be updated by monitor
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("[TalkieService] Launch failed: \(errorMessage)")
                await MainActor.run {
                    self.lastError = errorMessage
                    self.state = .stopped
                }
            }
        } catch {
            logger.error("[TalkieService] Launch failed: \(error.localizedDescription)")
            await MainActor.run {
                self.lastError = error.localizedDescription
                self.state = .stopped
            }
        }
    }

    /// Terminate TalkieEngine gracefully
    @MainActor
    public func terminate() {
        guard state == .running, let pid = processId else {
            logger.warning("[TalkieService] Not running")
            return
        }

        state = .terminating
        logger.info("[TalkieService] Terminating PID \(pid)")

        // Send SIGTERM to the process
        kill(pid, SIGTERM)

        // Force kill after 3 seconds if still running
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.refreshState()
            if self?.state == .running, let stillPid = self?.processId {
                logger.warning("[TalkieService] Force killing PID \(stillPid)")
                kill(stillPid, SIGKILL)
            }
        }
    }

    /// Restart TalkieEngine
    @MainActor
    public func restart() async {
        logger.info("[TalkieService] Restarting...")
        terminate()

        // Wait for termination then launch
        try? await Task.sleep(for: .seconds(1.5))
        await launch()
    }

    // MARK: - Log Streaming

    /// Start streaming logs from TalkieEngine using `log stream`
    private func startLogStream() {
        stopLogStream()  // Clean up any existing stream

        logger.info("[TalkieService] Starting log stream")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = [
            "stream",
            "--predicate", "process == 'TalkieEngine'",
            "--style", "compact",
            "--level", "info"
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
            logger.info("[TalkieService] Log stream started")
        } catch {
            logger.error("[TalkieService] Failed to start log stream: \(error.localizedDescription)")
        }
    }

    /// Stop log streaming
    private func stopLogStream() {
        if let task = logStreamTask, task.isRunning {
            task.terminate()
            logger.info("[TalkieService] Log stream stopped")
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
                // Update UI on main actor
                Task { @MainActor in
                    addLogEntry(entry)

                    // Also forward to system console for important logs
                    if entry.level == .error || entry.level == .fault {
                        SystemEventManager.shared.logSync(
                            .error,
                            "[TalkieService] \(entry.message)",
                            detail: entry.category
                        )
                    }
                }
            }
        }
    }

    private func parseCompactLogEntry(_ line: String) -> TalkieServiceLogEntry? {
        // Very simplified parsing - just extract key parts
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Try to extract level
        var level: TalkieServiceLogEntry.LogLevel = .info
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
                let afterColon = bracketContent.index(after: colonIndex)
                let beforeEnd = bracketContent.index(before: bracketContent.endIndex)
                // Only extract if we have content after the colon
                if afterColon < beforeEnd {
                    category = String(bracketContent[afterColon..<beforeEnd])
                }
            }
        }

        // Extract message (everything after the last ])
        var message = trimmed
        if let lastBracket = trimmed.lastIndex(of: "]") {
            message = String(trimmed[trimmed.index(after: lastBracket)...]).trimmingCharacters(in: .whitespaces)
        }

        guard !message.isEmpty else { return nil }

        return TalkieServiceLogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
    }

    @MainActor
    private func addLogEntry(_ entry: TalkieServiceLogEntry) {
        logs.insert(entry, at: 0)
        if logs.count > maxLogEntries {
            logs = Array(logs.prefix(maxLogEntries))
        }
    }

    /// Clear all logs
    @MainActor
    public func clearLogs() {
        logs.removeAll()
        logger.info("[TalkieService] Logs cleared")
    }

    // MARK: - Helpers

    /// Format memory usage for display
    @MainActor
    public var formattedMemory: String {
        let mb = Double(memoryUsage) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    /// Format uptime for display
    @MainActor
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
}
