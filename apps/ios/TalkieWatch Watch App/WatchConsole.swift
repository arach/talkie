//
//  WatchConsole.swift
//  TalkieWatch Watch App
//
//  Compatibility adapter for old print-style watch diagnostics.
//

import Foundation
import TalkieMobileKit

enum WatchConsole {
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
}
