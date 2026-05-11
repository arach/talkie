//
//  ConsoleTypes.swift
//  TalkieKit
//
//  Shared types for console/log display across Talkie apps
//

import SwiftUI

// MARK: - Log Level

/// Standard log levels for console display
public enum ConsoleLogLevel: String, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    case fault = "FAULT"

    public var color: Color {
        switch self {
        case .debug: return Color.gray
        case .info: return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .warning: return Color.orange
        case .error: return Color(red: 1.0, green: 0.4, blue: 0.4)
        case .fault: return Color.purple
        }
    }

    public var icon: String {
        switch self {
        case .debug: return "ant"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .fault: return "bolt.circle"
        }
    }
}

// MARK: - Console Entry

/// A single log entry for display in the console
public struct ConsoleEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: ConsoleLogLevel
    public let category: String
    public let message: String
    public let detail: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: ConsoleLogLevel,
        category: String,
        message: String,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.detail = detail
    }

    /// Serialize to log line format
    public func toLogLine() -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = isoFormatter.string(from: timestamp)
        let escapedMessage = message.replacingOccurrences(of: "|", with: "\\|")
        let escapedDetail = detail?.replacingOccurrences(of: "|", with: "\\|") ?? ""
        return "\(ts)|\(level.rawValue)|\(category)|\(escapedMessage)|\(escapedDetail)"
    }

    /// Parse from log line format
    public static func fromLogLine(_ line: String) -> ConsoleEntry? {
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 4 else { return nil }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let timestamp = isoFormatter.date(from: parts[0]),
              let level = ConsoleLogLevel(rawValue: parts[1]) else { return nil }

        let category = parts[2]
        let message = parts[3].replacingOccurrences(of: "\\|", with: "|")
        let detail = parts.count > 4 && !parts[4].isEmpty
            ? parts[4].replacingOccurrences(of: "\\|", with: "|")
            : nil

        return ConsoleEntry(
            timestamp: timestamp,
            level: level,
            category: category,
            message: message,
            detail: detail
        )
    }
}

// MARK: - Console Theme

/// Theme configuration for the console
public struct ConsoleTheme {
    public let background: Color
    public let backgroundSecondary: Color
    public let foreground: Color
    public let foregroundMuted: Color
    public let divider: Color
    public let surface: Color
    public let accentColor: Color

    public init(
        background: Color = Color(red: 0.08, green: 0.08, blue: 0.1),
        backgroundSecondary: Color = Color(red: 0.1, green: 0.1, blue: 0.12),
        foreground: Color = Color(red: 0.9, green: 0.9, blue: 0.9),
        foregroundMuted: Color = Color(red: 0.5, green: 0.5, blue: 0.5),
        divider: Color = Color(red: 0.2, green: 0.2, blue: 0.22),
        surface: Color = Color(red: 0.12, green: 0.12, blue: 0.14),
        accentColor: Color = Color(red: 0.4, green: 0.8, blue: 0.4)
    ) {
        self.background = background
        self.backgroundSecondary = backgroundSecondary
        self.foreground = foreground
        self.foregroundMuted = foregroundMuted
        self.divider = divider
        self.surface = surface
        self.accentColor = accentColor
    }

    /// Default dark theme
    public static let dark = ConsoleTheme()

    /// Light theme
    public static let light = ConsoleTheme(
        background: Color(red: 0.98, green: 0.98, blue: 0.98),
        backgroundSecondary: Color(red: 0.94, green: 0.94, blue: 0.94),
        foreground: Color(red: 0.1, green: 0.1, blue: 0.1),
        foregroundMuted: Color(red: 0.5, green: 0.5, blue: 0.5),
        divider: Color(red: 0.85, green: 0.85, blue: 0.85),
        surface: Color(red: 0.92, green: 0.92, blue: 0.92),
        accentColor: Color(red: 0.2, green: 0.6, blue: 0.2)
    )
}
