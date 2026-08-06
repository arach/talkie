//
//  DeckMicSettings.swift
//  Talkie iOS
//
//  Which microphone a deck's dictate key opens.
//
//  A deck is a bank of controls with nothing on it — you set it down next to
//  the Mac and press keys, and the Mac does the work. So the default is the
//  host's microphone: the machine you are looking at is the machine that
//  listens, and the phone is just the thing your thumb is on.
//
//  The other mode exists for the case that breaks that assumption: you can see
//  the screen but you are across the room from it. Then the nearest microphone
//  is the one in your hand. In that mode the phone records, transcribes on
//  device, and sends only the finished words over the bridge — the audio never
//  makes the trip.
//
//  One setting, read by every deck, so the answer doesn't drift between them.
//

import Foundation
import SwiftUI

enum DeckMicSource: String, CaseIterable, Identifiable {
    /// The Mac's microphone, driven by its own dictation shortcut.
    case host
    /// This phone's microphone, transcribed on device, delivered as text.
    case phone

    var id: String { rawValue }

    var label: String {
        switch self {
        case .host: "Host mic"
        case .phone: "iPhone mic"
        }
    }

    /// Short enough for a deck key's caption, where there is no room to explain.
    var shortLabel: String {
        switch self {
        case .host: "HOST"
        case .phone: "PHONE"
        }
    }

    var systemImage: String {
        switch self {
        case .host: "desktopcomputer"
        case .phone: "iphone"
        }
    }

    var explanation: String {
        switch self {
        case .host: "The Mac listens and transcribes, the way it does when you press its own hotkey."
        case .phone: "This phone listens and transcribes on device. Only the text crosses to the Mac."
        }
    }
}

@MainActor
final class DeckMicSettings: ObservableObject {
    static let shared = DeckMicSettings()

    private static let defaultsKey = "deck.micSource"

    /// Defaults to `.host` — see the file comment. A deck with nothing on it is
    /// the normal case, and the phone mic is the exception you reach for.
    @Published var source: DeckMicSource {
        didSet {
            UserDefaults.standard.set(source.rawValue, forKey: Self.defaultsKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        source = stored.flatMap(DeckMicSource.init(rawValue:)) ?? .host
    }

    func toggle() {
        source = source == .host ? .phone : .host
    }
}
