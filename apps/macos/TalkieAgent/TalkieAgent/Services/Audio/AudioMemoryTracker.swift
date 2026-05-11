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

    /// Audio chunks in memory (AmbientAudioCapture)
    private var chunkAllocations: [UUID: Int] = [:]  // id -> bytes

    /// PCM buffer sizes
    private var pcmBufferBytes: Int = 0

    /// Audio file buffers (AVAudioPCMBuffer allocations we know about)
    private var activeBufferCount: Int = 0

    /// Temp audio files on disk
    private var tempFiles: Set<String> = []

    private init() {}

    // MARK: - Chunk Tracking

    func chunkAllocated(id: UUID, bytes: Int) {
        lock.lock()
        chunkAllocations[id] = bytes
        let totalMB = _totalChunkMB_locked
        let count = chunkAllocations.count
        lock.unlock()

        log.debug("Chunk allocated", detail: "\(bytes / 1000)KB, total=\(count) chunks (\(totalMB)MB)")
    }

    func chunkDeallocated(id: UUID) {
        lock.lock()
        let bytes = chunkAllocations.removeValue(forKey: id) ?? 0
        let totalMB = _totalChunkMB_locked
        let count = chunkAllocations.count
        lock.unlock()

        log.debug("Chunk freed", detail: "\(bytes / 1000)KB, remaining=\(count) chunks (\(totalMB)MB)")
    }

    /// Internal: call only when lock is already held
    private var _totalChunkBytes_locked: Int {
        chunkAllocations.values.reduce(0, +)
    }

    /// Internal: call only when lock is already held
    private var _totalChunkMB_locked: Int {
        _totalChunkBytes_locked / 1_000_000
    }

    var totalChunkBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalChunkBytes_locked
    }

    var totalChunkMB: Int {
        lock.lock()
        defer { lock.unlock() }
        return _totalChunkMB_locked
    }

    var chunkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return chunkAllocations.count
    }

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
        let chunks = chunkAllocations.count
        let chunkMB = _totalChunkMB_locked
        let pcmKB = pcmBufferBytes / 1000
        let files = tempFiles.count
        lock.unlock()

        log.info("Audio memory summary", detail: "chunks=\(chunks) (\(chunkMB)MB), pcm=\(pcmKB)KB, temp_files=\(files)")
    }

    /// Get summary as dictionary for MemoryMonitor
    var summary: [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return [
            "audio_chunks": chunkAllocations.count,
            "audio_chunk_mb": _totalChunkMB_locked,
            "pcm_buffer_kb": pcmBufferBytes / 1000,
            "temp_files": tempFiles.count
        ]
    }
}
