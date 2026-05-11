//
//  RoutingMode.swift
//  Talkie
//
//  Routing mode for Live transcripts
//

import Foundation

enum RoutingMode: String, CaseIterable, Codable {
    case clipboardOnly = "clipboardOnly"  // Copy to clipboard only
    case paste = "paste"                  // Copy to clipboard and paste (⌘V)

    var displayName: String {
        switch self {
        case .clipboardOnly: return "Clipboard Only"
        case .paste: return "Copy & Paste"
        }
    }

    var description: String {
        switch self {
        case .clipboardOnly: return "Copy text to clipboard without pasting"
        case .paste: return "Copy to clipboard and automatically paste"
        }
    }
}
