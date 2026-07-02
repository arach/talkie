//
//  TalkieMotion.swift
//  Talkie iOS
//
//  Single gate for decorative motion. True when either the system Reduce
//  Motion setting or the app's own LOOK toggle asks for calm.
//
//  Rule of thumb: data-driven surfaces (waveforms fed by live audio levels)
//  don't gate — their motion IS the signal and it stills when the signal
//  does. Cosmetic loops (pulses, marquees, generating glyphs, repeatForever
//  of any kind) must check this before starting, or pass it to
//  `TimelineView(.animation(paused:))`.
//

import UIKit

@MainActor
enum TalkieMotion {
    static var isReduced: Bool {
        UIAccessibility.isReduceMotionEnabled || TalkieAppSettings.shared.reduceMotionEnabled
    }
}
