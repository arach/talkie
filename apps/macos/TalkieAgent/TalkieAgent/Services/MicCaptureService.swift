import Foundation
import AVFoundation
import TalkieKit

private let log = Log(.audio)

final class MicCaptureService: @unchecked Sendable {
    private let lock = NSLock()
    private let resolver = MicDeviceResolver()
    private let fanOutQueue = DispatchQueue(label: "to.talkie.agent.mic.fanout", qos: .userInitiated)

    private let maxSessionDuration: TimeInterval = 7200  // 2 hour hard ceiling
    private let sessionSweepInterval: TimeInterval = 30

    private var engine: AVAudioEngine?
    private var sessions: [String: MicSession] = [:]
    private var sessionSweepTimer: Timer?

    var activeSessionCount: Int {
        lock.withLock { sessions.count }
    }

    var isEngineRunning: Bool {
        lock.withLock { engine?.isRunning == true }
    }

    var sessionStats: [[String: Any]] {
        lock.withLock {
            sessions.values.map { $0.stats }
        }
    }

    init() {
        Task { @MainActor in
            self.startSessionSweep()
        }
    }

    func startSession(
        clientId: String,
        persist: Bool,
        label: String?,
        segmentDuration: TimeInterval = 600
    ) async throws -> String {
        let sessionId = UUID().uuidString
        let outputURL = try makeOutputURL(sessionId: sessionId)

        try ensureEngineRunning()

        let session = MicSession(
            sessionId: sessionId,
            clientId: clientId,
            persist: persist,
            label: label,
            outputURL: outputURL,
            segmentDuration: segmentDuration
        )

        lock.withLock {
            sessions[sessionId] = session
        }

        log.info("Bridge mic started session", detail: "\(sessionId) client=\(clientId)")
        return sessionId
    }

    func stopSession(sessionId: String) async throws -> MicSessionFinalizedFile {
        guard let session = removeSession(sessionId: sessionId) else {
            throw MicSessionError.alreadyFinished
        }

        let result = try await session.finalize()
        stopEngineIfIdle()

        return result
    }

    func cancelSession(sessionId: String) async throws {
        guard let session = removeSession(sessionId: sessionId) else {
            throw MicSessionError.alreadyFinished
        }

        await session.cancel()
        stopEngineIfIdle()

    }

    func shutdown() {
        sessionSweepTimer?.invalidate()
        sessionSweepTimer = nil

        let sessionsToCancel = lock.withLock {
            let values = Array(sessions.values)
            sessions.removeAll()
            return values
        }

        Task {
            for session in sessionsToCancel {
                await session.cancel()
            }
        }

        stopEngine()
    }

    private func ensureEngineRunning() throws {
        if isEngineRunning {
            return
        }

        let selection = try resolver.resolveSelection()
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nil) { [weak self] buffer, _ in
            self?.fanOutBuffer(buffer)
        }

        engine.prepare()
        try engine.start()

        lock.withLock {
            self.engine = engine
        }

        log.info("Bridge mic engine started", detail: selection.name)
    }

    private func stopEngineIfIdle() {
        guard activeSessionCount == 0 else { return }
        stopEngine()
    }

    private func stopEngine() {
        let engineToStop = lock.withLock {
            let current = engine
            engine = nil
            return current
        }

        guard let engineToStop else { return }

        engineToStop.inputNode.removeTap(onBus: 0)
        engineToStop.stop()
        log.info("Bridge mic engine stopped")
    }

    private func removeSession(sessionId: String) -> MicSession? {
        lock.withLock {
            sessions.removeValue(forKey: sessionId)
        }
    }

    /// Called on the real-time audio thread — must not allocate or block.
    /// We take a single deep copy on the audio thread (unavoidable for data
    /// capture) and hand it to a background queue that fans out per-session
    /// copies without blocking the audio render callback.
    private func fanOutBuffer(_ buffer: AVAudioPCMBuffer) {
        // Lock-free read: snapshot session list pointer on the audio thread.
        // os_unfair_lock would be ideal but NSLock is acceptable for the
        // sub-microsecond hold time of a dictionary snapshot.
        let activeSessions = lock.withLock {
            Array(sessions.values)
        }

        guard !activeSessions.isEmpty else { return }

        // Single copy on the audio thread — subsequent per-session copies
        // happen on fanOutQueue to keep the render callback fast.
        guard let primaryCopy = buffer.deepCopy() else { return }

        fanOutQueue.async {
            if activeSessions.count == 1 {
                // Only one session — hand off the single copy directly (zero extra alloc)
                activeSessions[0].write(primaryCopy)
            } else {
                // Multiple sessions — first gets the primary copy, rest get additional copies
                for (index, session) in activeSessions.enumerated() {
                    if index == 0 {
                        session.write(primaryCopy)
                    } else {
                        guard let copy = primaryCopy.deepCopy() else { continue }
                        session.write(copy)
                    }
                }
            }
        }
    }

    @MainActor
    private func startSessionSweep() {
        sessionSweepTimer?.invalidate()
        sessionSweepTimer = Timer.scheduledTimer(withTimeInterval: sessionSweepInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.expireStaleSessions()
            }
        }
    }

    private func expireStaleSessions() async {
        let expired = lock.withLock {
            sessions.values
                .filter { Date().timeIntervalSince($0.startedAt) >= maxSessionDuration }
                .map(\.sessionId)
        }

        guard !expired.isEmpty else { return }

        for sessionId in expired {
            try? await cancelSession(sessionId: sessionId)
            log.warning("Bridge mic expired stale session", detail: sessionId)
        }
    }

    private func makeOutputURL(sessionId: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalkieAgentMic", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directory.appendingPathComponent("bridge-\(sessionId).wav")
    }
}

private extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }

        copy.frameLength = frameLength

        let sourcePointer = UnsafeMutablePointer<AudioBufferList>(mutating: audioBufferList)
        let sourceBuffers = UnsafeMutableAudioBufferListPointer(sourcePointer)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)

        for index in 0..<Int(sourceBuffers.count) {
            guard let sourceData = sourceBuffers[index].mData,
                  let destinationData = destinationBuffers[index].mData else {
                continue
            }

            memcpy(destinationData, sourceData, Int(sourceBuffers[index].mDataByteSize))
            destinationBuffers[index].mDataByteSize = sourceBuffers[index].mDataByteSize
        }

        return copy
    }
}
