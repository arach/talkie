//
//  HistoryViewStubs.swift
//  Talkie
//
//  Minimal stubs for History View components
//

import SwiftUI
import os.log

// MARK: - Stubs for HistoryView

// StatusBar is now implemented in Views/Live/Components/StatusBar.swift

struct LogViewerConsole: View {
    var body: some View {
        // Reuse Talkie's existing SystemLogsView
        SystemLogsView()
    }
}

// MARK: - AppLogger

@Observable
final class AppLogger {
    static let shared = AppLogger()

    private let logger = Logger(subsystem: "jdi.talkie", category: "AppLogger")

    enum Category {
        case system, file, transcription, error, debug, ui, database
    }

    func log(_ category: Category, _ message: String, detail: String = "") {
        logger.info("\(message): \(detail)")
    }

    func error(_ category: Category, _ message: String, detail: String = "") {
        logger.error("\(message): \(detail)")

        // Notify Performance Monitor about error during active action
        Task { @MainActor in
            let fullMessage = detail.isEmpty ? message : "\(message): \(detail)"
            PerformanceMonitor.shared.recordWarning(fullMessage)
        }
    }

    func warning(_ category: Category, _ message: String, detail: String = "") {
        logger.warning("\(message): \(detail)")

        // Notify Performance Monitor about warning during active action
        Task { @MainActor in
            let fullMessage = detail.isEmpty ? message : "\(message): \(detail)"
            PerformanceMonitor.shared.recordWarning(fullMessage)
        }
    }
}

// MARK: - TranscriptRouter Stub

struct TranscriptRouter {
    enum Mode {
        case paste
    }

    let mode: Mode

    func handle(transcript: String) async {
        // Simple stub - just copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
}

// MARK: - Notification Names for HistoryView

extension Notification.Name {
    static let switchToLogs = Notification.Name("switchToLogs")
    static let switchToRecent = Notification.Name("switchToRecent")
    static let switchToSettings = Notification.Name("switchToSettings")
    static let switchToSettingsAudio = Notification.Name("switchToSettingsAudio")
    static let switchToSettingsEngine = Notification.Name("switchToSettingsEngine")
    static let selectUtterance = Notification.Name("selectUtterance")
    static let selectDictation = Notification.Name("selectDictation")  // Alias for selectUtterance
    static let navigateToLive = Notification.Name("navigateToLive")
}
