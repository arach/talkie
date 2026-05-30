//
//  DictationMicMonitor.swift
//  Talkie iOS
//
//  Lightweight mic-level monitor for the Command Deck cockpit mag-
//  tape waveform. Reads the iPhone's microphone purely to animate
//  the strip — never writes to disk, never transcribes. The cockpit
//  observes `level` (0…1, smoothed) and uses it to modulate bar
//  height, scroll speed, and write-head glow. When the user is
//  silent the tape barely moves; when they speak it rolls and the
//  bars swing.
//
//  Lifecycle is reference-counted via `retain`/`release` so multiple
//  observers don't fight over the AVAudioEngine.
//

import AVFoundation
import Foundation
import SwiftUI

@MainActor
final class DictationMicMonitor: ObservableObject {
    static let shared = DictationMicMonitor()

    /// Smoothed envelope, 0…1. Reads as "how loud is the voice
    /// right now" with asymmetric attack/release so flicker stays
    /// calm between words.
    @Published private(set) var level: Double = 0

    /// Rolling ring buffer of recent envelope samples. The waveform
    /// renders one bar per sample; new samples push in on the right
    /// at the 30Hz tick rate and the oldest fall off the left. This
    /// is the "real audio" path — bars actually reflect what the
    /// mic just heard instead of a repeating synthetic seed.
    @Published private(set) var samples: [Double] = Array(repeating: 0, count: DictationMicMonitor.bufferSize)

    /// Length of the rolling buffer. At the 30Hz tick rate this is
    /// ~1.7s of recent audio history visible at any time — fewer,
    /// chunkier bars read with more character than a dense strip.
    fileprivate static let bufferSize = 50

    private let engine = AVAudioEngine()
    private var retainCount = 0
    private var smoothed: Double = 0
    private var isRunning = false
    private var phaseTimer: Timer?
    /// Tick counter from start — used to discard the first ~6 ticks
    /// (~200ms) of engine startup transients and to ease the initial
    /// attack curve so the bars don't snap to full on the first
    /// audible frame.
    private var startupTicks: Int = 0
    /// Most-recent raw RMS pushed from the audio tap callback. The
    /// 30Hz phase timer reads and smooths it — keeping the publish
    /// rate steady regardless of buffer size or sample rate so the
    /// view never gets dragged into ~50–100Hz re-render churn.
    private var pendingRMS: Double = 0

    private init() {}

    /// Begin observing. Safe to call multiple times — only the
    /// first call spins up the engine; subsequent calls just bump
    /// the retain count.
    func retain() {
        retainCount += 1
        guard !isRunning else { return }
        start()
    }

    func release() {
        retainCount = max(0, retainCount - 1)
        guard retainCount == 0, isRunning else { return }
        stop()
    }

    private func start() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true, options: [])

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                let rms = Self.rms(buffer)
                // Stash only — the 30Hz timer publishes. Avoids
                // the audio thread driving @Published changes at
                // the buffer cadence (causes view churn on big
                // sample rates).
                Task { @MainActor in
                    self?.pendingRMS = rms
                }
            }
            engine.prepare()
            try engine.start()
            isRunning = true
            startupTicks = 0

            // 30Hz integrator for level + scroll phase. Single tick,
            // single publish, so SwiftUI only re-renders observers
            // 30 times per second instead of being whipped by both
            // the audio thread and the timer in tandem.
            phaseTimer?.invalidate()
            phaseTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick(dt: 1.0 / 30.0)
                }
            }
        } catch {
            // Visualizer mic is a nice-to-have. If start fails the
            // tape still renders from its seed; don't surface.
            isRunning = false
        }
    }

    private func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        phaseTimer?.invalidate()
        phaseTimer = nil
        isRunning = false
        smoothed = 0
        level = 0
        samples = Array(repeating: 0, count: DictationMicMonitor.bufferSize)
        // Don't deactivate the AVAudioSession — other recorders or
        // the bridge may still be holding it for their own purposes.
    }

    /// Single tick — smooth the latest RMS and push it onto the
    /// rolling buffer. One @Published update per frame, so SwiftUI
    /// re-renders observers at a steady 30Hz.
    private func tick(dt: TimeInterval) {
        // RMS for normal speech sits around 0.01..0.10. Sqrt + scale
        // spreads the perceptual range so quiet voice still pushes
        // the meter without loud voice clipping at the top.
        let raw = min(1.0, sqrt(max(0, pendingRMS)) * 3.2)

        // Startup ramp: ease the attack curve from very soft (0.15)
        // up to the steady-state 0.45 over the first ~10 ticks
        // (~330ms). Without this the very first audible buffer
        // jerks the bars from flat to peak in two frames, which
        // reads as a "jumpiness" glitch right after dictation
        // arms. After ramp-up the response is snappy as usual.
        startupTicks += 1
        let rampProgress = min(1.0, Double(startupTicks) / 10.0)
        let attack = 0.15 + (0.45 - 0.15) * rampProgress

        if raw > smoothed {
            smoothed += (raw - smoothed) * attack
        } else {
            // Moderate release so peaks linger briefly — gives the
            // bars a little rebound feel between syllables.
            smoothed += (raw - smoothed) * 0.30
        }

        // Roll the buffer: drop oldest, append newest. The waveform
        // renders bars left-to-right matching this array, so the
        // shift produces the right-to-left "tape rolling" motion
        // naturally — and every bar represents a real moment of
        // audio instead of a fixed seed pattern.
        var next = samples
        next.removeFirst()
        next.append(smoothed)
        samples = next
        level = smoothed
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        var sum: Double = 0
        for i in 0..<frameCount {
            let v = Double(channelData[i])
            sum += v * v
        }
        return sqrt(sum / Double(frameCount))
    }
}
