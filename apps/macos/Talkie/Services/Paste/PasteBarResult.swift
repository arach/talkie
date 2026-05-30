//
//  PasteBarResult.swift
//  Talkie
//
//  Paste format variants for the Quick Paste chord (Hyper+V).
//

import Foundation

// MARK: - Paste Format

enum PasteFormat: String, CaseIterable {
    case image    // PNG data → pasteboard .png
    case filePath // Absolute file path string
    case url      // http://localhost:8766/tray/<uuid>.png
    case base64   // data:image/png;base64,<encoded>
    case visionDescription // VLM UI description text
    case dragFile // Programmatic drag session with file

    var label: String {
        switch self {
        case .image:    "image"
        case .filePath: "path"
        case .url:      "url"
        case .base64:   "base64"
        case .visionDescription: "describe"
        case .dragFile: "drag"
        }
    }

    var shortLabel: String {
        switch self {
        case .image:    "IMG"
        case .filePath: "PATH"
        case .url:      "URL"
        case .base64:   "B64"
        case .visionDescription: "VLM"
        case .dragFile: "DRAG"
        }
    }

    var modifierSymbol: String {
        switch self {
        case .image:    ""
        case .filePath: "⇧"
        case .url:      "⌥"
        case .base64:   "⌃"
        case .visionDescription: "⇧⌥"
        case .dragFile: "⌘"
        }
    }

    /// Whether this format pastes via Cmd+V or uses a different delivery mechanism.
    var pastesByKeyboard: Bool {
        switch self {
        case .image, .filePath, .url, .base64, .visionDescription: true
        case .dragFile: false
        }
    }
}

// MARK: - Paste Bar Result

struct PasteBarResult {
    let item: TrayItem
    let format: PasteFormat
}
