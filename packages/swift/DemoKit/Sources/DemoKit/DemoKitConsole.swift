//
//  DemoKitConsole.swift
//  DemoKit
//
//  Package-local console adapter for demo diagnostics.
//

import Darwin
import Foundation

enum DemoKitConsole {
    static func info(_ message: Any = "") {
        fputs("\(String(describing: message))\n", stdout)
    }

    static func formatted(_ format: String, _ arguments: CVarArg...) {
        info(String(format: format, arguments: arguments))
    }
}
