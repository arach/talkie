import Foundation
import AVFoundation
import TalkieKit

private let log = Log(.audio)

enum MicSessionError: LocalizedError {
    case alreadyFinished
    case noAudioCaptured

    var errorDescription: String? {
        switch self {
        case .alreadyFinished:
            return "Session already finished"
        case .noAudioCaptured:
            return "No audio captured"
        }
    }
}

final class MicSession: @unchecked Sendable {
    let sessionId: String
    let clientId: String
    let persist: Bool
    let label: String?
    let startedAt: Date

    private let queue: DispatchQueue
    private let stateLock = NSLock()
    private let writer: MicSessionFileWriter

    private var state: State = .recording

    private enum State {
        case recording
        case finalizing
        case finished
        case cancelled
    }

    init(
        sessionId: String,
        clientId: String,
        persist: Bool,
        label: String?,
        outputURL: URL,
        segmentDuration: TimeInterval = 600
    ) {
        self.sessionId = sessionId
        self.clientId = clientId
        self.persist = persist
        self.label = label
        self.startedAt = Date()
        self.queue = DispatchQueue(label: "to.talkie.agent.mic.session.\(sessionId)")
        self.writer = MicSessionFileWriter(outputURL: outputURL, segmentDuration: segmentDuration)
    }

    var stats: [String: Any] {
        [
            "sessionId": sessionId,
            "clientId": clientId,
            "label": label ?? "",
            "duration": Date().timeIntervalSince(startedAt),
            "bytesWritten": writer.bytesWritten,
            "segments": writer.segmentCount
        ]
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        let shouldWrite = stateLock.withLock { state == .recording }
        guard shouldWrite else { return }

        queue.async { [writer] in
            writer.write(buffer)
        }
    }

    func finalize() async throws -> MicSessionFinalizedFile {
        let canFinalize = stateLock.withLock {
            guard state == .recording else { return false }
            state = .finalizing
            return true
        }

        guard canFinalize else {
            throw MicSessionError.alreadyFinished
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<MicSessionFinalizedFile, Error>) in
            queue.async {
                do {
                    let result = try self.writer.finalize()
                    guard result.fileSize > 0 else {
                        self.stateLock.withLock {
                            self.state = .finished
                        }
                        continuation.resume(throwing: MicSessionError.noAudioCaptured)
                        return
                    }
                    self.stateLock.withLock {
                        self.state = .finished
                    }
                    continuation.resume(returning: result)
                } catch {
                    self.stateLock.withLock {
                        self.state = .finished
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func cancel() async {
        let canCancel = stateLock.withLock {
            guard state == .recording || state == .finalizing else { return false }
            state = .cancelled
            return true
        }

        guard canCancel else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.writer.cancel()
                log.info("Bridge mic cancelled session", detail: self.sessionId)
                continuation.resume()
            }
        }
    }
}
