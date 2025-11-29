//
//  AppLogger.swift
//  talkie
//
//  Centralized logging using os.Logger for the Talkie app.
//

import os
import Foundation
import SwiftUI

/// In-memory log entry for display in debug UI
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String

    enum LogLevel: String {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"

        var color: Color {
            switch self {
            case .info: return .secondary
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

/// Observable log store for displaying recent logs in UI
class LogStore: ObservableObject {
    static let shared = LogStore()

    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 100

    private init() {}

    func add(level: LogEntry.LogLevel, category: String, message: String) {
        DispatchQueue.main.async {
            let entry = LogEntry(timestamp: Date(), level: level, category: category, message: message)
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                self.entries = Array(self.entries.prefix(self.maxEntries))
            }
        }
    }

    func clear() {
        DispatchQueue.main.async {
            self.entries.removeAll()
        }
    }

    /// Filter to show only errors and warnings
    var importantEntries: [LogEntry] {
        entries.filter { $0.level == .error || $0.level == .warning }
    }
}

/// Wrapper around os.Logger that also captures to LogStore
struct CapturedLogger {
    private let osLogger: Logger
    private let category: String

    init(subsystem: String, category: String) {
        self.osLogger = Logger(subsystem: subsystem, category: category)
        self.category = category
    }

    func debug(_ message: String) {
        osLogger.debug("\(message)")
        // Don't capture debug to LogStore - too verbose
    }

    func info(_ message: String) {
        osLogger.info("\(message)")
        LogStore.shared.add(level: .info, category: category, message: message)
    }

    func warning(_ message: String) {
        osLogger.warning("\(message)")
        LogStore.shared.add(level: .warning, category: category, message: message)
    }

    func error(_ message: String) {
        osLogger.error("\(message)")
        LogStore.shared.add(level: .error, category: category, message: message)
    }
}

/// Centralized loggers for different subsystems of the app
enum AppLogger {
    private static let subsystem = "jdi.talkie-os"

    /// General app lifecycle and background tasks
    static let app = CapturedLogger(subsystem: subsystem, category: "App")

    /// Audio recording operations
    static let recording = CapturedLogger(subsystem: subsystem, category: "Recording")

    /// Audio playback operations
    static let playback = CapturedLogger(subsystem: subsystem, category: "Playback")

    /// Speech transcription
    static let transcription = CapturedLogger(subsystem: subsystem, category: "Transcription")

    /// Core Data and persistence
    static let persistence = CapturedLogger(subsystem: subsystem, category: "Persistence")

    /// UI and view-related logging
    static let ui = CapturedLogger(subsystem: subsystem, category: "UI")
}
