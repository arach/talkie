//
//  HeadlessConsole.swift
//  TalkieHeadless
//
//  Compatibility adapter for old print-style diagnostics.
//

import Foundation
import TalkieKit

enum HeadlessConsole {
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
