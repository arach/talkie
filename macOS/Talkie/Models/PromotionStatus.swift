//
//  PromotionStatus.swift
//  Talkie
//
//  Tracks what happened to a Live after capture
//

import Foundation

enum PromotionStatus: String, Codable, CaseIterable {
    case none       // Just a Live, no follow-up
    case memo       // Promoted to a Talkie memo
    case command    // Turned into a workflow/command
    case ignored    // Explicitly marked as "don't bother me again"

    var displayName: String {
        switch self {
        case .none: return "Raw"
        case .memo: return "Memo"
        case .command: return "Command"
        case .ignored: return "Ignored"
        }
    }
}
