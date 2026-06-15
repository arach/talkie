//
//  TalkieConsole.swift
//  Talkie macOS
//
//  Adapter for legacy console-style diagnostics. New code should prefer a
//  feature-local `Log(...)` value directly.
//

import Foundation
import TalkieKit

enum TalkieConsole {
    static func debug(_ message: Any = "", category: LogCategory = .system) {
        TalkieLogger.debug(category, String(describing: message))
    }

    static func info(_ message: Any = "", category: LogCategory = .system) {
        TalkieLogger.info(category, String(describing: message))
    }

    static func warning(_ message: Any = "", category: LogCategory = .system) {
        TalkieLogger.warning(category, String(describing: message))
    }

    static func error(_ message: Any = "", category: LogCategory = .system) {
        TalkieLogger.error(category, String(describing: message))
    }

    static func critical(_ message: Any = "", category: LogCategory = .system) {
        TalkieLogger.info(category, String(describing: message), critical: true)
    }

    static func critical(_ format: String, _ arguments: CVarArg...) {
        critical(String(format: format, arguments: arguments), category: .system)
    }
}
