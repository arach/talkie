//
//  AudioMemoryTracker.swift
//  TalkieAgent
//
//  Tracks audio-related memory allocations.
//  Logs when buffers are allocated/freed to identify leaks.
//

import Foundation
import TalkieKit

private let log = Log(.audio)

/// Tracks audio memory allocations
final class AudioMemoryTracker {
    static let shared = AudioMemoryTracker()

    private let lock = NSLock()

    // MARK: - Tracked Allocations

    /// PCM buffer sizes
    private var pcmBufferBytes: Int = 0

    /// Audio file buffers (AVAudioPCMBuffer allocations we know about)
    private var activeBufferCount: Int = 0

    /// Temp audio files on disk
    private var tempFiles: Set<String> = []

    private init() {}

    // MARK: - PCM Buffer Tracking

    func pcmBufferUpdated(sampleCount: Int) {
        lock.lock()
        pcmBufferBytes = sampleCount * MemoryLayout<Float>.size
        lock.unlock()

        // Only log if getting large (>1MB)
        if pcmBufferBytes > 1_000_000 {
            log.debug("PCM buffer large", detail: "\(pcmBufferBytes / 1000)KB (\(sampleCount) samples)")
        }
    }

    // MARK: - Temp File Tracking

    func tempFileCreated(path: String) {
        lock.lock()
        tempFiles.insert(path)
        let count = tempFiles.count
        lock.unlock()

        log.debug("Temp audio file created", detail: "path=\(URL(fileURLWithPath: path).lastPathComponent), total=\(count)")
    }

    func tempFileDeleted(path: String) {
        lock.lock()
        tempFiles.remove(path)
        let count = tempFiles.count
        lock.unlock()

        log.debug("Temp audio file deleted", detail: "remaining=\(count)")
    }

    var tempFileCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return tempFiles.count
    }

    // MARK: - Summary

    func logSummary() {
        lock.lock()
        let pcmKB = pcmBufferBytes / 1000
        let files = tempFiles.count
        lock.unlock()

        log.info("Audio memory summary", detail: "pcm=\(pcmKB)KB, temp_files=\(files)")
    }

    /// Get summary as dictionary for MemoryMonitor
    var summary: [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return [
            "pcm_buffer_kb": pcmBufferBytes / 1000,
            "temp_files": tempFiles.count
        ]
    }
}
