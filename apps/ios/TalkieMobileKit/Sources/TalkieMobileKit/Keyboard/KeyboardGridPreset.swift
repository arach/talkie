//
//  KeyboardGridPreset.swift
//  TalkieMobileKit
//
//  Presets for slot-grid density in TalkieKeys.
//

import Foundation

public enum KeyboardGridPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case sixteen
    case twelve
    case nine
    case six

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sixteen: return "16-Key"
        case .twelve: return "12-Key"
        case .nine: return "9-Key"
        case .six: return "6-Key"
        }
    }

    /// Rows are listed top-to-bottom.
    public var slotRows: [[Int]] {
        switch self {
        case .sixteen:
            return [
                [9, 10, 11, 12],
                [5, 6, 7, 8],
                [1, 2, 3, 4]
            ]
        case .twelve:
            return [
                [9, 10, 11, 12],
                [5, 6, 7, 8]
            ]
        case .nine:
            return [
                [10, 11, 12],
                [7, 8, 9],
                [4, 5, 6]
            ]
        case .six:
            return [
                [10, 11, 12],
                [7, 8, 9]
            ]
        }
    }

    public var columnCount: Int {
        slotRows.first?.count ?? 4
    }
}
