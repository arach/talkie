//
//  WalkieFX.swift
//  Talkie iOS
//
//  Synthesized walkie-talkie kerchunk + squelch tail used to bookend
//  AI response playback. No audio assets are shipped; buffers are
//  generated deterministically at runtime and cached for reuse.
//

import Foundation
@preconcurrency import AVFoundation
import Observation

@MainActor
@Observable
final class WalkieFX {
    static let shared = WalkieFX()

    private(set) var voicePlaybackState: VoicePlaybackState = .idle
    private(set) var voicePlaybackProgress: Double = 0
    private(set) var voicePlaybackDuration: TimeInterval = 0
    private(set) var voiceWaveform: [Double] = []
    private(set) var voicePlaybackTranscript: String = ""
    private(set) var voicePlaybackTitle: String?

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
    private var voicePlaybackElapsed: TimeInterval = 0
    private var voicePlaybackStartedAt: Date?
    private var voiceProgressTask: Task<Void, Never>?
    private var isUsingFallbackVoicePlayback = false
    private var voicePlaybackFile: AVAudioFile?
    private var voicePlaybackFileURL: URL?

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
    /// chain (high-pass + low-pass + presence peak). Returns its effective
    /// duration while this player owns progress, pause, resume, and completion.
    /// Falls back to plain `AudioPlayerManager` playback if anything fails.
    @discardableResult
    func playVoiceAudio(
        data: Data,
        playbackRate: Float = 1.0,
        transcript: String = "",
        title: String? = nil
    ) async -> TimeInterval {
        voiceVarispeed.rate = playbackRate > 0 ? playbackRate : 1.0
        voicePlaybackTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        voicePlaybackTitle = normalizedTitle?.isEmpty == false ? normalizedTitle : nil
        AppLogger.ai.info("WalkieFX voice requested bytes=\(data.count) rate=\(voiceVarispeed.rate)")

        guard ensureRunning() else {
            AppLogger.ai.warning("WalkieFX voice engine unavailable; using unfiltered playback")
            return playFallbackVoiceAudio(data: data, playbackRate: playbackRate)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkie-voice-\(UUID().uuidString).audio")

        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            AppLogger.ai.warning("WalkieFX failed to stage TTS data: \(error.localizedDescription)")
            return playFallbackVoiceAudio(data: data, playbackRate: playbackRate)
        }

        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let file = try AVAudioFile(forReading: tempURL)
            let processingFormat = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            AppLogger.ai.info(
                "WalkieFX voice decoded frames=\(frameCount) rate=\(processingFormat.sampleRate) "
                    + "channels=\(processingFormat.channelCount)"
            )
            guard frameCount > 0,
                  let decodedBuffer = AVAudioPCMBuffer(
                      pcmFormat: processingFormat,
                      frameCapacity: frameCount
                  ) else {
                throw NSError(domain: "WalkieFX", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to allocate decode buffer"
                ])
            }
            try file.read(into: decodedBuffer)

            let playbackBuffer = try makeVoicePlaybackBuffer(from: decodedBuffer)
            let duration = effectiveDuration(
                frameLength: playbackBuffer.frameLength,
                sampleRate: playbackBuffer.format.sampleRate,
                playbackRate: voiceVarispeed.rate
            )
            AppLogger.ai.info(
                "WalkieFX voice ready frames=\(playbackBuffer.frameLength) "
                    + "rate=\(playbackBuffer.format.sampleRate) "
                    + "channels=\(playbackBuffer.format.channelCount)"
            )

            if voicePlayer.isPlaying {
                voicePlayer.stop()
            }
            clearVoicePlaybackFile()
            let stagedVoice = try stageVoicePlaybackFile(from: playbackBuffer)
            isUsingFallbackVoicePlayback = false
            voicePlaybackFile = stagedVoice.file
            voicePlaybackFileURL = stagedVoice.url
            scheduleVoicePlaybackSegment(startingAt: 0)
            if !voicePlayer.isPlaying {
                voicePlayer.play()
            }
            beginVoicePlayback(
                duration: duration,
                waveform: waveformSamples(from: playbackBuffer)
            )
            AppLogger.ai.info("WalkieFX voice scheduled playing=\(voicePlayer.isPlaying)")
            return duration
        } catch {
            AppLogger.ai.warning("WalkieFX voice decode failed: \(error.localizedDescription); falling back to plain playback")
            return playFallbackVoiceAudio(data: data, playbackRate: playbackRate)
        }
    }

    var isVoicePlaybackActive: Bool {
        voicePlaybackState != .idle
    }

    var voicePlaybackCurrentTime: TimeInterval {
        voicePlaybackProgress * voicePlaybackDuration
    }

    func toggleVoicePlayback() {
        switch voicePlaybackState {
        case .idle:
            return
        case .playing:
            pauseVoicePlayback()
        case .paused:
            resumeVoicePlayback()
        }
    }

    func pauseVoicePlayback() {
        guard voicePlaybackState == .playing else { return }
        updateVoicePlaybackProgress()
        voicePlaybackElapsed = voicePlaybackProgress * voicePlaybackDuration
        voicePlaybackStartedAt = nil
        voiceProgressTask?.cancel()
        voiceProgressTask = nil

        if isUsingFallbackVoicePlayback {
            fallbackPlayer.pausePlayback()
        } else {
            voicePlayer.pause()
        }
        voicePlaybackState = .paused
    }

    func resumeVoicePlayback() {
        guard voicePlaybackState == .paused else { return }

        if isUsingFallbackVoicePlayback {
            fallbackPlayer.resumePlayback()
        } else {
            guard ensureRunning() else { return }
            voicePlayer.play()
        }
        voicePlaybackStartedAt = Date()
        voicePlaybackState = .playing
        startVoiceProgressUpdates()
    }

    func seekVoicePlayback(to progress: Double) {
        guard isVoicePlaybackActive, voicePlaybackDuration > 0 else { return }

        let targetProgress = min(1, max(0, progress))
        if targetProgress >= 1 {
            finishVoicePlayback()
            return
        }

        let wasPlaying = voicePlaybackState == .playing
        if isUsingFallbackVoicePlayback {
            fallbackPlayer.seek(to: targetProgress * fallbackPlayer.duration)
        } else {
            guard ensureRunning(),
                  let voicePlaybackFile else { return }

            voicePlayer.stop()
            let startFrame = AVAudioFramePosition(Double(voicePlaybackFile.length) * targetProgress)
            scheduleVoicePlaybackSegment(startingAt: startFrame)
            if wasPlaying {
                voicePlayer.play()
            }
        }

        voicePlaybackProgress = targetProgress
        voicePlaybackElapsed = targetProgress * voicePlaybackDuration
        voicePlaybackStartedAt = wasPlaying ? Date() : nil
        if wasPlaying {
            startVoiceProgressUpdates()
        }
    }

    func skipVoicePlayback(by interval: TimeInterval) {
        guard voicePlaybackDuration > 0 else { return }
        let targetTime = voicePlaybackCurrentTime + interval
        seekVoicePlayback(to: targetTime / voicePlaybackDuration)
    }

    /// Converts provider-specific TTS output into the exact format used by the
    /// fixed radio filter graph. `AVAudioPlayerNode.scheduleBuffer` raises an
    /// Objective-C exception (rather than a catchable Swift error) when these
    /// formats differ, so the invariant must be established before scheduling.
    private func makeVoicePlaybackBuffer(
        from decodedBuffer: AVAudioPCMBuffer
    ) throws -> AVAudioPCMBuffer {
        let decodedFormat = decodedBuffer.format
        let alreadyMatchesVoiceGraph = decodedFormat.sampleRate == voiceFormat.sampleRate
            && decodedFormat.channelCount == voiceFormat.channelCount
            && decodedFormat.commonFormat == voiceFormat.commonFormat
            && decodedFormat.isInterleaved == voiceFormat.isInterleaved

        if alreadyMatchesVoiceGraph {
            return decodedBuffer
        }

        guard let converter = AVAudioConverter(from: decodedFormat, to: voiceFormat) else {
            throw NSError(domain: "WalkieFX", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create voice format converter"
            ])
        }

        let sampleRateRatio = voiceFormat.sampleRate / decodedFormat.sampleRate
        let convertedFrameCapacity = AVAudioFrameCount(
            ceil(Double(decodedBuffer.frameLength) * sampleRateRatio) + 32
        )
        guard convertedFrameCapacity > 0,
              let convertedBuffer = AVAudioPCMBuffer(
                  pcmFormat: voiceFormat,
                  frameCapacity: convertedFrameCapacity
              ) else {
            throw NSError(domain: "WalkieFX", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to allocate converted voice buffer"
            ])
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: convertedBuffer, error: &conversionError) {
            _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return decodedBuffer
        }

        if let conversionError {
            throw conversionError
        }
        guard status != .error, convertedBuffer.frameLength > 0 else {
            throw NSError(domain: "WalkieFX", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "Voice format conversion produced no audio"
            ])
        }

        return convertedBuffer
    }

    private func stageVoicePlaybackFile(
        from buffer: AVAudioPCMBuffer
    ) throws -> (file: AVAudioFile, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkie-voice-normalized-\(UUID().uuidString).caf")
        do {
            var writer: AVAudioFile? = try AVAudioFile(
                forWriting: url,
                settings: buffer.format.settings,
                commonFormat: buffer.format.commonFormat,
                interleaved: buffer.format.isInterleaved
            )
            try writer?.write(from: buffer)
            writer = nil
            return (try AVAudioFile(forReading: url), url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func scheduleVoicePlaybackSegment(startingAt requestedFrame: AVAudioFramePosition) {
        guard let voicePlaybackFile else { return }
        let startFrame = min(max(0, requestedFrame), max(0, voicePlaybackFile.length - 1))
        let remainingFrames = AVAudioFrameCount(voicePlaybackFile.length - startFrame)
        guard remainingFrames > 0 else { return }
        voicePlayer.scheduleSegment(
            voicePlaybackFile,
            startingFrame: startFrame,
            frameCount: remainingFrames,
            at: nil,
            completionHandler: nil
        )
    }

    private func clearVoicePlaybackFile() {
        voicePlaybackFile = nil
        if let voicePlaybackFileURL {
            try? FileManager.default.removeItem(at: voicePlaybackFileURL)
        }
        voicePlaybackFileURL = nil
    }

    /// Immediately silences voice playback and any scheduled bookend FX.
    ///
    /// Used when the user starts a new capture while a response is still being
    /// read aloud. Stopping `player` matters as much as stopping `voicePlayer`:
    /// the closing squelch/kerchunk are scheduled ahead of time, so without this
    /// they would fire into the middle of the next utterance.
    func stopVoicePlayback() {
        voiceProgressTask?.cancel()
        voiceProgressTask = nil
        voicePlaybackState = .idle
        voicePlaybackProgress = 0
        voicePlaybackDuration = 0
        voicePlaybackElapsed = 0
        voicePlaybackStartedAt = nil
        voicePlaybackTranscript = ""
        voicePlaybackTitle = nil
        isUsingFallbackVoicePlayback = false
        voicePlayer.stop()
        player.stop()
        fallbackPlayer.stopPlayback()
        clearVoicePlaybackFile()
    }

    private func playFallbackVoiceAudio(data: Data, playbackRate: Float) -> TimeInterval {
        isUsingFallbackVoicePlayback = true
        clearVoicePlaybackFile()
        fallbackPlayer.setPlaybackRate(playbackRate)
        fallbackPlayer.playAudio(data: data)
        let duration = effectiveDuration(
            duration: fallbackPlayer.duration,
            playbackRate: fallbackPlayer.playbackRate
        )
        beginVoicePlayback(duration: duration, waveform: fallbackWaveform)
        return duration
    }

    private func beginVoicePlayback(duration: TimeInterval, waveform: [Double]) {
        voiceProgressTask?.cancel()
        voicePlaybackDuration = max(0, duration)
        voicePlaybackElapsed = 0
        voicePlaybackStartedAt = Date()
        voicePlaybackProgress = 0
        voiceWaveform = waveform
        voicePlaybackState = .playing
        startVoiceProgressUpdates()
    }

    private func startVoiceProgressUpdates() {
        voiceProgressTask?.cancel()
        voiceProgressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled, let self else { return }
                guard self.voicePlaybackState == .playing else { return }
                self.updateVoicePlaybackProgress()
                if self.voicePlaybackProgress >= 1 {
                    self.finishVoicePlayback()
                    return
                }
            }
        }
    }

    private func updateVoicePlaybackProgress() {
        guard voicePlaybackDuration > 0 else { return }
        let runningElapsed = voicePlaybackStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        voicePlaybackProgress = min(1, max(0, (voicePlaybackElapsed + runningElapsed) / voicePlaybackDuration))
    }

    private func finishVoicePlayback() {
        voiceProgressTask?.cancel()
        voiceProgressTask = nil
        voicePlaybackProgress = 1
        voicePlaybackState = .idle
        voicePlaybackDuration = 0
        voicePlaybackElapsed = 0
        voicePlaybackStartedAt = nil
        voicePlaybackTranscript = ""
        voicePlaybackTitle = nil
        voicePlayer.stop()
        fallbackPlayer.stopPlayback()
        clearVoicePlaybackFile()
        playClosingSequence(after: 0)
    }

    private func effectiveDuration(
        frameLength: AVAudioFrameCount,
        sampleRate: Double,
        playbackRate: Float
    ) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return effectiveDuration(
            duration: Double(frameLength) / sampleRate,
            playbackRate: playbackRate
        )
    }

    private func effectiveDuration(duration: TimeInterval, playbackRate: Float) -> TimeInterval {
        let rate = playbackRate > 0 ? Double(playbackRate) : 1
        return duration.isFinite ? duration / rate : 0
    }

    private func waveformSamples(from buffer: AVAudioPCMBuffer, count: Int = 36) -> [Double] {
        guard count > 0,
              let channel = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else { return fallbackWaveform }

        let frameCount = Int(buffer.frameLength)
        let binSize = max(1, frameCount / count)
        var samples: [Double] = []
        samples.reserveCapacity(count)

        for bin in 0..<count {
            let start = min(frameCount - 1, bin * binSize)
            let end = min(frameCount, start + binSize)
            let strideSize = max(1, (end - start) / 96)
            var peak: Float = 0
            var frame = start
            while frame < end {
                peak = max(peak, abs(channel[frame]))
                frame += strideSize
            }
            samples.append(Double(peak))
        }

        let maximum = samples.max() ?? 0
        guard maximum > 0 else { return fallbackWaveform }
        return samples.map { min(1, max(0.16, $0 / maximum)) }
    }

    private var fallbackWaveform: [Double] {
        [0.24, 0.36, 0.52, 0.30, 0.68, 0.44, 0.78, 0.38, 0.60, 0.88, 0.50, 0.72,
         0.32, 0.62, 0.84, 0.46, 0.74, 0.40, 0.58, 0.80, 0.36, 0.66, 0.48, 0.76,
         0.30, 0.56, 0.70, 0.42, 0.82, 0.52, 0.64, 0.34, 0.72, 0.46, 0.60, 0.28]
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
        do {
            // Inline dictation releases the shared audio session as soon as the
            // mic closes. Narration owns the next phase, so it must explicitly
            // reactivate a playback session even when this engine survived the
            // previous turn. AVAudioEngine state alone does not prove that iOS
            // currently has an audible output route.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)

            if engineStarted && engine.isRunning {
                return true
            }

            if !engine.isRunning {
                engine.prepare()
                try engine.start()
            }
            engineStarted = true
            AppLogger.ai.info("WalkieFX engine running=\(engine.isRunning)")
            return true
        } catch {
            engineStarted = false
            AppLogger.ai.error("WalkieFX engine start failed: \(error.localizedDescription)")
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

enum VoicePlaybackState: Equatable {
    case idle
    case playing
    case paused
}
