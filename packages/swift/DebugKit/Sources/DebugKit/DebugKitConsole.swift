//
//  DebugKitConsole.swift
//  DebugKit
//
//  Package-local console adapter for debug tooling output.
//

import Darwin
import Foundation

enum DebugKitConsole {
    static func info(_ message: Any = "") {
        fputs("\(String(describing: message))\n", stdout)
    }

    static func formatted(_ format: String, _ arguments: CVarArg...) {
        info(String(format: format, arguments: arguments))
    }
}
