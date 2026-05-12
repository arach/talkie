//
//  TalkieLogger.swift
//  TalkieKit
//
//  Unified logging for the Talkie suite.
//
//  ┌─────────────────────────────────────────────────────────────────────────────┐
//  │                           LOGGING ARCHITECTURE                              │
//  ├─────────────────────────────────────────────────────────────────────────────┤
//  │                                                                             │
//  │  All logging goes through TalkieLogger, which routes to multiple outputs:  │
//  │                                                                             │
//  │                        TalkieLogger.error(.audio, "Failed", error: e)       │
//  │                                          │                                  │
//  │                    ┌─────────────────────┼─────────────────────┐            │
//  │                    ▼                     ▼                     ▼            │
//  │               Console               os.Logger            LogFile           │
//  │             (DEBUG only)          (Instruments)       (Persistent)         │
//  │                                                                             │
//  │  Log Levels:                                                                │
//  │    • debug   - Development only, verbose                                    │
//  │    • info    - Normal operation events                                      │
//  │    • warning - Recoverable issues                                           │
//  │    • error   - Failures that affect functionality                           │
//  │    • fault   - Critical failures, potential crash                           │
//  │                                                                             │
//  │  Categories:                                                                │
//  │    • system       - App lifecycle, initialization                           │
//  │    • audio        - Recording, playback, devices                            │
//  │    • transcription - Whisper/Parakeet, model loading                        │
//  │    • database     - SQLite, Core Data, migrations                           │
//  │    • xpc          - Inter-process communication                             │
//  │    • sync         - CloudKit, iCloud sync                                   │
//  │    • ui           - View lifecycle, user interactions                       │
//  │    • workflow     - Workflow execution                                      │
//  │                                                                             │
//  │  Usage:                                                                     │
//  │    TalkieLogger.configure(source: .talkie)  // Call once at app start       │
//  │    TalkieLogger.error(.database, "Store failed", error: error)              │
//  │    TalkieLogger.info(.audio, "Recording started", detail: "48kHz stereo")   │
//  │                                                                             │
//  │  Critical (Startup) Logging:                                                │
//  │    Use critical: true for pre-runloop startup code where crash visibility   │
//  │    is essential. This adds synchronous NSLog output.                        │
//  │                                                                             │
//  │    log.info("XPC listener starting", critical: true)  // Startup context    │
//  │    log.info("Recording started")                      // Normal runtime     │
//  │                                                                             │
//  └─────────────────────────────────────────────────────────────────────────────┘
//

import Foundation
import os

// MARK: - Log Level

/// Log severity level
public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0    // Verbose development info
    case info = 1     // Normal operation
    case warning = 2  // Recoverable issues
    case error = 3    // Failures affecting functionality
    case fault = 4    // Critical failures

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .fault: return "💥"
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .fault: return .fault
        }
    }
}

// MARK: - Log Category

/// Log category for filtering and routing
public enum LogCategory: String, Sendable {
    case system = "system"
    case audio = "audio"
    case transcription = "transcription"
    case database = "database"
    case xpc = "xpc"
    case sync = "sync"
    case ui = "ui"
    case workflow = "workflow"

    /// Map to TalkieLogFileWriter's LogEventType
    var fileLogType: LogEventType {
        switch self {
        case .system: return .system
        case .audio: return .record
        case .transcription: return .transcribe
        case .database: return .system
        case .xpc: return .system
        case .sync: return .sync
        case .ui: return .system
        case .workflow: return .workflow
        }
    }
}

// MARK: - TalkieLogger

/// Unified logger for the Talkie suite
/// Routes logs to console (DEBUG), os.Logger, and persistent file
public final class TalkieLogger: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = TalkieLogger()

    // MARK: - Configuration

    private var source: LogSource = .talkie
    private var minimumLevel: LogLevel = .debug
    private var isConfigured = false

    /// os.Logger instances by category
    private var osLoggers: [LogCategory: Logger] = [:]

    /// File writer for persistent logs
    private var fileWriter: TalkieLogFileWriter?

    /// Console output enabled (DEBUG builds only)
    private var consoleEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    /// Whether DEBUG builds should also mirror log lines to os.Logger.
    /// Default is false to avoid duplicate console lines (print + os.Logger).
    private var mirrorToOSLogInDebug = false

    private let queue = DispatchQueue(label: "to.talkie.app.logger", qos: .utility)

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    /// Configure the logger for a specific app
    /// Call once at app startup
    public static func configure(
        source: LogSource,
        minimumLevel: LogLevel = .debug,
        consoleEnabled: Bool? = nil,
        mirrorToOSLogInDebug: Bool = false
    ) {
        shared.queue.sync {
            shared.source = source
            shared.minimumLevel = minimumLevel
            shared.fileWriter = TalkieLogFileWriter(source: source)
            shared.isConfigured = true
            shared.mirrorToOSLogInDebug = mirrorToOSLogInDebug

            if let console = consoleEnabled {
                shared.consoleEnabled = console
            }

            // Create os.Logger for each category
            let subsystem = "to.talkie.app.\(source.rawValue.lowercased())"
            for category in [LogCategory.system, .audio, .transcription, .database, .xpc, .sync, .ui, .workflow] {
                shared.osLoggers[category] = Logger(subsystem: subsystem, category: category.rawValue)
            }
        }
    }

    // MARK: - Logging Methods

    /// Log a debug message (development only)
    public static func debug(_ category: LogCategory, _ message: String, detail: String? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        shared.log(level: .debug, category: category, message: message, detail: detail, error: nil, section: section, critical: critical, file: file, line: line)
    }

    /// Log an info message (normal operation)
    /// - Parameter section: If provided, formats with vertical bar: `│ [Section] message`
    /// - Parameter critical: If true, also writes to NSLog for crash-safe visibility (use during startup)
    public static func info(_ category: LogCategory, _ message: String, detail: String? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        shared.log(level: .info, category: category, message: message, detail: detail, error: nil, section: section, critical: critical, file: file, line: line)
    }

    /// Log a warning (recoverable issue)
    /// - Parameter section: If provided, formats with vertical bar: `│ [Section] message`
    /// - Parameter critical: If true, also writes to NSLog for crash-safe visibility (use during startup)
    public static func warning(_ category: LogCategory, _ message: String, detail: String? = nil, error: Error? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        shared.log(level: .warning, category: category, message: message, detail: detail, error: error, section: section, critical: critical, file: file, line: line)
    }

    /// Log an error (failure affecting functionality)
    /// - Parameter section: If provided, formats with vertical bar: `│ [Section] message`
    /// - Parameter critical: If true, also writes to NSLog for crash-safe visibility (use during startup)
    public static func error(_ category: LogCategory, _ message: String, detail: String? = nil, error: Error? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        shared.log(level: .error, category: category, message: message, detail: detail, error: error, section: section, critical: critical, file: file, line: line)
    }

    /// Log a fault (critical failure)
    /// - Parameter section: If provided, formats with vertical bar: `│ [Section] message`
    /// - Parameter critical: If true, also writes to NSLog for crash-safe visibility (use during startup)
    public static func fault(_ category: LogCategory, _ message: String, detail: String? = nil, error: Error? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        shared.log(level: .fault, category: category, message: message, detail: detail, error: error, section: section, critical: critical, file: file, line: line)
    }


    // MARK: - Core Implementation

    private func log(
        level: LogLevel,
        category: LogCategory,
        message: String,
        detail: String?,
        error: Error?,
        section: String?,
        critical: Bool,
        file: String,
        line: Int
    ) {
        // Skip if below minimum level
        guard level >= minimumLevel else { return }

        // Build full message with error if present
        var fullDetail = detail ?? ""
        if let error = error {
            let errorDesc = error.localizedDescription
            fullDetail = fullDetail.isEmpty ? errorDesc : "\(fullDetail) | \(errorDesc)"
        }

        // Get filename without path
        let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let location = "[\(filename):\(line)]"

        // Section formatting: synchronous NSLog with section prefix
        // Used for grouped startup logs or other visual sections
        if let section = section {
            let prefix = level >= .error ? "❌ " : ""
            let detailSuffix = fullDetail.isEmpty ? "" : " - \(fullDetail)"
            NSLog("[%@] %@%@%@", section, prefix, message, detailSuffix)
            // Still write to file, but skip os.Logger to avoid duplicate console output
        }
        // Critical path: synchronous NSLog for crash-safe visibility (startup code)
        // This runs BEFORE async queue to ensure visibility if we crash during startup
        else if critical {
            let nslogMsg = "\(level.emoji) \(message)\(fullDetail.isEmpty ? "" : " - \(fullDetail)") \(location)"
            NSLog("%@", nslogMsg)
        }

        queue.async { [weak self] in
            guard let self = self else { return }

            #if DEBUG
            // DEBUG: Always print to Xcode console (skip if section/critical already used NSLog)
            if section == nil && !critical {
                let debugMsg = "\(level.emoji) [\(category.rawValue)] \(message)\(fullDetail.isEmpty ? "" : " - \(fullDetail)")"
                print(debugMsg)
            }
            #endif

            // os.Logger (for Instruments/Console.app)
            // Skip when section is set (already output via NSLog with section formatting)
            // Skip in DEBUG when critical=true (NSLog already output synchronously)
            #if DEBUG
            let skipOsLog = section != nil || critical || !self.mirrorToOSLogInDebug
            #else
            let skipOsLog = section != nil
            #endif

            if !skipOsLog, let osLogger = self.osLoggers[category] {
                #if DEBUG
                let osMsg = "\(level.emoji) \(message)\(fullDetail.isEmpty ? "" : " - \(fullDetail)") \(location)"
                #else
                let osMsg = "\(message)\(fullDetail.isEmpty ? "" : " - \(fullDetail)") \(location)"
                #endif
                osLogger.log(level: level.osLogType, "\(osMsg, privacy: .public)")
            }

            // File output (errors/warnings/faults always, others if configured)
            if let writer = self.fileWriter {
                // Errors and above always go to file with immediate flush
                // Critical path and section logs also get immediate flush
                let writeMode: LogWriteMode = (level >= .error || critical || section != nil) ? .critical : .bestEffort

                // Only write info+ to file (skip debug to reduce file size)
                if level >= .info {
                    let fileType: LogEventType = level >= .error ? .error : category.fileLogType
                    let fileDetail = fullDetail.isEmpty ? location : "\(fullDetail) \(location)"
                    writer.log(fileType, message, detail: fileDetail, mode: writeMode)
                }
            }

            // Reporter buffer (info+ for feedback reports)
            // Include all categories except sync (rarely relevant for feedback)
            if level >= .info && category != .sync {
                let reportLine = "\(level.emoji) [\(category.rawValue)] \(message)"
                Task { @MainActor in
                    TalkieReporter.shared.addLog(reportLine)
                }
            }
        }
    }

    /// Flush any buffered logs to disk
    public static func flush() {
        shared.fileWriter?.flush()
    }
}

// MARK: - Convenience Extensions

public extension TalkieLogger {
    /// Quick error log with just an Error object
    static func error(_ category: LogCategory, error: Error, file: String = #file, line: Int = #line) {
        shared.log(level: .error, category: category, message: error.localizedDescription, detail: nil, error: nil, section: nil, critical: false, file: file, line: line)
    }
}

// MARK: - Log (Per-File Logger)

/// Lightweight per-file logger with fixed category
///
/// Usage:
/// ```swift
/// // At top of file
/// private let log = Log(.database)
///
/// // Throughout file
/// log.info("Connected")
/// log.error("Store failed", error: error)
/// log.debug("Query took \(ms)ms")
/// ```
public struct Log: Sendable {
    private let category: LogCategory

    public init(_ category: LogCategory) {
        self.category = category
    }

    // MARK: - Logging Methods

    /// Log a debug message
    /// - Parameter section: If provided, formats with vertical bar: `│ [Section] message`
    /// - Parameter critical: If true, also writes to NSLog for crash-safe visibility (use during startup)
    public func debug(_ message: String, detail: String? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        TalkieLogger.debug(category, message, detail: detail, section: section, critical: critical, file: file, line: line)
    }

    /// Log an info message
    /// - Parameter section: If provided, formats with vertical bar: `│ [Section] message`
    /// - Parameter critical: If true, also writes to NSLog for crash-safe visibility (use during startup)
    public func info(_ message: String, detail: String? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        TalkieLogger.info(category, message, detail: detail, section: section, critical: critical, file: file, line: line)
    }

    /// Log a warning
    /// - Parameter section: If provided, formats with vertical bar: `│ [Section] message`
    /// - Parameter critical: If true, also writes to NSLog for crash-safe visibility (use during startup)
    public func warning(_ message: String, detail: String? = nil, error: Error? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        TalkieLogger.warning(category, message, detail: detail, error: error, section: section, critical: critical, file: file, line: line)
    }

    /// Log an error
    /// - Parameter section: If provided, formats with vertical bar: `│ [Section] message`
    /// - Parameter critical: If true, also writes to NSLog for crash-safe visibility (use during startup)
    public func error(_ message: String, detail: String? = nil, error: Error? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        TalkieLogger.error(category, message, detail: detail, error: error, section: section, critical: critical, file: file, line: line)
    }

    /// Log an error from an Error object
    public func error(_ error: Error, file: String = #file, line: Int = #line) {
        TalkieLogger.error(category, error.localizedDescription, file: file, line: line)
    }

    /// Log a fault (critical failure)
    /// - Parameter section: If provided, formats with vertical bar: `│ [Section] message`
    /// - Parameter critical: If true, also writes to NSLog for crash-safe visibility (use during startup)
    public func fault(_ message: String, detail: String? = nil, error: Error? = nil, section: String? = nil, critical: Bool = false, file: String = #file, line: Int = #line) {
        TalkieLogger.fault(category, message, detail: detail, error: error, section: section, critical: critical, file: file, line: line)
    }
}

// MARK: - Log Section

/// Grouped log output with visual formatting
/// Usage:
/// ```
/// let section = LogSection("Startup")
/// section.log("Loading database...")
/// section.log("Database ready ✓")
/// section.end()
/// ```
/// Output:
/// ```
/// │ [Startup] Loading database...
/// │ [Startup] Database ready ✓
/// └──────────────────────────────
/// ```
public struct LogSection {
    public let name: String
    public let dividerWidth: Int

    /// Create a log section with a name
    /// - Parameters:
    ///   - name: Section name shown in brackets
    ///   - dividerWidth: Width of the ending divider (default: 40)
    public init(_ name: String, dividerWidth: Int = 40) {
        self.name = name
        self.dividerWidth = dividerWidth
    }

    /// Log a message within this section (with vertical bar prefix)
    public func log(_ message: String) {
        NSLog("│ [%@] %@", name, message)
    }

    /// Log a message without the section name (just the bar)
    public func logPlain(_ message: String) {
        NSLog("│ %@", message)
    }

    /// End the section with a divider
    public func end() {
        NSLog("└%@", String(repeating: "─", count: dividerWidth))
    }

    /// Log a message and immediately end the section
    public func logAndEnd(_ message: String) {
        log(message)
        end()
    }

    // MARK: - Static Convenience

    /// Quick one-liner: logs a message in a section and ends it
    public static func single(_ name: String, _ message: String, dividerWidth: Int = 40) {
        let section = LogSection(name, dividerWidth: dividerWidth)
        section.log(message)
        section.end()
    }

    /// Quick group: logs multiple messages in a section and ends it
    public static func group(_ name: String, _ messages: [String], dividerWidth: Int = 40) {
        let section = LogSection(name, dividerWidth: dividerWidth)
        for message in messages {
            section.log(message)
        }
        section.end()
    }
}
