import Foundation

/// Single shared blob for keyboard <-> app dictation state.
public struct DictationSharedState: Codable {
    public enum Phase: String, Codable {
        case idle
        case ready
        case arming
        case recording
        case stopping
        case transcribing
        case done
        case error

        /// Valid transitions from this phase (debug-only validation)
        public var validTransitions: [Phase] {
            switch self {
            case .idle:     return [.ready, .arming, .recording]
            case .ready:    return [.recording, .idle, .arming]
            case .arming:   return [.recording, .idle]
            case .recording: return [.stopping, .transcribing, .idle]
            case .stopping: return [.transcribing, .idle]
            case .transcribing: return [.done, .idle, .error]
            case .done:     return [.ready, .idle]
            case .error:    return [.idle, .ready]
            }
        }
    }

    public enum Capability: String, Codable {
        case none
        case foregroundOnly
        case warm
    }

    public enum CommandKind: String, Codable {
        case start
        case stop
        case cancel
    }

    public struct Command: Codable {
        public let id: UUID
        public let kind: CommandKind
        public let sessionId: UUID
        public let requestedAt: TimeInterval
        public let epoch: Int

        public init(id: UUID, kind: CommandKind, sessionId: UUID, requestedAt: TimeInterval, epoch: Int) {
            self.id = id
            self.kind = kind
            self.sessionId = sessionId
            self.requestedAt = requestedAt
            self.epoch = epoch
        }
    }

    public struct CommandAck: Codable {
        public let id: UUID
        public let phase: Phase
        public let ackedAt: TimeInterval

        public init(id: UUID, phase: Phase, ackedAt: TimeInterval) {
            self.id = id
            self.phase = phase
            self.ackedAt = ackedAt
        }
    }

    public struct ResultPayload: Codable {
        public let sessionId: UUID
        public let text: String
        public let timestamp: TimeInterval
        public let durationSeconds: Double?

        public init(sessionId: UUID, text: String, timestamp: TimeInterval, durationSeconds: Double?) {
            self.sessionId = sessionId
            self.text = text
            self.timestamp = timestamp
            self.durationSeconds = durationSeconds
        }
    }

    public struct ErrorPayload: Codable {
        public let sessionId: UUID?
        public let message: String
        public let code: String?
        public let recoverable: Bool
        public let retryAfter: TimeInterval?
        public let timestamp: TimeInterval

        public init(
            sessionId: UUID?,
            message: String,
            code: String?,
            recoverable: Bool,
            retryAfter: TimeInterval?,
            timestamp: TimeInterval
        ) {
            self.sessionId = sessionId
            self.message = message
            self.code = code
            self.recoverable = recoverable
            self.retryAfter = retryAfter
            self.timestamp = timestamp
        }
    }

    public struct KeyboardDebugEvent: Codable {
        public let sequence: Int
        public let message: String
        public let snapshot: String
        public let timestamp: TimeInterval

        public init(sequence: Int, message: String, snapshot: String, timestamp: TimeInterval) {
            self.sequence = sequence
            self.message = message
            self.snapshot = snapshot
            self.timestamp = timestamp
        }
    }

    public var epoch: Int
    public var phase: Phase
    public var phaseUpdatedAt: TimeInterval
    public var capability: Capability
    public var activeSessionId: UUID?
    public var command: Command?
    public var commandAck: CommandAck?
    public var lastResult: ResultPayload?
    public var lastResultConsumedAt: TimeInterval?
    public var lastError: ErrorPayload?
    public var lastErrorConsumedAt: TimeInterval?
    public var cooldownUntil: TimeInterval?
    public var appHeartbeat: TimeInterval
    public var keyboardHeartbeat: TimeInterval
    public var updatedAt: TimeInterval
    public var updatedBy: String?

    public init(now: TimeInterval = Date().timeIntervalSince1970) {
        epoch = 0
        phase = .idle
        phaseUpdatedAt = now
        capability = .none
        activeSessionId = nil
        command = nil
        commandAck = nil
        lastResult = nil
        lastResultConsumedAt = nil
        lastError = nil
        lastErrorConsumedAt = nil
        cooldownUntil = nil
        appHeartbeat = 0
        keyboardHeartbeat = 0
        updatedAt = now
        updatedBy = nil
    }

    public var phaseAge: TimeInterval {
        Date().timeIntervalSince1970 - phaseUpdatedAt
    }

    public func isCoolingDown(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let cooldownUntil else { return false }
        return now < cooldownUntil
    }

    public func isCommandAcked(_ command: Command) -> Bool {
        commandAck?.id == command.id
    }

    public mutating func setPhase(_ newPhase: Phase, now: TimeInterval = Date().timeIntervalSince1970) {
        phase = newPhase
        phaseUpdatedAt = now
    }
}

/// Read-only snapshot of shared state, constructed from individual key reads.
/// Explicitly non-atomic — fields may be from slightly different moments.
/// Use for diagnostics, logging, and call sites that read multiple fields at once.
public struct DictationSnapshot {
    public let epoch: Int
    public let phase: DictationSharedState.Phase
    public let phaseUpdatedAt: TimeInterval
    public let capability: DictationSharedState.Capability
    public let activeSessionId: UUID?
    public let command: DictationSharedState.Command?
    public let commandAck: DictationSharedState.CommandAck?
    public let lastResult: DictationSharedState.ResultPayload?
    public let lastResultConsumedAt: TimeInterval?
    public let lastError: DictationSharedState.ErrorPayload?
    public let lastErrorConsumedAt: TimeInterval?
    public let cooldownUntil: TimeInterval?
    public let appHeartbeat: TimeInterval
    public let keyboardHeartbeat: TimeInterval
    public let updatedAt: TimeInterval
    public let updatedBy: String?

    public var phaseAge: TimeInterval {
        Date().timeIntervalSince1970 - phaseUpdatedAt
    }

    public func isCoolingDown(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let cooldownUntil else { return false }
        return now < cooldownUntil
    }

    public func isCommandAcked(_ command: DictationSharedState.Command) -> Bool {
        commandAck?.id == command.id
    }
}
