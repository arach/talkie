//
//  SoundManager.swift
//  TalkieLive
//
//  Audio feedback for recording events
//

import Foundation
import AppKit
import AVFoundation

// MARK: - Sound Options

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
}

// MARK: - Sound Manager

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private init() {}

    func play(_ sound: TalkieSound) {
        guard let name = sound.systemSoundName else { return }

        if let soundURL = Self.systemSoundURL(named: name) {
            var soundID: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID)
            AudioServicesPlaySystemSound(soundID)
        } else {
            // Fallback to NSSound
            NSSound(named: NSSound.Name(name))?.play()
        }
    }

    func playStart() {
        play(LiveSettings.shared.startSound)
    }

    func playFinish() {
        play(LiveSettings.shared.finishSound)
    }

    func playPasted() {
        play(LiveSettings.shared.pastedSound)
    }

    // Preview a sound (for settings UI)
    func preview(_ sound: TalkieSound) {
        play(sound)
    }

    private static func systemSoundURL(named name: String) -> URL? {
        let paths = [
            "/System/Library/Sounds/\(name).aiff",
            "/System/Library/Sounds/\(name).wav",
            "/System/Library/Sounds/\(name).mp3"
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
