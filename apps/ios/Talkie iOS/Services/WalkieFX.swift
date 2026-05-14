//
//  WalkieFX.swift
//  Talkie iOS
//
//  Synthesized walkie-talkie kerchunk + squelch tail used to bookend
//  AI response playback. No audio assets are shipped; buffers are
//  generated deterministically at runtime and cached for reuse.
//

import Foundation
import AVFoundation

@MainActor
final class WalkieFX {
    static let shared = WalkieFX()

    private let sampleRate: Double = 44100
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let voicePlayer = AVAudioPlayerNode()
    private let voiceVarispeed = AVAudioUnitVarispeed()
    private let voiceEQ = AVAudioUnitEQ(numberOfBands: 3)
    private let format: AVAudioFormat
    private let voiceFormat: AVAudioFormat
    private let fallbackPlayer = AudioPlayerManager()

    private var engineStarted = false
    private var kerchunkBuffer: AVAudioPCMBuffer?
    private var tailBuffer: AVAudioPCMBuffer?

    private init() {
        // Mono float32 at 44.1kHz. Connecting through the main mixer lets
        // CoreAudio convert to the output hardware format as needed.
        self.format = AVAudioFormat(
            standardFormatWithSampleRate: 44100,
            channels: 1
        ) ?? AVAudioFormat()
        self.voiceFormat = AVAudioFormat(
            standardFormatWithSampleRate: 44100,
            channels: 2
        ) ?? AVAudioFormat()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        configureVoiceChain()
    }

    private func configureVoiceChain() {
        let highPass = voiceEQ.bands[0]
        highPass.filterType = .highPass
        highPass.frequency = 420
        highPass.bandwidth = 1.6
        highPass.bypass = false

        let lowPass = voiceEQ.bands[1]
        lowPass.filterType = .lowPass
        lowPass.frequency = 2700
        lowPass.bandwidth = 1.6
        lowPass.bypass = false

        let presence = voiceEQ.bands[2]
        presence.filterType = .parametric
        presence.frequency = 1600
        presence.bandwidth = 1.0
        presence.gain = 4.5
        presence.bypass = false

        voiceEQ.globalGain = 0

        engine.attach(voicePlayer)
        engine.attach(voiceVarispeed)
        engine.attach(voiceEQ)
        engine.connect(voicePlayer, to: voiceVarispeed, format: voiceFormat)
        engine.connect(voiceVarispeed, to: voiceEQ, format: voiceFormat)
        engine.connect(voiceEQ, to: engine.mainMixerNode, format: voiceFormat)
    }

    // MARK: - Public API

    func playOpeningClick() {
        guard ensureRunning(), let buffer = kerchunk() else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    /// Plays a chunk of TTS audio data through a fixed radio-voice filter
    /// chain (high-pass + low-pass + presence peak). Returns immediately;
    /// the caller is responsible for its own duration-based scheduling.
    /// Falls back to plain `AudioPlayerManager` playback if anything fails.
    func playVoiceAudio(data: Data, playbackRate: Float = 1.0) async {
        voiceVarispeed.rate = playbackRate > 0 ? playbackRate : 1.0

        guard ensureRunning() else {
            AppLogger.ai.warning("WalkieFX voice engine unavailable; using unfiltered playback")
            fallbackPlayer.setPlaybackRate(playbackRate)
            fallbackPlayer.playAudio(data: data)
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkie-voice-\(UUID().uuidString).audio")

        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            AppLogger.ai.warning("WalkieFX failed to stage TTS data: \(error.localizedDescription)")
            fallbackPlayer.setPlaybackRate(playbackRate)
            fallbackPlayer.playAudio(data: data)
            return
        }

        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let file = try AVAudioFile(forReading: tempURL)
            let processingFormat = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCount) else {
                throw NSError(domain: "WalkieFX", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to allocate decode buffer"
                ])
            }
            try file.read(into: buffer)

            if voicePlayer.isPlaying {
                voicePlayer.stop()
            }
            voicePlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            if !voicePlayer.isPlaying {
                voicePlayer.play()
            }
        } catch {
            AppLogger.ai.warning("WalkieFX voice decode failed: \(error.localizedDescription); falling back to plain playback")
            fallbackPlayer.setPlaybackRate(playbackRate)
            fallbackPlayer.playAudio(data: data)
        }
    }

    /// Schedules a squelch tail followed by a closing kerchunk so that the
    /// tail begins `delay` seconds from now (i.e. lined up with the end of
    /// the spoken audio).
    func playClosingSequence(after delay: TimeInterval) {
        guard ensureRunning(),
              let tail = tail(),
              let click = kerchunk() else { return }

        let safeDelay = max(0, delay)
        let startTime = futureTime(secondsFromNow: safeDelay)
        player.scheduleBuffer(tail, at: startTime, options: [], completionHandler: nil)

        let tailDuration = Double(tail.frameLength) / format.sampleRate
        let clickStart = futureTime(secondsFromNow: safeDelay + tailDuration)
        player.scheduleBuffer(click, at: clickStart, options: [], completionHandler: nil)

        if !player.isPlaying {
            player.play()
        }
    }

    // MARK: - Engine lifecycle

    @discardableResult
    private func ensureRunning() -> Bool {
        if engineStarted && engine.isRunning {
            return true
        }
        do {
            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            engineStarted = true
            return true
        } catch {
            engineStarted = false
            return false
        }
    }

    private func futureTime(secondsFromNow seconds: Double) -> AVAudioTime? {
        guard let lastRenderTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: lastRenderTime) else {
            // Player has not started yet; use sample-time relative to zero.
            let frame = AVAudioFramePosition(seconds * format.sampleRate)
            return AVAudioTime(sampleTime: frame, atRate: format.sampleRate)
        }
        let frameOffset = AVAudioFramePosition(seconds * format.sampleRate)
        return AVAudioTime(
            sampleTime: playerTime.sampleTime + frameOffset,
            atRate: format.sampleRate
        )
    }

    // MARK: - Buffer synthesis (cached)

    private func kerchunk() -> AVAudioPCMBuffer? {
        if let cached = kerchunkBuffer { return cached }
        let buffer = synthesizeKerchunk(durationMs: 70, peakGain: 0.35)
        kerchunkBuffer = buffer
        return buffer
    }

    private func tail() -> AVAudioPCMBuffer? {
        if let cached = tailBuffer { return cached }
        let buffer = synthesizeTail(durationMs: 180, gain: 0.07, fadeOutMs: 30)
        tailBuffer = buffer
        return buffer
    }

    /// Filtered noise burst with an exponential decay envelope plus a small
    /// initial transient suggesting a relay snap.
    private func synthesizeKerchunk(durationMs: Double, peakGain: Float) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount((durationMs / 1000.0) * format.sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        var lastSample: Float = 0
        let length = Float(frameCount)
        for i in 0..<Int(frameCount) {
            let t = Float(i) / length
            var env = pow(1 - t, 2.4)
            if i < 32 {
                env += pow(1 - Float(i) / 32, 3) * 0.6
            }
            let white = Float.random(in: -1...1)
            lastSample = lastSample * 0.6 + white * 0.4
            channel[i] = lastSample * env * peakGain
        }
        return buffer
    }

    /// Low-gain pink-ish noise burst with a short fade-out so it doesn't
    /// cut hard at the end of the transmission.
    private func synthesizeTail(durationMs: Double, gain: Float, fadeOutMs: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount((durationMs / 1000.0) * format.sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount

        let fadeFrames = max(1, Int((fadeOutMs / 1000.0) * format.sampleRate))
        let fadeStart = max(0, Int(frameCount) - fadeFrames)
        var lastSample: Float = 0
        for i in 0..<Int(frameCount) {
            let white = Float.random(in: -1...1)
            lastSample = lastSample * 0.6 + white * 0.4
            var sample = lastSample * gain
            if i >= fadeStart {
                let fadeT = Float(i - fadeStart) / Float(fadeFrames)
                sample *= (1 - fadeT)
            }
            channel[i] = sample
        }
        return buffer
    }
}
