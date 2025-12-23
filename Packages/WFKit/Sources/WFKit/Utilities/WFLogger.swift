import Foundation
import os.log

// MARK: - WFLogger

/// Centralized logging for WFKit with categories and levels
public enum WFLogger {
    /// Log categories for filtering
    public enum Category: String {
        case canvas = "Canvas"
        case connection = "Connection"
        case node = "Node"
        case gesture = "Gesture"
        case state = "State"
        case ui = "UI"
        case hitTest = "HitTest"
    }

    /// Log levels
    public enum Level: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }

        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
    }

    /// Minimum level to log (set to .debug to see everything)
    public static var minimumLevel: Level = .debug

    /// Whether logging is enabled
    public static var isEnabled: Bool = true

    /// Whether to also print to console (in addition to os_log)
    public static var printToConsole: Bool = true

    /// OSLog subsystem
    private static let subsystem = "com.wfkit"

    /// Get or create logger for a category
    private static func logger(for category: Category) -> OSLog {
        OSLog(subsystem: subsystem, category: category.rawValue)
    }

    // MARK: - Logging Methods

    public static func debug(_ message: String, category: Category = .state) {
        log(message, level: .debug, category: category)
    }

    public static func info(_ message: String, category: Category = .state) {
        log(message, level: .info, category: category)
    }

    public static func warning(_ message: String, category: Category = .state) {
        log(message, level: .warning, category: category)
    }

    public static func error(_ message: String, category: Category = .state) {
        log(message, level: .error, category: category)
    }

    /// Main logging function
    public static func log(_ message: String, level: Level, category: Category) {
        guard isEnabled, level >= minimumLevel else { return }

        let formattedMessage = "\(level.emoji) [\(category.rawValue)] \(message)"

        // Log to os_log
        os_log("%{public}@", log: logger(for: category), type: level.osLogType, formattedMessage)

        // Also print to console for terminal visibility
        if printToConsole {
            print(formattedMessage)
        }
    }

    // MARK: - Convenience Methods for Common Operations

    /// Log a connection operation
    public static func connection(_ operation: String, details: String? = nil) {
        var message = operation
        if let details = details {
            message += "\n   \(details)"
        }
        debug(message, category: .connection)
    }

    /// Log a gesture event
    public static func gesture(_ event: String, details: String? = nil) {
        var message = event
        if let details = details {
            message += " - \(details)"
        }
        debug(message, category: .gesture)
    }

    /// Log state changes
    public static func state(_ change: String, before: Any? = nil, after: Any? = nil) {
        var message = change
        if let before = before {
            message += "\n   Before: \(before)"
        }
        if let after = after {
            message += "\n   After: \(after)"
        }
        debug(message, category: .state)
    }

    /// Log hit test events
    public static func hitTest(_ event: String, details: String? = nil) {
        var message = event
        if let details = details {
            message += "\n   \(details)"
        }
        debug(message, category: .hitTest)
    }
}

// MARK: - Global Shorthand

/// Shorthand for quick logging
public func wfLog(_ message: String, level: WFLogger.Level = .debug, category: WFLogger.Category = .state) {
    WFLogger.log(message, level: level, category: category)
}
