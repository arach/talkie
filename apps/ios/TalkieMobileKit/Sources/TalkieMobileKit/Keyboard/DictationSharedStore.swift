import Foundation

/// Shared store for keyboard <-> app dictation state.
///
/// Storage: individual UserDefaults keys (not a JSON blob).
/// Each key is written by exactly one process, eliminating cross-process clobber.
public final class DictationSharedStore {
    public static let shared = DictationSharedStore()

    private let defaults: UserDefaults?
    private let log = Log(.keyboard)

    // MARK: - Key Constants

    private enum Key {
        static let epoch = "ds.epoch"
        static let phase = "ds.phase"
        static let capability = "ds.capability"
        static let activeSessionId = "ds.activeSessionId"
        static let command = "ds.command"
        static let commandAck = "ds.commandAck"
        static let lastResult = "ds.lastResult"
        static let lastResultConsumedAt = "ds.lastResultConsumedAt"
        static let lastError = "ds.lastError"
        static let lastErrorConsumedAt = "ds.lastErrorConsumedAt"
        static let cooldownUntil = "ds.cooldownUntil"
        static let appHeartbeat = "ds.appHeartbeat"
        static let keyboardHeartbeat = "ds.keyboardHeartbeat"
        static let updatedAt = "ds.updatedAt"
        static let updatedBy = "ds.updatedBy"
    }

    /// Legacy key — the old JSON blob. Used for migration only.
    private let legacyStateKey = "dictation.sharedState"
    /// Legacy heartbeat keys (already separate — migrated to new prefix)
    private let legacyKeyboardHeartbeatKey = "dictation.sharedState.keyboardHeartbeat"
    private let legacyAppHeartbeatKey = "dictation.sharedState.appHeartbeat"

    private let keyboardDebugKey = "dictation.sharedState.keyboardDebug"
    private let keyboardDebugSequenceKey = "dictation.sharedState.keyboardDebugSequence"
    private let startCommandTTL: TimeInterval = 10.0
    private let stopCommandTTL: TimeInterval = 15.0

    /// Atomic phase+timestamp pair (written as micro-JSON)
    private struct PhaseEntry: Codable {
        let p: String   // Phase rawValue
        let at: Double  // TimeInterval
    }

    public var isAvailable: Bool { defaults != nil }

    private init() {
        defaults = UserDefaults(suiteName: kTalkieAppGroup)
        if defaults == nil {
            log.error("DictationSharedStore: Cannot access App Group")
        }
        migrateFromLegacyBlobIfNeeded()
    }

    // MARK: - Migration

    private func migrateFromLegacyBlobIfNeeded() {
        // If new keys already present, no migration needed
        if defaults?.object(forKey: Key.epoch) != nil { return }

        // Check for legacy blob
        guard let data = defaults?.data(forKey: legacyStateKey) else { return }

        guard let old = try? JSONDecoder().decode(DictationSharedState.self, from: data) else {
            log.warning("DictationSharedStore: Legacy blob undecodable — starting fresh")
            return
        }

        log.info("DictationSharedStore: Migrating from legacy JSON blob")

        // Scatter fields into individual keys
        defaults?.set(old.epoch, forKey: Key.epoch)
        writePhase(old.phase, at: old.phaseUpdatedAt)
        defaults?.set(old.capability.rawValue, forKey: Key.capability)
        if let sid = old.activeSessionId {
            defaults?.set(sid.uuidString, forKey: Key.activeSessionId)
        }
        writeJSON(old.command, forKey: Key.command)
        writeJSON(old.commandAck, forKey: Key.commandAck)
        writeJSON(old.lastResult, forKey: Key.lastResult)
        if let v = old.lastResultConsumedAt { defaults?.set(v, forKey: Key.lastResultConsumedAt) }
        writeJSON(old.lastError, forKey: Key.lastError)
        if let v = old.lastErrorConsumedAt { defaults?.set(v, forKey: Key.lastErrorConsumedAt) }
        if let v = old.cooldownUntil { defaults?.set(v, forKey: Key.cooldownUntil) }
        defaults?.set(old.updatedAt, forKey: Key.updatedAt)
        if let by = old.updatedBy { defaults?.set(by, forKey: Key.updatedBy) }

        // Migrate heartbeats from legacy separate keys (or from blob)
        let legacyAppHB = defaults?.double(forKey: legacyAppHeartbeatKey) ?? 0
        let legacyKBHB = defaults?.double(forKey: legacyKeyboardHeartbeatKey) ?? 0
        defaults?.set(max(old.appHeartbeat, legacyAppHB), forKey: Key.appHeartbeat)
        defaults?.set(max(old.keyboardHeartbeat, legacyKBHB), forKey: Key.keyboardHeartbeat)

        // Delete legacy keys
        defaults?.removeObject(forKey: legacyStateKey)
        defaults?.removeObject(forKey: legacyAppHeartbeatKey)
        defaults?.removeObject(forKey: legacyKeyboardHeartbeatKey)

        log.info("DictationSharedStore: Migration complete (epoch=\(old.epoch))")
    }

    // MARK: - Per-Key Read Helpers

    private func readPhase() -> (DictationSharedState.Phase, TimeInterval) {
        guard let data = defaults?.data(forKey: Key.phase),
              let entry = try? JSONDecoder().decode(PhaseEntry.self, from: data),
              let phase = DictationSharedState.Phase(rawValue: entry.p) else {
            return (.idle, Date().timeIntervalSince1970)
        }
        return (phase, entry.at)
    }

    private func writePhase(_ phase: DictationSharedState.Phase, at: TimeInterval) {
        let entry = PhaseEntry(p: phase.rawValue, at: at)
        if let data = try? JSONEncoder().encode(entry) {
            defaults?.set(data, forKey: Key.phase)
        }
    }

    private func readJSON<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func writeJSON<T: Encodable>(_ value: T?, forKey key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults?.set(data, forKey: key)
        } else {
            defaults?.removeObject(forKey: key)
        }
    }

    // MARK: - Public Property Readers

    public var phase: DictationSharedState.Phase { readPhase().0 }
    public var phaseUpdatedAt: TimeInterval { readPhase().1 }
    public var phaseAge: TimeInterval { Date().timeIntervalSince1970 - phaseUpdatedAt }

    public var epoch: Int { defaults?.integer(forKey: Key.epoch) ?? 0 }

    public var capability: DictationSharedState.Capability {
        guard let raw = defaults?.string(forKey: Key.capability),
              let cap = DictationSharedState.Capability(rawValue: raw) else {
            return .none
        }
        return cap
    }

    public var activeSessionId: UUID? {
        guard let str = defaults?.string(forKey: Key.activeSessionId) else { return nil }
        return UUID(uuidString: str)
    }

    public var command: DictationSharedState.Command? {
        readJSON(DictationSharedState.Command.self, forKey: Key.command)
    }

    public var commandAck: DictationSharedState.CommandAck? {
        readJSON(DictationSharedState.CommandAck.self, forKey: Key.commandAck)
    }

    public var lastResult: DictationSharedState.ResultPayload? {
        readJSON(DictationSharedState.ResultPayload.self, forKey: Key.lastResult)
    }

    public var lastResultConsumedAt: TimeInterval? {
        let v = defaults?.double(forKey: Key.lastResultConsumedAt) ?? 0
        return v > 0 ? v : nil
    }

    public var lastError: DictationSharedState.ErrorPayload? {
        readJSON(DictationSharedState.ErrorPayload.self, forKey: Key.lastError)
    }

    public var lastErrorConsumedAt: TimeInterval? {
        let v = defaults?.double(forKey: Key.lastErrorConsumedAt) ?? 0
        return v > 0 ? v : nil
    }

    public var cooldownUntil: TimeInterval? {
        let v = defaults?.double(forKey: Key.cooldownUntil) ?? 0
        return v > 0 ? v : nil
    }

    public var appHeartbeat: TimeInterval {
        defaults?.double(forKey: Key.appHeartbeat) ?? 0
    }

    public var keyboardHeartbeat: TimeInterval {
        defaults?.double(forKey: Key.keyboardHeartbeat) ?? 0
    }

    public var updatedAt: TimeInterval {
        defaults?.double(forKey: Key.updatedAt) ?? 0
    }

    public var updatedBy: String? {
        defaults?.string(forKey: Key.updatedBy)
    }

    // MARK: - Convenience Queries

    public func isCoolingDown(now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let cooldownUntil else { return false }
        return now < cooldownUntil
    }

    public func isCommandAcked(_ cmd: DictationSharedState.Command) -> Bool {
        commandAck?.id == cmd.id
    }

    // MARK: - Snapshot

    /// Non-atomic convenience snapshot for diagnostics and multi-field reads.
    public func snapshot() -> DictationSnapshot {
        let (p, pat) = readPhase()
        return DictationSnapshot(
            epoch: epoch,
            phase: p,
            phaseUpdatedAt: pat,
            capability: capability,
            activeSessionId: activeSessionId,
            command: command,
            commandAck: commandAck,
            lastResult: lastResult,
            lastResultConsumedAt: lastResultConsumedAt,
            lastError: lastError,
            lastErrorConsumedAt: lastErrorConsumedAt,
            cooldownUntil: cooldownUntil,
            appHeartbeat: appHeartbeat,
            keyboardHeartbeat: keyboardHeartbeat,
            updatedAt: updatedAt,
            updatedBy: updatedBy
        )
    }

    // MARK: - Phase Writes

    public func appSetPhase(_ phase: DictationSharedState.Phase, sessionId: UUID?) {
        let now = Date().timeIntervalSince1970

        #if DEBUG
        validateTransition(from: self.phase, to: phase)
        #endif

        writePhase(phase, at: now)
        if let sessionId {
            defaults?.set(sessionId.uuidString, forKey: Key.activeSessionId)
        }
        stampUpdate("app")
        DictationNotificationCenter.shared.post(.stateChanged)
    }

    // MARK: - Capability

    public func setCapability(_ capability: DictationSharedState.Capability) {
        defaults?.set(capability.rawValue, forKey: Key.capability)
        stampUpdate("app")
    }

    // MARK: - Epoch / Reset

    public func bumpEpoch(reason: String? = nil) {
        let currentEpoch = epoch
        let cap = capability
        let ahb = appHeartbeat
        let khb = keyboardHeartbeat

        resetAllKeys()

        let newEpoch = max(currentEpoch + 1, 1)
        defaults?.set(newEpoch, forKey: Key.epoch)
        defaults?.set(cap.rawValue, forKey: Key.capability)
        defaults?.set(ahb, forKey: Key.appHeartbeat)
        defaults?.set(khb, forKey: Key.keyboardHeartbeat)
        writePhase(.idle, at: Date().timeIntervalSince1970)
        stampUpdate("app")

        if let reason {
            log.info("DictationSharedStore: Epoch bumped (\(reason))")
        }
    }

    public func forceReset(reason: String, preserveCapability: Bool = true, updatedBy: String? = nil) {
        let currentEpoch = epoch
        let cap = preserveCapability ? capability : .none
        let ahb = appHeartbeat
        let khb = keyboardHeartbeat

        resetAllKeys()

        defaults?.set(currentEpoch, forKey: Key.epoch)
        defaults?.set(cap.rawValue, forKey: Key.capability)
        defaults?.set(ahb, forKey: Key.appHeartbeat)
        defaults?.set(khb, forKey: Key.keyboardHeartbeat)
        writePhase(.idle, at: Date().timeIntervalSince1970)
        stampUpdate(updatedBy)

        log.warning("DictationSharedStore: Force reset (\(reason))")
    }

    // MARK: - Heartbeats

    public func updateKeyboardHeartbeat() {
        defaults?.set(Date().timeIntervalSince1970, forKey: Key.keyboardHeartbeat)
    }

    public func updateAppHeartbeat() {
        defaults?.set(Date().timeIntervalSince1970, forKey: Key.appHeartbeat)
    }

    // MARK: - Command Helpers

    public func keyboardRequestStart(sessionId: UUID) -> DictationSharedState.Command {
        let now = Date().timeIntervalSince1970
        let currentEpoch = epoch
        let cmd = DictationSharedState.Command(
            id: UUID(),
            kind: .start,
            sessionId: sessionId,
            requestedAt: now,
            epoch: currentEpoch
        )

        // Write individual keys — no read needed
        writeJSON(cmd, forKey: Key.command)
        writeJSON(nil as DictationSharedState.CommandAck?, forKey: Key.commandAck)
        defaults?.set(sessionId.uuidString, forKey: Key.activeSessionId)
        writeJSON(nil as DictationSharedState.ResultPayload?, forKey: Key.lastResult)
        defaults?.removeObject(forKey: Key.lastResultConsumedAt)
        writeJSON(nil as DictationSharedState.ErrorPayload?, forKey: Key.lastError)
        defaults?.removeObject(forKey: Key.lastErrorConsumedAt)
        writePhase(.arming, at: now)
        stampUpdate("keyboard")

        DictationNotificationCenter.shared.post(.commandChanged)
        return cmd
    }

    public func keyboardRequestStop(sessionId: UUID) -> DictationSharedState.Command {
        let now = Date().timeIntervalSince1970
        let currentEpoch = epoch
        let cmd = DictationSharedState.Command(
            id: UUID(),
            kind: .stop,
            sessionId: sessionId,
            requestedAt: now,
            epoch: currentEpoch
        )

        writeJSON(cmd, forKey: Key.command)
        writeJSON(nil as DictationSharedState.CommandAck?, forKey: Key.commandAck)
        writePhase(.stopping, at: now)
        stampUpdate("keyboard")

        DictationNotificationCenter.shared.post(.commandChanged)
        return cmd
    }

    public func keyboardRequestCancel(sessionId: UUID) -> DictationSharedState.Command {
        let now = Date().timeIntervalSince1970
        let currentEpoch = epoch
        let cmd = DictationSharedState.Command(
            id: UUID(),
            kind: .cancel,
            sessionId: sessionId,
            requestedAt: now,
            epoch: currentEpoch
        )

        writeJSON(cmd, forKey: Key.command)
        writeJSON(nil as DictationSharedState.CommandAck?, forKey: Key.commandAck)
        stampUpdate("keyboard")

        DictationNotificationCenter.shared.post(.commandChanged)
        return cmd
    }

    public func keyboardConsumeResult(sessionId: UUID) {
        guard let result = lastResult, result.sessionId == sessionId else { return }
        let now = Date().timeIntervalSince1970

        writeJSON(nil as DictationSharedState.ResultPayload?, forKey: Key.lastResult)
        defaults?.set(now, forKey: Key.lastResultConsumedAt)
        writeJSON(nil as DictationSharedState.ErrorPayload?, forKey: Key.lastError)
        defaults?.removeObject(forKey: Key.lastErrorConsumedAt)
        writePhase(.idle, at: now)
        writeJSON(nil as DictationSharedState.Command?, forKey: Key.command)
        writeJSON(nil as DictationSharedState.CommandAck?, forKey: Key.commandAck)
        stampUpdate("keyboard")
    }

    public func keyboardConsumeError(sessionId: UUID?) {
        guard let error = lastError else { return }
        if let sessionId, error.sessionId != nil, error.sessionId != sessionId {
            return
        }
        let now = Date().timeIntervalSince1970

        writeJSON(nil as DictationSharedState.ErrorPayload?, forKey: Key.lastError)
        defaults?.set(now, forKey: Key.lastErrorConsumedAt)
        writePhase(.idle, at: now)
        writeJSON(nil as DictationSharedState.Command?, forKey: Key.command)
        writeJSON(nil as DictationSharedState.CommandAck?, forKey: Key.commandAck)
        stampUpdate("keyboard")
    }

    public func appAcknowledgeCommand(_ command: DictationSharedState.Command, phase: DictationSharedState.Phase) {
        let now = Date().timeIntervalSince1970
        let ack = DictationSharedState.CommandAck(id: command.id, phase: phase, ackedAt: now)
        writeJSON(ack, forKey: Key.commandAck)
        defaults?.set(command.sessionId.uuidString, forKey: Key.activeSessionId)
        writePhase(phase, at: now)
        stampUpdate("app")
        DictationNotificationCenter.shared.post(.stateChanged)
    }

    public func appClearCommand() {
        writeJSON(nil as DictationSharedState.Command?, forKey: Key.command)
        writeJSON(nil as DictationSharedState.CommandAck?, forKey: Key.commandAck)
        stampUpdate("app")
        DictationNotificationCenter.shared.post(.stateChanged)
    }

    public func appSetResult(text: String, sessionId: UUID, durationSeconds: Double?) {
        let now = Date().timeIntervalSince1970
        let result = DictationSharedState.ResultPayload(
            sessionId: sessionId, text: text, timestamp: now, durationSeconds: durationSeconds
        )
        writeJSON(result, forKey: Key.lastResult)
        defaults?.removeObject(forKey: Key.lastResultConsumedAt)
        writeJSON(nil as DictationSharedState.ErrorPayload?, forKey: Key.lastError)
        defaults?.removeObject(forKey: Key.lastErrorConsumedAt)
        defaults?.set(sessionId.uuidString, forKey: Key.activeSessionId)

        // Flush result to disk before setting phase=done.
        // Without this, the keyboard extension can see phase=done
        // before lastResult has propagated cross-process, causing
        // an empty insertion on the first dictation.
        defaults?.synchronize()

        writePhase(.done, at: now)
        writeJSON(nil as DictationSharedState.Command?, forKey: Key.command)
        writeJSON(nil as DictationSharedState.CommandAck?, forKey: Key.commandAck)
        stampUpdate("app")
        DictationNotificationCenter.shared.post(.stateChanged)
    }

    public func appSetError(
        message: String,
        sessionId: UUID?,
        code: String? = nil,
        recoverable: Bool = true,
        retryAfter: TimeInterval? = nil
    ) {
        let now = Date().timeIntervalSince1970
        let errorPayload = DictationSharedState.ErrorPayload(
            sessionId: sessionId, message: message, code: code,
            recoverable: recoverable, retryAfter: retryAfter, timestamp: now
        )
        writeJSON(errorPayload, forKey: Key.lastError)
        defaults?.removeObject(forKey: Key.lastErrorConsumedAt)
        writeJSON(nil as DictationSharedState.ResultPayload?, forKey: Key.lastResult)
        defaults?.removeObject(forKey: Key.lastResultConsumedAt)

        // Flush error payload before phase change (same race as appSetResult)
        defaults?.synchronize()

        writePhase(.error, at: now)
        if let retryAfter {
            defaults?.set(now + retryAfter, forKey: Key.cooldownUntil)
        }
        writeJSON(nil as DictationSharedState.Command?, forKey: Key.command)
        writeJSON(nil as DictationSharedState.CommandAck?, forKey: Key.commandAck)
        stampUpdate("app")
        DictationNotificationCenter.shared.post(.stateChanged)
    }

    // MARK: - Command Validation

    public func isCommandFresh(_ command: DictationSharedState.Command, now: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        let ttl: TimeInterval
        switch command.kind {
        case .start:  ttl = startCommandTTL
        case .stop:   ttl = stopCommandTTL
        case .cancel: ttl = stopCommandTTL
        }
        return (now - command.requestedAt) <= ttl
    }

    // MARK: - Keyboard Debug Events

    public func publishKeyboardDebug(message: String, snapshot: String) {
        let nextSequence = (defaults?.integer(forKey: keyboardDebugSequenceKey) ?? 0) + 1
        defaults?.set(nextSequence, forKey: keyboardDebugSequenceKey)
        let event = DictationSharedState.KeyboardDebugEvent(
            sequence: nextSequence,
            message: message,
            snapshot: snapshot,
            timestamp: Date().timeIntervalSince1970
        )
        writeJSON(event, forKey: keyboardDebugKey)
    }

    public func readKeyboardDebug() -> DictationSharedState.KeyboardDebugEvent? {
        readJSON(DictationSharedState.KeyboardDebugEvent.self, forKey: keyboardDebugKey)
    }

    // MARK: - Private Helpers

    private func stampUpdate(_ updatedBy: String?) {
        defaults?.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        if let updatedBy {
            defaults?.set(updatedBy, forKey: Key.updatedBy)
        } else {
            defaults?.removeObject(forKey: Key.updatedBy)
        }
    }

    /// Clear all ds.* keys to defaults — used by bumpEpoch and forceReset
    private func resetAllKeys() {
        defaults?.removeObject(forKey: Key.epoch)
        defaults?.removeObject(forKey: Key.phase)
        defaults?.removeObject(forKey: Key.capability)
        defaults?.removeObject(forKey: Key.activeSessionId)
        defaults?.removeObject(forKey: Key.command)
        defaults?.removeObject(forKey: Key.commandAck)
        defaults?.removeObject(forKey: Key.lastResult)
        defaults?.removeObject(forKey: Key.lastResultConsumedAt)
        defaults?.removeObject(forKey: Key.lastError)
        defaults?.removeObject(forKey: Key.lastErrorConsumedAt)
        defaults?.removeObject(forKey: Key.cooldownUntil)
        // Don't clear heartbeats or updatedAt — set by caller
    }

    #if DEBUG
    private func validateTransition(from old: DictationSharedState.Phase, to new: DictationSharedState.Phase) {
        guard old != new, !old.validTransitions.contains(new) else { return }
        log.warning("""
            ⚠️ INVALID PHASE TRANSITION
               From: \(old.rawValue)
               To:   \(new.rawValue)
               Valid: \(old.validTransitions.map { $0.rawValue })
            """)
    }
    #endif
}
