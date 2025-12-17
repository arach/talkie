//
//  TalkieSound.swift
//  Talkie
//
//  Sound options for Live recording feedback
//

import Foundation

enum TalkieSound: String, CaseIterable, Codable {
    case none = "none"
    case pop = "pop"
    case tink = "tink"
    case morse = "morse"
    case ping = "ping"
    case purr = "purr"
    case submarine = "submarine"
    case blow = "blow"
    case bottle = "bottle"
    case frog = "frog"
    case funk = "funk"
    case glass = "glass"
    case hero = "hero"
    case sosumi = "sosumi"

    var displayName: String {
        switch self {
        case .none: return "None"
        case .pop: return "Pop"
        case .tink: return "Tink"
        case .morse: return "Morse"
        case .ping: return "Ping"
        case .purr: return "Purr"
        case .submarine: return "Submarine"
        case .blow: return "Blow"
        case .bottle: return "Bottle"
        case .frog: return "Frog"
        case .funk: return "Funk"
        case .glass: return "Glass"
        case .hero: return "Hero"
        case .sosumi: return "Sosumi"
        }
    }

    var systemSoundName: String? {
        switch self {
        case .none: return nil
        default: return rawValue
        }
    }
}
