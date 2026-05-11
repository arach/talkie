//
//  AudioEngineStubs.swift
//  TalkieAgent
//
//  Stub types for incomplete refactor. These allow the project to compile
//  while the unified audio capture system is still being developed.
//
//  TODO: Remove these stubs once UnifiedAudioCapture is fully implemented.
//

import AVFoundation

// MARK: - AudioEngine Debug Flags

/// Debug flags for audio engine simulation
enum AudioEngine {
    /// Simulate HAL (Hardware Abstraction Layer) failure for testing recovery
    static var simulateHALFailure: Bool = false

    /// Simulate no audio buffers being received
    static var simulateNoBuffers: Bool = false
}

// MARK: - Capture Configuration

/// Configuration for capture sessions
enum CaptureConfig {
    case standard   // Normal recording
    case ephemeral  // Short-lived XPC capture
}

// MARK: - Capture Result

/// Result of a completed capture
struct CaptureResult {
    let fileURL: URL
    let duration: TimeInterval
    let fileSize: Int

    var isValid: Bool {
        fileSize > 1000 && duration > 0.1
    }
}

// MARK: - Capture Session

/// Placeholder for capture session tracking
struct CaptureSession {
    let id: String
}

// MARK: - Unified Audio Capture Stubs

/// Placeholder for unified audio capture system (not yet implemented)
/// Conforms to AgentAudioCapture for use in AgentController
final class UnifiedAudioCapture: AgentAudioCapture {
    /// Error callback (AgentAudioCapture protocol)
    var onCaptureError: ((String) -> Void)?
    var onSegmentCompleted: ((AudioWriterSegment) -> Void)?
    var currentSegmentIndex: Int { 0 }

    /// Error callback (async API)
    var onError: ((Error) -> Void)?

    /// Chunk callback for AgentAudioCapture
    private var onChunk: (([String]) -> Void)?

    // MARK: - AgentAudioCapture Protocol

    func startCapture(onChunk: @escaping ([String]) -> Void) {
        self.onChunk = onChunk
        // Stub - no actual capture
    }

    func stopCapture() {
        // Stub - no actual capture
        onChunk = nil
    }

    func requestCheckpoint() {
        // Stub - no-op
    }

    // MARK: - Async API (for ephemeral capture)

    /// Warm up the capture system
    func warmUp() async -> Bool {
        // Stub - always succeeds
        return true
    }

    /// Start capturing audio (async version)
    func startCapture(config: CaptureConfig = .standard) async throws -> CaptureSession {
        // Stub - returns dummy session
        return CaptureSession(id: UUID().uuidString)
    }

    /// Stop capturing and return result (async version)
    func stopCapture() async -> CaptureResult? {
        // Stub - returns nil (no actual capture)
        return nil
    }

    /// Clean up resources
    func tearDown() {
        // Stub - no-op
    }

    /// Reboot audio system
    @discardableResult
    func reboot() async -> AudioRebootResult {
        // Stub - no-op
        return .success
    }
}
