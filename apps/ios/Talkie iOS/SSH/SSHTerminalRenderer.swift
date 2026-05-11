//
//  SSHTerminalRenderer.swift
//  Talkie iOS
//
//  Terminal rendering backends available to the SSH screen.
//

import Foundation

enum SSHTerminalRenderer: String, CaseIterable {
    case ghostty
    case web

    var title: String {
        switch self {
        case .ghostty:
            "Ghostty"
        case .web:
            "Web"
        }
    }

    var summary: String {
        switch self {
        case .ghostty:
            "Native terminal rendering with the existing Talkie keyboard and SSH session."
        case .web:
            "Current xterm.js path in a web view."
        }
    }

    static var availableCases: [SSHTerminalRenderer] {
        allCases
    }
}
