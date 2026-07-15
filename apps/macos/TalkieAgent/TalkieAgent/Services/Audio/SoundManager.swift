//
//  SoundManager.swift
//  TalkieAgent
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
    case basso = "basso"
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
        case .basso: return "Basso"
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
        case .basso: return "Basso"
        case .sosumi: return "Sosumi"
        }
    }
}

// MARK: - Sound Manager

@MainActor
final class SoundManager {
    static let shared = SoundManager()

    private var activeSounds: [NSSound] = []

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

    func playMicRecoveryStarted() {
        playSubtle(.tink, volume: 0.12)
    }

    func playMicRecoverySucceeded() {
        playSubtle(.pop, volume: 0.16)
    }

    func playMicRecoveryDegraded() {
        playSubtle(.submarine, volume: 0.12)
    }

    func playMicRecoveryFailed() {
        playSubtle(.basso, volume: 0.15)
    }

    /// Play error sound when paste is blocked (e.g., missing accessibility permission)
    func playPasteBlocked() {
        play(.basso)
    }

    /// Play sound for graceful cancellations (dev builds only)
    func playCancelled() {
        #if DEBUG
        play(LiveSettings.shared.cancelledSound)
        #endif
    }

    // Preview a sound (for settings UI)
    func preview(_ sound: TalkieSound) {
        play(sound)
    }

    private func playSubtle(_ sound: TalkieSound, volume: Float) {
        guard isAudioFeedbackEnabled,
              let name = sound.systemSoundName,
              let soundURL = Self.systemSoundURL(named: name),
              let player = NSSound(contentsOf: soundURL, byReference: true) else { return }

        player.volume = volume
        activeSounds.append(player)
        player.play()

        Task { @MainActor [weak self, weak player] in
            try? await Task.sleep(for: .seconds(3))
            guard let self else { return }
            self.activeSounds.removeAll { activeSound in
                guard let player else { return true }
                return activeSound === player
            }
        }
    }

    private var isAudioFeedbackEnabled: Bool {
        let settings = LiveSettings.shared
        return settings.startSound != .none
            || settings.finishSound != .none
            || settings.pastedSound != .none
            || settings.cancelledSound != .none
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
