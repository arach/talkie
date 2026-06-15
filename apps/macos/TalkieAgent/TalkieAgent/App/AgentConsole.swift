//
//  AgentConsole.swift
//  TalkieAgent
//
//  Small compatibility adapter for old print/NSLog-style call sites.
//

import Foundation
import TalkieKit

enum AgentConsole {
    static func category(named name: String) -> LogCategory {
        switch name.lowercased() {
        case "audio", "record", "recording", "audioplayback", "audiodevicemanager", "audiodiagnostics", "audioinputlogger":
            return .audio
        case "transcription":
            return .transcription
        case "database", "dictationstore", "audiostorage":
            return .database
        case "xpc":
            return .xpc
        case "sync":
            return .sync
        case "ui", "floatingpill", "sidecaroverlay":
            return .ui
        case "workflow":
            return .workflow
        default:
            return .system
        }
    }

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
