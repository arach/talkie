//
//  AgentVoiceAudioMeter.swift
//  TalkieAgent
//
//  Two jobs on one audio tap:
//
//    1. Real-time mic RMS → onLevel callback. Drives the scope trace
//       amplitude in AgentVoiceScopeView.
//    2. Lazy WAV file capture → recordedFileURL on stop. Hands the
//       transcript stage a file path that EngineClient can read.
//
//  Single AVAudioEngine, single tap. Cheaper than running two parallel
//  audio inputs and avoids fighting over the default input device.
//

import AVFoundation
import TalkieKit

private let log = Log(.audio)

@MainActor
final class AgentVoiceAudioMeter {
    private let engine = AVAudioEngine()
    private let onLevel: (Float) -> Void
    private var audioFile: AVAudioFile?
    private var fileURL: URL?
    private var isRunning = false
    private var capturedFrameCount: AVAudioFramePosition = 0
    private let minimumCapturedFileSize = 1000

    /// Set after `stop()`. Caller owns cleanup once consumed.
    private(set) var recordedFileURL: URL?

    init(onLevel: @escaping (Float) -> Void) {
        self.onLevel = onLevel
    }

    func start() {
        guard !isRunning else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard format.channelCount > 0 else {
            log.error("Agent voice meter: input bus has 0 channels, skipping start")
            return
        }

        // Allocate a fresh temp file URL — created lazily on first
        // buffer so we match the hardware format exactly.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent_voice_\(UUID().uuidString).wav")
        fileURL = url
        audioFile = nil
        recordedFileURL = nil
        capturedFrameCount = 0

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let frameLength = Int(buffer.frameLength)
            if frameLength > 0 {
                self.capturedFrameCount += AVAudioFramePosition(frameLength)
            }

            // Level (RMS) — drives the scope trace.
            if let channelData = buffer.floatChannelData?[0] {
                if frameLength > 0 {
                    var sumSquares: Float = 0
                    for i in 0..<frameLength {
                        let s = channelData[i]
                        sumSquares += s * s
                    }
                    let rms = sqrt(sumSquares / Float(frameLength))
                    let dB = 20 * log10(max(rms, 0.000_1))
                    let normalized = max(0, min(1, (dB + 60) / 60))
                    Task { @MainActor in
                        self.onLevel(normalized)
                    }
                }
            }

            // Lazy file creation matching the buffer's actual format —
            // mirrors the proven InterstitialVoiceCommand pattern.
            if self.audioFile == nil, let url = self.fileURL {
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: buffer.format.sampleRate,
                    AVNumberOfChannelsKey: buffer.format.channelCount,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false,
                ]
                do {
                    self.audioFile = try AVAudioFile(forWriting: url, settings: settings)
                } catch {
                    log.error("Agent voice meter: failed to open audio file — \(error.localizedDescription)")
                }
            }

            if let file = self.audioFile {
                do {
                    try file.write(from: buffer)
                } catch {
                    log.error("Agent voice meter: write failed — \(error.localizedDescription)")
                }
            }
        }

        do {
            try engine.start()
            isRunning = true
            log.info("Agent voice meter started (rate=\(format.sampleRate), ch=\(format.channelCount))")
        } catch {
            log.error("Agent voice meter failed to start: \(error.localizedDescription)")
            input.removeTap(onBus: 0)
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        // Flush by dropping the AVAudioFile reference — its deinit
        // closes the file. Promote the captured URL so the caller
        // can transcribe.
        let capturedURL = fileURL
        let capturedFrames = capturedFrameCount
        audioFile = nil
        fileURL = nil
        capturedFrameCount = 0

        if let capturedURL {
            let fileSize = ((try? FileManager.default.attributesOfItem(atPath: capturedURL.path))?[.size] as? NSNumber)?.intValue ?? 0
            if capturedFrames > 0 && fileSize > minimumCapturedFileSize {
                recordedFileURL = capturedURL
            } else {
                try? FileManager.default.removeItem(at: capturedURL)
                recordedFileURL = nil
                log.info("Agent voice meter stopped without usable audio", detail: "frames=\(capturedFrames) bytes=\(fileSize)")
            }
        } else {
            recordedFileURL = nil
        }

        Task { @MainActor in
            self.onLevel(0)
        }
        log.info("Agent voice meter stopped")
    }
}
