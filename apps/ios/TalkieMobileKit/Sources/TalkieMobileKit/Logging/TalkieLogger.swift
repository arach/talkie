//
//  TalkieLogger.swift
//  TalkieMobileKit (iOS)
//
//  Unified logging for the Talkie iOS suite.
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
//  │                NSLog                os.Logger             (Future)          │
//  │            (Extensions)           (Console.app)          File logs          │
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
//  │    • transcription - Speech recognition                                     │
//  │    • database     - SQLite, Core Data, migrations                           │
//  │    • sync         - CloudKit, iCloud sync                                   │
//  │    • ui           - View lifecycle, user interactions                       │
//  │    • keyboard     - Keyboard extension specific                             │
//  │                                                                             │
//  │  Usage:                                                                     │
//  │    TalkieLogger.configure(source: .talkieMemos)  // Call once at app start  │
//  │    TalkieLogger.error(.database, "Store failed", error: error)              │
//  │    TalkieLogger.info(.audio, "Recording started", detail: "48kHz stereo")   │
//  │                                                                             │
//  │  Per-file logger:                                                           │
//  │    private let log = Log(.keyboard)                                         │
//  │    log.info("Started")                                                      │
//  │    log.error("Failed", error: error)                                        │
//  │                                                                             │
//  └─────────────────────────────────────────────────────────────────────────────┘
//

import Foundation
import os

// MARK: - Log Source

/// App/extension that is logging
public enum LogSource: String, Sendable {
    case talkieMemos = "TalkieMemos"
    case talkieKeys = "TalkieKeys"
    case talkieWidget = "TalkieWidget"
    case talkieWatch = "TalkieWatch"
}

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
    case sync = "sync"
    case ui = "ui"
    case keyboard = "keyboard"  // iOS keyboard extension
}

// MARK: - TalkieLogger

/// Unified logger for the Talkie iOS suite
/// Routes logs to NSLog (for extension debugging) and os.Logger (for Console.app/Instruments)
public final class TalkieLogger: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = TalkieLogger()

    // MARK: - Configuration

    // Release builds default to .info so verbose debug payloads (full responses,
    // transcript fragments) never reach the persistent unified log.
    #if DEBUG
    public static let defaultMinimumLevel: LogLevel = .debug
    #else
    public static let defaultMinimumLevel: LogLevel = .info
    #endif

    private var source: LogSource = .talkieMemos
    private var minimumLevel: LogLevel = TalkieLogger.defaultMinimumLevel
    private var osLoggers: [LogCategory: Logger] = [:]

    private let queue = DispatchQueue(label: "jdi.talkie.logger", qos: .utility)

    // MARK: - Initialization

    private init() {}

    // MARK: - Configuration

    /// Configure the logger for a specific app/extension
    /// Call once at startup
    public static func configure(source: LogSource) {
        configure(source: source, minimumLevel: TalkieLogger.defaultMinimumLevel)
    }

    /// Configure the logger for a specific app/extension with an explicit minimum level.
    /// Call once at startup.
    public static func configure(source: LogSource, minimumLevel: LogLevel) {
        shared.queue.sync {
            shared.source = source
            shared.minimumLevel = minimumLevel

            // Create os.Logger for each category
            let subsystem = "jdi.talkie.\(source.rawValue.lowercased())"
            for category in [LogCategory.system, .audio, .transcription, .database, .sync, .ui, .keyboard] {
                shared.osLoggers[category] = Logger(subsystem: subsystem, category: category.rawValue)
            }
        }
    }

    // MARK: - Static Logging Methods

    /// Log a debug message (development only)
    public static func debug(_ category: LogCategory, _ message: String, detail: String? = nil, file: String = #file, line: Int = #line) {
        shared.log(level: .debug, category: category, message: message, detail: detail, error: nil, file: file, line: line)
    }

    /// Log an info message (normal operation)
    public static func info(_ category: LogCategory, _ message: String, detail: String? = nil, file: String = #file, line: Int = #line) {
        shared.log(level: .info, category: category, message: message, detail: detail, error: nil, file: file, line: line)
    }

    /// Log a warning (recoverable issue)
    public static func warning(_ category: LogCategory, _ message: String, detail: String? = nil, error: Error? = nil, file: String = #file, line: Int = #line) {
        shared.log(level: .warning, category: category, message: message, detail: detail, error: error, file: file, line: line)
    }

    /// Log an error (failure affecting functionality)
    public static func error(_ category: LogCategory, _ message: String, detail: String? = nil, error: Error? = nil, file: String = #file, line: Int = #line) {
        shared.log(level: .error, category: category, message: message, detail: detail, error: error, file: file, line: line)
    }

    /// Log a fault (critical failure)
    public static func fault(_ category: LogCategory, _ message: String, detail: String? = nil, error: Error? = nil, file: String = #file, line: Int = #line) {
        shared.log(level: .fault, category: category, message: message, detail: detail, error: error, file: file, line: line)
    }

    // MARK: - Core Implementation

    private func log(
        level: LogLevel,
        category: LogCategory,
        message: String,
        detail: String?,
        error: Error?,
        file: String,
        line: Int
    ) {
        guard level >= minimumLevel else { return }

        var fullDetail = detail ?? ""
        if let error = error {
            fullDetail = fullDetail.isEmpty ? error.localizedDescription : "\(fullDetail) | \(error.localizedDescription)"
        }

        let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let location = "[\(filename):\(line)]"

        // NSLog is debug-only: it bypasses os_log privacy redaction entirely, so in
        // release the persistent unified log would carry every message in cleartext.
        #if DEBUG
        let nslogMsg = "[\(source.rawValue)] \(level.emoji) [\(category.rawValue.uppercased())] \(message)\(fullDetail.isEmpty ? "" : " - \(fullDetail)") \(location)"
        NSLog("%@", nslogMsg)
        #endif

        // Also log to os.Logger for Console.app/Instruments
        queue.async { [weak self] in
            guard let self = self else { return }
            if let osLogger = self.osLoggers[category] {
                let osMsg = "\(message)\(fullDetail.isEmpty ? "" : " - \(fullDetail)") \(location)"
                #if DEBUG
                osLogger.log(level: level.osLogType, "\(osMsg, privacy: .public)")
                #else
                // Default (.private) redaction: message content stays out of
                // sysdiagnoses and paired-Mac log captures in release builds.
                osLogger.log(level: level.osLogType, "\(osMsg)")
                #endif
            }
        }
    }
}

// MARK: - Convenience Extensions

public extension TalkieLogger {
    /// Quick error log with just an Error object
    static func error(_ category: LogCategory, error: Error, file: String = #file, line: Int = #line) {
        shared.log(level: .error, category: category, message: error.localizedDescription, detail: nil, error: nil, file: file, line: line)
    }
}

// MARK: - Log (Per-File Logger)

/// Lightweight per-file logger with fixed category
///
/// Usage:
/// ```swift
/// // At top of file
/// private let log = Log(.keyboard)
///
/// // Throughout file
/// log.info("Started")
/// log.error("Failed", error: error)
/// log.debug("Details: \(value)")
/// ```
public struct Log: Sendable {
    private let category: LogCategory

    public init(_ category: LogCategory) {
        self.category = category
    }

    public func debug(_ message: String, detail: String? = nil, file: String = #file, line: Int = #line) {
        TalkieLogger.debug(category, message, detail: detail, file: file, line: line)
    }

    public func info(_ message: String, detail: String? = nil, file: String = #file, line: Int = #line) {
        TalkieLogger.info(category, message, detail: detail, file: file, line: line)
    }

    public func warning(_ message: String, detail: String? = nil, error: Error? = nil, file: String = #file, line: Int = #line) {
        TalkieLogger.warning(category, message, detail: detail, error: error, file: file, line: line)
    }

    public func error(_ message: String, detail: String? = nil, error: Error? = nil, file: String = #file, line: Int = #line) {
        TalkieLogger.error(category, message, detail: detail, error: error, file: file, line: line)
    }

    public func error(_ error: Error, file: String = #file, line: Int = #line) {
        TalkieLogger.error(category, error.localizedDescription, file: file, line: line)
    }

    public func fault(_ message: String, detail: String? = nil, error: Error? = nil, file: String = #file, line: Int = #line) {
        TalkieLogger.fault(category, message, detail: detail, error: error, file: file, line: line)
    }
}
