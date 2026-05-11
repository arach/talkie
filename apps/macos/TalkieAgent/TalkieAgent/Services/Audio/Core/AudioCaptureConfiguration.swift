//
//  AudioCaptureConfiguration.swift
//  TalkieAgent
//
//  Shared capture format configuration.
//

import AVFoundation
import TalkieKit

private let log = Log(.audio)

enum AudioCaptureConfiguration {
    static let bufferSize: AVAudioFrameCount = 4096
    static let preferredSampleRate: Double = 48_000
    static let preferredChannelCount: AVAudioChannelCount = 1

    /// Create output format matching hardware sample rate, downmixed to mono.
    /// Returns nil if format creation fails (invalid sample rate, etc.)
    static func outputFormat(for inputFormat: AVAudioFormat) -> AVAudioFormat {
        guard inputFormat.sampleRate > 0 else {
            log.error("Invalid input format: sample rate is 0")
            // Fall back to preferred sample rate
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: preferredSampleRate,
                channels: preferredChannelCount,
                interleaved: false
            )!
        }

        // Match hardware sample rate for reliability; downmix to preferred channel count.
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: preferredChannelCount,
            interleaved: false
        ) else {
            log.error("Failed to create output format", detail: "sampleRate=\(inputFormat.sampleRate)")
            // Fall back to preferred format
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: preferredSampleRate,
                channels: preferredChannelCount,
                interleaved: false
            )!
        }

        return format
    }
}
