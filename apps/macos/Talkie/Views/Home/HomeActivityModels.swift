//
//  HomeActivityModels.swift
//  Talkie
//
//  Activity heatmap models for Home surfaces.
//

import SwiftUI

// MARK: - Activity Level

enum ActivityLevel: Int {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3
    case max = 4

    var color: Color {
        switch self {
        case .none: return Color.gray.opacity(0.15)
        case .low: return Color.green.opacity(0.3)
        case .medium: return Color.green.opacity(0.5)
        case .high: return Color.green.opacity(0.7)
        case .max: return Color.green
        }
    }

    static func from(count: Int, max: Int) -> ActivityLevel {
        if count <= 0 { return .none }
        if max <= 0 { return .none }
        let ratio = Double(count) / Double(max)
        switch ratio {
        case 0..<0.25: return .low
        case 0.25..<0.5: return .medium
        case 0.5..<0.75: return .high
        default: return .max
        }
    }
}

// MARK: - Day Activity

struct DayActivity: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
    let level: ActivityLevel
}
