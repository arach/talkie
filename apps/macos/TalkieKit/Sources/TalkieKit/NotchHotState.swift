//
//  NotchHotState.swift
//  TalkieKit
//
//  Memory-mapped file for zero-latency notch UI state.
//  Agent writes, Talkie reads at display-link rate.
//
//  Layout: 16 bytes, naturally aligned.
//  One writer (Agent), one reader (Talkie). No locks needed —
//  worst case is a torn read giving one frame of wrong data.
//

import Foundation

// MARK: - Hot State Struct

/// Raw layout for memory-mapped notch state.
/// Written by TalkieAgent at audio-buffer rate (~40Hz).
/// Read by Talkie at display-link rate (~60Hz).
public struct NotchHotState {
    /// LiveState raw value: 0=idle, 1=listening, 2=transcribing, 3=routing
    public var phase: UInt8
    private var _pad1: UInt8
    private var _pad2: UInt8
    private var _pad3: UInt8
    /// Audio level 0.0–1.0
    public var audioLevel: Float
    /// Seconds since recording started
    public var elapsedTime: Float
    /// Monotonic counter, bumped on every write. Reader uses for change detection.
    public var sequence: UInt32

    public static let zero = NotchHotState(
        phase: 0, _pad1: 0, _pad2: 0, _pad3: 0,
        audioLevel: 0, elapsedTime: 0, sequence: 0
    )

    public var liveState: LiveState {
        switch phase {
        case 1: return .listening
        case 2: return .transcribing
        case 3: return .routing
        default: return .idle
        }
    }

    public static func phaseValue(for state: LiveState) -> UInt8 {
        switch state {
        case .idle: return 0
        case .listening: return 1
        case .transcribing: return 2
        case .routing: return 3
        case .refining: return 4
        }
    }
}

// MARK: - File Path

extension NotchHotState {
    /// Shared file path for the memory-mapped hot state.
    /// Uses /tmp/ for guaranteed cross-process visibility (non-sandboxed apps).
    public static func filePath(for environment: TalkieEnvironment = .current) -> String {
        "/tmp/talkie-notch-\(environment.rawValue)"
    }
}

// MARK: - Writer (Agent side)

/// Writes notch hot state to a memory-mapped file.
/// Create once, call `writePhase` and `writeAudioLevel` as state changes.
/// Not thread-safe — call from a single thread (MainActor).
public final class NotchHotStateWriter {
    private var fd: Int32 = -1
    private var ptr: UnsafeMutablePointer<NotchHotState>?
    private var current = NotchHotState.zero
    private let size = MemoryLayout<NotchHotState>.size

    public var isActive: Bool { ptr != nil }

    public init(environment: TalkieEnvironment = .current) {
        let path = NotchHotState.filePath(for: environment)

        fd = open(path, O_RDWR | O_CREAT, 0o666)
        guard fd >= 0 else {
            TalkieLogger.info(.system, "[NotchHotState] Writer: failed to open \(path)")
            return
        }

        // Ensure file is the right size
        ftruncate(fd, off_t(size))

        let raw = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0)
        guard raw != MAP_FAILED else {
            TalkieLogger.info(.system, "[NotchHotState] Writer: mmap failed")
            close(fd); fd = -1
            return
        }

        ptr = raw!.assumingMemoryBound(to: NotchHotState.self)
        // Zero out on creation
        ptr?.pointee = .zero
        TalkieLogger.info(.system, "[NotchHotState] Writer: active at \(path) (\(size) bytes)")
    }

    deinit {
        if let ptr = ptr {
            // Set idle before unmapping
            ptr.pointee.phase = 0
            ptr.pointee.sequence &+= 1
            munmap(UnsafeMutableRawPointer(ptr), size)
        }
        if fd >= 0 {
            close(fd)
        }
    }

    /// Write a phase (state) change with elapsed time.
    public func writePhase(_ phase: UInt8, elapsedTime: Float) {
        current.phase = phase
        current.elapsedTime = elapsedTime
        flush()
    }

    /// Write an audio level update.
    public func writeAudioLevel(_ level: Float) {
        current.audioLevel = level
        flush()
    }

    /// Write everything at once.
    public func write(phase: UInt8, audioLevel: Float, elapsedTime: Float) {
        current.phase = phase
        current.audioLevel = audioLevel
        current.elapsedTime = elapsedTime
        flush()
    }

    private func flush() {
        guard let ptr = ptr else { return }
        current.sequence &+= 1
        ptr.pointee = current
    }
}

// MARK: - Reader (Talkie side)

/// Reads notch hot state from a memory-mapped file.
/// Call `read()` at display-link rate for zero-latency state.
public final class NotchHotStateReader {
    private var fd: Int32 = -1
    private var ptr: UnsafePointer<NotchHotState>?
    private let size = MemoryLayout<NotchHotState>.size

    /// Whether the reader successfully mapped the file.
    public private(set) var isActive: Bool = false

    public init(environment: TalkieEnvironment = .current) {
        tryOpen(environment: environment)
    }

    deinit {
        if let ptr = ptr {
            munmap(UnsafeMutableRawPointer(mutating: ptr), size)
        }
        if fd >= 0 {
            close(fd)
        }
    }

    /// Attempt to open/reopen the hot state file.
    /// Returns true if now active.
    @discardableResult
    public func tryOpen(environment: TalkieEnvironment = .current) -> Bool {
        guard !isActive else { return true }

        let path = NotchHotState.filePath(for: environment)
        fd = open(path, O_RDONLY)
        guard fd >= 0 else { return false }

        let raw = mmap(nil, size, PROT_READ, MAP_SHARED, fd, 0)
        guard raw != MAP_FAILED else {
            close(fd); fd = -1
            return false
        }

        ptr = UnsafePointer(raw!.assumingMemoryBound(to: NotchHotState.self))
        isActive = true
        TalkieLogger.info(.system, "[NotchHotState] Reader: active")
        return true
    }

    /// Read the current hot state. Returns `.zero` if not active.
    public func read() -> NotchHotState {
        guard let ptr = ptr else { return .zero }
        return ptr.pointee
    }
}
