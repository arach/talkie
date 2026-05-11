//
//  AudioWriterTypes.swift
//  TalkieAgent
//
//  Types for unified audio writing system.
//

import AVFoundation

// MARK: - Audio Format

/// Audio format type for writing
enum AudioWriterFormat {
    case linearPCM
    case aac
}

// MARK: - Writer Config

/// Configuration for audio file writing
struct AudioWriterConfig {
    let format: AudioWriterFormat
    let maxChannels: Int

    /// PCM configuration (fast, no encoder flush)
    static let pcm = AudioWriterConfig(format: .linearPCM, maxChannels: 2)

    /// AAC configuration (compressed, requires encoder flush)
    static let aac = AudioWriterConfig(format: .aac, maxChannels: 2)
}

// MARK: - Writer Result

/// A single completed audio segment
struct AudioWriterSegment {
    let url: URL
    let fileSize: Int
    let duration: TimeInterval
    let index: Int
}

/// Result of finalizing an audio file
struct AudioWriterResult {
    let url: URL
    let fileSize: Int
    let bufferCount: Int
    let framesWritten: Int64
    let duration: TimeInterval
    let segments: [AudioWriterSegment]
}

// MARK: - Writer Protocol

/// Protocol for audio file writers
protocol AudioWriterProtocol {
    var isOpen: Bool { get }
    var currentURL: URL? { get }
    var currentSegmentIndex: Int { get }

    func createFile(at url: URL, format: AVAudioFormat, config: AudioWriterConfig) -> Bool
    func write(_ buffer: AVAudioPCMBuffer) -> Bool
    func finalize() -> AudioWriterResult?
    func requestCheckpoint()
}
