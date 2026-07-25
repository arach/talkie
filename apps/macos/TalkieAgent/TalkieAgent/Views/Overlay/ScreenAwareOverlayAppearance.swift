//
//  ScreenAwareOverlayAppearance.swift
//  TalkieAgent
//
//  Chooses context-appropriate overlay chrome from the pixels immediately
//  beneath the overlay. A broad hysteresis band prevents visible tone-flipping
//  when the sampled content sits near middle gray.
//

import AppKit
import Observation
import SwiftUI
import TalkieKit

@MainActor
@Observable
final class ScreenAwareOverlayAppearance {
    private(set) var tone: LiveGlassTone
    private var candidateTone: LiveGlassTone?
    private var candidateSampleCount = 0

    init(tone: LiveGlassTone? = nil) {
        self.tone = tone ?? Self.fallbackTone()
    }

    func refresh(
        for screenRect: CGRect,
        excludingWindowIDs: [CGWindowID] = []
    ) async {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            tone = .graphite
            candidateTone = nil
            candidateSampleCount = 0
            return
        }

        guard let brightness = await WallpaperLuminanceSampler.sampleBrightness(
            for: screenRect,
            excludingWindowIDs: excludingWindowIDs
        ) else {
            return
        }
        apply(brightness: brightness)
    }

    func apply(brightness: CGFloat) {
        let proposedTone: LiveGlassTone?
        if brightness >= 0.62 {
            proposedTone = .pearl
        } else if brightness <= 0.45 {
            proposedTone = .graphite
        } else {
            proposedTone = nil
        }

        guard let proposedTone, proposedTone != tone else {
            candidateTone = nil
            candidateSampleCount = 0
            return
        }

        if candidateTone == proposedTone {
            candidateSampleCount += 1
        } else {
            candidateTone = proposedTone
            candidateSampleCount = 1
        }

        guard candidateSampleCount >= 3 else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            tone = proposedTone
        }
        candidateTone = nil
        candidateSampleCount = 0
    }

    static func fallbackTone() -> LiveGlassTone {
        let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return appearance == .darkAqua ? .graphite : .pearl
    }
}
